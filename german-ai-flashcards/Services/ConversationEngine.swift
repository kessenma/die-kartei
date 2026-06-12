import Foundation
import SwiftData

/// A single "what could I say next?" suggestion (German + an optional English gloss).
struct HintSuggestion: Identifiable, Equatable {
    let id = UUID()
    let german: String
    let english: String?
}

/// A word the learner tapped to inspect (translate + optionally save).
struct InspectedWord: Identifiable, Equatable {
    let id = UUID()
    let word: String
    var translation: String?
    var loading: Bool
    var saved: Bool
}

/// Drives a single voice conversation: recording, correction, streamed replies,
/// translation, playback, and the end-of-session coaching summary. Persists as it goes.
@Observable
@MainActor
final class ConversationEngine {

    enum Phase: Equatable {
        case idle           // ready for the user to speak
        case loadingModel   // downloading / loading the model into memory
        case listening      // recording the user's turn
        case thinking       // running correction + reply
        case summarizing    // generating the end-of-session report
    }

    // Injected
    let conversation: ChatConversation
    let config: ConversationConfig
    let speechRecognizer = SpeechRecognitionService()
    private let mlxService: MLXGenerationService
    private let modelManager: MLXModelManager
    private let modelContext: ModelContext

    // Derived
    private let systemPrompt: String

    // UI state
    private(set) var phase: Phase = .idle
    /// The cumulative text of the AI reply currently streaming in.
    private(set) var streamingReply: String = ""
    private(set) var errorMessage: String?
    /// IDs of assistant messages whose translation is being generated.
    private(set) var translatingIDs: Set<UUID> = []
    /// The message currently being spoken aloud, if any.
    private(set) var speakingMessageID: UUID?
    /// The word range currently being spoken (for read-along highlighting), within `spokenText`.
    private(set) var spokenRange: NSRange?
    private(set) var spokenText: String?
    /// "What could I say?" suggestions, shown in an inline card when requested.
    private(set) var hints: [HintSuggestion] = []
    private(set) var hintLoading = false
    /// Pre-computed hints (eager assist), tied to the assistant message they were made for.
    private var cachedHints: [HintSuggestion] = []
    private var cachedHintMessageID: UUID?
    /// Background pre-loading work (translation + hint) when eager assist is on.
    private var eagerTask: Task<Void, Never>?
    /// Set when the user views a hint; the next user turn is then marked hint-assisted.
    private var pendingHintUse = false
    /// The word the user tapped to inspect (translate / save), if any.
    private(set) var inspectedWord: InspectedWord?

    // Timer
    private var appearedAt: Date?
    private var baseDuration: Int

    var isRecording: Bool { speechRecognizer.isRecording }
    var liveTranscript: String { speechRecognizer.transcript }
    var micLevel: Double { speechRecognizer.level }
    var isBusy: Bool { phase == .thinking || phase == .loadingModel || phase == .summarizing }

    init(
        conversation: ChatConversation,
        config: ConversationConfig,
        mlxService: MLXGenerationService,
        modelManager: MLXModelManager,
        modelContext: ModelContext
    ) {
        self.conversation = conversation
        self.config = config
        self.mlxService = mlxService
        self.modelManager = modelManager
        self.modelContext = modelContext
        self.systemPrompt = ConversationPrompts.systemPrompt(for: config)
        self.baseDuration = conversation.durationSeconds
    }

    // MARK: - Lifecycle

    func onAppear() {
        if appearedAt == nil { appearedAt = Date() }
        Task { await generateOpenerIfNeeded() }
    }

    /// Live elapsed seconds for the header timer.
    func elapsedSeconds() -> Int {
        guard let appearedAt else { return baseDuration }
        return baseDuration + Int(Date().timeIntervalSince(appearedAt))
    }

    /// Persist the running duration (call on disappear / end).
    func commitDuration() {
        conversation.durationSeconds = elapsedSeconds()
        baseDuration = conversation.durationSeconds
        if appearedAt != nil { appearedAt = Date() }
        save()
    }

    /// Stop the timer accruing while the app is backgrounded / not actively in view.
    func pause() {
        guard let appearedAt else { return }
        baseDuration += Int(Date().timeIntervalSince(appearedAt))
        self.appearedAt = nil
        conversation.durationSeconds = baseDuration
        save()
    }

    /// Resume counting when the user returns to the foreground.
    func resume() {
        if appearedAt == nil { appearedAt = Date() }
    }

    func tearDown() {
        speechRecognizer.cancel()
        SpeechService.shared.stop()
        eagerTask?.cancel()
        pause()
    }

    // MARK: - Model loading

    private func ensureModelLoaded() async -> Bool {
        if mlxService.isModelLoaded, mlxService.currentModel == config.model { return true }
        phase = .loadingModel
        await mlxService.loadModel(config.model)
        if mlxService.isModelLoaded, mlxService.currentModel == config.model {
            modelManager.lastLoadedModel = config.model
            if phase == .loadingModel { phase = .idle }
            return true
        }
        errorMessage = mlxService.loadError ?? "Couldn’t load \(config.model.rawValue)."
        phase = .idle
        return false
    }

    // MARK: - Opener

    private func generateOpenerIfNeeded() async {
        guard conversation.messages.isEmpty else { return }
        guard await ensureModelLoaded() else { return }

        phase = .thinking
        streamingReply = ""
        do {
            let reply = try await mlxService.streamChatReply(
                history: [(role: .user, content: ConversationPrompts.openerSeed)],
                system: systemPrompt,
                model: config.model,
                maxTokens: 200,
                temperature: 0.7
            ) { [weak self] partial in
                self?.streamingReply = partial
            }
            streamingReply = ""
            if let message = appendAssistant(reply) {
                if modelManager.autoPlayReplies { play(message, slow: false) }
                startEagerAssist(for: message)
            }
        } catch is CancellationError {
            // ignore
        } catch {
            errorMessage = friendly(error)
        }
        streamingReply = ""
        phase = .idle
    }

    // MARK: - Recording → turn

    func toggleRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stop()
            return
        }
        guard phase == .idle else { return }
        eagerTask?.cancel()
        eagerTask = nil
        Task { await beginRecording() }
    }

    private func beginRecording() async {
        if !speechRecognizer.isAvailable {
            let granted = await speechRecognizer.requestAuthorization()
            guard granted else {
                errorMessage = authMessage()
                return
            }
        }
        SpeechService.shared.stop()
        speakingMessageID = nil
        errorMessage = nil
        phase = .listening
        speechRecognizer.start { [weak self] finalText in
            guard let self else { return }
            self.phase = .idle
            let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { await self.handleUtterance(trimmed) }
        }
    }

    private func handleUtterance(_ text: String, viaPhraseHelper: Bool = false) async {
        guard await ensureModelLoaded() else { return }

        // 1. Persist the user's turn.
        let userMessage = ChatMessage(role: .user, text: text, sortOrder: nextSortOrder())
        userMessage.targetWordsUsed = ConversationPrompts.matchedWords(in: text, targetWords: config.deckWords)
        userMessage.usedHint = pendingHintUse
        userMessage.usedPhraseHelper = viaPhraseHelper
        pendingHintUse = false
        hints = []  // dismiss the hint card now that the turn is taken
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)
        save()

        phase = .thinking

        // 2. Correction pass (optional). Skip for phrase-helper turns — the German is model-generated.
        if config.correctionsEnabled && !viaPhraseHelper {
            await runCorrection(on: userMessage)
        }

        // 3. Reply pass.
        await runReply()

        phase = .idle
    }

    private func runCorrection(on message: ChatMessage) async {
        let partnerLine = lastAssistantText()
        let system = ConversationPrompts.correctionSystemPrompt(for: config)
        let user = ConversationPrompts.correctionUserPrompt(partnerLine: partnerLine, studentLine: message.text)
        do {
            let raw = try await mlxService.generateText(
                system: system, user: user, model: config.model, maxTokens: 120
            )
            let result = ConversationPrompts.parseCorrection(raw, original: message.text)
            if let corrected = result.correctedText {
                message.correctedText = corrected
                message.correctionNote = result.note
                save()
            }
        } catch {
            // A failed correction shouldn't block the conversation.
        }
    }

    private func runReply() async {
        streamingReply = ""
        let history = recentHistory()
        do {
            let reply = try await mlxService.streamChatReply(
                history: history,
                system: systemPrompt,
                model: config.model,
                maxTokens: 220,
                temperature: 0.7
            ) { [weak self] partial in
                self?.streamingReply = partial
            }
            streamingReply = ""
            if let message = appendAssistant(reply) {
                if modelManager.autoPlayReplies { play(message, slow: false) }
                startEagerAssist(for: message)
            }
        } catch is CancellationError {
            streamingReply = ""
        } catch {
            streamingReply = ""
            errorMessage = friendly(error)
        }
    }

    // MARK: - Translation

    /// User actively reveals an AI reply's translation (counts as a "click"); generates it if needed.
    func revealTranslation(_ message: ChatMessage) {
        guard !message.isUser else { return }
        message.translationViewed = true
        save()
        if message.translationText == nil {
            Task { await translateInline(message) }
        }
    }

    @discardableResult
    private func translateInline(_ message: ChatMessage) async -> Bool {
        guard !message.isUser, message.translationText == nil,
              !translatingIDs.contains(message.id) else { return false }
        translatingIDs.insert(message.id)
        defer { translatingIDs.remove(message.id) }
        guard await ensureModelLoaded() else { return false }
        do {
            let raw = try await mlxService.generateText(
                system: ConversationPrompts.translationSystemPrompt,
                user: ConversationPrompts.translationUserPrompt(german: message.text),
                model: config.model,
                maxTokens: 220
            )
            message.translationText = ConversationPrompts.cleanTranslation(raw)
            save()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    func isTranslating(_ message: ChatMessage) -> Bool {
        translatingIDs.contains(message.id)
    }

    /// Whether the translation block should be displayed under an AI reply.
    func shouldShowTranslation(_ message: ChatMessage) -> Bool {
        message.translationViewed || (config.eagerAssist && config.autoShowTranslation)
    }

    // MARK: - Hint ("what could I say?")

    func requestHints() {
        guard !hintLoading else { return }
        // Actively asking for a hint marks this turn as hint-assisted.
        pendingHintUse = true
        // Use pre-computed hints if they're for the latest assistant turn.
        if !cachedHints.isEmpty, cachedHintMessageID == latestAssistantID() {
            hints = cachedHints
            return
        }
        hintLoading = true
        hints = []
        Task {
            defer { hintLoading = false }
            let produced = await produceHints(count: config.hintCount)
            if !produced.isEmpty {
                hints = produced
                cachedHints = produced
                cachedHintMessageID = latestAssistantID()
            }
        }
    }

    private func produceHints(count: Int) async -> [HintSuggestion] {
        guard await ensureModelLoaded() else { return [] }
        let n = max(1, min(3, count))
        let partner = lastAssistantText() ?? ""
        let system = """
        You are a helpful German tutor. The learner (level \(config.level.rawValue), \(config.formality.rawValue) form) is mid-conversation and may be stuck. \
        Suggest \(n) different, natural thing\(n == 1 ? "" : "s") they could say next in German, each a single sentence appropriate as a reply. \
        Output each suggestion on its own line in EXACTLY this format and nothing else:
        German sentence | English translation
        """
        let user = partner.isEmpty
            ? "Suggest \(n) opening line\(n == 1 ? "" : "s") the learner could say."
            : "The partner just said: \"\(partner)\". Suggest \(n) thing\(n == 1 ? "" : "s") the learner could say in reply."
        do {
            let raw = try await mlxService.generateText(system: system, user: user, model: config.model, maxTokens: 80 + n * 60)
            return parseHintSuggestions(raw, limit: n)
        } catch {
            if !(error is CancellationError) { errorMessage = friendly(error) }
            return []
        }
    }

    private func parseHintSuggestions(_ raw: String, limit: Int) -> [HintSuggestion] {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var result: [HintSuggestion] = []
        for line in cleaned.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            // Drop leading list markers like "1." / "-".
            trimmed = trimmed.replacingOccurrences(of: #"^\s*(\d+[\.\)]|[-•*])\s*"#, with: "", options: .regularExpression)
            guard !trimmed.isEmpty else { continue }
            if let sep = trimmed.range(of: "|") ?? trimmed.range(of: " — ") ?? trimmed.range(of: " - ") {
                let german = String(trimmed[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
                let english = String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !german.isEmpty {
                    result.append(HintSuggestion(german: german, english: english.isEmpty ? nil : english))
                }
            } else {
                result.append(HintSuggestion(german: trimmed, english: nil))
            }
            if result.count >= limit { break }
        }
        return result
    }

    func clearHints() { hints = []; hintLoading = false }

    // MARK: - Tap-a-word inspector (translate + save)

    /// Inspect a tapped word: show its translation and let the user save it to the deck library.
    func inspectWord(_ raw: String) {
        let word = cleanWord(raw)
        guard !word.isEmpty else { return }
        inspectedWord = InspectedWord(
            word: word,
            translation: nil,
            loading: true,
            saved: conversation.isVocabSaved(german: word)
        )
        Task {
            let translation = await translateSingleWord(word)
            // Only apply if the inspector is still showing the same word.
            if inspectedWord?.word == word {
                inspectedWord?.translation = translation
                inspectedWord?.loading = false
            }
        }
    }

    private func translateSingleWord(_ word: String) async -> String? {
        guard await ensureModelLoaded() else { return nil }
        do {
            let raw = try await mlxService.generateText(
                system: ConversationPrompts.translationSystemPrompt,
                user: ConversationPrompts.translationUserPrompt(german: word),
                model: config.model,
                maxTokens: 48
            )
            let cleaned = ConversationPrompts.cleanTranslation(raw)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    /// Save the currently-inspected word to the conversation's vocabulary library.
    func saveInspectedWord() {
        guard let inspected = inspectedWord else { return }
        conversation.saveVocab(german: inspected.word, english: inspected.translation ?? "")
        inspectedWord?.saved = true
        save()
    }

    func dismissInspector() { inspectedWord = nil }

    /// Number of words saved to the library this conversation.
    var savedWordCount: Int { conversation.savedVocab.count }

    func removeSavedWord(_ german: String) {
        conversation.removeVocab(german: german)
        save()
    }

    /// Trim surrounding punctuation/whitespace but keep umlauts and hyphens.
    private func cleanWord(_ s: String) -> String {
        var allowed = CharacterSet.letters
        allowed.insert(charactersIn: "-'’")
        return s.trimmingCharacters(in: allowed.inverted)
    }

    private func latestAssistantID() -> UUID? {
        conversation.sortedMessages.last(where: { !$0.isUser })?.id
    }

    // MARK: - "Say it in German" phrase helper

    /// Translate the learner's intended English response into natural German.
    func englishToGerman(_ english: String) async -> String? {
        let text = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, await ensureModelLoaded() else { return nil }
        let system = """
        You are a German tutor helping a learner (level \(config.level.rawValue), \(config.formality.rawValue) form) say something. \
        Translate the learner's English into ONE natural German sentence they could say out loud. Use the \(config.formality.rawValue) form. \
        Reply with ONLY the German sentence — no English, no quotes, no notes.
        """
        do {
            let raw = try await mlxService.generateText(system: system, user: "English: \(text)\nGerman:", model: config.model, maxTokens: 120)
            let german = ConversationPrompts.cleanTranslation(raw)  // reuses quote/label stripping
            return german.isEmpty ? nil : german
        } catch {
            if !(error is CancellationError) { errorMessage = friendly(error) }
            return nil
        }
    }

    /// Post a phrase-helper sentence as the learner's spoken turn.
    func usePhrase(_ german: String) {
        let text = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, phase == .idle else { return }
        eagerTask?.cancel()
        Task { await handleUtterance(text, viaPhraseHelper: true) }
    }

    // MARK: - Eager assist (background pre-loading)

    private func startEagerAssist(for message: ChatMessage) {
        guard config.eagerAssist else { return }
        eagerTask?.cancel()
        // Lower priority so background translation/hint work doesn't compete with the
        // read-along highlight updates on the main actor while the reply is being read aloud.
        eagerTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.translateInline(message)
            if Task.isCancelled { return }
            let produced = await self.produceHints(count: self.config.hintCount)
            if !produced.isEmpty {
                self.cachedHints = produced
                self.cachedHintMessageID = message.id
            }
        }
    }

    // MARK: - Playback

    func play(_ message: ChatMessage, slow: Bool) {
        speakingMessageID = message.id
        spokenText = message.text
        spokenRange = nil
        SpeechService.shared.speak(
            message.text,
            slow: slow,
            onWord: { [weak self] range in
                guard self?.speakingMessageID == message.id else { return }
                self?.spokenRange = range
            },
            onFinish: { [weak self] in
                if self?.speakingMessageID == message.id {
                    self?.speakingMessageID = nil
                    self?.spokenRange = nil
                    self?.spokenText = nil
                }
            }
        )
    }

    func stopPlayback() {
        SpeechService.shared.stop()
        speakingMessageID = nil
        spokenRange = nil
        spokenText = nil
    }

    // MARK: - Summary

    @discardableResult
    func endAndSummarize() async -> ConversationSummary? {
        speechRecognizer.cancel()
        SpeechService.shared.stop()
        speakingMessageID = nil
        commitDuration()

        let messages = conversation.sortedMessages
        let userTurns = messages.filter { $0.isUser }
        let correctionCount = messages.filter { $0.hasCorrection }.count
        let hintsUsed = messages.filter { $0.usedHint }.count
        let translationsUsed = messages.filter { !$0.isUser && $0.translationViewed }.count
        let phraseHelperUsed = messages.filter { $0.usedPhraseHelper }.count
        var wordsPracticed: [String] = []
        for m in messages { wordsPracticed.append(contentsOf: m.targetWordsUsed) }
        wordsPracticed = Array(Set(wordsPracticed)).sorted()

        // Too little to analyze — store a gentle placeholder.
        guard userTurns.count >= 1, await ensureModelLoaded() else {
            let summary = ConversationSummary(
                strengths: userTurns.isEmpty ? [] : ["You started a conversation in German — keep going!"],
                improvements: ["Try to speak a few more turns next time so there's more to review."],
                patternNote: "",
                wordsPracticed: wordsPracticed,
                correctionCount: correctionCount,
                hintsUsed: hintsUsed,
                translationsUsed: translationsUsed,
                phraseHelperUsed: phraseHelperUsed,
                turnCount: userTurns.count,
                generatedAt: Date(),
                rawText: nil
            )
            conversation.setSummary(summary)
            save()
            return summary
        }

        phase = .summarizing
        defer { phase = .idle }

        let transcript = ConversationPrompts.transcript(from: messages)
        do {
            let raw = try await mlxService.generateText(
                system: ConversationPrompts.summarySystemPrompt(for: config),
                user: transcript,
                model: config.model,
                maxTokens: 360
            )
            let parsed = ConversationPrompts.parseSummary(raw)
            let summary = ConversationSummary(
                strengths: parsed.strengths,
                improvements: parsed.improvements,
                patternNote: parsed.pattern,
                wordsPracticed: wordsPracticed,
                correctionCount: correctionCount,
                hintsUsed: hintsUsed,
                translationsUsed: translationsUsed,
                phraseHelperUsed: phraseHelperUsed,
                turnCount: userTurns.count,
                generatedAt: Date(),
                rawText: (parsed.strengths.isEmpty && parsed.improvements.isEmpty)
                    ? ConversationPrompts.stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
            )
            conversation.setSummary(summary)
            save()
            return summary
        } catch {
            errorMessage = friendly(error)
            return nil
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func appendAssistant(_ text: String) -> ChatMessage? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let message = ChatMessage(role: .assistant, text: clean, sortOrder: nextSortOrder())
        message.conversation = conversation
        conversation.messages.append(message)
        modelContext.insert(message)
        save()
        return message
    }

    private func nextSortOrder() -> Int {
        (conversation.messages.map(\.sortOrder).max() ?? -1) + 1
    }

    private func lastAssistantText() -> String? {
        conversation.sortedMessages.last(where: { !$0.isUser })?.text
    }

    /// The most recent turns, mapped for the model (capped to keep latency sane).
    private func recentHistory() -> [(role: ChatRole, content: String)] {
        conversation.sortedMessages
            .suffix(12)
            .map { (role: $0.role, content: $0.text) }
    }

    private func save() {
        conversation.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            print("[ConversationEngine] save failed: \(error)")
        }
    }

    private func friendly(_ error: Error) -> String {
        if let mlxError = error as? MLXError { return mlxError.errorDescription ?? "Something went wrong." }
        return error.localizedDescription
    }

    private func authMessage() -> String {
        switch speechRecognizer.availability {
        case .denied(let m), .unavailable(let m): return m
        default: return "Microphone and speech recognition access are required to talk."
        }
    }
}
