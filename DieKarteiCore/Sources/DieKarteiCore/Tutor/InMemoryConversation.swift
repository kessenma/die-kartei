import Foundation
import Observation
#if os(Android)
import SkipFuse   // Android: @Observable through Skip's registrar, so Compose sees the changes
#endif

// A real file in the core, not a link to the app: iOS keeps its chats in SwiftData.
// A conversation kept in memory: the records and host the Android app runs its chats on until
// they're saved to disk, and the ones the core tests drive the session with. Observable, so a
// SwiftUI view redraws when the session annotates a message (a correction landing, a
// translation filled in).

@Observable
final class MemoryChatMessage: TutorChatMessage, Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
    let sortOrder: Int
    let createdAt = Date()

    var correctedText: String?
    var correctionNote: String?
    var correctionHint: String?
    var confirmedClean = false
    var selfCorrected = false
    var correctionTranslationText: String?
    var targetWordsUsed: [String] = []
    var reviewedWords: [String] = []
    var usedHint = false
    var usedPhraseHelper = false
    var translationText: String?
    var translationViewed = false

    init(role: ChatRole, text: String, sortOrder: Int) {
        self.role = role
        self.text = text
        self.sortOrder = sortOrder
    }

    var isUser: Bool { role == .user }
    var hasCorrection: Bool { correctedText?.isEmpty == false }
}

@Observable
final class MemoryChatRecord: TutorChatRecord {
    let id = UUID()
    var messages: [MemoryChatMessage] = []
    var durationSeconds = 0
    var inputModeRaw: String
    var updatedAt = Date()
    private(set) var savedVocab: [SavedVocabItem] = []
    private(set) var summary: ConversationSummary?

    init(inputMode: ChatInputMode = .type) {
        inputModeRaw = inputMode.rawValue
    }

    var sortedMessages: [MemoryChatMessage] { messages.sorted { $0.sortOrder < $1.sortOrder } }

    func isVocabSaved(german: String) -> Bool {
        savedVocab.contains { $0.german.lowercased() == german.lowercased() }
    }

    func saveVocab(german: String, english: String) {
        guard !isVocabSaved(german: german) else { return }
        savedVocab.append(SavedVocabItem(german: german, english: english))
    }

    func removeVocab(german: String) {
        savedVocab.removeAll { $0.german.lowercased() == german.lowercased() }
    }

    func setSummary(_ summary: ConversationSummary) { self.summary = summary }
}

/// Settings and services for an in-memory chat. Every hook is a plain property or closure, so
/// the Android app wires it to its own stores and a test can watch what the session did.
final class MemoryConversationHost: ConversationHost {
    let conversation: MemoryChatRecord
    var autoPlayReplies: Bool
    var bestUnaidedStreak: Int
    /// Called after every save (Android: write the chat to disk).
    var onSave: () -> Void = {}
    var onStudyTime: (Int) -> Void = { _ in }
    var onLoaded: (MLXModel) -> Void = { _ in }
    var onSummary: (_ raw: String, _ wordsPracticed: [String]) -> Void = { _, _ in }
    var dictionary: (String) -> (article: GermanArticle, english: String?)? = { _ in nil }

    init(conversation: MemoryChatRecord? = nil, autoPlayReplies: Bool = false,
         bestUnaidedStreak: Int = 0) {
        self.conversation = conversation ?? MemoryChatRecord()
        self.autoPlayReplies = autoPlayReplies
        self.bestUnaidedStreak = bestUnaidedStreak
    }

    func appendMessage(role: ChatRole, text: String, sortOrder: Int) -> MemoryChatMessage {
        let message = MemoryChatMessage(role: role, text: text, sortOrder: sortOrder)
        conversation.messages.append(message)
        return message
    }

    func save() { onSave() }
    func recordStudyTime(seconds: Int) { onStudyTime(seconds) }
    func sessionSummarized(raw: String, messages: [MemoryChatMessage], wordsPracticed: [String]) {
        onSummary(raw, wordsPracticed)
    }
    func rememberLoaded(_ model: MLXModel) { onLoaded(model) }
    func nounLookup(_ word: String) -> (article: GermanArticle, english: String?)? { dictionary(word) }
}

/// A voice that says nothing: for tests, and for a platform without one.
final class SilentSpeechOutput: SpeechOutput {
    func speak(_ text: String, slow: Bool, onWord: @escaping (NSRange) -> Void, onFinish: @escaping () -> Void) {
        onFinish()
    }
    func stop() {}
    func startBackgroundNoise() {}
    func stopBackgroundNoise() {}
}
