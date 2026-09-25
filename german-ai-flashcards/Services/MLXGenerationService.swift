import Foundation
import os
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

// MARK: - Hub Cache Helpers

extension MLXModel {
    /// Whether this model is ready to use. For the built-in Apple model there is nothing to
    /// download — "ready" means Apple Intelligence is currently available on this device.
    var isDownloaded: Bool {
        if self == .appleIntelligence { return AppleIntelligenceService.currentlyAvailable() }
        return HubCacheLocation.isDownloaded(repoID: configuration.name)
    }

    /// Disk size of the cached model in bytes, or nil if not downloaded.
    /// The built-in Apple model uses no app-managed storage, so it reports nil (excluded from the
    /// storage breakdown).
    var cachedSizeBytes: Int64? {
        if self == .appleIntelligence { return nil }
        return HubCacheLocation.cachedSizeBytes(repoID: configuration.name)
    }

    /// Delete the cached model from the HuggingFace Hub cache, along with any partially
    /// downloaded files a resumable download left behind.
    func deleteFromCache() throws {
        if self == .appleIntelligence { return }   // built-in model — nothing to delete
        try HubCacheLocation.delete(repoID: configuration.name)
    }

    /// Bytes an interrupted download of this model already holds safely on disk — completed
    /// files in the hub cache plus the in-flight file's partial. 0 once fully downloaded (or
    /// for the built-in model), so non-zero means "there's a download to resume". Walks the
    /// cache directory; don't call it on every progress tick.
    var pausedDownloadBytes: Int64 {
        if self == .appleIntelligence || isDownloaded { return 0 }
        let cached = HubCacheLocation.cachedSizeBytes(repoID: configuration.name) ?? 0
        let partials = HubCacheLocation.directorySize(
            ResumableModelDownloader.partialsDirectory(forRepo: configuration.name)
        )
        return cached + partials
    }
}

// MARK: - Background download continuation

/// Finishes an interrupted model download while the app is woken in the *background* for
/// URLSession events: each completed file gets committed and the next file's transfer
/// enqueued, so the whole model can land — and post its "ready to use offline" notification —
/// without the user ever reopening the app. Stopped the moment the app becomes active, where
/// `MLXGenerationService.resumeInterruptedDownloadIfNeeded()` takes over: two drivers on the
/// same repo would race each other's partials.
@MainActor
enum BackgroundDownloadResumer {
    private static var task: Task<Void, Never>?

    /// Kick from the app delegate's background-session wake. No-op unless a download is on
    /// record as unfinished.
    static func kickIfNeeded() {
        guard task == nil,
              let raw = UserDefaults.standard.string(forKey: MLXGenerationService.downloadInFlightKey),
              let model = MLXModel(rawValue: raw),
              model != .appleIntelligence,
              !model.isDownloaded
        else { return }
        task = Task {
            defer { task = nil }
            try? await ResumableModelDownloader().download(repoID: model.configuration.name) { _, _ in }
            guard !Task.isCancelled, model.isDownloaded else { return }
            UserDefaults.standard.removeObject(forKey: MLXGenerationService.downloadInFlightKey)
            await ModelDownloadNotificationService.notifyDownloadFinished(modelName: model.displayName)
        }
    }

    /// Cancel and wait for the driver to fully unwind — its in-flight segment lands as resume
    /// data first — so a foreground resume can safely start the moment this returns.
    static func stop() async {
        task?.cancel()
        await task?.value
        task = nil
    }
}

// MARK: - Codable types for JSON deserialization from MLX output

struct CodableConjugation: Codable {
    let tense: String
    let ich: String
    let du: String
    let erSieEs: String
    let wir: String
    let ihr: String
    let sieSie: String

    func toConjugation() -> Conjugation {
        Conjugation(
            tense: tense, ich: ich, du: du,
            erSieEs: erSieEs, wir: wir, ihr: ihr, sieSie: sieSie
        )
    }

    /// Remove pronoun prefixes that a model may include in conjugation values.
    /// e.g. "ich unterrichte" → "unterrichte", "er/sie/es unterrichtet" → "unterrichtet"
    func strippingPronouns() -> CodableConjugation {
        CodableConjugation(
            tense: tense,
            ich: stripPrefix(ich, prefixes: ["ich "]),
            du: stripPrefix(du, prefixes: ["du "]),
            erSieEs: stripPrefix(erSieEs, prefixes: ["er/sie/es ", "er ", "sie ", "es "]),
            wir: stripPrefix(wir, prefixes: ["wir "]),
            ihr: stripPrefix(ihr, prefixes: ["ihr "]),
            sieSie: stripPrefix(sieSie, prefixes: ["sie/Sie ", "sie ", "Sie "])
        )
    }

    private func stripPrefix(_ value: String, prefixes: [String]) -> String {
        for prefix in prefixes {
            if value.lowercased().hasPrefix(prefix.lowercased()) {
                return String(value.dropFirst(prefix.count))
            }
        }
        return value
    }
}

struct CodableVocabCard: Codable {
    let germanWord: String
    let englishTranslation: String
    let wordType: String?
    let article: String?
    let exampleSentence: String?
    let conjugations: [CodableConjugation]?

    enum CodingKeys: String, CodingKey {
        case germanWord, englishTranslation, wordType, article, exampleSentence, conjugations
    }

    init(from decoder: any Swift.Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.germanWord = try container.decode(String.self, forKey: .germanWord)
        self.englishTranslation = try container.decode(String.self, forKey: .englishTranslation)
        self.wordType = try container.decodeIfPresent(String.self, forKey: .wordType)
        self.article = try container.decodeIfPresent(String.self, forKey: .article)
        self.exampleSentence = try container.decodeIfPresent(String.self, forKey: .exampleSentence)

        // Handle three conjugation formats models produce:
        // 1. Array:      [{"tense":"Präsens","ich":"lerne",...}]
        // 2. Dict:       {"Präsens":{"ich":"lebe",...}}
        // 3. Flat obj:   {"tense":"Präsens","ich":"lerne",...}
        if let array = try? container.decodeIfPresent([CodableConjugation].self, forKey: .conjugations) {
            self.conjugations = array.map { $0.strippingPronouns() }
        } else if let dict = try? container.decodeIfPresent([String: ConjugationForms].self, forKey: .conjugations) {
            self.conjugations = dict.map { tense, forms in
                CodableConjugation(
                    tense: tense,
                    ich: forms.ich, du: forms.du,
                    erSieEs: forms.erSieEs, wir: forms.wir,
                    ihr: forms.ihr, sieSie: forms.sieSie
                ).strippingPronouns()
            }
        } else if let flat = try? container.decodeIfPresent(CodableConjugation.self, forKey: .conjugations) {
            self.conjugations = [flat.strippingPronouns()]
        } else {
            self.conjugations = nil
        }
    }

    func toVocabCard() -> VocabCard {
        VocabCard(
            germanWord: germanWord,
            englishTranslation: englishTranslation,
            wordType: wordType,
            article: article,
            exampleSentence: exampleSentence,
            conjugations: conjugations?.map { $0.toConjugation() }
        )
    }
}

/// Helper for decoding the dictionary-style conjugation format: {"ich":"lebe","du":"lebst",...}
struct ConjugationForms: Codable {
    let ich: String
    let du: String
    let erSieEs: String
    let wir: String
    let ihr: String
    let sieSie: String
}

struct CodableVocabCardResponse: Codable {
    let cards: [CodableVocabCard]
}

// MARK: - Errors

enum MLXError: LocalizedError {
    case modelNotLoaded
    case generationTimedOut
    case jsonExtractionFailed(rawOutput: String)
    case jsonDecodingFailed(extractedJSON: String, decodingError: String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "Model not loaded. Please load the model first in Settings."
        case .generationTimedOut:
            "The model stopped responding. It may be busy or stuck."
        case .jsonExtractionFailed(let rawOutput):
            "Could not find JSON in model output. Raw output:\n\(String(rawOutput.prefix(500)))"
        case .jsonDecodingFailed(let json, let decodingError):
            "JSON decode error: \(decodingError)\n\nExtracted JSON:\n\(String(json.prefix(500)))"
        }
    }
}

// MARK: - Generation stall watchdog

/// Records when a streaming generation last made progress (a token arrived). Main-actor confined,
/// so the streaming task and the watchdog can share it without a data race — they interleave
/// cooperatively on the main actor rather than running in parallel.
@MainActor
final class GenerationActivity {
    private(set) var lastProgress = Date()
    func recordProgress() { lastProgress = Date() }
    var idleSeconds: TimeInterval { Date().timeIntervalSince(lastProgress) }
}

/// What a card batch has produced so far, kept *outside* the decode task so a stall that cancels
/// the task still leaves the partial output for the salvage parse. Main-actor confined for the
/// same reason as `GenerationActivity`.
@MainActor
private final class PartialOutput {
    var text = ""
    var tokenCount = 0
    var exitedEarly = false
}

// MARK: - MLX Generation Service

@Observable
@MainActor
class MLXGenerationService {
    var isModelLoaded = false
    var isLoading = false
    var loadError: String?
    private(set) var currentModel: MLXModel?

    /// The model currently loaded in memory, or `nil` if none is ready. Drives per-model brand
    /// theming (`MLXModel.theme`) on screens that should pick up the active model's colors —
    /// the Create screen and the nav bar. `currentModel` can be non-nil mid-load, so gate on
    /// `isModelLoaded` to only theme once the model is actually ready.
    var loadedModel: MLXModel? { isModelLoaded ? currentModel : nil }

    /// Download progress (0.0–1.0). `nil` means indeterminate (connecting/preparing).
    var downloadProgress: Double?
    /// Short status label shown next to the spinner (e.g. "Downloading Gemma…").
    var downloadInfo: String?
    /// Byte-count string shown trailing below the progress bar (e.g. "1.3 GB / 2.62 GB").
    var downloadBytesInfo: String?
    /// When the current load started, for elapsed-time display.
    var loadStartTime: Date?

    /// Token count within the currently-streaming batch. Resets to 0 at the start of each batch.
    /// Observed by the UI to smooth the progress bar within a batch.
    var streamingTokenCount: Int = 0
    /// Set to true by the coordinator when the user taps Stop; checked in the token loop.
    var isStopRequested: Bool = false
    /// True after generateCards() returns if the batch exited early (timeout or stop).
    /// The coordinator uses this to decide whether to break the batch loop.
    var lastBatchEndedEarly: Bool = false

    private var modelContainer: ModelContainer?
    /// Backend for the built-in Apple on-device model (`.appleIntelligence`). The four generation
    /// methods delegate to this when that model is selected; everything else stays on MLX.
    let appleService = AppleIntelligenceService()
    private var loadTask: Task<Void, Never>?
    /// Model whose download was cut off by a network drop or app suspension. Partial files stay
    /// on disk, so `resumeInterruptedDownloadIfNeeded()` (called when the app returns to the
    /// foreground) picks up exactly where the transfer stopped.
    private(set) var interruptedDownloadModel: MLXModel?

    /// Generations in flight right now. Memory eviction waits for zero — freeing weights out from
    /// under a live decode saves nothing (the running task holds its own reference) and costs the
    /// learner a reload for a reply that was already on its way.
    private var activeGenerations = 0

    /// A generation is in flight on the loaded model (a chat reply, a story, the batch queue). A
    /// second writer checks this before it starts, so two never share one model.
    var isGenerating: Bool { activeGenerations > 0 }

    /// A model the *app* dropped to stay alive — a background eviction or a memory warning — as
    /// opposed to one the user unloaded on purpose. Whoever was using it reloads it on return
    /// rather than leaving the learner tapping Send at a model that isn't there any more.
    /// Cleared by the next successful load, and by `unloadModel()` (a deliberate unload is not
    /// something to undo behind the user's back).
    private(set) var evictedModel: MLXModel?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "de.germanflashcards", category: "ModelLoad")
    private let genLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "de.germanflashcards", category: "Generation")

    init() {
        // The weights are nearly all of what this app ever holds; name them in the memory
        // breakdown (Settings ▸ Speicher). MLX's active buffers are the loaded model plus any live
        // KV cache, and nothing else in the app allocates through MLX.
        MemoryDiagnostics.register(
            "tutor",
            name: { [weak self] in
                guard let self, let model = self.loadedModel else { return "Tutor" }
                return "Tutor · \(model.rawValue)"
            },
            bytes: { [weak self] in
                self?.isModelLoaded == true && MemorySaver.mlxRuntimeReady ? Memory.activeMemory : 0
            }
        )
    }

    /// Physical memory footprint of this process in MB — `phys_footprint`, what jetsam measures.
    private func memFootprintMB() -> Int { MemoryBudget.footprintMB }

    /// How long a card batch may go without a single token before it's declared stuck. Longer
    /// than the chat watchdog: the prompt carries every word already generated, so prefill on a
    /// governed device can take a while before the first token lands.
    private static let cardStallTimeout: Double = 90

    /// Generation parameters with the memory governors applied. Every generation path builds its
    /// parameters through here, so a model running over this device's budget stays bounded no
    /// matter which feature started the run. A no-op when Memory Saver isn't active.
    private func tunedParameters(maxTokens: Int, temperature: Float) -> GenerateParameters {
        var parameters = GenerateParameters(maxTokens: maxTokens, temperature: temperature)
        MemorySaver.tune(&parameters, for: currentModel)
        return parameters
    }

    /// How often the token loops check headroom. Cheap enough to do often, rare enough not to
    /// show up in generation speed.
    private static let memoryCheckInterval = 32

    /// True when the run should stop to stay inside the memory budget. Callers keep whatever text
    /// they already have — an answer that ends early beats the app being killed mid-sentence.
    private func shouldStopForMemory(at tokenCount: Int) -> Bool {
        guard tokenCount > 0, tokenCount % Self.memoryCheckInterval == 0 else { return false }
        return MemoryPressureMonitor.shared.sample(model: currentModel)
    }

    /// Load a model into memory. Downloads from HuggingFace Hub on first use.
    func loadModel(_ model: MLXModel) async {
        guard !isLoading else { return }
        guard !isModelLoaded || currentModel != model else { return }

        // One heavy resident at a time. A running generation holds its own reference to the
        // container, so dropping ours below frees nothing — a second model would load on top of
        // the first, which on an 8 GB device is the app being killed. Same for the drawing model:
        // every illustrate path unloads the tutor before the pipeline loads, and this is the
        // matching guard in the other direction.
        if activeGenerations > 0, currentModel != model {
            loadError = "The tutor is still answering. Try again in a moment."
            return
        }
        if StoryImageService.shared.isBusy {
            loadError = "Pictures are being drawn right now. The tutor loads once they finish."
            return
        }

        // Unload previous model if switching
        if currentModel != model {
            modelContainer = nil
            isModelLoaded = false
        }

        // Apple's built-in model: no download and no MLX container — just verify availability.
        if model == .appleIntelligence {
            isLoading = true
            loadError = nil
            downloadProgress = nil
            downloadInfo = nil
            downloadBytesInfo = nil
            if appleService.isAvailable {
                currentModel = .appleIntelligence
                isModelLoaded = true
                evictedModel = nil
                lastBatchEndedEarly = false
            } else {
                isModelLoaded = false
                loadError = appleService.unavailableReason ?? "Apple Intelligence isn't available."
            }
            isLoading = false
            return
        }

        // The live budget, on every path — not just the Settings screen's memory check. Seventeen
        // call sites auto-load without asking; on a device the model doesn't fit, each of them was
        // a jetsam waiting to happen. "Use it anyway" in Settings ▸ Model & Downloads is the one
        // door through, and it stays open.
        if MemoryBudget.isOverBudget(model), !MemorySaver.allowsOversizedModels {
            let needs = MemoryBudget.formattedGB(MemoryBudget.requiredMB(for: model) + MemoryBudget.reserveMB)
            let has = MemoryBudget.formattedGB(MemoryBudget.totalMB)
            loadError = "\(model.displayName) needs about \(needs) of memory and this device gives the app \(has). Choose it under Settings ▸ Model & Downloads to run it anyway."
            logger.warning("[\(model.rawValue, privacy: .public)] Load refused — over budget (needs \(needs, privacy: .public), budget \(has, privacy: .public)) and the oversized opt-in is off")
            return
        }

        isLoading = true
        loadError = nil
        downloadProgress = nil  // nil = indeterminate until first progress callback
        downloadInfo = model.isDownloaded
            ? "Loading \(model.displayName) from storage…"
            : "Connecting to Hugging Face…"
        loadStartTime = Date()

        let physicalMB = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        let footprintBefore = memFootprintMB()
        let budgetMB = MemoryBudget.totalMB
        let neededMB = MemoryBudget.requiredMB(for: model)
        logger.info("[\(model.rawValue, privacy: .public)] Load started — Device RAM: \(physicalMB, privacy: .public) MB, App budget: \(budgetMB, privacy: .public) MB, App footprint: \(footprintBefore, privacy: .public) MB, Model size: \(model.approximateSizeMB, privacy: .public) MB, Model needs: \(neededMB, privacy: .public) MB, Memory Saver: \(MemorySaver.isActive(for: model), privacy: .public), Already cached: \(model.isDownloaded, privacy: .public)")
        MemoryDiagnostics.record(
            .modelLoadStart,
            title: "Loading \(model.rawValue)",
            detail: "Needs about \(neededMB) MB of a \(budgetMB) MB budget · Memory Saver \(MemorySaver.isActive(for: model) ? "on" : "off") · \(model.isDownloaded ? "from storage" : "downloading first")"
        )

        // Start from as much headroom as we can get: drop MLX's reuse cache before pulling several
        // GB of weights in, and size the allocator for what this model costs on this device.
        // This is the process's first MLX call, so the runtime gate opens here (never in the sim).
        MemorySaver.markRuntimeReady()
        MemorySaver.releaseCaches()
        MemorySaver.applyAllocatorLimits(for: model)
        MemoryPressureMonitor.shared.startMonitoring()
        MemoryPressureMonitor.shared.onCriticalPressure = { [weak self] in
            self?.releaseMemory(reason: .pressure)
        }

        let task = Task {
            do {
                try Task.checkCancellation()

                // Not cached yet: fetch with the resumable downloader first, so an interrupted
                // transfer keeps its bytes on disk and the next attempt continues mid-file.
                // Progress here is byte-accurate (from the repo's true file sizes).
                if !model.isDownloaded {
                    await ModelDownloadNotificationService.requestAuthorizationIfNeeded()

                    // Survives the process: if iOS terminates the app mid-download (switching
                    // to a heavy app is enough), the next launch — or a background wake —
                    // resumes from the saved partials instead of starting over.
                    UserDefaults.standard.set(model.rawValue, forKey: Self.downloadInFlightKey)

                    try await ResumableModelDownloader().download(
                        repoID: model.configuration.name
                    ) { [self] downloaded, total in
                        guard self.isLoading else { return }
                        self.downloadInfo = "Downloading \(model.displayName)…"
                        self.downloadBytesInfo = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
                            + " / " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                        if total > 0 {
                            self.downloadProgress = Double(downloaded) / Double(total)
                        }
                    }
                    UserDefaults.standard.removeObject(forKey: Self.downloadInFlightKey)
                    await ModelDownloadNotificationService.notifyDownloadFinished(modelName: model.displayName)
                }

                try Task.checkCancellation()
                downloadProgress = nil
                downloadBytesInfo = nil
                downloadInfo = "Loading \(model.displayName) into memory…"

                // Survives the process, so a load that gets the app killed is visible on the next
                // launch (see `takeInterruptedLoad()`) instead of silently repeating. Set only for
                // the in-memory phase: dying during the *download* is a lifecycle event handled by
                // `downloadInFlightKey` above, not a memory verdict.
                UserDefaults.standard.set(model.rawValue, forKey: Self.loadInFlightKey)

                // Everything is in the hub cache now, so this resolves without downloading.
                let container = try await LLMModelFactory.shared.loadContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: model.configuration
                ) { _ in }

                try Task.checkCancellation()
                modelContainer = container
                currentModel = model
                isModelLoaded = true
                evictedModel = nil
                interruptedDownloadModel = nil
                let footprintAfter = memFootprintMB()
                logger.info("[\(model.rawValue, privacy: .public)] Loaded successfully — App footprint: \(footprintAfter, privacy: .public) MB")
                MemoryDiagnostics.record(.modelLoaded, title: "Loaded \(model.rawValue)")
            } catch is CancellationError {
                loadError = nil
                logger.info("[\(model.rawValue, privacy: .public)] Load cancelled by user")
            } catch let error as URLError where error.code == .cancelled {
                loadError = nil
                logger.info("[\(model.rawValue, privacy: .public)] Load cancelled by user")
            } catch {
                let footprintOnError = memFootprintMB()
                logger.error("[\(model.rawValue, privacy: .public)] Load FAILED — footprint: \(footprintOnError, privacy: .public) MB, error: \(error.localizedDescription, privacy: .public), raw: \(String(describing: error), privacy: .public)")
                MemoryDiagnostics.record(.modelLoadFailed, title: "Couldn't load \(model.rawValue)", detail: error.localizedDescription)
                if Self.isNetworkInterruption(error), !model.isDownloaded {
                    interruptedDownloadModel = model
                    loadError = "Download interrupted — progress is saved. It resumes automatically, or select the model again."
                } else {
                    // Not resumable (bad repo, HTTP error, disk) — don't let the next launch
                    // auto-retry a download that will fail the same way.
                    UserDefaults.standard.removeObject(forKey: Self.downloadInFlightKey)
                    loadError = "Failed to load model: \(error.localizedDescription)"
                }
                isModelLoaded = false
            }

            // Reached on success, failure, and cancellation alike — anything but the app dying.
            UserDefaults.standard.removeObject(forKey: Self.loadInFlightKey)

            downloadProgress = nil
            downloadInfo = nil
            downloadBytesInfo = nil
            loadStartTime = nil
            isLoading = false
            loadTask = nil
        }
        loadTask = task
        await task.value
    }

    // MARK: - Interrupted loads

    private static let loadInFlightKey = "modelLoadInFlight"
    /// Set while the resumable downloader is fetching a model; cleared when the download
    /// completes, the user cancels, or the model is deleted. Unlike `interruptedDownloadModel`
    /// it survives the process, so a download the app *died* holding resumes on relaunch —
    /// and can be pushed forward by a background wake (`BackgroundDownloadResumer`).
    fileprivate static let downloadInFlightKey = "modelDownloadInFlight"

    /// A model whose load was still running when the app last stopped — which, for a model that
    /// runs over this device's budget, usually means iOS killed the app for memory. Read once at
    /// launch so the UI can offer something that fits instead of walking into the same wall.
    /// Reading it clears it.
    static func takeInterruptedLoad() -> MLXModel? {
        guard let raw = UserDefaults.standard.string(forKey: loadInFlightKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: loadInFlightKey)
        return MLXModel(rawValue: raw)
    }

    /// True for failures where the transfer stopped but saved partial files can resume it
    /// (connection drops, timeouts, app suspension killing the socket).
    private static func isNetworkInterruption(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case ModelDownloadError.incompleteTransfer = error { return true }
        return false
    }

    /// Call when the app becomes active: if a download was cut off while the user was away —
    /// including by iOS terminating the app entirely — restart it. Completed files are
    /// skipped and the interrupted file resumes from its partial (plus any saved resume
    /// data), so this costs seconds, not gigabytes.
    func resumeInterruptedDownloadIfNeeded() {
        guard !isLoading else { return }
        var candidate = interruptedDownloadModel
        if candidate == nil, let raw = UserDefaults.standard.string(forKey: Self.downloadInFlightKey) {
            // The app died mid-download; only the on-disk flag remembers.
            candidate = MLXModel(rawValue: raw)
            if candidate == nil {
                UserDefaults.standard.removeObject(forKey: Self.downloadInFlightKey)
            }
        }
        guard let model = candidate else { return }
        interruptedDownloadModel = nil
        if model.isDownloaded {
            // A background wake finished it while the user was away — nothing to fetch, and
            // loading multi-GB weights into memory stays the user's call.
            UserDefaults.standard.removeObject(forKey: Self.downloadInFlightKey)
            return
        }
        Task { await loadModel(model) }
    }

    /// Cancel an in-progress model load/download. Downloaded bytes stay on disk (completed
    /// files in the hub cache, the in-flight file as a partial), so selecting the model again
    /// continues where this left off. Cancelling is explicit, so no auto-resume.
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        interruptedDownloadModel = nil
        UserDefaults.standard.removeObject(forKey: Self.downloadInFlightKey)
        downloadProgress = nil
        downloadInfo = nil
        loadStartTime = nil
        isLoading = false
        loadError = nil
    }

    /// Drop the loaded model from memory but keep its files on disk. Callers that need the
    /// LLM later (grading, translation, chat) reload lazily through their existing
    /// ensureModelReady-style guards. Used to make room for the Stable Diffusion pipeline
    /// during story illustration — the two never fit in memory together on 6 GB devices.
    func unloadModel() {
        guard !isLoading else { return }
        let unloaded = currentModel
        modelContainer = nil
        isModelLoaded = false
        currentModel = nil
        evictedModel = nil
        MemorySaver.releaseCaches()
        // Back to the ungoverned allocator settings — a governed model's tight cache limit has no
        // business outliving it.
        MemorySaver.applyAllocatorLimits(for: nil)
        logger.info("Model unloaded — App footprint: \(self.memFootprintMB(), privacy: .public) MB")
        if let unloaded {
            MemoryDiagnostics.record(.modelUnloaded, title: "Unloaded \(unloaded.rawValue)")
        }
    }

    // MARK: - Memory eviction

    /// Why the app is giving memory back.
    enum EvictionReason: String {
        /// The app left the foreground. iOS ranks a suspended app for termination largely by
        /// footprint, and an app sitting on multi-GB weights is at the front of that queue — so a
        /// trip to Settings to add a keyboard is enough to get it killed and take the open
        /// conversation's in-flight turn with it.
        case background
        /// A `didReceiveMemoryWarning`. Freeing caches alone rarely moves the needle when the
        /// weights are the footprint.
        case pressure
    }

    /// Give memory back, dropping the loaded model when holding it is what's putting the app at
    /// risk. Always safe to call: it no-ops mid-load and mid-generation, and a model with real
    /// headroom on this device is kept (reloading it costs the learner a wait for nothing).
    ///
    /// A model dropped here is remembered in ``evictedModel`` so the screen that was using it can
    /// bring it straight back, instead of the learner discovering it's gone by tapping Send.
    func releaseMemory(reason: EvictionReason) {
        guard !isLoading, activeGenerations == 0 else { return }
        MemorySaver.releaseCaches()

        guard let model = currentModel, isModelLoaded, !model.isAppleIntelligence else { return }
        // A pressure warning means it's already going wrong, so the model goes regardless of fit.
        // Backgrounding only sheds a model this device has no room to spare for — on a device with
        // headroom, coming back to a loaded tutor is worth more than the footprint.
        let mustGo = reason == .pressure
            || MemoryBudget.isOverBudget(model)
            || MemoryBudget.hasSlimHeadroom(model)
        guard mustGo else { return }

        modelContainer = nil
        isModelLoaded = false
        currentModel = nil
        evictedModel = model
        MemorySaver.releaseCaches()
        MemorySaver.applyAllocatorLimits(for: nil)
        logger.notice("[\(model.rawValue, privacy: .public)] Evicted (\(reason.rawValue, privacy: .public)) — App footprint: \(self.memFootprintMB(), privacy: .public) MB")
        MemoryDiagnostics.record(
            .modelEvicted,
            title: "Dropped \(model.rawValue) to stay alive",
            detail: reason == .pressure
                ? "iOS warned that memory was low. The screen using the tutor reloads it on return."
                : "The app went to the background holding a tutor this device has little room for; a suspended app that size is the first one iOS closes."
        )
    }

    /// Whether `model` was dropped by the app and hasn't been brought back yet.
    func wasEvicted(_ model: MLXModel) -> Bool { evictedModel == model && !isModelLoaded }

    /// Forget a pending eviction without reloading — the user moved on.
    func clearEviction() { evictedModel = nil }

    /// Delete a downloaded model from the HuggingFace Hub cache.
    /// If it's the currently loaded model, unloads it first.
    func deleteModel(_ model: MLXModel) throws {
        if currentModel == model {
            modelContainer = nil
            isModelLoaded = false
            currentModel = nil
            MemorySaver.releaseCaches()
            MemorySaver.applyAllocatorLimits(for: nil)
        }
        if UserDefaults.standard.string(forKey: Self.downloadInFlightKey) == model.rawValue {
            UserDefaults.standard.removeObject(forKey: Self.downloadInFlightKey)
        }
        try model.deleteFromCache()
    }

    /// Generate vocab cards using the loaded MLX model.
    /// - Parameters:
    ///   - timeoutSeconds: Per-batch timeout. If the token stream stalls longer than this, the
    ///     batch exits early and whatever tokens arrived are parsed (partial results kept).
    ///   - excludeWords: Words already generated in previous batches, to avoid duplicates.
    func generateCards(
        topic: String,
        count: Int,
        includeExamples: Bool,
        includeGender: Bool,
        wordTypeFilter: WordTypeFilter,
        includeConjugations: Bool,
        selectedTenses: [String],
        model: MLXModel,
        timeoutSeconds: Double = 300,
        excludeWords: [String] = []
    ) async throws -> [VocabCard] {
        // Apple's built-in model has no MLX container: build the same prompt, generate raw text,
        // and reuse the existing tolerant parser. (See AppleIntelligence-CardGeneration-TODO.md
        // for the planned @Generable upgrade.)
        if model == .appleIntelligence {
            guard isModelLoaded, currentModel == model else { throw MLXError.modelNotLoaded }
            let applePrompt = buildJSONPrompt(
                topic: topic,
                count: count,
                includeExamples: includeExamples,
                includeGender: includeGender,
                wordTypeFilter: wordTypeFilter,
                includeConjugations: includeConjugations,
                selectedTenses: selectedTenses,
                excludeWords: excludeWords
            )
            let appleSystem = "You are a German language tutor. Respond ONLY with valid JSON. No markdown fences, no explanation."
            streamingTokenCount = 0
            lastBatchEndedEarly = false
            let raw = try await appleService.generateCardsRaw(system: appleSystem, user: applePrompt)
            print("--- Apple Intelligence raw output ---")
            print(raw)
            print("--- end raw output ---")
            return try parseVocabCards(from: raw)
        }

        guard let container = modelContainer, isModelLoaded, currentModel == model else {
            throw MLXError.modelNotLoaded
        }

        let prompt = buildJSONPrompt(
            topic: topic,
            count: count,
            includeExamples: includeExamples,
            includeGender: includeGender,
            wordTypeFilter: wordTypeFilter,
            includeConjugations: includeConjugations,
            selectedTenses: selectedTenses,
            excludeWords: excludeWords
        )

        let systemPrompt = "You are a German language tutor. Respond ONLY with valid JSON. No markdown fences, no explanation."

        let userMessage = prompt

        print("[MLX:\(model.rawValue)] User prompt:\n\(userMessage)")

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(userMessage)
        ])

        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

        let lmInput = try await container.prepare(input: userInput)
        let parameters = tunedParameters(maxTokens: 4096, temperature: 0.6)

        let footprintBeforeGen = memFootprintMB()
        genLogger.info("[\(model.rawValue, privacy: .public)] Generation start — batch excludeWords=\(excludeWords.count, privacy: .public), count=\(count, privacy: .public), footprint=\(footprintBeforeGen, privacy: .public) MB")

        let stream = try await container.generate(input: lmInput, parameters: parameters)

        streamingTokenCount = 0
        lastBatchEndedEarly = false
        MemoryPressureMonitor.shared.beginRun()
        activeGenerations += 1
        defer { activeGenerations -= 1 }
        let batchStartTime = Date()

        // The batch timeout above only fires when a token arrives. A stream that never yields one
        // used to sit here forever — and with `activeGenerations` pinned above zero, the model
        // could never be evicted either. The same watchdog the chat path uses cancels the decode
        // after `cardStallTimeout` of silence; the partial output survives in `partial`.
        let partial = PartialOutput()
        let activity = GenerationActivity()
        let decode = Task { @MainActor in
            for try await generation in stream {
                try Task.checkCancellation()
                activity.recordProgress()
                if self.isStopRequested {
                    partial.exitedEarly = true
                    break
                }
                if Date().timeIntervalSince(batchStartTime) > timeoutSeconds {
                    let elapsed = Int(Date().timeIntervalSince(batchStartTime))
                    self.genLogger.warning("[\(model.rawValue, privacy: .public)] Batch timeout after \(elapsed, privacy: .public)s (\(partial.tokenCount, privacy: .public) tokens) — attempting partial parse")
                    partial.exitedEarly = true
                    break
                }
                if self.shouldStopForMemory(at: partial.tokenCount) {
                    self.genLogger.warning("[\(model.rawValue, privacy: .public)] Memory floor reached after \(partial.tokenCount, privacy: .public) tokens (available=\(MemoryBudget.availableMB, privacy: .public) MB) — stopping early, parsing what arrived")
                    partial.exitedEarly = true
                    break
                }
                if let chunk = generation.chunk {
                    partial.text += chunk
                    partial.tokenCount += 1
                    if partial.tokenCount % 256 == 0 {
                        let fp = self.memFootprintMB()
                        self.genLogger.info("[\(model.rawValue, privacy: .public)] token=\(partial.tokenCount, privacy: .public) footprint=\(fp, privacy: .public) MB")
                        self.streamingTokenCount = partial.tokenCount
                    }
                }
            }
        }
        do {
            try await value(of: decode, abortingIfIdlePast: Self.cardStallTimeout, tracking: activity)
        } catch MLXError.generationTimedOut {
            genLogger.warning("[\(model.rawValue, privacy: .public)] No token for \(Int(Self.cardStallTimeout), privacy: .public)s (\(partial.tokenCount, privacy: .public) so far) — declaring the batch stuck, parsing what arrived")
            partial.exitedEarly = true
        }
        let fullText = partial.text
        let tokenCount = partial.tokenCount
        let exitedEarly = partial.exitedEarly

        let footprintAfterGen = memFootprintMB()
        genLogger.info("[\(model.rawValue, privacy: .public)] Generation \(exitedEarly ? "interrupted" : "done", privacy: .public) — tokens=\(tokenCount, privacy: .public), footprint=\(footprintAfterGen, privacy: .public) MB, output_chars=\(fullText.count, privacy: .public)")

        if exitedEarly {
            lastBatchEndedEarly = true
            // Try to salvage whatever cards arrived before the cutoff
            print("--- MLX partial output (\(model.rawValue)) ---")
            print(fullText)
            print("--- end partial output ---")
            return (try? parseVocabCards(from: fullText)) ?? []
        }

        print("--- MLX raw output (\(model.rawValue)) ---")
        print(fullText)
        print("--- end raw output ---")

        return try parseVocabCards(from: fullText)
    }

    /// Low-level text generation — returns the raw model output as a trimmed string.
    /// The model must already be loaded and must match `model`.
    func generateText(
        system systemPrompt: String,
        user userMessage: String,
        model: MLXModel,
        maxTokens: Int = 32
    ) async throws -> String {
        if model == .appleIntelligence {
            guard isModelLoaded, currentModel == model else { throw MLXError.modelNotLoaded }
            return try await appleService.generateText(
                system: systemPrompt, user: userMessage, maxTokens: maxTokens
            )
        }

        guard let container = modelContainer, isModelLoaded, currentModel == model else {
            throw MLXError.modelNotLoaded
        }

        let adjustedUser = userMessage

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(adjustedUser)
        ])

        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        let lmInput = try await container.prepare(input: userInput)
        let parameters = tunedParameters(maxTokens: maxTokens, temperature: 0.1)
        let stream = try await container.generate(input: lmInput, parameters: parameters)

        var output = ""
        var tokenCount = 0
        MemoryPressureMonitor.shared.beginRun()
        activeGenerations += 1
        defer { activeGenerations -= 1 }
        for try await generation in stream {
            try Task.checkCancellation()
            if shouldStopForMemory(at: tokenCount) {
                genLogger.warning("[\(model.rawValue, privacy: .public)] Memory floor reached after \(tokenCount, privacy: .public) tokens — returning partial text")
                break
            }
            if let chunk = generation.chunk {
                output += chunk
                tokenCount += 1
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like `generateText`, but built for long-form output (story writing): streams with live
    /// `streamingTokenCount` updates, honors `isStopRequested` (returning the partial text and
    /// setting `lastBatchEndedEarly`), and takes a sampling temperature — creative prose needs
    /// more than the near-greedy default the short extraction calls use.
    /// The model must already be loaded and must match `model`.
    func generateStreamedText(
        system systemPrompt: String,
        user userMessage: String,
        model: MLXModel,
        maxTokens: Int,
        temperature: Float = 0.7,
        timeoutSeconds: Double = 300
    ) async throws -> String {
        if model == .appleIntelligence {
            guard isModelLoaded, currentModel == model else { throw MLXError.modelNotLoaded }
            streamingTokenCount = 0
            lastBatchEndedEarly = false
            return try await appleService.generateText(
                system: systemPrompt, user: userMessage, maxTokens: maxTokens
            )
        }

        guard let container = modelContainer, isModelLoaded, currentModel == model else {
            throw MLXError.modelNotLoaded
        }

        let adjustedUser = userMessage

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(adjustedUser)
        ])

        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        let lmInput = try await container.prepare(input: userInput)
        let parameters = tunedParameters(maxTokens: maxTokens, temperature: temperature)
        let stream = try await container.generate(input: lmInput, parameters: parameters)

        var output = ""
        var tokenCount = 0
        var exitedEarly = false
        streamingTokenCount = 0
        lastBatchEndedEarly = false
        isStopRequested = false
        MemoryPressureMonitor.shared.beginRun()
        activeGenerations += 1
        defer { activeGenerations -= 1 }
        let startTime = Date()

        for try await generation in stream {
            try Task.checkCancellation()
            if isStopRequested {
                exitedEarly = true
                break
            }
            if Date().timeIntervalSince(startTime) > timeoutSeconds {
                exitedEarly = true
                break
            }
            if shouldStopForMemory(at: tokenCount) {
                genLogger.warning("[\(model.rawValue, privacy: .public)] Memory floor reached after \(tokenCount, privacy: .public) tokens — ending this answer early")
                exitedEarly = true
                break
            }
            if let chunk = generation.chunk {
                output += chunk
                tokenCount += 1
                if tokenCount % 32 == 0 {
                    streamingTokenCount = tokenCount
                }
            }
        }

        if exitedEarly { lastBatchEndedEarly = true }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Conversation chat

    /// Streamed, multi-turn chat reply for the conversation feature.
    /// - Parameters:
    ///   - history: Ordered turns (user/assistant) of the conversation so far.
    ///   - system: The system prompt steering persona, level, focus, etc.
    ///   - onPartial: Called on the main actor with the cumulative *visible* reply
    ///     (with any `<think>` blocks stripped) as tokens arrive.
    /// - Returns: The final visible reply text.
    func streamChatReply(
        history: [(role: ChatRole, content: String)],
        system: String,
        model: MLXModel,
        maxTokens: Int = 256,
        temperature: Float = 0.7,
        /// Give up if no token arrives within this many seconds (a wedged GPU / stalled decode).
        /// It's an *idle* timeout, so a legitimately long reply keeps going as long as tokens flow.
        stallTimeout: Double = 30,
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        // Several chat templates (notably Gemma's) require the turn sequence to begin with a
        // `user` message and to strictly alternate user/assistant; anything else calls
        // `raise_exception(...)` and surfaces to the learner as "Jinja.TemplateException".
        // ``ChatTurnNormalizer`` is the single place that guarantees the accepted shape — see it
        // for every way an ordinary conversation drifts out of it.
        let turns = ChatTurnNormalizer.normalized(history, openerSeed: ConversationPrompts.openerSeed)

        if model == .appleIntelligence {
            guard isModelLoaded, currentModel == model else { throw MLXError.modelNotLoaded }
            let reply = try await appleService.streamChatReply(
                history: turns,
                system: system,
                maxTokens: maxTokens,
                temperature: Double(temperature),
                onPartial: { partial in
                    let visible = ConversationPrompts.stripThinkBlocks(partial)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    onPartial(visible)
                }
            )
            return ConversationPrompts.stripThinkBlocks(reply)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let container = modelContainer, isModelLoaded, currentModel == model else {
            throw MLXError.modelNotLoaded
        }

        var messages: [Chat.Message] = [.system(system)]
        for turn in turns {
            let content = turn.content
            switch turn.role {
            case .system:    messages.append(.system(content))
            case .user:      messages.append(.user(content))
            case .assistant: messages.append(.assistant(content))
            }
        }

        let userInput = UserInput(chat: messages)
        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        let parameters = tunedParameters(maxTokens: maxTokens, temperature: temperature)

        // Run the decode as a cancellable child task so a stall watchdog can abort it. Without this,
        // a GPU that never yields a token leaves `for try await generation in stream` suspended
        // forever — the user is stuck on the typing indicator with no way out. The watchdog cancels
        // the task if no token arrives within `stallTimeout`; the loop stops at its next
        // `checkCancellation()` and we surface `generationTimedOut` (shown with "Try again").
        let activity = GenerationActivity()
        MemoryPressureMonitor.shared.beginRun()
        activeGenerations += 1
        defer { activeGenerations -= 1 }
        let decode = Task { @MainActor in
            let lmInput: LMInput
            do {
                lmInput = try await container.prepare(input: userInput)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The template rejected even the normalized sequence — a rule we haven't met. A
                // single user turn is the one shape every chat template renders, so fall back to
                // the transcript-in-one-turn prompt rather than ending the conversation on an
                // error nobody can read. Worse replies beat dead ends.
                self.genLogger.warning("Chat template rejected the turn sequence (\(error.localizedDescription, privacy: .public)) — retrying as a flattened prompt")
                let flattened = UserInput(chat: [
                    .system(system),
                    .user(ChatTurnNormalizer.flattened(turns, openerSeed: ConversationPrompts.openerSeed))
                ])
                lmInput = try await container.prepare(input: flattened)
            }
            let stream = try await container.generate(input: lmInput, parameters: parameters)
            var full = ""
            var tokenCount = 0
            for try await generation in stream {
                try Task.checkCancellation()
                activity.recordProgress()
                if self.shouldStopForMemory(at: tokenCount) {
                    self.genLogger.warning("Memory floor reached after \(tokenCount, privacy: .public) tokens — cutting the reply short")
                    break
                }
                if let chunk = generation.chunk {
                    full += chunk
                    tokenCount += 1
                    let visible = ConversationPrompts.stripThinkBlocks(full)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    onPartial(visible)
                }
            }
            return ConversationPrompts.stripThinkBlocks(full)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try await value(of: decode, abortingIfIdlePast: stallTimeout, tracking: activity)
    }

    /// Await a streaming generation's result, but abort it if it goes idle (no token) longer than
    /// `stallTimeout`. On stall, cancels the task and throws `MLXError.generationTimedOut`. The
    /// watchdog runs on the main actor alongside the (also main-actor) decode task, so they share
    /// `activity` safely and interleave at each other's suspension points.
    private func value<T: Sendable>(
        of task: Task<T, Error>,
        abortingIfIdlePast stallTimeout: Double,
        tracking activity: GenerationActivity
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await task.value }
            group.addTask { @MainActor in
                while true {
                    let idle = activity.idleSeconds
                    if idle >= stallTimeout {
                        task.cancel()
                        throw MLXError.generationTimedOut
                    }
                    // Sleep just past the projected deadline, then re-check.
                    let wait = max(0.25, stallTimeout - idle)
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    // MARK: - Prompt Building

    private func buildJSONPrompt(
        topic: String,
        count: Int,
        includeExamples: Bool,
        includeGender: Bool,
        wordTypeFilter: WordTypeFilter,
        includeConjugations: Bool,
        selectedTenses: [String],
        excludeWords: [String] = []
    ) -> String {
        // Build a concrete example card matching the requested word type
        let exampleCard: String
        switch wordTypeFilter {
        case .verbs, .verbsAndAdjectives:
            exampleCard = """
                {"germanWord":"kochen","englishTranslation":"to cook","wordType":"verb","article":null,\
                "exampleSentence":\(includeExamples ? "\"Ich koche gerne.\"" : "null"),\
                "conjugations":null}
                """
        case .adjectives:
            exampleCard = """
                {"germanWord":"heiß","englishTranslation":"hot","wordType":"adjective","article":null,\
                "exampleSentence":\(includeExamples ? "\"Das Wasser ist heiß.\"" : "null"),\
                "conjugations":null}
                """
        default:
            exampleCard = """
                {"germanWord":"der Tisch","englishTranslation":"the table","wordType":"noun","article":"der",\
                "exampleSentence":\(includeExamples ? "\"Der Tisch ist groß.\"" : "null"),\
                "conjugations":null}
                """
        }

        // Word type instruction
        let wordTypeInstruction: String
        switch wordTypeFilter {
        case .all:
            wordTypeInstruction = "Include a mix of nouns, verbs, and adjectives."
        case .nouns:
            wordTypeInstruction = "Only generate nouns. Set wordType to \"noun\" for each."
        case .verbs:
            wordTypeInstruction = "Only generate verbs (action words like kochen, backen, braten). Set wordType to \"verb\" for each."
        case .adjectives:
            wordTypeInstruction = "Only generate adjectives. Set wordType to \"adjective\" for each."
        case .verbsAndAdjectives:
            wordTypeInstruction = "Only generate verbs and adjectives, no nouns."
        }

        var prompt = """
            Generate exactly \(count) different German \(wordTypeFilter == .verbs ? "verbs" : "words") \
            related to "\(topic)".
            \(wordTypeInstruction)
            Respond with a JSON object: {"cards":[\(exampleCard), ...]}
            Each card MUST be a different German word. Do NOT repeat any word.
            Each card MUST have a unique English translation — no two cards may share the same englishTranslation.
            Use the most precise, literal English translation for each word (e.g. "to see" for sehen, "to look" for schauen, not both "to watch"). \
            You may add parenthetical context to disambiguate similar words (e.g. "to watch (a film)", "to look (at something)").
            """

        if includeGender && wordTypeFilter.includesNouns {
            prompt += "\nFor nouns, include the article (der/die/das). Non-nouns have article:null."
        } else {
            prompt += "\nSet article to null."
        }

        if !includeExamples {
            prompt += "\nSet exampleSentence to null."
        }

        if wordTypeFilter.includesVerbs && includeConjugations && !selectedTenses.isEmpty {
            let tenseList = selectedTenses.joined(separator: ", ")
            prompt += """
                \nFor verbs, include conjugations: \
                [{"tense":"...","ich":"...","du":"...","erSieEs":"...","wir":"...","ihr":"...","sieSie":"..."}] \
                for: \(tenseList). Non-verbs have conjugations:null.
                """
        } else {
            prompt += "\nSet conjugations to null."
        }

        if !excludeWords.isEmpty {
            let wordList = excludeWords.joined(separator: ", ")
            prompt += "\nDo NOT include these words (already generated): \(wordList)."
        }

        return prompt
    }

    // MARK: - JSON Parsing

    private func parseVocabCards(from rawOutput: String) throws -> [VocabCard] {
        guard let jsonString = extractJSON(from: rawOutput) else {
            throw MLXError.jsonExtractionFailed(rawOutput: rawOutput)
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw MLXError.jsonExtractionFailed(rawOutput: rawOutput)
        }

        let hasConjugationData = jsonString.contains("\"conjugations\"") &&
            !jsonString.contains("\"conjugations\":null") &&
            !jsonString.contains("\"conjugations\": null")
        print("[MLX] Extracted JSON length: \(jsonString.count) chars, conjugation data present: \(hasConjugationData)")

        // Try normal decode first
        if let response = try? JSONDecoder().decode(CodableVocabCardResponse.self, from: data) {
            let withConj = response.cards.filter { !($0.conjugations?.isEmpty ?? true) }.count
            print("[MLX] Full decode succeeded — \(response.cards.count) cards, \(withConj) with conjugations")
            return response.cards.map { $0.toVocabCard() }
        }

        print("[MLX] Full decode FAILED — falling back to card salvage")

        // Fallback: try to salvage individual card objects from the JSON.
        // The model sometimes produces cards where some are valid and others are garbled.
        let salvaged = salvageCards(from: jsonString)
        if !salvaged.isEmpty {
            let withConj = salvaged.filter { !($0.conjugations?.isEmpty ?? true) }.count
            print("[MLX] Salvaged \(salvaged.count) cards, \(withConj) with conjugations")
            return salvaged
        }

        throw MLXError.jsonDecodingFailed(
            extractedJSON: jsonString,
            decodingError: "Could not parse any valid cards from model output"
        )
    }

    /// Attempt to extract individual valid card JSON objects from a potentially malformed response.
    private func salvageCards(from json: String) -> [VocabCard] {
        // First sanitize the JSON to fix common model output errors
        let sanitized = sanitizeModelJSON(json)

        var cards: [VocabCard] = []
        let decoder = JSONDecoder()

        // Find each top-level object within the cards array by brace-matching
        var searchStart = sanitized.startIndex
        while searchStart < sanitized.endIndex {
            guard let openBrace = sanitized[searchStart...].firstIndex(of: "{") else { break }

            var depth = 0
            var end: String.Index?
            for i in sanitized.indices[openBrace...] {
                if sanitized[i] == "{" { depth += 1 }
                if sanitized[i] == "}" { depth -= 1 }
                if depth == 0 {
                    end = i
                    break
                }
            }

            if let closeBrace = end {
                let candidate = String(sanitized[openBrace...closeBrace])
                searchStart = sanitized.index(after: closeBrace)

                // Skip if it doesn't look like a card (e.g. it's a conjugation sub-object)
                guard candidate.contains("germanWord") else { continue }

                if let data = candidate.data(using: .utf8),
                   let card = try? decoder.decode(CodableVocabCard.self, from: data) {
                    cards.append(card.toVocabCard())
                    continue
                }

                // Brace-matched but couldn't decode — try stripping conjugations
                // (the most common source of corruption) and retry
                let stripped = stripConjugationsJSON(candidate)
                if let data = stripped.data(using: .utf8),
                   let card = try? decoder.decode(CodableVocabCard.self, from: data) {
                    print("[MLX] Salvage: stripped corrupt conjugations from '\(card.germanWord)' to recover card")
                    cards.append(card.toVocabCard())
                    continue
                }
                print("[MLX] Salvage: could not decode candidate even after stripping conjugations — skipping")
            } else {
                // Unbalanced braces — skip past this '{' and keep scanning
                searchStart = sanitized.index(after: openBrace)
                continue
            }
        }

        // Last resort: regex-based extraction for when JSON structure is too broken
        if cards.isEmpty {
            cards = extractCardsWithRegex(from: sanitized)
        }

        return cards
    }

    /// Remove the "conjugations" field and its value from a card JSON string.
    /// This lets us salvage the core card data when conjugation sub-objects are corrupted.
    private func stripConjugationsJSON(_ cardJSON: String) -> String {
        // Remove "conjugations": [...] or "conjugations": null (with optional trailing comma)
        var result = cardJSON.replacingOccurrences(
            of: #",?\s*"conjugations"\s*:\s*\[.*?\]"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #",?\s*"conjugations"\s*:\s*null"#,
            with: "",
            options: .regularExpression
        )
        // Fix leading comma after opening brace: {, "key" -> {"key"
        result = result.replacingOccurrences(
            of: #"\{\s*,"#,
            with: "{",
            options: .regularExpression
        )
        return result
    }

    /// Extract card data using regex when JSON parsing completely fails.
    /// Looks for germanWord/englishTranslation pairs and constructs minimal cards.
    private func extractCardsWithRegex(from text: String) -> [VocabCard] {
        var cards: [VocabCard] = []
        var seen = Set<String>()

        // Pattern: "germanWord" : "value" ... "englishTranslation" : "value"
        // Allow flexible whitespace and separator characters between key-value pairs
        let pattern = #""germanWord"\s*:\s*"([^"]+)"\s*[,\s]*"englishTranslation"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let germanWord = nsString.substring(with: match.range(at: 1))
            let englishTranslation = nsString.substring(with: match.range(at: 2))

            let key = germanWord.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            // Try to also extract wordType, article, exampleSentence nearby
            let matchEnd = match.range.location + match.range.length
            let lookAhead = min(matchEnd + 500, nsString.length)
            let context = nsString.substring(with: NSRange(location: match.range.location, length: lookAhead - match.range.location))

            let wordType = extractRegexField("wordType", from: context)
            let article = extractRegexField("article", from: context)
            let example = extractRegexField("exampleSentence", from: context)

            cards.append(VocabCard(
                germanWord: germanWord,
                englishTranslation: englishTranslation,
                wordType: wordType,
                article: (article?.lowercased() == "null") ? nil : article,
                exampleSentence: (example?.lowercased() == "null") ? nil : example,
                conjugations: nil
            ))
        }

        if !cards.isEmpty {
            print("[MLX] Regex fallback extracted \(cards.count) cards")
        }
        return cards
    }

    /// Extract a single string field value from a JSON-like context string.
    private func extractRegexField(_ field: String, from context: String) -> String? {
        let pattern = "\"\(field)\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: context, range: NSRange(location: 0, length: (context as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        let value = (context as NSString).substring(with: match.range(at: 1))
        return value.isEmpty ? nil : value
    }

    /// Fix common character substitutions that small models produce.
    /// The Qwen3 model sometimes outputs CJK or fullwidth characters instead of ASCII punctuation.
    private func sanitizeModelJSON(_ text: String) -> String {
        var s = text

        // Fix fullwidth/CJK character substitutions
        let replacements: [(String, String)] = [
            ("：", ":"),   // fullwidth colon
            ("，", ","),   // fullwidth comma
            ("｛", "{"),   // fullwidth left brace
            ("｝", "}"),   // fullwidth right brace
            ("［", "["),   // fullwidth left bracket
            ("］", "]"),   // fullwidth right bracket
            ("（", "("),   // fullwidth left paren
            ("）", ")"),   // fullwidth right paren
            ("\u{201C}", "\""), // left double quotation mark
            ("\u{201D}", "\""), // right double quotation mark
            ("\u{2018}", "'"),  // left single quotation mark
            ("\u{2019}", "'"),  // right single quotation mark
            ("'", "'"),   // fullwidth apostrophe alternative
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // Remove stray CJK / Japanese / Korean characters that appear as model noise.
        // The model often inserts these inside or adjacent to quoted strings,
        // e.g. "filmen"打ち" → after removal becomes "filmen"" which is still broken.
        // So we also clean up resulting double-quote artifacts afterward.
        s = s.replacingOccurrences(
            of: #"[\u{3000}-\u{303F}\u{3040}-\u{309F}\u{30A0}-\u{30FF}\u{3400}-\u{4DBF}\u{4E00}-\u{9FFF}\u{AC00}-\u{D7AF}\u{F900}-\u{FAFF}]+"#,
            with: "",
            options: .regularExpression
        )

        // Fix double-quote artifacts left after CJK removal: "value"" -> "value"
        // Pattern: a quote followed immediately by another quote where the second
        // is followed by a structural character (comma, brace, bracket, end)
        s = s.replacingOccurrences(
            of: #"""([,\]\}\s])"#,
            with: #""$1"#,
            options: .regularExpression
        )

        // Fix missing colon between key and value: "key" "value" -> "key": "value"
        // Pattern: quote-word-quote whitespace quote -> add colon
        s = s.replacingOccurrences(
            of: #"("\w+")\s*("[^"]*")"#,
            with: #"$1: $2"#,
            options: .regularExpression
        )

        // Fix "key". "value" -> "key": "value" (period instead of colon)
        s = s.replacingOccurrences(
            of: #"("\w+")\.\s*"#,
            with: #"$1: "#,
            options: .regularExpression
        )

        // Fix missing commas between key-value pairs: "value" "key" -> "value", "key"
        // Look for patterns like: "value" \n "nextKey"
        s = s.replacingOccurrences(
            of: #"("(?:[^"\\]|\\.)*")\s*\n\s*""#,
            with: #"$1, ""#,
            options: .regularExpression
        )

        return s
    }

    /// Extract the first complete JSON object from raw text using brace matching.
    /// Strips thinking blocks, markdown fences, and other wrapper text first.
    /// If the JSON is truncated (e.g. token limit), attempts to repair it —
    /// `arrayKey` names the top-level array ("cards", "exercises", "questions") the repair scans for.
    /// Internal so other generation services (story questions) can reuse the salvage chain.
    func extractJSON(from text: String, arrayKey: String = "cards") -> String? {
        var cleaned = text

        // Strip all <think>...</think> blocks (Qwen3 may emit multiple in one response)
        var thinkBlockCount = 0
        var thinkCharsStripped = 0
        while let thinkRange = cleaned.range(of: #"<think>[\s\S]*?</think>"#, options: .regularExpression) {
            thinkCharsStripped += cleaned.distance(from: thinkRange.lowerBound, to: thinkRange.upperBound)
            cleaned.removeSubrange(thinkRange)
            thinkBlockCount += 1
        }
        if thinkBlockCount > 0 {
            print("[MLX] Stripped \(thinkBlockCount) <think> block(s), \(thinkCharsStripped) chars removed")
        } else if text.contains("<think>") {
            print("[MLX] WARNING: <think> tag found but no complete </think> — block NOT stripped (truncated?)")
        }

        // Strip markdown code fences (```json ... ``` or ''' variants)
        cleaned = cleaned.replacingOccurrences(
            of: #"(?:```|''')json?\s*"#, with: "", options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"(?:```|''')\s*"#, with: "", options: .regularExpression
        )

        // Fix common character substitutions from the model
        cleaned = sanitizeModelJSON(cleaned)

        guard let startIndex = cleaned.firstIndex(of: "{") else { return nil }

        var braceCount = 0
        var bracketCount = 0
        var endIndex: String.Index?

        for index in cleaned.indices[startIndex...] {
            let char = cleaned[index]
            if char == "{" { braceCount += 1 }
            if char == "}" { braceCount -= 1 }
            if char == "[" { bracketCount += 1 }
            if char == "]" { bracketCount -= 1 }
            if braceCount == 0 {
                endIndex = index
                break
            }
        }

        if let end = endIndex {
            return String(cleaned[startIndex...end])
        }

        // JSON is truncated — try to repair by finding the last complete card object
        return repairTruncatedJSON(String(cleaned[startIndex...]), arrayKey: arrayKey)
    }

    /// Attempt to repair truncated JSON like `{"cards":[{...},{...},{incomplete`
    /// by finding the last complete card and closing the structure.
    private func repairTruncatedJSON(_ json: String, arrayKey: String = "cards") -> String? {
        // Find the last complete "}" that closes a card object inside the cards array.
        // Strategy: find last occurrence of "},{"  or the pattern "}]}" which would be the end.
        // If we find "},", we can cut there, close the array and object.

        // Look for the last complete card boundary: "},{"
        // or a complete card ending with just "}"
        guard let cardsStart = json.range(of: "\"\(arrayKey)\"\\s*:\\s*\\[", options: .regularExpression) else {
            return nil
        }

        let afterCardsStart = cardsStart.upperBound
        let cardsContent = String(json[afterCardsStart...])

        // Walk through finding complete card objects using brace matching
        var lastCompleteCardEnd: String.Index?
        var i = cardsContent.startIndex
        while i < cardsContent.endIndex {
            let char = cardsContent[i]
            if char == "{" {
                // Try to find the matching close brace
                var depth = 1
                var j = cardsContent.index(after: i)
                while j < cardsContent.endIndex && depth > 0 {
                    if cardsContent[j] == "{" { depth += 1 }
                    if cardsContent[j] == "}" { depth -= 1 }
                    j = cardsContent.index(after: j)
                }
                if depth == 0 {
                    // Found a complete card object
                    lastCompleteCardEnd = cardsContent.index(before: j)
                    i = j
                    continue
                } else {
                    break  // Incomplete card, stop here
                }
            }
            i = cardsContent.index(after: i)
        }

        guard let cardEnd = lastCompleteCardEnd else { return nil }

        // Rebuild: everything from original start up to the last complete card, then close ]}
        let completeCards = cardsContent[cardsContent.startIndex...cardEnd]

        let repaired = String(json[json.startIndex..<cardsStart.upperBound])
            + String(completeCards)
            + "]}"

        print("--- Repaired truncated JSON (kept cards up to index \(cardEnd)) ---")
        return repaired
    }
}

// MARK: - Article-noun generation (der/die/das game)

extension MLXGenerationService {

    /// Topic nouns for the article game. Same contract as the other generators: model must
    /// already be loaded; returns whatever parses (possibly empty on stop/timeout). Every
    /// survivor is dictionary-checked — when the bundled Wiktionary is unanimous about a
    /// noun's gender, its article wins over the model's, so the game never teaches a wrong one.
    func generateArticleNouns(
        topic: String,
        count: Int,
        model: MLXModel,
        timeoutSeconds: Double = 120
    ) async throws -> [ArticleQuestion] {
        let systemPrompt = "You are a German language tutor. Respond ONLY with valid JSON. No markdown fences, no explanation."
        let prompt = """
            List exactly \(count) common German nouns about the topic "\(topic)".
            Respond with a JSON object: {"nouns":[{"noun":"Gabel","article":"die","english":"fork"}, ...]}
            Rules:
            - "article" is the noun's definite article: der, die, or das. It must be correct.
            - "noun" is the singular noun WITHOUT the article, capitalized.
            - "english" is a short English translation.
            - Concrete, useful words a learner meets at A1-B1. No plural-only nouns, no proper names. Every noun must be different.
            """

        if model == .appleIntelligence {
            guard isModelLoaded, currentModel == model else { throw MLXError.modelNotLoaded }
            streamingTokenCount = 0
            lastBatchEndedEarly = false
            let raw = try await appleService.generateCardsRaw(system: systemPrompt, user: prompt)
            return parseArticleNouns(from: raw)
        }

        guard let container = modelContainer, isModelLoaded, currentModel == model else {
            throw MLXError.modelNotLoaded
        }

        let userMessage = prompt

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(userMessage)
        ])

        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        let lmInput = try await container.prepare(input: userInput)
        let parameters = tunedParameters(maxTokens: 1536, temperature: 0.6)

        genLogger.info("[\(model.rawValue, privacy: .public)] Article-noun generation start — topic length=\(topic.count, privacy: .public), count=\(count, privacy: .public)")

        let stream = try await container.generate(input: lmInput, parameters: parameters)

        var fullText = ""
        var tokenCount = 0
        streamingTokenCount = 0
        lastBatchEndedEarly = false
        isStopRequested = false
        MemoryPressureMonitor.shared.beginRun()
        activeGenerations += 1
        defer { activeGenerations -= 1 }
        let startTime = Date()

        for try await generation in stream {
            if isStopRequested || Date().timeIntervalSince(startTime) > timeoutSeconds
                || shouldStopForMemory(at: tokenCount) {
                lastBatchEndedEarly = true
                break
            }
            if let chunk = generation.chunk {
                fullText += chunk
                tokenCount += 1
                if tokenCount % 32 == 0 {
                    streamingTokenCount = tokenCount
                }
            }
        }

        genLogger.info("[\(model.rawValue, privacy: .public)] Article-noun generation done — tokens=\(tokenCount, privacy: .public)")
        return parseArticleNouns(from: fullText)
    }

    private struct CodableArticleNoun: Decodable {
        let noun: String
        let article: String
        let english: String
    }

    private struct CodableArticleNounResponse: Decodable {
        let nouns: [CodableArticleNoun]
    }

    private func parseArticleNouns(from rawOutput: String) -> [ArticleQuestion] {
        guard let jsonString = extractJSON(from: rawOutput, arrayKey: "nouns"),
              let data = jsonString.data(using: .utf8) else { return [] }

        var decoded: [CodableArticleNoun] = []
        if let response = try? JSONDecoder().decode(CodableArticleNounResponse.self, from: data) {
            decoded = response.nouns
        } else {
            decoded = salvageArticleNouns(from: jsonString)
        }

        var seen = Set<String>()
        var questions: [ArticleQuestion] = []
        for item in decoded {
            var noun = ArticleGameService.bareNoun(item.noun)
            let english = item.english.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !noun.isEmpty, !english.isEmpty,
                  var article = GermanArticle(text: item.article),
                  seen.insert(noun.lowercased()).inserted
            else { continue }
            noun = noun.prefix(1).uppercased() + noun.dropFirst()
            // The dictionary outranks the model — a gender game must never teach a wrong article.
            if let hit = WiktionaryValidator.shared.nounArticle(for: noun) {
                article = hit.article
            }
            questions.append(ArticleQuestion(noun: noun, article: article, english: english))
        }
        return questions
    }

    /// Brace-match individual noun objects out of malformed JSON (same idea as `salvageCards`).
    private func salvageArticleNouns(from json: String) -> [CodableArticleNoun] {
        let sanitized = sanitizeModelJSON(json)
        var nouns: [CodableArticleNoun] = []
        let decoder = JSONDecoder()

        var searchStart = sanitized.startIndex
        while searchStart < sanitized.endIndex {
            guard let openBrace = sanitized[searchStart...].firstIndex(of: "{") else { break }
            var depth = 0
            var end: String.Index?
            for i in sanitized.indices[openBrace...] {
                if sanitized[i] == "{" { depth += 1 }
                if sanitized[i] == "}" { depth -= 1 }
                if depth == 0 {
                    end = i
                    break
                }
            }
            guard let closeBrace = end else { break }
            let candidate = String(sanitized[openBrace...closeBrace])
            searchStart = sanitized.index(after: closeBrace)

            guard candidate.contains("article") else { continue }
            if let data = candidate.data(using: .utf8),
               let noun = try? decoder.decode(CodableArticleNoun.self, from: data) {
                nouns.append(noun)
            }
        }
        return nouns
    }
}
