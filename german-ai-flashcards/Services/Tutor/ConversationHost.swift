import Foundation

// What a ConversationSession needs from the platform it runs on, besides the model
// (`TutorGenerating`). iOS answers with SwiftData records, the Speech framework and
// AVSpeechSynthesizer (ConversationEngine.swift); Android with in-memory records and its own
// voice. Each protocol lists exactly the members the session touches.

/// One message of a conversation, as the session reads and annotates it. iOS: `ChatMessage`.
@MainActor
protocol TutorChatMessage: AnyObject {
    var id: UUID { get }
    var role: ChatRole { get }
    var text: String { get }
    var sortOrder: Int { get }
    var isUser: Bool { get }
    var hasCorrection: Bool { get }

    var correctedText: String? { get set }
    var correctionNote: String? { get set }
    /// The German nudge question ("Nudge me" feedback).
    var correctionHint: String? { get set }
    /// The correction pass looked and found nothing to fix.
    var confirmedClean: Bool { get set }
    /// The learner repaired their own line after a nudge.
    var selfCorrected: Bool { get set }
    var correctionTranslationText: String? { get set }
    var targetWordsUsed: [String] { get set }
    var reviewedWords: [String] { get set }
    var usedHint: Bool { get set }
    var usedPhraseHelper: Bool { get set }
    var translationText: String? { get set }
    var translationViewed: Bool { get set }
}

/// The conversation record. iOS: `ChatConversation`.
@MainActor
protocol TutorChatRecord: AnyObject {
    associatedtype Message: TutorChatMessage
    var id: UUID { get }
    var messages: [Message] { get }
    var sortedMessages: [Message] { get }
    /// Seconds spent in this chat (only ever added to: iCloud merges it per device).
    var durationSeconds: Int { get set }
    var inputModeRaw: String { get set }
    var updatedAt: Date { get set }
    var savedVocab: [SavedVocabItem] { get }
    func isVocabSaved(german: String) -> Bool
    func saveVocab(german: String, english: String)
    func removeVocab(german: String)
    func setSummary(_ summary: ConversationSummary)
}

/// Storage, settings and app services for one conversation.
@MainActor
protocol ConversationHost: AnyObject {
    associatedtype Conversation: TutorChatRecord
    var conversation: Conversation { get }

    /// A new message, attached to the conversation (and inserted into the store). Not saved yet.
    func appendMessage(role: ChatRole, text: String, sortOrder: Int) -> Conversation.Message
    /// Persist the conversation. Called after every change.
    func save()
    /// Hand a stretch of chat time to the study calendar.
    func recordStudyTime(seconds: Int)
    /// The session's summary is in: fold it into the learner's long-term memory, if that's on.
    func sessionSummarized(raw: String, messages: [Conversation.Message], wordsPracticed: [String])

    /// Read replies aloud when they arrive (the learner's setting; typing mode overrides it).
    var autoPlayReplies: Bool { get }
    /// The learner's best run of unaided turns, across all chats.
    var bestUnaidedStreak: Int { get set }
    /// The model just loaded for a chat, for the app to offer first next time.
    func rememberLoaded(_ model: MLXModel)
    /// A dictionary answer for a capitalized word (article and English), so a tap on a known
    /// noun needs no model. `nil` when the dictionary doesn't know it or there's none.
    func nounLookup(_ word: String) -> (article: GermanArticle, english: String?)?
}

/// The microphone side: live speech-to-text for the learner's turn.
@MainActor
protocol SpeechInput: AnyObject {
    var isRecording: Bool { get }
    var transcript: String { get }
    /// 0…1 input level, for the mic animation.
    var level: Double { get }
    var isAvailable: Bool { get }
    /// Why speaking isn't possible (permission denied, no recognizer), if that's known.
    var unavailableMessage: String? { get }
    func requestAuthorization() async -> Bool
    /// Start listening; `onFinal` gets the finished turn.
    func start(onFinal: @escaping (String) -> Void)
    func stop()
    func restart()
    func cancel()
    func appendPunctuation(_ mark: String)
}

/// The speaker side: the tutor's voice.
@MainActor
protocol SpeechOutput: AnyObject {
    /// Speak `text`; `onWord` gets each word's range as it's spoken (if the platform reports it),
    /// `onFinish` fires once at the end or on stop.
    func speak(_ text: String, slow: Bool, onWord: @escaping (NSRange) -> Void, onFinish: @escaping () -> Void)
    func stop()
    /// Stammtisch's pub noise, under the tutor's voice only.
    func startBackgroundNoise()
    func stopBackgroundNoise()
}

/// Spaced re-encounter: SRS-due words steered into the chat, advanced when used correctly.
@MainActor
protocol ConversationReviewing: AnyObject {
    var dueDisplayWords: [String] { get }
    /// The due words this turn used correctly (their schedule has been advanced).
    func registerTurn(text: String, correctedText: String?) -> [String]
}

/// For platforms without speech recognition yet: always unavailable, typing only.
@MainActor
final class NoSpeechInput: SpeechInput {
    let unavailableMessage: String?
    init(reason: String) { unavailableMessage = reason }
    var isRecording: Bool { false }
    var transcript: String { "" }
    var level: Double { 0 }
    var isAvailable: Bool { false }
    func requestAuthorization() async -> Bool { false }
    func start(onFinal: @escaping (String) -> Void) {}
    func stop() {}
    func restart() {}
    func cancel() {}
    func appendPunctuation(_ mark: String) {}
}
