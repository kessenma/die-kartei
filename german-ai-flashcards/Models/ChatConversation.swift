import Foundation
import SwiftData

// MARK: - Persisted coaching summary

/// The end-of-session analysis, encoded into `ChatConversation.summaryData`.
nonisolated struct ConversationSummary: Codable {
    var strengths: [String]
    var improvements: [String]
    var patternNote: String
    var wordsPracticed: [String]
    var correctionCount: Int
    /// Optional for backward-compatibility with summaries saved before hint tracking.
    var hintsUsed: Int?
    /// Optional for backward-compatibility — AI replies the learner translated to English.
    var translationsUsed: Int?
    /// Optional — turns produced via the "Say it in German" helper.
    var phraseHelperUsed: Int?
    var turnCount: Int
    var generatedAt: Date
    /// Raw model text kept as a fallback when structured parsing was incomplete.
    var rawText: String?

    var isEmpty: Bool {
        strengths.isEmpty && improvements.isEmpty && patternNote.isEmpty
    }
}

/// A vocabulary word the learner tapped and saved during a conversation.
nonisolated struct SavedVocabItem: Codable, Identifiable, Hashable {
    var german: String
    var english: String
    var id: String { german.lowercased() }
}

// MARK: - Conversation

@Model
final class ChatConversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Total elapsed seconds the user spent in the conversation.
    var durationSeconds: Int

    // Configuration snapshot (raw values mirror the enums in ConversationConfig)
    var modeRaw: String
    var scenarioRaw: String?
    var customScenario: String?
    var focusRaw: [String]
    var levelRaw: String
    var formalityRaw: String
    var strictnessRaw: String
    var correctionsEnabled: Bool
    var autoPlay: Bool
    var modelRaw: String
    var deckIDsRaw: [String]
    var deckLabel: String
    /// For `.paper` mode: the paper's title and reference text (summary) injected into the chat.
    var paperTitle: String?
    var paperContext: String?

    /// Encoded `ConversationSummary`, set when the session is ended & analyzed.
    var summaryData: Data?

    /// Encoded `[SavedVocabItem]` — words the learner tapped and saved during the chat.
    var savedVocabData: Data?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]

    init(config: ConversationConfig, createdAt: Date = .now) {
        self.id = UUID()
        self.title = config.displayTitle
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.durationSeconds = 0
        self.modeRaw = config.mode.rawValue
        self.scenarioRaw = config.scenario?.rawValue
        self.customScenario = config.customScenario.isEmpty ? nil : config.customScenario
        self.focusRaw = config.focusAreas.map { $0.rawValue }
        self.levelRaw = config.level.rawValue
        self.formalityRaw = config.formality.rawValue
        self.strictnessRaw = config.strictness.rawValue
        self.correctionsEnabled = config.correctionsEnabled
        self.autoPlay = config.autoPlay
        self.modelRaw = config.model.rawValue
        self.deckIDsRaw = config.deckIDs.map { $0.uuidString }
        self.deckLabel = config.deckLabel
        self.paperTitle = config.paperTitle
        self.paperContext = config.paperContext
        self.summaryData = nil
        self.messages = []
    }

    // MARK: Derived

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.sortOrder < $1.sortOrder }
    }

    var mode: ConversationMode { ConversationMode(rawValue: modeRaw) ?? .freestyle }
    var scenario: ConversationScenario? { scenarioRaw.flatMap { ConversationScenario(rawValue: $0) } }
    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a2 }
    var formality: Formality { Formality(rawValue: formalityRaw) ?? .du }
    var strictness: CorrectionStrictness { CorrectionStrictness(rawValue: strictnessRaw) ?? .balanced }
    var focusAreas: [GrammarFocus] { focusRaw.compactMap { GrammarFocus(rawValue: $0) } }

    /// The model used, or nil if the stored model no longer exists.
    var model: MLXModel? { MLXModel(rawValue: modelRaw) }

    var summary: ConversationSummary? {
        guard let summaryData else { return nil }
        return try? JSONDecoder().decode(ConversationSummary.self, from: summaryData)
    }

    func setSummary(_ summary: ConversationSummary) {
        self.summaryData = try? JSONEncoder().encode(summary)
    }

    // MARK: Saved vocabulary

    var savedVocab: [SavedVocabItem] {
        guard let savedVocabData else { return [] }
        return (try? JSONDecoder().decode([SavedVocabItem].self, from: savedVocabData)) ?? []
    }

    /// Lowercased German words already saved (for marking them in the message text).
    var savedVocabWords: Set<String> {
        Set(savedVocab.map { $0.german.lowercased() })
    }

    func isVocabSaved(german: String) -> Bool {
        savedVocabWords.contains(german.lowercased())
    }

    /// Save a tapped word (dedups by German word, case-insensitive).
    func saveVocab(german: String, english: String) {
        var items = savedVocab
        guard !items.contains(where: { $0.german.lowercased() == german.lowercased() }) else { return }
        items.append(SavedVocabItem(german: german, english: english))
        savedVocabData = try? JSONEncoder().encode(items)
    }

    func removeVocab(german: String) {
        var items = savedVocab
        items.removeAll { $0.german.lowercased() == german.lowercased() }
        savedVocabData = try? JSONEncoder().encode(items)
    }

    /// Formatted "m:ss" duration for the list/summary UI.
    var durationLabel: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// SF Symbol shown for this conversation in the list.
    var symbolName: String {
        if let scenario { return scenario.systemImage }
        return mode.systemImage
    }
}

// MARK: - Message

@Model
final class ChatMessage {
    var id: UUID
    /// "user" or "assistant".
    var roleRaw: String
    var text: String
    var createdAt: Date
    var sortOrder: Int

    /// For user messages: the corrected German sentence, when the AI flagged an issue.
    var correctedText: String?
    /// For user messages: a short English explanation of the mistake.
    var correctionNote: String?
    /// For user messages: target deck words the learner actually used.
    var targetWordsUsed: [String]
    /// For user messages: whether the learner viewed a hint before this turn.
    /// Default value keeps this a lightweight, additive SwiftData migration.
    var usedHint: Bool = false
    /// For user messages: whether this turn came from the "Say it in German" helper.
    var usedPhraseHelper: Bool = false

    /// For assistant messages: cached English translation (filled on demand).
    var translationText: String?
    /// For assistant messages: whether the learner actively revealed the translation (a "click").
    var translationViewed: Bool = false

    var conversation: ChatConversation?

    init(
        role: ChatRole,
        text: String,
        sortOrder: Int,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.correctedText = nil
        self.correctionNote = nil
        self.targetWordsUsed = []
        self.translationText = nil
    }

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .assistant }
    var isUser: Bool { role == .user }

    /// True when a correction is available to show above the user's bubble.
    var hasCorrection: Bool {
        correctedText?.isEmpty == false
    }
}

// MARK: - Chat role

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}
