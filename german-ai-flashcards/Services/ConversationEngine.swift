import Foundation
import SwiftData

/// A single "what could I say next?" suggestion (German + an optional English gloss).
struct HintSuggestion: Identifiable, Equatable {
    let id = UUID()
    let german: String
    let english: String?
}

/// A phrase the learner asked help with via "Say it in German", now shown above the mic so they
/// can practice saying it out loud themselves (instead of it being auto-posted). Tracks their
/// spoken attempt so the card can coach them when they miss.
struct SayItPrompt: Identifiable, Equatable {
    let id = UUID()
    /// The target German sentence to say out loud.
    let german: String
    /// The learner's original English (shown as a reminder of intent), if any.
    let english: String?
    /// What the recognizer heard on their most recent attempt.
    var heardText: String?
    /// nil until they've tried; true if the attempt was close enough, false if it missed.
    var matched: Bool?
}

/// An in-flight elicitation ("Nudge me") repair: the coach found a mistake and, instead of handing
/// over the fix, is asking a targeted question so the learner can correct themselves. The AI's reply
/// is deferred until the repair resolves (a good-enough spoken retry, a reveal, or a skip). Mirrors
/// `SayItPrompt`'s try-again loop, but the target is the corrected version of the learner's own line.
struct RepairPrompt: Identifiable, Equatable {
    let id = UUID()
    /// The user message being repaired.
    let messageID: UUID
    /// The corrected sentence the learner should reproduce (the hidden answer).
    let target: String
    /// The German question steering the learner toward their mistake.
    let hint: String
    /// The short English "why", shown alongside the answer once it's revealed.
    let note: String?
    /// What the recognizer heard on the learner's most recent retry.
    var heardText: String?
    /// nil until they've tried; true if the retry matched the target, false if it missed.
    var matched: Bool?
    /// Whether the answer has been revealed — after a miss, or on request.
    var revealed: Bool = false
}

/// Drives a single voice conversation: recording, correction, streamed replies,
/// translation, playback, and the end-of-session coaching summary. Persists as it goes.
/// Conforms to `WordInspecting` (inspectedWord/save/dismiss) so the shared `WordInspectorSheet`
/// can present its tap-a-word state.
@Observable
@MainActor
final class ConversationEngine: WordInspecting {

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
    /// Spaced re-encounter: surfaces SRS-due words and advances their schedule on correct use.
    /// `nil` when the feature is off, doesn't apply to this mode, or nothing is currently due.
    private let reviewTracker: ConversationReviewTracker?

    // UI state
    private(set) var phase: Phase = .idle
    /// The cumulative text of the AI reply currently streaming in.
    private(set) var streamingReply: String = ""
    private(set) var errorMessage: String?
    /// IDs of assistant messages whose translation is being generated.
    private(set) var translatingIDs: Set<UUID> = []
    /// IDs of user messages whose correction's English meaning is being generated.
    private(set) var translatingCorrectionIDs: Set<UUID> = []
    /// The message currently being spoken aloud, if any.
    private(set) var speakingMessageID: UUID?
    /// The word range currently being spoken (for read-along highlighting), within `spokenText`.
    private(set) var spokenRange: NSRange?
    private(set) var spokenText: String?
    /// "What could I say?" suggestions, shown in an inline card when requested.
    private(set) var hints: [HintSuggestion] = []
    private(set) var hintLoading = false
    /// A "Say it in German" phrase the learner is practicing saying out loud, shown above the mic.
    private(set) var sayItPrompt: SayItPrompt?
    /// An in-flight "Nudge me" repair — the AI's reply is deferred until this resolves. `nil` unless
    /// the learner is mid-elicitation on their latest turn.
    private(set) var repairPrompt: RepairPrompt?
    /// Pre-computed hints (eager assist), tied to the assistant message they were made for.
    private var cachedHints: [HintSuggestion] = []
    private var cachedHintMessageID: UUID?
    /// Background pre-loading work (translation + hint) when eager assist is on.
    private var eagerTask: Task<Void, Never>?
    /// Set when the user views a hint; the next user turn is then marked hint-assisted.
    private var pendingHintUse = false
    /// The word the user tapped to inspect (translate / save), if any.
    private(set) var inspectedWord: InspectedWord?
    /// Set when the user taps a model-requiring control before the model is loaded.
    /// Drives the "load this conversation's model" prompt in the view.
    private(set) var showModelLoadPrompt = false
    /// Action to run once the model finishes loading from that prompt (if any).
    private var pendingModelAction: (() -> Void)?

    // Timer
    private var appearedAt: Date?
    private var baseDuration: Int
    /// How much of `conversation.durationSeconds` has already been banked into the day log. Seeded
    /// from the stored duration so re-opening an old chat replays none of its history; only the
    /// seconds added in this sitting get logged.
    private var loggedSeconds: Int

    var isRecording: Bool { speechRecognizer.isRecording }
    var liveTranscript: String { speechRecognizer.transcript }
    var micLevel: Double { speechRecognizer.level }
    var isBusy: Bool { phase == .thinking || phase == .loadingModel || phase == .summarizing }
    /// True when this conversation's model is loaded into memory and ready to generate.
    var isModelReady: Bool { mlxService.isModelLoaded && mlxService.currentModel == config.model }
    /// True while this conversation's model is loading / downloading.
    var isLoadingModel: Bool { phase == .loadingModel }

    init(
        conversation: ChatConversation,
        config: ConversationConfig,
        mlxService: MLXGenerationService,
        modelManager: MLXModelManager,
        modelContext: ModelContext
    ) {
        self.conversation = conversation
        self.mlxService = mlxService
        self.modelManager = modelManager
        self.modelContext = modelContext

        // Inject the learner's persistent coach memory (steering + correction hints) at session
        // start, when personalized coaching is on. Only the compact top-slice reaches the prompt.
        var cfg = config
        if modelManager.chatPersonalizedCoaching {
            cfg.learnerBriefing = LearnerMemoryService.briefing(in: modelContext)
            cfg.correctionMemoryHint = LearnerMemoryService.correctionHint(in: modelContext)
        }

        // Spaced re-encounter: surface any SRS-due words and steer the conversation toward them.
        // The tracker holds live SavedCard references so a correct re-use advances the real schedule.
        if modelManager.chatSpacedReview,
           let tracker = ConversationReviewTracker.make(
               scope: modelManager.spacedReviewScope,
               mode: cfg.mode,
               deckIDs: cfg.deckIDs,
               in: modelContext
           ) {
            cfg.dueReviewWords = tracker.dueDisplayWords
            self.reviewTracker = tracker
        } else {
            self.reviewTracker = nil
        }

        self.config = cfg
        self.systemPrompt = ConversationPrompts.systemPrompt(for: cfg)
        self.baseDuration = conversation.durationSeconds
        self.loggedSeconds = conversation.durationSeconds
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
        bankStudyTime()
        save()
    }

    /// Stop the timer accruing while the app is backgrounded / not actively in view.
    func pause() {
        guard let appearedAt else { return }
        baseDuration += Int(Date().timeIntervalSince(appearedAt))
        self.appearedAt = nil
        conversation.durationSeconds = baseDuration
        bankStudyTime()
        save()
    }

    /// Hand the seconds added since the last commit to the day log. Done as a running delta rather
    /// than once at the end so time still lands on the calendar for a chat that's abandoned, never
    /// summarized, or spread over several sittings — and never double-counts a resummarized one.
    private func bankStudyTime() {
        let delta = conversation.durationSeconds - loggedSeconds
        guard delta > 0 else { return }
        loggedSeconds = conversation.durationSeconds
        StudyLogService.recordTime(.conversation, seconds: delta, in: modelContext)
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

    /// Guard a model-dependent action. Returns `true` if the model is already loaded; otherwise
    /// raises the load prompt (optionally stashing `action` to run after a successful load) and
    /// returns `false`. Lets every entry point fail gracefully when an older conversation is opened
    /// before its model is in memory.
    @discardableResult
    func requireModelReady(orRun action: (() -> Void)? = nil) -> Bool {
        if isModelReady { return true }
        pendingModelAction = action
        showModelLoadPrompt = true
        return false
    }

    /// Explicitly load this conversation's model (e.g. from the header menu). No-op if it's already
    /// loaded or currently loading.
    func loadModel() {
        guard !isModelReady, !isLoadingModel else { return }
        Task { await ensureModelLoaded() }
    }

    /// The user confirmed the load prompt — load the model, then run any stashed action.
    func confirmModelLoad() {
        showModelLoadPrompt = false
        let action = pendingModelAction
        pendingModelAction = nil
        Task { if await ensureModelLoaded() { action?() } }
    }

    /// The user dismissed the load prompt without loading.
    func cancelModelLoad() {
        showModelLoadPrompt = false
        pendingModelAction = nil
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
            } else {
                // The opener came back empty — surface it so the screen isn't stuck on
                // "Getting ready…" with no way forward. "Try again" re-runs this.
                errorMessage = "The conversation couldn’t get started."
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
        // An older conversation may be open before its model is loaded — prompt to load it rather
        // than silently starting a (possibly long) load with a live mic. The user taps again once
        // it's ready, so we don't hot-mic them at the end of a download.
        guard requireModelReady() else { return }
        eagerTask?.cancel()
        eagerTask = nil
        Task { await beginRecording() }
    }

    /// Add a punctuation mark to the live transcript while recording (period / question mark).
    func addPunctuation(_ mark: String) {
        speechRecognizer.appendPunctuation(mark)
    }

    /// Clear the current spoken turn and keep listening, for when the learner wants a do-over.
    func restartRecording() {
        guard speechRecognizer.isRecording else { return }
        speechRecognizer.restart()
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
            // A live nudge means this turn is a self-correction attempt; a live "say it" target
            // means it's a practice attempt. Otherwise it's a free reply.
            if self.repairPrompt != nil {
                Task { await self.evaluateRepairAttempt(trimmed) }
            } else if self.sayItPrompt != nil {
                Task { await self.evaluateSayItAttempt(trimmed) }
            } else {
                Task { await self.handleUtterance(trimmed) }
            }
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
        sayItPrompt = nil  // and the say-it practice card
        userMessage.conversation = conversation
        conversation.messages.append(userMessage)
        modelContext.insert(userMessage)
        save()

        phase = .thinking

        // 2. Correction pass (optional). Skip for phrase-helper turns — the German is model-generated.
        if config.correctionsEnabled && !viaPhraseHelper {
            await runCorrection(on: userMessage)
        }

        // 2b. Spaced re-encounter: advance any SRS-due card the learner used correctly this turn.
        //     Skip phrase-helper turns — the learner didn't produce that German themselves.
        if let reviewTracker, !viaPhraseHelper {
            let reviewed = reviewTracker.registerTurn(text: text, correctedText: userMessage.correctedText)
            if !reviewed.isEmpty {
                userMessage.reviewedWords = reviewed
                save()
            }
        }

        // 2c. Elicitation feedback ("Nudge me"): if there's a fix and a nudge question, hold the AI
        //     reply and ask the learner to repair their own line first. The reply runs once the
        //     repair resolves (see `continueAfterNudge`). Phrase-helper turns skip this — the German
        //     wasn't the learner's own production.
        if config.feedbackStyle == .nudgeMe, !viaPhraseHelper,
           userMessage.hasCorrection, let hint = userMessage.correctionHint, !hint.isEmpty {
            beginRepair(for: userMessage)
            phase = .idle
            return
        }

        // 3. Reply pass.
        await runReply()

        phase = .idle

        // 4. With the turn done and the model free, fill in the correction's English meaning if the
        //    setting is on (no-op when there was no correction). Kept off the reply's critical path.
        if config.correctionTranslationEnabled && !viaPhraseHelper {
            await translateCorrection(userMessage)
        }
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
                // Elicitation feedback: keep the German nudge question so the learner can self-correct.
                if config.feedbackStyle == .nudgeMe { message.correctionHint = result.hint }
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
            } else {
                // Empty reply: nothing gets appended, so the turn would silently end on the
                // learner's message. Flag it so a "Try again" affordance appears.
                errorMessage = "The reply came back empty."
            }
        } catch is CancellationError {
            streamingReply = ""
        } catch {
            streamingReply = ""
            errorMessage = friendly(error)
        }
    }

    // MARK: - Retry

    /// True when the thread is left hanging on the learner: the AI opener never landed, or the
    /// last message is the learner's with no reply after it (a failed or empty generation). Drives
    /// the "Try again" affordance so the user isn't stuck as the last speaker.
    var canRetryReply: Bool {
        guard phase == .idle else { return false }
        guard let last = conversation.sortedMessages.last else { return true }
        return last.isUser
    }

    /// Re-run the generation that failed or came back empty: the opener when no messages exist yet,
    /// otherwise a fresh reply to the learner's last turn. Correction isn't re-run — it already ran
    /// (or was skipped) on the original turn, so this only regenerates the AI's reply.
    func retryReply() {
        guard canRetryReply else { return }
        errorMessage = nil
        if conversation.messages.isEmpty {
            Task { await generateOpenerIfNeeded() }
            return
        }
        Task {
            guard await ensureModelLoaded() else { return }
            phase = .thinking
            await runReply()
            phase = .idle
        }
    }

    // MARK: - Translation

    /// User actively reveals an AI reply's translation (counts as a "click"); generates it if needed.
    func revealTranslation(_ message: ChatMessage) {
        guard !message.isUser else { return }
        guard requireModelReady(orRun: { [weak self] in self?.revealTranslation(message) }) else { return }
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

    // MARK: - Correction translation ("what the suggestion means")

    /// Whether the English meaning should be shown under a correction (driven by the setting).
    func shouldShowCorrectionTranslation(_ message: ChatMessage) -> Bool {
        config.correctionTranslationEnabled && message.hasCorrection
    }

    func isTranslatingCorrection(_ message: ChatMessage) -> Bool {
        translatingCorrectionIDs.contains(message.id)
    }

    /// Lazily generate a correction's English meaning if it's missing — used when an older
    /// conversation is reopened (or the setting is flipped on mid-session). Won't force a model
    /// load; it runs once the model is ready.
    func ensureCorrectionTranslation(_ message: ChatMessage) {
        guard config.correctionTranslationEnabled,
              message.hasCorrection,
              message.correctionTranslationText == nil,
              phase == .idle,
              isModelReady else { return }
        Task { await translateCorrection(message) }
    }

    @discardableResult
    private func translateCorrection(_ message: ChatMessage) async -> Bool {
        guard let corrected = message.correctedText, !corrected.isEmpty,
              message.correctionTranslationText == nil,
              !translatingCorrectionIDs.contains(message.id) else { return false }
        translatingCorrectionIDs.insert(message.id)
        defer { translatingCorrectionIDs.remove(message.id) }
        guard await ensureModelLoaded() else { return false }
        do {
            let raw = try await mlxService.generateText(
                system: ConversationPrompts.translationSystemPrompt,
                user: ConversationPrompts.translationUserPrompt(german: corrected),
                model: config.model,
                maxTokens: 160
            )
            let cleaned = ConversationPrompts.cleanTranslation(raw)
            message.correctionTranslationText = cleaned.isEmpty ? nil : cleaned
            save()
            return message.correctionTranslationText != nil
        } catch is CancellationError {
            return false
        } catch {
            return false
        }
    }

    // MARK: - Hint ("what could I say?")

    func requestHints() {
        guard !hintLoading else { return }
        guard requireModelReady(orRun: { [weak self] in self?.requestHints() }) else { return }
        // Actively asking for a hint marks this turn as hint-assisted.
        pendingHintUse = true
        sayItPrompt = nil  // don't stack with a say-it practice card
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
        let word = SingleWordTranslator.cleanWord(raw)
        guard !word.isEmpty else { return }
        // Translating a tapped word needs the model — prompt to load it rather than opening an
        // inspector that just spins.
        guard requireModelReady(orRun: { [weak self] in self?.inspectWord(raw) }) else { return }
        inspectedWord = InspectedWord(
            word: word,
            translation: nil,
            loading: true,
            loadingModel: !SingleWordTranslator.isReady(config.model, in: mlxService),
            saved: conversation.isVocabSaved(german: word)
        )
        Task {
            let translation = await translateSingleWord(word) { [weak self] in
                guard let self, inspectedWord?.word == word else { return }
                inspectedWord?.loadingModel = false
            }
            // Only apply if the inspector is still showing the same word.
            if inspectedWord?.word == word {
                inspectedWord?.translation = translation
                inspectedWord?.loading = false
                inspectedWord?.loadingModel = false
            }
        }
    }

    /// `onModelReady` fires once the weights are in memory, so the sheet can stop explaining the
    /// load wait and say it's translating.
    private func translateSingleWord(
        _ word: String,
        onModelReady: (@MainActor () -> Void)? = nil
    ) async -> String? {
        guard await ensureModelLoaded() else { return nil }
        return await SingleWordTranslator.translate(
            word, mlxService: mlxService, model: config.model, onModelReady: onModelReady
        )
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

    /// Surface a translated phrase above the mic so the learner can practice *saying* it themselves,
    /// rather than auto-posting it. Mirrors how hints are shown. The user then taps the mic and
    /// speaks it; `evaluateSayItAttempt` judges the result.
    func practiceSaying(_ german: String, english: String?) {
        let text = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        hints = []  // don't stack with a hint card
        let gloss = english?.trimmingCharacters(in: .whitespacesAndNewlines)
        sayItPrompt = SayItPrompt(german: text, english: (gloss?.isEmpty == false) ? gloss : nil)
    }

    func clearSayItPrompt() { sayItPrompt = nil }

    /// Post the active say-it target as the learner's turn without a spoken attempt — the
    /// "use it anyway" escape hatch that preserves the old one-tap behavior.
    func useSayItPromptAnyway() {
        guard let prompt = sayItPrompt else { return }
        sayItPrompt = nil
        usePhrase(prompt.german)
    }

    /// Judge a spoken attempt against the active say-it target. Close enough → post the correct
    /// German as the turn; otherwise keep the card up in a coaching state so they can try again.
    private func evaluateSayItAttempt(_ heard: String) async {
        guard let prompt = sayItPrompt else {
            await handleUtterance(heard)  // safety: no target, treat as a normal turn
            return
        }
        if Self.phraseSimilarity(heard, prompt.german) >= 0.75 {
            sayItPrompt = nil
            await handleUtterance(prompt.german, viaPhraseHelper: true)
        } else {
            sayItPrompt?.heardText = heard
            sayItPrompt?.matched = false
        }
    }

    // MARK: - Elicitation repair ("Nudge me")

    /// The message whose correction is currently being elicited (its full fix stays hidden until the
    /// repair resolves). Lets the view swap the answer card for a nudge while this is active.
    var activeRepairMessageID: UUID? { repairPrompt?.messageID }

    /// Raise a nudge for a corrected turn: show the question, defer the AI reply, and gate the mic so
    /// the next utterance is judged as a self-correction attempt.
    private func beginRepair(for message: ChatMessage) {
        guard let corrected = message.correctedText,
              let hint = message.correctionHint, !hint.isEmpty else { return }
        hints = []          // don't stack with a hint card
        sayItPrompt = nil   // …or a say-it practice card
        repairPrompt = RepairPrompt(
            messageID: message.id,
            target: corrected,
            hint: hint,
            note: message.correctionNote
        )
    }

    /// Judge a spoken retry against the corrected sentence. Close enough → the learner repaired their
    /// own error: mark it and let the conversation continue. A miss reveals the answer so they can
    /// try again or move on.
    private func evaluateRepairAttempt(_ heard: String) async {
        guard let prompt = repairPrompt,
              let message = conversation.messages.first(where: { $0.id == prompt.messageID }) else {
            await handleUtterance(heard)  // safety: no active nudge, treat as a normal turn
            return
        }
        if Self.phraseSimilarity(heard, prompt.target) >= 0.75 {
            message.selfCorrected = true
            save()
            repairPrompt = nil
            await continueAfterNudge(message)
        } else {
            // Missed — reveal the fix (per "only after a miss, or on request") and keep the card up.
            repairPrompt?.heardText = heard
            repairPrompt?.matched = false
            repairPrompt?.revealed = true
        }
    }

    /// Reveal the corrected sentence without a spoken retry ("show me the answer").
    func revealRepair() {
        repairPrompt?.revealed = true
    }

    /// Dismiss the nudge and let the conversation continue — the fix stays visible on the message,
    /// but the learner didn't repair it themselves. Used by "Continue", "Skip", and the close button.
    func skipRepair() {
        guard let prompt = repairPrompt,
              let message = conversation.messages.first(where: { $0.id == prompt.messageID }) else {
            repairPrompt = nil
            return
        }
        repairPrompt = nil
        Task { await continueAfterNudge(message) }
    }

    /// Run the deferred AI reply after a nudge resolves, then fill in the correction's meaning if on.
    private func continueAfterNudge(_ message: ChatMessage) async {
        guard await ensureModelLoaded() else { return }
        phase = .thinking
        await runReply()
        phase = .idle
        if config.correctionTranslationEnabled {
            await translateCorrection(message)
        }
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
        let selfCorrections = messages.filter { $0.selfCorrected }.count
        let hintsUsed = messages.filter { $0.usedHint }.count
        let translationsUsed = messages.filter { !$0.isUser && $0.translationViewed }.count
        let phraseHelperUsed = messages.filter { $0.usedPhraseHelper }.count
        var wordsPracticed: [String] = []
        for m in messages { wordsPracticed.append(contentsOf: m.targetWordsUsed) }
        wordsPracticed = Array(Set(wordsPracticed)).sorted()

        // SRS-due words the learner re-used correctly, whose review schedule was advanced this session.
        var spacedReviews: [String] = []
        for m in messages { spacedReviews.append(contentsOf: m.reviewedWords) }
        spacedReviews = Array(Set(spacedReviews)).sorted()

        // Too little to analyze — store a gentle placeholder.
        guard userTurns.count >= 1, await ensureModelLoaded() else {
            let summary = ConversationSummary(
                strengths: userTurns.isEmpty ? [] : ["You started a conversation in German — keep going!"],
                improvements: ["Try to speak a few more turns next time so there's more to review."],
                patternNote: "",
                wordsPracticed: wordsPracticed,
                correctionCount: correctionCount,
                selfCorrections: selfCorrections,
                hintsUsed: hintsUsed,
                translationsUsed: translationsUsed,
                phraseHelperUsed: phraseHelperUsed,
                spacedReviews: spacedReviews.isEmpty ? nil : spacedReviews,
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
                selfCorrections: selfCorrections,
                hintsUsed: hintsUsed,
                translationsUsed: translationsUsed,
                phraseHelperUsed: phraseHelperUsed,
                spacedReviews: spacedReviews.isEmpty ? nil : spacedReviews,
                turnCount: userTurns.count,
                generatedAt: Date(),
                rawText: (parsed.strengths.isEmpty && parsed.improvements.isEmpty)
                    ? ConversationPrompts.stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
            )
            conversation.setSummary(summary)

            // Fold this session into the persistent learner profile (decay + WEAK/STRONG delta,
            // vocabulary, single-token slips), cleaning old memories into the archive.
            if modelManager.chatPersonalizedCoaching {
                LearnerMemoryService.applySession(
                    summaryRaw: raw,
                    messages: messages,
                    savedVocab: conversation.savedVocab,
                    wordsPracticed: wordsPracticed,
                    in: modelContext
                )
            }

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

    // MARK: - Phrase similarity (say-it practice)

    /// A 0…1 similarity between two German phrases, ignoring case, punctuation and ß/ss spelling —
    /// used to decide whether a spoken attempt matches the say-it target closely enough.
    static func phraseSimilarity(_ a: String, _ b: String) -> Double {
        let x = Array(normalizedForCompare(a))
        let y = Array(normalizedForCompare(b))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 1 }
        let distance = levenshtein(x, y)
        let maxLen = max(x.count, y.count)
        return maxLen == 0 ? 1 : 1 - Double(distance) / Double(maxLen)
    }

    /// Lowercase, fold ß→ss, drop everything but letters and single spaces — so the comparison
    /// reflects the spoken words, not capitalization or end punctuation the recognizer omits anyway.
    private static func normalizedForCompare(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "ß", with: "ss")
        let kept = lowered.unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(kept))
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
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
