#if canImport(CLlama)
import CLlama
import Foundation

/// The tutor models on Android: llama.cpp's C API, called straight from Swift.
///
/// What makes it quick on a phone:
/// - **The right kernels per phone.** llama.cpp's CPU backend ships as one library per ARM feature
///   level (dotprod, i8mm, SVE2, SME); `ggml_backend_load_all_from_path` picks the best one the
///   phone supports at launch.
/// - **The fast cores only.** Phones pair a few fast cores with slow efficiency cores, and a
///   llama.cpp step waits for its slowest thread, so the thread count is the number of cores
///   outside the slowest cluster (`performanceCores`).
/// - **Nothing computed twice.** The tutor sends the same long system prompt on every turn, and a
///   conversation only grows. Each slot keeps what is already in the KV cache and only the new
///   tokens are read. The conversation and the per-turn correction check use different system
///   prompts, so they get separate slots and don't evict each other.
/// - **Q4_0 weights**, which llama.cpp repacks for ARM's int8 dot-product instructions (see
///   training/ANDROID_GGUF.md for the speed and score numbers).
///
/// All llama.cpp calls run on one serial queue; the engine is not reentrant.
final class TutorEngine: @unchecked Sendable {
    enum Family: String {
        case gemma4, granite
    }

    /// A KV-cache sequence with its own reused prefix.
    enum Slot: Int32, CaseIterable {
        /// The conversation: system prompt, then every turn.
        case chat = 0
        /// One-off checks (corrections, sentence checks) that share a system prompt.
        case check = 1
    }

    struct Stats: Sendable {
        var promptTokens = 0
        /// Prompt tokens that were already in the cache and not read again.
        var reusedTokens = 0
        var generatedTokens = 0
        var prefillSeconds = 0.0
        var generateSeconds = 0.0

        var tokensPerSecond: Double {
            generateSeconds > 0 ? Double(generatedTokens) / generateSeconds : 0
        }
    }

    enum EngineError: LocalizedError {
        case loadFailed(String)
        case promptTooLong(Int, Int)
        case decodeFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .loadFailed(let path): "Could not load the model at \(path)."
            case .promptTooLong(let n, let max): "The conversation is too long for the model (\(n) of \(max) tokens)."
            case .decodeFailed(let code): "The model stopped with error \(code)."
            }
        }
    }

    let family: Family
    let threads: Int
    /// Context per slot, in tokens.
    let slotContext: Int
    /// What llama.cpp reports about the CPU features it is using.
    let systemInfo: String

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let queue = DispatchQueue(label: "die.kartei.tutor-engine")
    private var cached: [Slot: [llama_token]] = [:]
    private let cancelLock = NSLock()
    private var cancelRequested = false

    private init(model: OpaquePointer, context: OpaquePointer, family: Family, threads: Int, slotContext: Int) {
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.family = family
        self.threads = threads
        self.slotContext = slotContext
        self.systemInfo = String(cString: llama_print_system_info())
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    // MARK: - Loading

    /// Loads llama.cpp's backends once per process, from the directory the app's libraries were
    /// extracted to (where libllama.so lives).
    private static let backendsLoaded: Void = {
        // llama.cpp logs to stderr, which Android drops; send warnings and errors to logcat.
        llama_log_set({ level, text, _ in
            guard let text, level.rawValue >= GGML_LOG_LEVEL_WARN.rawValue else { return }
            let line = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.count > 1 { logger.warning("llama.cpp: \(line)") }   // skips the load progress dots
        }, nil)
        if let dir = nativeLibraryDirectory() {
            logger.info("llama.cpp: loading backends from \(dir)")
            dir.withCString { ggml_backend_load_all_from_path($0) }
        } else {
            ggml_backend_load_all()
        }
        llama_backend_init()
    }()

    /// Loads a GGUF. Slow (seconds): call it off the main thread.
    static func load(path: String, slotContext: Int = 3072) throws -> TutorEngine {
        _ = backendsLoaded

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0       // CPU: the phone GPU backends are a later step
        modelParams.load_mode = LLAMA_LOAD_MODE_MMAP     // weights stay in the file; pages come in as used
        modelParams.lazy_mode = LLAMA_LAZY_MODE_ON       // Gemma's per-layer embeddings: only the rows a token needs
        guard let model = path.withCString({ llama_model_load_from_file($0, modelParams) }) else {
            logger.error("llama.cpp: could not load \(path)")
            throw EngineError.loadFailed(path)
        }
        logger.info("llama.cpp: loaded \(path); \(String(cString: llama_print_system_info()))")

        let threads = performanceCores()
        var contextParams = llama_context_default_params()
        contextParams.n_seq_max = UInt32(Slot.allCases.count)
        contextParams.n_ctx = UInt32(slotContext * Slot.allCases.count)
        contextParams.kv_unified = false    // the slots share no prefix
        contextParams.swa_full = true       // lets Gemma's sliding-window layers keep a reusable prefix
        contextParams.n_batch = 512
        contextParams.n_ubatch = 512
        contextParams.n_threads = Int32(threads)
        contextParams.n_threads_batch = Int32(threads)
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw EngineError.loadFailed(path)
        }

        let architecture = metadata(model, "general.architecture") ?? ""
        let family: Family = architecture.hasPrefix("gemma") ? .gemma4 : .granite
        return TutorEngine(model: model, context: context, family: family, threads: threads, slotContext: slotContext)
    }

    // MARK: - Generating

    func cancel() {
        cancelLock.withLock { cancelRequested = true }
    }

    private var isCancelled: Bool {
        cancelLock.withLock { cancelRequested }
    }

    /// Generates a reply to `messages` (system first, then alternating user/assistant). `onText`
    /// gets the whole reply so far after every token, on the engine's queue.
    func generate(
        messages: [(role: String, content: String)],
        slot: Slot,
        maxTokens: Int,
        temperature: Float,
        onText: (@Sendable (String) -> Void)? = nil
    ) async throws -> (text: String, stats: Stats) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.run(messages: messages, slot: slot, maxTokens: maxTokens,
                                                                temperature: temperature, onText: onText))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func run(
        messages: [(role: String, content: String)],
        slot: Slot,
        maxTokens: Int,
        temperature: Float,
        onText: (@Sendable (String) -> Void)?
    ) throws -> (text: String, stats: Stats) {
        cancelLock.withLock { cancelRequested = false }
        var stats = Stats()
        let tokens = tokenize(prompt(for: messages))
        stats.promptTokens = tokens.count
        guard tokens.count + maxTokens <= slotContext else {
            throw EngineError.promptTooLong(tokens.count + maxTokens, slotContext)
        }

        // Keep the longest prefix already in this slot's cache; read only the rest. At least one
        // token is always read, for the logits of the next one.
        let memory = llama_get_memory(context)
        var have = cached[slot] ?? []
        var keep = zip(have, tokens).prefix { $0 == $1 }.count
        keep = min(keep, tokens.count - 1)
        if keep < have.count {
            if !llama_memory_seq_rm(memory, slot.rawValue, llama_pos(keep), -1) {
                llama_memory_seq_rm(memory, slot.rawValue, -1, -1)
                keep = 0
            }
            have = Array(have.prefix(keep))
        }
        stats.reusedTokens = keep

        let prefillStart = Date()
        try decode(Array(tokens[keep...]), slot: slot, startingAt: keep)
        have = tokens
        cached[slot] = have
        stats.prefillSeconds = Date().timeIntervalSince(prefillStart)

        let sampler = makeSampler(temperature: temperature)
        defer { llama_sampler_free(sampler) }

        let generateStart = Date()
        var bytes: [UInt8] = []
        var text = ""
        for _ in 0..<maxTokens {
            if isCancelled { break }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token)
            try decode([token], slot: slot, startingAt: have.count)
            have.append(token)
            cached[slot] = have
            stats.generatedTokens += 1
            text = String(decoding: bytes, as: UTF8.self)
            // A multi-byte character can arrive split over two tokens; don't show half of it.
            if text.last == "\u{FFFD}" { continue }
            onText?(Self.clean(text))
        }
        stats.generateSeconds = Date().timeIntervalSince(generateStart)
        return (Self.clean(String(decoding: bytes, as: UTF8.self)), stats)
    }

    /// Forgets a slot's cache, e.g. when a new conversation starts.
    func reset(_ slot: Slot) {
        queue.async {
            llama_memory_seq_rm(llama_get_memory(self.context), slot.rawValue, -1, -1)
            self.cached[slot] = []
        }
    }

    // MARK: - Prompt format

    /// The chat template, written out. Gemma 4's template is newer than llama.cpp's built-in list
    /// (which matches templates by pattern, without a Jinja engine), so it's spelled out here,
    /// byte for byte what the model's chat_template.jinja renders. Granite's is built in.
    private func prompt(for messages: [(role: String, content: String)]) -> String {
        switch family {
        case .gemma4:
            var s = ""   // <bos> comes from tokenize(add_special:)
            for m in messages {
                let role = m.role == "assistant" ? "model" : m.role
                s += "<|turn>\(role)\n\(m.content.trimmingCharacters(in: .whitespacesAndNewlines))<turn|>\n"
            }
            return s + "<|turn>model\n"
        case .granite:
            return applyBuiltinTemplate(messages)
        }
    }

    private func applyBuiltinTemplate(_ messages: [(role: String, content: String)]) -> String {
        let template = llama_model_chat_template(model, nil)
        // C strings that live for the call.
        let roles = messages.map { strdup($0.role) }
        let contents = messages.map { strdup($0.content) }
        defer {
            roles.forEach { free($0) }
            contents.forEach { free($0) }
        }
        var chat = (0..<messages.count).map { llama_chat_message(role: roles[$0], content: contents[$0]) }
        var capacity = Int32(messages.reduce(0) { $0 + $1.content.utf8.count } * 2 + 512)
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        var n = llama_chat_apply_template(template, &chat, chat.count, true, &buffer, capacity)
        if n > capacity {
            capacity = n + 1
            buffer = [CChar](repeating: 0, count: Int(capacity))
            n = llama_chat_apply_template(template, &chat, chat.count, true, &buffer, capacity)
        }
        guard n > 0 else {
            // Unknown template: a plain transcript beats failing.
            return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n") + "\nassistant:"
        }
        return String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Drops what a model sometimes writes past its answer: an end-of-turn marker as text, or a
    /// thinking block.
    private static func clean(_ text: String) -> String {
        var t = text
        for marker in ["<turn|>", "<|end_of_text|>", "<end_of_turn>"] {
            if let r = t.range(of: marker) { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - llama.cpp plumbing

    private func tokenize(_ text: String) -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 8)
        var n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true)
        }
        return Array(tokens.prefix(Int(max(n, 0))))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(n, 0))).map { UInt8(bitPattern: $0) }
    }

    /// Reads `tokens` into `slot` at positions `start...`, in batches; logits for the last one only.
    private func decode(_ tokens: [llama_token], slot: Slot, startingAt start: Int) throws {
        let batchSize = 512
        var batch = llama_batch_init(Int32(batchSize), 0, 1)
        defer { llama_batch_free(batch) }
        var offset = 0
        while offset < tokens.count {
            let chunk = tokens[offset..<min(offset + batchSize, tokens.count)]
            batch.n_tokens = Int32(chunk.count)
            for (i, token) in chunk.enumerated() {
                batch.token[i] = token
                batch.pos[i] = llama_pos(start + offset + i)
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = slot.rawValue
                batch.logits[i] = (offset + i == tokens.count - 1) ? 1 : 0
            }
            let result = llama_decode(context, batch)
            guard result == 0 else { throw EngineError.decodeFailed(result) }
            offset += chunk.count
        }
    }

    private func makeSampler(temperature: Float) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if temperature <= 0.05 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(0.05, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        }
        return chain
    }

    private static func metadata(_ model: OpaquePointer, _ key: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = llama_model_meta_val_str(model, key, &buffer, buffer.count)
        guard n > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: - The phone

    /// Cores outside the slowest cluster: on a phone with 1 prime, 3 performance and 4 efficiency
    /// cores, 4. Falls back to 4 (or fewer) where the CPU doesn't report frequencies, as on the
    /// emulator.
    static func performanceCores() -> Int {
        let count = ProcessInfo.processInfo.activeProcessorCount
        let frequencies: [Int] = (0..<count).compactMap { cpu in
            let path = "/sys/devices/system/cpu/cpu\(cpu)/cpufreq/cpuinfo_max_freq"
            guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard frequencies.count == count, let slowest = frequencies.min(), let fastest = frequencies.max(),
              fastest > slowest else {
            return max(1, min(4, count))
        }
        let fast = frequencies.filter { $0 > slowest }.count
        return max(2, min(fast, 8))
    }

    /// Where Android extracted the app's native libraries: the directory holding libllama.so.
    private static func nativeLibraryDirectory() -> String? {
        // procfs files report size 0, so read to EOF instead of by size.
        guard let handle = FileHandle(forReadingAtPath: "/proc/self/maps") else { return nil }
        defer { try? handle.close() }
        let maps = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        for line in maps.split(separator: "\n") where line.hasSuffix("/libllama.so") {
            guard let start = line.firstIndex(of: "/") else { continue }
            let path = String(line[start...])
            return (path as NSString).deletingLastPathComponent
        }
        return nil
    }
}
#endif
