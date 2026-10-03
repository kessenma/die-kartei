import CoreGraphics
import Foundation

/// One picture, described for both kinds of model. The on-device pipeline reads the Stable
/// Diffusion half (CLIP-sized keyword prompt, negative prompt, seed, steps); a cloud model reads
/// `cloudPrompt`, a plain-English instruction, plus any reference pictures.
struct PictureRequest {
    var sdPrompt: String
    var sdNegative: String = ImageGenConstants.negativePrompt
    var cloudPrompt: String
    /// Earlier pictures to keep the look consistent with (a story's first picture). Cloud only;
    /// trimmed to what the model accepts.
    var references: [URL] = []
    var seed: UInt32? = nil
    var stepCount: Int? = nil
    /// Long edge of the saved file for cloud pictures (`CloudPictureWriter`). The on-device
    /// model draws at its native 512 regardless.
    var maxPixel: Int = CloudPictureWriter.cardMaxPixel
}

/// A run of pictures on one source, fixed when the run starts: switching the source in Settings
/// mid-run takes effect on the next run, never halfway through a deck.
///
/// Every illustration path opens one with `StoryImageService.beginSession(unloading:)`, draws,
/// and calls `end()`. On-device that is the old unload-the-tutor / load-the-pipeline / unload
/// dance; in the cloud there is nothing to load and the tutor stays where it is.
@MainActor
final class PictureSession {
    enum Backend {
        case onDevice
        case cloud(model: CloudImageModel, apiKey: String)
    }

    let backend: Backend
    private unowned let service: StoryImageService
    /// Dollars OpenRouter reported for this run's pictures.
    private(set) var cost: Double = 0
    private(set) var picturesDrawn = 0

    fileprivate init(service: StoryImageService, backend: Backend) {
        self.service = service
        self.backend = backend
    }

    var isCloud: Bool {
        if case .cloud = backend { return true }
        return false
    }

    /// How many pictures a cloud run keeps in flight. Each card has its own prompt, so it's one
    /// request per picture, but nothing makes them wait for each other: eight at once draws a
    /// 20-card deck in about the time of three Muse pictures, and stays far under OpenRouter's
    /// per-model limit (Muse: 100 requests a minute). A rate limit is retried, not dropped.
    static let cloudParallelism = 8

    /// How many pictures to draw at once. The on-device pipeline is a single model in memory; a
    /// cloud model is a web request.
    var parallelism: Int { isCloud ? Self.cloudParallelism : 1 }

    /// Draw one picture to `destination`. Returns false when nothing was written because the
    /// learner stopped (or the on-device pipeline is gone). Throws `OpenRouterError` for a
    /// cloud failure; check `stopsRun` to decide whether the next picture is worth trying.
    func draw(
        _ request: PictureRequest,
        saveTo destination: URL,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void,
        onPreview: (@MainActor @Sendable (CGImage) -> Void)? = nil
    ) async throws -> Bool {
        switch backend {
        case .onDevice:
            let written = try await service.generateImage(
                prompt: request.sdPrompt,
                negativePrompt: request.sdNegative,
                saveTo: destination,
                stepCount: request.stepCount,
                seed: request.seed,
                onStepProgress: onProgress,
                onPreview: onPreview
            )
            if written { picturesDrawn += 1 }
            return written

        case .cloud(let model, let apiKey):
            let image = try await drawInCloud(
                request, model: model, apiKey: apiKey, destination: destination, onProgress: onProgress
            )
            guard let image else { return false }
            model.hasDrawnBefore = true
            picturesDrawn += 1
            onProgress(1)
            onPreview?(image)
            return true
        }
    }

    /// End the run: frees the on-device pipeline; a cloud run has nothing to give back.
    func end() {
        if case .onDevice = backend { service.unloadPipeline() }
    }

    // MARK: - Cloud

    private func drawInCloud(
        _ request: PictureRequest,
        model: CloudImageModel,
        apiKey: String,
        destination: URL,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let references = request.references.prefix(model.maxReferences)
            .compactMap { try? Data(contentsOf: $0) }
        let prompt = request.cloudPrompt
        let user = OpenRouterAccount.userTag

        // Neither model streams, so the bar runs on the clock: it eases toward 90% around the
        // model's typical wait and jumps to done when the picture lands.
        let expected = model.typicalSeconds
        let ticker = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start) / expected
                onProgress(0.9 * (1 - exp(-1.5 * t)))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { ticker.cancel() }

        let id = UUID()
        let work = Task.detached(priority: .userInitiated) { () throws -> CGImage in
            let picture = try await OpenRouterClient(apiKey: apiKey)
                .generateImage(model: model, prompt: prompt, references: Array(references), user: user)
            try Task.checkCancellation()
            let image = try CloudPictureWriter.write(picture.bytes, maxPixel: request.maxPixel, to: destination)
            await MainActor.run { [weak self] in self?.cost += picture.cost ?? 0 }
            return image
        }
        service.cloudRequests[id] = { work.cancel() }
        defer { service.cloudRequests[id] = nil }

        do {
            return try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
        } catch is CancellationError {
            return nil
        } catch OpenRouterError.needsAgeConfirmation {
            model.hasDrawnBefore = false
            throw OpenRouterError.needsAgeConfirmation
        } catch OpenRouterError.unauthorized {
            OpenRouterAccount.shared.handleUnauthorized()
            throw OpenRouterError.unauthorized
        }
    }
}

extension StoryImageService {
    /// Start a picture run on the current source. Returns nil, with `loadError` set, when that
    /// source can't draw: the on-device model isn't downloaded or won't load, or no OpenRouter
    /// key is stored.
    ///
    /// On-device, the tutor is unloaded first: the language model and the diffusion pipeline
    /// don't fit together on 6 GB devices. Cloud pictures leave it loaded, which is what lets a
    /// story go straight on to grading and translation without a reload.
    func beginSession(unloading mlxService: MLXGenerationService?) async -> PictureSession? {
        switch PictureSource.current {
        case .onDevice:
            mlxService?.unloadModel()
            guard await loadPipeline() else { return nil }
            return PictureSession(service: self, backend: .onDevice)
        case .cloud:
            guard let key = OpenRouterAccount.apiKey() else {
                loadError = OpenRouterError.notConnected.errorDescription
                return nil
            }
            loadError = nil
            return PictureSession(service: self, backend: .cloud(model: .current, apiKey: key))
        }
    }
}
