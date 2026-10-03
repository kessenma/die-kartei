#if os(macOS)
import CoreGraphics
import Foundation
import KarteiDiffusion
import MLX
import os

// MAC-PICTURES: the Mac's MLX picture engine (docs/MAC_PICTURES.md).

/// Draws with Z-Image Turbo or FLUX.2 klein through the vendored engine (`KarteiDiffusion`).
///
/// It sits behind `StoryImageService`, whose `loadPipeline` / `generateImage` / `unloadPipeline`
/// hand over here when `ImageGenModel.current.engine == .mlx`, so the deck and story illustrators
/// don't know which engine drew. Same contract as the Core ML pipeline: one picture at a time,
/// written as a PNG to the destination, stopped through the caller's cancel flag.
@Observable
@MainActor
final class MacDiffusionService {
    static let shared = MacDiffusionService()

    private let logger = Logger(subsystem: "com.germanflashcards", category: "MacDiffusion")

    /// The model in memory, if any.
    private(set) var loadedModel: ImageGenModel?
    private var box: EngineBox?
    /// Off after a memory warning, for the rest of the run: a preview is one more decode.
    private var previewsAllowed = true

    /// Memory Diagnostics already counts the drawing model through `StoryImageService`
    /// ("drawingModel", sized by the download), which is close to these models' real footprint.
    private init() {}

    // MARK: Load / unload

    /// Load the model's checkpoint. Weights stay lazy until the first picture, so this is quick.
    func load(_ model: ImageGenModel) async throws {
        if loadedModel == model, box != nil { return }
        unload()
        guard let root = model.resourcesURL else { throw MacDiffusionError.missingFiles }
        let family: FamilyLoader.Family = model == .flux2Klein ? .flux2Klein4B : .zImageTurbo

        MemorySaver.markRuntimeReady()
        // MemorySaver caps MLX at the tutors' budget (RAM/2 on a Mac). A picture needs more, so the
        // run gets the drawing budget instead; `unload` puts the tutors' cap back.
        Memory.memoryLimit = MacPictureSizing.deviceBudgetMB * 1_048_576
        Memory.cacheLimit = 256 * 1_048_576

        let loaded = try await Task.detached(priority: .userInitiated) {
            EngineBox(model: try FamilyLoader.load(family, modelPath: root))
        }.value
        box = loaded
        loadedModel = model
        previewsAllowed = true
        MemoryDiagnostics.record(.pipelineLoaded, title: "Loaded the drawing model · \(model.displayName)")
    }

    func unload() {
        guard box != nil else { return }
        box = nil
        loadedModel = nil
        MemorySaver.releaseCaches()
        MemorySaver.applyAllocatorLimits(for: nil)
        MemoryDiagnostics.record(.pipelineUnloaded, title: "Unloaded the drawing model")
    }

    /// A memory warning mid-run: give back MLX's cache and skip previews, but keep drawing.
    /// (A critical one stops the run, through `StoryImageService.stopForMemoryPressure`.)
    func shed() {
        previewsAllowed = false
        Memory.clearCache()
    }

    // MARK: Drawing

    /// Draw one picture and write it as a PNG to `destination`. Returns false when stopped.
    ///
    /// `purpose` and the quality tier pick the size (`MacPictureSizing`); the memory budget can
    /// lower it. The prompt reader stays in memory only when the budget has room for it at this
    /// size; otherwise it's released after encoding and read back from disk for the next picture,
    /// which costs a second or two against a 10–60 s picture.
    func generate(
        prompt: String,
        purpose: MacPictureSizing.Purpose,
        seed: UInt32,
        saveTo destination: URL,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void,
        onPreview: (@MainActor @Sendable (CGImage) -> Void)?
    ) async throws -> Bool {
        guard let box, let model = loadedModel else { return false }
        let budget = MacPictureSizing.deviceBudgetMB
        guard let size = MacPictureSizing.size(model, purpose: purpose, tier: .current, budgetMB: budget) else {
            throw MacDiffusionError.notEnoughMemory(model)
        }
        let keepPromptReader = MacPictureSizing.residentPeakMB(model, size: size) <= budget
        let steps = MacPictureSizing.steps(model)
        let preview = previewsAllowed ? onPreview : nil
        let started = Date()

        let written = try await Task.detached(priority: .userInitiated) {
            try box.draw(
                prompt: prompt, size: size, steps: steps, seed: Int(seed), model: model,
                keepPromptReader: keepPromptReader, destination: destination,
                isCancelled: isCancelled, onProgress: onProgress, onPreview: preview
            )
        }.value
        if written {
            MacPictureTiming.record(Date().timeIntervalSince(started), model: model, size: size)
        }
        return written
    }
}

enum MacDiffusionError: LocalizedError {
    case missingFiles
    case notEnoughMemory(ImageGenModel)

    var errorDescription: String? {
        switch self {
        case .missingFiles:
            "The picture model's files are missing. Download it again in Settings."
        case .notEnoughMemory(let model):
            "This Mac doesn't have the memory for \(model.displayName). Pick a smaller picture model in Settings."
        }
    }
}

/// The engine is not Sendable; exactly one picture is drawn at a time (the MainActor service
/// awaits each one), so handing it to a background task is safe.
nonisolated private final class EngineBox: @unchecked Sendable {
    let model: FamilyModel

    init(model: FamilyModel) { self.model = model }

    func draw(
        prompt: String, size: Int, steps: Int, seed: Int, model kind: ImageGenModel,
        keepPromptReader: Bool, destination: URL,
        isCancelled: @Sendable () -> Bool,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void,
        onPreview: (@MainActor @Sendable (CGImage) -> Void)?
    ) throws -> Bool {
        // Z-Image always decodes in tiles (it costs nothing measurable and keeps 1024 px at the
        // 512 px peak); klein ignores it. The prompt reader goes only when memory is short.
        model.lowRam = true
        model.releasesPromptReader = !keepPromptReader
        try model.encode(prompt)
        model.promptsEncoded()

        let request = FamilyRequest(
            prompt: prompt, seed: seed, width: size, height: size, steps: steps,
            guidance: kind == .flux2Klein ? 1 : 0, flattenAlpha: true
        )
        let image: GeneratedImage
        do {
            if let onPreview, let previewing = model as? PreviewingFamilyModel {
                image = try previewing.generate(
                    request, phase: { _ in },
                    progress: { step, total in Self.report(step, total, onProgress) },
                    preview: { preview in
                        guard let cg = try? ImageOutput.cgImage(from: preview.pixels) else { return }
                        Task { @MainActor in onPreview(cg) }
                    },
                    isCancelled: isCancelled
                )
            } else {
                image = try model.generate(
                    request, phase: { _ in },
                    progress: { step, total in Self.report(step, total, onProgress) },
                    isCancelled: isCancelled
                )
            }
        } catch GenerationError.cancelled {
            return false
        }
        if isCancelled() { return false }

        // Written beside the destination and moved into place, so iCloud file sync never picks
        // up half a PNG.
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent(".drawing-\(UUID().uuidString).png")
        try ImageOutput.writePNG(
            image.pixels, to: staged, source: .trainedAlgorithmicMedia,
            metadata: ["prompt": prompt, "model": kind.rawValue, "seed": seed, "size": size]
        )
        if let finished = try? ImageOutput.cgImage(from: image.pixels), let onPreview {
            Task { @MainActor in onPreview(finished) }
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
        Memory.clearCache()
        return true
    }

    /// Steps map to 0–95 %; the decode is the rest.
    private static func report(_ step: Int, _ total: Int, _ onProgress: @escaping @MainActor @Sendable (Double) -> Void) {
        let fraction = 0.95 * Double(step) / Double(max(total, 1))
        Task { @MainActor in onProgress(fraction) }
    }
}
#endif
