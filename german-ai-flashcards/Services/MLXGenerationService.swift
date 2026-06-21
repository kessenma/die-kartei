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
    /// The HuggingFace repo directory name for this model (e.g. "models--Qwen--Qwen3-0.6B-4bit").
    private var repoDirectoryName: String {
        "models--" + configuration.name.replacingOccurrences(of: "/", with: "--")
    }

    /// Whether this model is ready to use. For the built-in Apple model there is nothing to
    /// download — "ready" means Apple Intelligence is currently available on this device.
    var isDownloaded: Bool {
        if self == .appleIntelligence { return AppleIntelligenceService.currentlyAvailable() }
        let refsFile = hubCacheDirectory
            .appendingPathComponent(repoDirectoryName)
            .appendingPathComponent("refs")
            .appendingPathComponent("main")
        return FileManager.default.fileExists(atPath: refsFile.path)
    }

    /// Disk size of the cached model in bytes, or nil if not downloaded.
    /// The built-in Apple model uses no app-managed storage, so it reports nil (excluded from the
    /// storage breakdown).
    var cachedSizeBytes: Int64? {
        if self == .appleIntelligence { return nil }
        let repoDir = hubCacheDirectory.appendingPathComponent(repoDirectoryName)
        guard FileManager.default.fileExists(atPath: repoDir.path) else { return nil }
        return directorySize(repoDir)
    }

    /// Delete the cached model from the HuggingFace Hub cache.
    func deleteFromCache() throws {
        if self == .appleIntelligence { return }   // built-in model — nothing to delete
        let repoDir = hubCacheDirectory.appendingPathComponent(repoDirectoryName)
        guard FileManager.default.fileExists(atPath: repoDir.path) else { return }
        try FileManager.default.removeItem(at: repoDir)
    }

    /// The HuggingFace Hub cache root directory.
    private var hubCacheDirectory: URL {
        // Matches CacheLocationProvider logic: sandboxed apps use Library/Caches,
        // non-sandboxed macOS uses ~/.cache
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        return URL.cachesDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
        #else
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            return URL.cachesDirectory
                .appendingPathComponent("huggingface")
                .appendingPathComponent("hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
        #endif
    }

    /// Recursively compute the size of a directory.
    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
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

    /// Remove pronoun prefixes that some models (e.g. Mistral) include in conjugation values.
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
        // 3. Flat obj:   {"tense":"Präsens","ich":"lerne",...}  (Mistral)
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
    case jsonExtractionFailed(rawOutput: String)
    case jsonDecodingFailed(extractedJSON: String, decodingError: String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "Model not loaded. Please load the model first in Settings."
        case .jsonExtractionFailed(let rawOutput):
            "Could not find JSON in model output. Raw output:\n\(String(rawOutput.prefix(500)))"
        case .jsonDecodingFailed(let json, let decodingError):
            "JSON decode error: \(decodingError)\n\nExtracted JSON:\n\(String(json.prefix(500)))"
        }
    }
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
    private var downloadPollingTask: Task<Void, Never>?
    private var activeProgress: Progress?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "de.germanflashcards", category: "ModelLoad")
    private let genLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "de.germanflashcards", category: "Generation")

    /// Physical memory footprint of this process in MB. Uses phys_footprint (what jetsam measures).
    private func memFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) / 1_048_576 : -1
    }

    /// Load a model into memory. Downloads from HuggingFace Hub on first use.
    func loadModel(_ model: MLXModel) async {
        guard !isLoading else { return }

        // Unload previous model if switching
        if currentModel != model {
            modelContainer = nil
            isModelLoaded = false
        }

        guard !isModelLoaded || currentModel != model else { return }

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
                lastBatchEndedEarly = false
            } else {
                isModelLoaded = false
                loadError = appleService.unavailableReason ?? "Apple Intelligence isn't available."
            }
            isLoading = false
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
        logger.info("[\(model.rawValue, privacy: .public)] Load started — Device RAM: \(physicalMB, privacy: .public) MB, App footprint: \(footprintBefore, privacy: .public) MB, Model size: \(model.approximateSizeMB, privacy: .public) MB, Already cached: \(model.isDownloaded, privacy: .public)")

        Memory.cacheLimit = 20 * 1024 * 1024

        let expectedBytes = Int64(model.approximateSizeMB) * 1024 * 1024

        // Snapshot existing temp files so we only count growth from THIS download,
        // not leftover CFNetworkDownload_*.tmp files from previous cancelled sessions.
        let tmpDir = FileManager.default.temporaryDirectory
        var initialTempSizes: [String: Int64] = [:]
        if let e = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            while let url = e.nextObject() as? URL {
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      v.isRegularFile == true, let sz = v.fileSize else { continue }
                initialTempSizes[url.path] = Int64(sz)
            }
        }

        // Poll temp file growth every 0.5s for byte-level progress.
        // The Progress callback fires ~5x/sec but completedUnitCount is frozen (known
        // swift-huggingface bug #48) — so we track CFNetworkDownload_*.tmp growth instead.
        downloadPollingTask = Task { @MainActor [weak self] in
            var lastReported: Int64 = -1
            var sawTempFiles = false
            var lastTempGrowth: Int64 = -1
            var staleCount = 0
            var pollCount = 0
            // Mutable — expands if the actual download exceeds the static estimate
            var effectiveExpectedBytes = expectedBytes

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.isLoading, let progress = self.activeProgress else { continue }
                pollCount += 1

                let cachedBytes = progress.completedUnitCount
                guard expectedBytes > 0, cachedBytes >= 0 else { continue }

                // Sum only the GROWTH of temp files since download started
                var tempGrowth: Int64 = 0
                var tempFileCount = 0
                var tempFileDetails: [(String, Int64, Int64)] = [] // (name, current, growth)
                if let enumerator = FileManager.default.enumerator(
                    at: tmpDir,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
                ) {
                    while let url = enumerator.nextObject() as? URL {
                        guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                              vals.isRegularFile == true, let sz = vals.fileSize else { continue }
                        let initial = initialTempSizes[url.path] ?? 0
                        let growth = Int64(sz) - initial
                        tempFileCount += 1
                        if growth > 0 {
                            tempGrowth += growth
                            tempFileDetails.append((url.lastPathComponent, Int64(sz), growth))
                        }
                    }
                }

                // Log every 10 polls (~5s) and whenever stale state changes
                let shouldLog = (pollCount % 10 == 0) || (staleCount == 1) || (staleCount == 10)
                if shouldLog {
                    print("[DLProgress] poll=\(pollCount) sawTempFiles=\(sawTempFiles) tempGrowth=\(tempGrowth) lastTempGrowth=\(lastTempGrowth) staleCount=\(staleCount) cachedBytes=\(cachedBytes) expectedBytes=\(expectedBytes) fileCount=\(tempFileCount)")
                    for (name, sz, growth) in tempFileDetails {
                        print("[DLProgress]   file: \(name) size=\(sz) growth=\(growth)")
                    }
                }

                if tempGrowth > 0 {
                    sawTempFiles = true

                    // Track how many consecutive polls show no new bytes.
                    // When temp files stop growing (download done, files being moved to cache)
                    // but haven't been deleted yet, we'd otherwise freeze at ~100%.
                    if tempGrowth == lastTempGrowth {
                        staleCount += 1
                    } else {
                        staleCount = 0
                        lastTempGrowth = tempGrowth
                    }

                    // 10 polls × 0.5s = 5 seconds with no new bytes → assume loading phase
                    if staleCount >= 10 {
                        print("[DLProgress] stale threshold reached — switching to loading state")
                        self.downloadProgress = nil
                        self.downloadInfo = "Loading \(model.displayName) into memory…"
                        self.downloadBytesInfo = nil
                        continue
                    }

                    let totalDownloaded = cachedBytes + tempGrowth
                    guard totalDownloaded != lastReported else { continue }
                    lastReported = totalDownloaded

                    // Expand denominator if actual download exceeds our static estimate
                    if totalDownloaded > effectiveExpectedBytes {
                        effectiveExpectedBytes = Int64(Double(totalDownloaded) * 1.05)
                        print("[DLProgress] expanding expectedBytes to \(effectiveExpectedBytes)")
                    }

                    let fraction = min(Double(totalDownloaded) / Double(effectiveExpectedBytes), 0.99)
                    let fmt = ByteCountFormatter()
                    fmt.countStyle = .file
                    // Always update bytes display; only gate fraction on forward progress
                    self.downloadInfo = "Downloading \(model.displayName)…"
                    self.downloadBytesInfo = "\(fmt.string(fromByteCount: totalDownloaded)) / ~\(fmt.string(fromByteCount: effectiveExpectedBytes))"
                    if fraction > (self.downloadProgress ?? 0) {
                        self.downloadProgress = fraction
                    }
                } else if sawTempFiles {
                    print("[DLProgress] tempGrowth=0 after sawTempFiles — switching to loading state")
                    // Temp files deleted — download finished, now loading weights
                    self.downloadProgress = nil
                    self.downloadInfo = "Loading \(model.displayName) into memory…"
                    self.downloadBytesInfo = nil
                } else if model.isDownloaded {
                    // Model is cached — loading weights from local storage into RAM
                    self.downloadInfo = "Loading \(model.displayName) into memory…"
                    self.downloadBytesInfo = nil
                } else {
                    // Pre-download phase — show size hint so the user knows what's coming
                    self.downloadInfo = "Downloading \(model.displayName)…"
                    self.downloadBytesInfo = "~\(ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file))"
                }
            }
            print("[DLProgress] polling task exited (cancelled=\(Task.isCancelled))")
        }

        let task = Task {
            do {
                try Task.checkCancellation()
                let container = try await LLMModelFactory.shared.loadContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: model.configuration
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.activeProgress = progress
                    }
                }

                try Task.checkCancellation()
                modelContainer = container
                currentModel = model
                isModelLoaded = true
                let footprintAfter = memFootprintMB()
                logger.info("[\(model.rawValue, privacy: .public)] Loaded successfully — App footprint: \(footprintAfter, privacy: .public) MB")
            } catch is CancellationError {
                loadError = nil
                logger.info("[\(model.rawValue, privacy: .public)] Load cancelled by user")
            } catch {
                let footprintOnError = memFootprintMB()
                logger.error("[\(model.rawValue, privacy: .public)] Load FAILED — footprint: \(footprintOnError, privacy: .public) MB, error: \(error.localizedDescription, privacy: .public), raw: \(String(describing: error), privacy: .public)")
                loadError = "Failed to load model: \(error.localizedDescription)"
                isModelLoaded = false
            }

            downloadPollingTask?.cancel()
            downloadPollingTask = nil
            activeProgress = nil
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

    /// Cancel an in-progress model load/download.
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        downloadPollingTask?.cancel()
        downloadPollingTask = nil
        activeProgress = nil
        downloadProgress = nil
        downloadInfo = nil
        loadStartTime = nil
        isLoading = false
        loadError = nil
    }

    /// Delete a downloaded model from the HuggingFace Hub cache.
    /// If it's the currently loaded model, unloads it first.
    func deleteModel(_ model: MLXModel) throws {
        if currentModel == model {
            modelContainer = nil
            isModelLoaded = false
            currentModel = nil
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

        // Qwen3's chat template only honors /no_think at the END of the user message,
        // not in the system prompt. Placing it elsewhere leaves thinking mode active,
        // which produces <think> blocks that corrupt the conjugation JSON.
        let userMessage: String
        switch model {
        case .qwen3_0_6B, .qwen3_4B:
            userMessage = prompt + "\n/no_think"
            print("[MLX:\(model.rawValue)] /no_think appended to user message")
        default:
            userMessage = prompt
        }

        print("[MLX:\(model.rawValue)] User prompt:\n\(userMessage)")

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(userMessage)
        ])

        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

        let lmInput = try await container.prepare(input: userInput)
        let parameters = GenerateParameters(maxTokens: 4096, temperature: 0.6)

        let footprintBeforeGen = memFootprintMB()
        genLogger.info("[\(model.rawValue, privacy: .public)] Generation start — batch excludeWords=\(excludeWords.count, privacy: .public), count=\(count, privacy: .public), footprint=\(footprintBeforeGen, privacy: .public) MB")

        let stream = try await container.generate(input: lmInput, parameters: parameters)

        var fullText = ""
        var tokenCount = 0
        var exitedEarly = false
        streamingTokenCount = 0
        lastBatchEndedEarly = false
        let batchStartTime = Date()

        for try await generation in stream {
            if isStopRequested {
                exitedEarly = true
                break
            }
            if Date().timeIntervalSince(batchStartTime) > timeoutSeconds {
                let elapsed = Int(Date().timeIntervalSince(batchStartTime))
                let elapsedVal = elapsed
                genLogger.warning("[\(model.rawValue, privacy: .public)] Batch timeout after \(elapsedVal, privacy: .public)s (\(tokenCount, privacy: .public) tokens) — attempting partial parse")
                exitedEarly = true
                break
            }
            if let chunk = generation.chunk {
                fullText += chunk
                tokenCount += 1
                if tokenCount % 256 == 0 {
                    let fp = memFootprintMB()
                    genLogger.info("[\(model.rawValue, privacy: .public)] token=\(tokenCount, privacy: .public) footprint=\(fp, privacy: .public) MB")
                    streamingTokenCount = tokenCount
                }
            }
        }

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

        let adjustedUser: String
        switch model {
        case .qwen3_0_6B, .qwen3_4B:
            adjustedUser = userMessage + "\n/no_think"
        default:
            adjustedUser = userMessage
        }

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(adjustedUser)
        ])

        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        let lmInput = try await container.prepare(input: userInput)
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.1)
        let stream = try await container.generate(input: lmInput, parameters: parameters)

        var output = ""
        for try await generation in stream {
            try Task.checkCancellation()
            if let chunk = generation.chunk {
                output += chunk
            }
        }
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
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        if model == .appleIntelligence {
            guard isModelLoaded, currentModel == model else { throw MLXError.modelNotLoaded }
            let reply = try await appleService.streamChatReply(
                history: history,
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
        for (index, turn) in history.enumerated() {
            var content = turn.content
            // Qwen3 small models only honor /no_think at the end of the final user turn.
            if turn.role == .user, index == history.count - 1 {
                switch model {
                case .qwen3_0_6B, .qwen3_4B: content += "\n/no_think"
                default: break
                }
            }
            switch turn.role {
            case .system:    messages.append(.system(content))
            case .user:      messages.append(.user(content))
            case .assistant: messages.append(.assistant(content))
            }
        }

        let userInput = UserInput(chat: messages)
        MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))
        let lmInput = try await container.prepare(input: userInput)
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: temperature)
        let stream = try await container.generate(input: lmInput, parameters: parameters)

        var full = ""
        for try await generation in stream {
            try Task.checkCancellation()
            if let chunk = generation.chunk {
                full += chunk
                let visible = ConversationPrompts.stripThinkBlocks(full)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                onPartial(visible)
            }
        }
        return ConversationPrompts.stripThinkBlocks(full)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// If the JSON is truncated (e.g. token limit), attempts to repair it.
    private func extractJSON(from text: String) -> String? {
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
        return repairTruncatedJSON(String(cleaned[startIndex...]))
    }

    /// Attempt to repair truncated JSON like `{"cards":[{...},{...},{incomplete`
    /// by finding the last complete card and closing the structure.
    private func repairTruncatedJSON(_ json: String) -> String? {
        // Find the last complete "}" that closes a card object inside the cards array.
        // Strategy: find last occurrence of "},{"  or the pattern "}]}" which would be the end.
        // If we find "},", we can cut there, close the array and object.

        // Look for the last complete card boundary: "},{"
        // or a complete card ending with just "}"
        guard let cardsStart = json.range(of: #""cards"\s*:\s*\["#, options: .regularExpression) else {
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
