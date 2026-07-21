import Foundation
import CoreML
import os
import StableDiffusion
import UIKit

// MARK: - Tuning

nonisolated enum ImageGenConstants {
    /// Pair with `ImageGenModel.subfolder`: "original/compiled" wants GPU, the
    /// split_einsum_v2 variant wants .cpuAndNeuralEngine. GPU is the deliberate choice —
    /// it's the resource the continued-processing background task is actually granted.
    static let computeUnits: MLComputeUnits = .cpuAndGPU
    static let guidanceScale: Float = 7.5
    static let scheduler: StableDiffusionScheduler = .dpmSolverMultistepScheduler
    /// The palettized repo ships no SafetyChecker model, so safety stays disabled and the
    /// negative prompt does the steering.
    static let negativePrompt = "text, watermark, signature, letters, words, blurry, lowres, deformed, distorted, disfigured, bad anatomy, extra limbs, mutated hands, ugly, duplicate, jpeg artifacts, nsfw"
}

// MARK: - Cross-thread plumbing

/// `StableDiffusionPipeline` is not Sendable; exactly one generation runs at a time (the
/// MainActor service awaits each background call), so a box hop is safe.
nonisolated private final class PipelineBox: @unchecked Sendable {
    let pipeline: StableDiffusionPipeline
    init(_ pipeline: StableDiffusionPipeline) { self.pipeline = pipeline }
}

/// Stop signal readable from inside the synchronous SD progress callback on a background thread.
nonisolated private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - Service

/// Downloads, loads, and runs the CoreML Stable Diffusion model that illustrates stories.
/// A singleton so the setup form and Settings observe the same download state — the same
/// reason `MLXGenerationService` is shared. Download-progress properties mirror that service
/// so the existing download UI pattern transplants directly.
@Observable
@MainActor
final class StoryImageService {
    static let shared = StoryImageService()

    private let logger = Logger(subsystem: "com.germanflashcards", category: "StoryImageService")

    var isDownloading = false
    var downloadProgress: Double?      // nil = indeterminate
    var downloadInfo: String?
    var downloadBytesInfo: String?
    var loadError: String?
    private(set) var isPipelineLoaded = false

    private var box: PipelineBox?
    private var downloadTask: Task<Void, Never>?
    private let cancelFlag = CancelFlag()

    private init() {}

    // MARK: Download

    /// Download the model's compiled variant into the shared hub cache. Resumable: cancelled
    /// or interrupted transfers keep their bytes and continue on the next call.
    /// Returns whether the model is fully downloaded afterwards.
    @discardableResult
    func downloadModel() async -> Bool {
        let model = ImageGenModel.current
        guard !isDownloading else { return model.isDownloaded }
        if model.isDownloaded { return true }

        isDownloading = true
        loadError = nil
        downloadProgress = nil
        downloadInfo = "Preparing download…"

        let task = Task {
            do {
                try await ResumableModelDownloader().download(
                    repoID: model.repoID,
                    matching: model.downloadPatterns
                ) { [weak self] downloaded, total in
                    guard let self, self.isDownloading else { return }
                    self.downloadInfo = "Downloading \(model.displayName)…"
                    self.downloadBytesInfo = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
                        + " / " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                    if total > 0 {
                        self.downloadProgress = Double(downloaded) / Double(total)
                    }
                }
            } catch is CancellationError {
                logger.info("Image model download cancelled")
            } catch let error as URLError where error.code == .cancelled {
                logger.info("Image model download cancelled")
            } catch {
                logger.error("Image model download failed: \(String(describing: error), privacy: .public)")
                loadError = "Download interrupted — progress is saved. Tap Download to continue."
            }
            isDownloading = false
            downloadProgress = nil
            downloadInfo = nil
            downloadBytesInfo = nil
            downloadTask = nil
        }
        downloadTask = task
        await task.value
        return model.isDownloaded
    }

    /// Cancel an in-progress download. Bytes stay on disk; the next Download continues there.
    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Delete the downloaded model (and any materialized copy of it).
    func deleteModel() throws {
        unloadPipeline()
        try ImageGenModel.current.deleteFromCache()
        try? FileManager.default.removeItem(at: Self.materializedRoot)
    }

    // MARK: Pipeline

    /// Load the Stable Diffusion pipeline from the downloaded snapshot. Heavy (CoreML model
    /// compilation on first load), so it runs off the main actor. Returns success.
    func loadPipeline() async -> Bool {
        if isPipelineLoaded { return true }
        let model = ImageGenModel.current
        guard let resources = model.resourcesURL,
              FileManager.default.fileExists(atPath: resources.path)
        else {
            loadError = "Image model files are missing — re-download it in Settings."
            return false
        }
        loadError = nil
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try Self.makePipeline(resourcesAt: resources)
            }.value
            box = loaded
            isPipelineLoaded = true
            return true
        } catch {
            // The hub cache stores snapshot files as symlinks into blobs/. CoreML resolves
            // them in practice; if this device/OS refuses, materialize real copies and retry.
            logger.error("Pipeline load failed (\(String(describing: error), privacy: .public)) — retrying from materialized copy")
            do {
                let copied = try await Task.detached(priority: .userInitiated) {
                    let real = try Self.materialize(resources, subfolder: model.subfolder)
                    return try Self.makePipeline(resourcesAt: real)
                }.value
                box = copied
                isPipelineLoaded = true
                return true
            } catch {
                logger.error("Pipeline load failed after materializing: \(String(describing: error), privacy: .public)")
                loadError = "Couldn’t load the image model: \(error.localizedDescription)"
                return false
            }
        }
    }

    func unloadPipeline() {
        box?.pipeline.unloadResources()
        box = nil
        isPipelineLoaded = false
    }

    /// Ask an in-flight `generateImage` call to stop at the next diffusion step.
    func requestStop() {
        cancelFlag.set(true)
    }

    // MARK: Generation

    /// Generate one image and write it as a PNG to `destination`, off the main actor. Returns
    /// whether a file was written — false means no pipeline is loaded, the learner stopped, or
    /// the pipeline produced nothing.
    ///
    /// The destination-based core: stories and flashcards name their files differently but the
    /// generation is identical, so callers own the naming and this owns the diffusion.
    /// `negativePrompt` defaults to the shared list; flashcards pass a longer one built from the
    /// learner's chosen picture style (`CardIllustrationPrompts.negativePrompt`).
    ///
    /// `stepCount` and `seed` default to the learner's quality tier and a random seed. The style
    /// picker overrides both: fewer steps so a sample isn't a two-minute wait, and a fixed seed so
    /// switching style changes the look and not the whole composition.
    func generateImage(
        prompt: String,
        negativePrompt: String = ImageGenConstants.negativePrompt,
        saveTo destination: URL,
        stepCount: Int? = nil,
        seed: UInt32? = nil,
        onStepProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Bool {
        guard let box else { return false }
        cancelFlag.set(false)
        let cancel = cancelFlag
        let seed = seed ?? UInt32.random(in: 0..<UInt32.max)
        // Snapshotted per image on the MainActor, so a mid-run tier change takes effect on the
        // next picture rather than being read from a background thread.
        let stepCount = stepCount ?? ImageGenQuality.current.stepCount
        return try await Task.detached(priority: .userInitiated) {
            try Self.runGeneration(
                box: box, prompt: prompt, negativePrompt: negativePrompt,
                seed: seed, stepCount: stepCount,
                destination: destination,
                cancel: cancel, onStepProgress: onStepProgress
            )
        }.value
    }

    /// Story-shaped wrapper: writes into the story's image directory as `00.png`, `01.png`, …
    /// Returns the saved file name, or nil if nothing was written.
    func generateImage(
        prompt: String,
        storyID: UUID,
        index: Int,
        onStepProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> String? {
        let fileName = String(format: "%02d.png", index)
        let written = try await generateImage(
            prompt: prompt,
            saveTo: StoryImageStore.url(fileName: fileName, storyID: storyID),
            onStepProgress: onStepProgress
        )
        return written ? fileName : nil
    }

    // MARK: - Off-main workers

    nonisolated private static func makePipeline(resourcesAt url: URL) throws -> PipelineBox {
        let config = MLModelConfiguration()
        config.computeUnits = ImageGenConstants.computeUnits
        let pipeline = try StableDiffusionPipeline(
            resourcesAt: url,
            controlNet: [],
            configuration: config,
            disableSafety: true,     // repo variant ships no SafetyChecker model
            reduceMemory: true
        )
        try pipeline.loadResources()
        return PipelineBox(pipeline)
    }

    nonisolated private static func runGeneration(
        box: PipelineBox,
        prompt: String,
        negativePrompt: String,
        seed: UInt32,
        stepCount: Int,
        destination: URL,
        cancel: CancelFlag,
        onStepProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) throws -> Bool {
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.stepCount = stepCount
        config.guidanceScale = ImageGenConstants.guidanceScale
        config.schedulerType = ImageGenConstants.scheduler
        config.seed = seed
        config.disableSafety = true
        config.imageCount = 1

        let images = try box.pipeline.generateImages(configuration: config) { progress in
            let fraction = Double(progress.step) / Double(max(progress.stepCount, 1))
            Task { @MainActor in onStepProgress(fraction) }
            return !cancel.isSet
        }
        guard !cancel.isSet, let image = images.compactMap({ $0 }).first,
              let data = UIImage(cgImage: image).pngData()
        else { return false }
        try data.write(to: destination, options: .atomic)
        return true
    }

    // MARK: - Materialized fallback

    nonisolated private static var materializedRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ImageGenResources")
    }

    /// Copy the snapshot's resources dir with symlinks resolved into real files, for the rare
    /// case where CoreML won't load through hub-cache symlinks.
    nonisolated private static func materialize(_ source: URL, subfolder: String) throws -> URL {
        let fm = FileManager.default
        let dest = materializedRoot.appendingPathComponent(subfolder)
        try? fm.removeItem(at: dest)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw CocoaError(.fileReadUnknown)
        }
        let sourcePath = source.standardizedFileURL.path
        for case let item as URL in enumerator {
            let relative = String(item.standardizedFileURL.path.dropFirst(sourcePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            let target = dest.appendingPathComponent(relative)
            let resolved = URL(fileURLWithPath: item.path).resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try? fm.removeItem(at: target)
                try fm.copyItem(at: resolved, to: target)
            }
        }
        return dest
    }
}
