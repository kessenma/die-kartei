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

    /// How many mid-diffusion previews to decode per picture when live preview is on. Each one is
    /// a full VAE decode inside the denoise loop, so this is the whole cost knob: five reads as
    /// continuous progress while adding only a few seconds to a minute-long picture.
    static let previewsPerImage = 5
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
    /// True while a picture is being drawn. With `isPipelineLoaded` it makes `isBusy`, which is
    /// what stops a tutor from loading on top of the pipeline.
    private(set) var isGenerating = false

    /// Whether the drawing model is in memory or about to draw — the moment a multi-GB tutor must
    /// not load. Every illustrate path unloads the tutor first; `MLXGenerationService.loadModel`
    /// checks this so nothing loads it back mid-run.
    var isBusy: Bool { isPipelineLoaded || isGenerating }

    private var box: PipelineBox?
    private var downloadTask: Task<Void, Never>?
    private let cancelFlag = CancelFlag()

    private init() {
        MemoryDiagnostics.register(
            "drawingModel",
            name: { "Drawing model · \(ImageGenModel.current.displayName)" },
            // The pipeline's real footprint isn't queryable; the download size is close enough
            // to say "the drawing model is what's holding this".
            bytes: { [weak self] in self?.isPipelineLoaded == true ? ImageGenModel.current.approximateSizeMB * 1_048_576 : 0 }
        )
    }

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
                ) { [self] downloaded, total in
                    guard self.isDownloading else { return }
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
            MemoryDiagnostics.record(.pipelineLoaded, title: "Loaded the drawing model · \(model.displayName)")
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
                MemoryDiagnostics.record(.pipelineLoaded, title: "Loaded the drawing model · \(model.displayName)", detail: "From a materialized copy")
                return true
            } catch {
                logger.error("Pipeline load failed after materializing: \(String(describing: error), privacy: .public)")
                loadError = "Couldn’t load the image model: \(error.localizedDescription)"
                return false
            }
        }
    }

    func unloadPipeline() {
        let wasLoaded = isPipelineLoaded
        box?.pipeline.unloadResources()
        box = nil
        isPipelineLoaded = false
        if wasLoaded {
            MemoryDiagnostics.record(.pipelineUnloaded, title: "Unloaded the drawing model")
        }
    }

    /// Ask an in-flight `generateImage` call to stop at the next diffusion step.
    func requestStop() {
        cancelFlag.set(true)
    }

    /// The memory-warning path: stop the current picture so the run winds down and its `defer`
    /// frees the pipeline. Only acts mid-run — an idle service holds nothing to give back.
    func stopForMemoryPressure() {
        guard isBusy else { return }
        logger.warning("Memory warning while drawing — stopping the run to free the pipeline")
        DeckIllustrationService.shared.stop()
        requestStop()
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
    ///
    /// `onPreview` (optional) receives the picture partway drawn, a handful of times per image, so
    /// a waiting screen can show the real thing instead of standing in for it. Passing it costs a
    /// VAE decode per preview; passing nil is exactly the old behaviour.
    func generateImage(
        prompt: String,
        negativePrompt: String = ImageGenConstants.negativePrompt,
        saveTo destination: URL,
        stepCount: Int? = nil,
        seed: UInt32? = nil,
        onStepProgress: @escaping @MainActor @Sendable (Double) -> Void,
        onPreview: (@MainActor @Sendable (CGImage) -> Void)? = nil
    ) async throws -> Bool {
        guard let box else { return false }
        cancelFlag.set(false)
        let cancel = cancelFlag
        let seed = seed ?? UInt32.random(in: 0..<UInt32.max)
        // Snapshotted per image on the MainActor, so a mid-run tier change takes effect on the
        // next picture rather than being read from a background thread.
        let stepCount = stepCount ?? ImageGenQuality.current.stepCount
        // Both halves of the preview gate are read here, on the MainActor, for the same reason.
        let previews = ImageGenPreview.isActive ? onPreview : nil
        isGenerating = true
        defer { isGenerating = false }
        return try await Task.detached(priority: .userInitiated) {
            try Self.runGeneration(
                box: box, prompt: prompt, negativePrompt: negativePrompt,
                seed: seed, stepCount: stepCount,
                destination: destination,
                cancel: cancel, onStepProgress: onStepProgress, onPreview: previews
            )
        }.value
    }

    /// Story-shaped wrapper: writes into the story's image directory as `00.png`, `01.png`, …
    /// Returns the saved file name, or nil if nothing was written.
    ///
    /// Stories pass one `seed` for all of their pictures, so the set shares a palette and
    /// rendering feel on top of the repeated character wording.
    func generateImage(
        prompt: String,
        storyID: UUID,
        index: Int,
        seed: UInt32? = nil,
        onStepProgress: @escaping @MainActor @Sendable (Double) -> Void,
        onPreview: (@MainActor @Sendable (CGImage) -> Void)? = nil
    ) async throws -> String? {
        let fileName = String(format: "%02d.png", index)
        let written = try await generateImage(
            prompt: prompt,
            saveTo: StoryImageStore.url(fileName: fileName, storyID: storyID),
            seed: seed,
            onStepProgress: onStepProgress,
            onPreview: onPreview
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
        onStepProgress: @escaping @MainActor @Sendable (Double) -> Void,
        onPreview: (@MainActor @Sendable (CGImage) -> Void)? = nil
    ) throws -> Bool {
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.stepCount = stepCount
        config.guidanceScale = ImageGenConstants.guidanceScale
        config.schedulerType = ImageGenConstants.scheduler
        config.seed = seed
        config.disableSafety = true
        config.imageCount = 1
        // Report the denoised prediction rather than the still-noisy latent. Both are already
        // computed by the loop, so this costs nothing and is the difference between a preview
        // that resolves out of a blur and one that looks like static until the last step.
        config.useDenoisedIntermediates = onPreview != nil

        let previewStride = onPreview == nil ? 0 : max(stepCount / ImageGenConstants.previewsPerImage, 1)

        let images = try box.pipeline.generateImages(configuration: config) { progress in
            let fraction = Double(progress.step) / Double(max(progress.stepCount, 1))
            Task { @MainActor in onStepProgress(fraction) }
            // Cancel first: a stop shouldn't wait out a decode that's only there to be looked at.
            if !cancel.isSet, let onPreview, let preview = Self.preview(
                for: progress, stride: previewStride, config: config, box: box
            ) {
                Task { @MainActor in onPreview(preview) }
            }
            return !cancel.isSet
        }
        guard !cancel.isSet, let image = images.compactMap({ $0 }).first,
              let data = UIImage(cgImage: image).pngData()
        else { return false }
        try data.write(to: destination, options: .atomic)
        return true
    }

    /// The picture as it stands at this step, or nil if this step isn't a preview step.
    ///
    /// Runs on the pipeline's own thread, inside the denoise loop, so the decode blocks the next
    /// UNet step rather than racing it — which is what keeps the memory spike to one decode at a
    /// time. Skipped entirely while headroom is short: a preview is a nicety, and the picture
    /// itself still has a final decode to survive.
    ///
    /// Deliberately not `progress.currentImages`, which decodes with `try!` and would turn a
    /// decoder hiccup into a crash on the one path that exists purely for looks.
    nonisolated private static func preview(
        for progress: StableDiffusionPipeline.Progress,
        stride: Int,
        config: StableDiffusionPipeline.Configuration,
        box: PipelineBox
    ) -> CGImage? {
        guard stride > 0 else { return nil }
        // Last step included on purpose: at that point the denoised latents *are* the final
        // picture, so the preview lands on the real result instead of stopping a few steps short.
        let isLast = progress.step == progress.stepCount - 1
        guard isLast || (progress.step + 1) % stride == 0 else { return nil }
        // Skipped at *elevated* too, not only critical: a preview's decoder spike on top of a
        // resident UNet is exactly the allocation that turns "running low" into being killed.
        guard MemoryBudget.pressure == .normal else { return nil }
        return try? box.pipeline
            .decodeToImages(progress.currentLatentSamples, configuration: config)
            .compactMap { $0 }
            .first
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
