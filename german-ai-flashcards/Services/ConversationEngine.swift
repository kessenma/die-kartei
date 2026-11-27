import Foundation
import SwiftData

// The iOS side of a conversation. The conversation itself (turn flow, corrections, replies,
// hints, nudges, the summary) is `ConversationSession` in Services/Tutor/, shared with the
// Android app; this file plugs it into SwiftData, the Speech framework, AVSpeechSynthesizer and
// the app's settings, and keeps the name and initializer the screens have always used.

typealias ConversationEngine = ConversationSession<SwiftDataConversationHost>

extension ConversationSession where Host == SwiftDataConversationHost {
    convenience init(
        conversation: ChatConversation,
        config: ConversationConfig,
        mlxService: MLXGenerationService,
        modelManager: MLXModelManager,
        modelContext: ModelContext
    ) {
        // Inject the learner's persistent coach memory (steering + correction hints) at session
        // start, when personalized coaching is on. Only the compact top-slice reaches the prompt.
        var cfg = config
        if modelManager.chatPersonalizedCoaching {
            cfg.learnerBriefing = LearnerMemoryService.briefing(in: modelContext)
            cfg.correctionMemoryHint = LearnerMemoryService.correctionHint(in: modelContext)
        }
        // The class, for every chat but the ones that carry their own document.
        if modelManager.classFeedsCoach, cfg.mode != .interview, cfg.mode != .paper {
            cfg.classContext = ClassTutorContext.text(in: modelContext)
        }

        // Spaced re-encounter: surface any SRS-due words and steer the conversation toward them.
        // The tracker holds live SavedCard references so a correct re-use advances the real schedule.
        var reviewer: ConversationReviewTracker?
        if modelManager.chatSpacedReview,
           let tracker = ConversationReviewTracker.make(
               scope: modelManager.spacedReviewScope,
               mode: cfg.mode,
               deckIDs: cfg.deckIDs,
               in: modelContext
           ) {
            cfg.dueReviewWords = tracker.dueDisplayWords
            reviewer = tracker
        }

        self.init(
            host: SwiftDataConversationHost(
                conversation: conversation, modelContext: modelContext, modelManager: modelManager),
            config: cfg,
            tutor: mlxService,
            speechInput: SpeechRecognitionService(),
            speechOutput: AppSpeechOutput(),
            reviewer: reviewer
        )
    }
}

/// Storage and settings for a conversation on iOS: SwiftData records, the study log, the learner
/// memory, and `MLXModelManager`'s settings.
@MainActor
final class SwiftDataConversationHost: ConversationHost {
    let conversation: ChatConversation
    private let modelContext: ModelContext
    private let modelManager: MLXModelManager

    init(conversation: ChatConversation, modelContext: ModelContext, modelManager: MLXModelManager) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.modelManager = modelManager
    }

    func appendMessage(role: ChatRole, text: String, sortOrder: Int) -> ChatMessage {
        let message = ChatMessage(role: role, text: text, sortOrder: sortOrder)
        message.conversation = conversation
        conversation.messages.append(message)
        modelContext.insert(message)
        return message
    }

    func save() {
        do {
            try modelContext.save()
        } catch {
            print("[ConversationEngine] save failed: \(error)")
        }
    }

    func recordStudyTime(seconds: Int) {
        StudyLogService.recordTime(.conversation, seconds: seconds, in: modelContext)
    }

    func sessionSummarized(raw: String, messages: [ChatMessage], wordsPracticed: [String]) {
        guard modelManager.chatPersonalizedCoaching else { return }
        LearnerMemoryService.applySession(
            summaryRaw: raw,
            messages: messages,
            savedVocab: conversation.savedVocab,
            wordsPracticed: wordsPracticed,
            in: modelContext
        )
    }

    var autoPlayReplies: Bool { modelManager.autoPlayReplies }

    var bestUnaidedStreak: Int {
        get { modelManager.chatBestUnaidedStreak }
        set { modelManager.chatBestUnaidedStreak = newValue }
    }

    func rememberLoaded(_ model: MLXModel) { modelManager.lastLoadedModel = model }

    func nounLookup(_ word: String) -> (article: GermanArticle, english: String?)? {
        WiktionaryValidator.shared.nounArticle(for: word)
    }
}

/// The tutor's voice on iOS: `SpeechService` (AVSpeechSynthesizer) and Stammtisch's pub noise.
@MainActor
final class AppSpeechOutput: SpeechOutput {
    func speak(_ text: String, slow: Bool, onWord: @escaping (NSRange) -> Void, onFinish: @escaping () -> Void) {
        SpeechService.shared.speak(text, slow: slow, onWord: onWord, onFinish: onFinish)
    }
    func stop() { SpeechService.shared.stop() }
    func startBackgroundNoise() { StammtischNoise.shared.start() }
    func stopBackgroundNoise() { StammtischNoise.shared.stop() }
}

extension ChatMessage: TutorChatMessage {}
extension ChatConversation: TutorChatRecord {}
extension ConversationReviewTracker: ConversationReviewing {}

extension SpeechRecognitionService: SpeechInput {
    var unavailableMessage: String? {
        switch availability {
        case .denied(let m), .unavailable(let m): return m
        default: return nil
        }
    }
}
