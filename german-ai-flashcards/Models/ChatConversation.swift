import Foundation
import SwiftData

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
    /// Raw `FeedbackStyle` — how corrections are delivered (tell vs. nudge). Default keeps this an
    /// additive SwiftData migration for chats saved before elicitation feedback existed.
    var feedbackStyleRaw: String = FeedbackStyle.tellMe.rawValue
    var correctionsEnabled: Bool
    /// Raw `ChatInputMode` — whether this chat was last taken by voice or by keyboard. Defaulted so
    /// chats saved before typing existed migrate additively (a non-defaulted field would trip the
    /// destructive store reset in the app entry point).
    var inputModeRaw: String = ChatInputMode.speak.rawValue
    var autoPlay: Bool
    var modelRaw: String
    var deckIDsRaw: [String]
    var deckLabel: String
    /// For `.paper` mode: the paper's title and reference text (summary) injected into the chat.
    var paperTitle: String?
    var paperContext: String?
    /// For `.interview` mode: the job title and posting text the recruiter interviews from.
    /// Defaults keep these an additive SwiftData migration.
    var jobTitle: String? = nil
    var jobContext: String? = nil
    /// Employer, job location, and the posting's URL for `.interview` chats. Defaulted so older
    /// stores migrate additively (the app has no versioned schema; a non-defaulted field would
    /// trip the destructive store reset in the app entry point).
    var jobCompany: String? = nil
    var jobLocation: String? = nil
    var jobURL: String? = nil
    /// Raw `InterviewRound` / `InterviewFormat`; nil for chats from before they existed.
    var interviewRoundRaw: String? = nil
    var interviewFormatRaw: String? = nil
    /// Saved PDF copy of the posting (`JobPostingSnapshotStore` file name). Deleted with the chat.
    var jobSnapshotFile: String? = nil
    /// The `JobPosting` this interview was started from (Job prep ▸ a studied posting), so the
    /// two can be grouped later. Nil for chats started straight from the setup screen.
    var jobPostingIDRaw: String? = nil
    /// Encoded `StammtischOptions` when the chat is a Stammtisch (roadmap item 8). Nil otherwise.
    var stammtischData: Data? = nil
    /// The interview used the learner's résumé. Only the flag: the résumé itself never leaves the device.
    var usesResume: Bool = false

    /// Encoded `ConversationSummary`, set when the session is ended & analyzed.
    var summaryData: Data?

    /// Encoded `[SavedVocabItem]` — words the learner tapped and saved during the chat.
    var savedVocabData: Data?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]

    /// What it keeps of the config comes from `ChatSetup` (shared with Android).
    init(config: ConversationConfig, createdAt: Date = .now) {
        let setup = ChatSetup(config: config)
        self.id = UUID()
        self.title = setup.title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.durationSeconds = 0
        self.modeRaw = setup.modeRaw
        self.scenarioRaw = setup.scenarioRaw
        self.customScenario = setup.customScenario
        self.focusRaw = setup.focusRaw
        self.levelRaw = setup.levelRaw
        self.formalityRaw = setup.formalityRaw
        self.strictnessRaw = setup.strictnessRaw
        self.feedbackStyleRaw = setup.feedbackStyleRaw
        self.correctionsEnabled = setup.correctionsEnabled
        self.inputModeRaw = setup.inputModeRaw
        self.autoPlay = setup.autoPlay
        self.modelRaw = setup.modelRaw
        self.deckIDsRaw = setup.deckIDsRaw
        self.deckLabel = setup.deckLabel
        self.paperTitle = setup.paperTitle
        self.paperContext = setup.paperContext
        self.jobTitle = setup.jobTitle
        self.jobContext = setup.jobContext
        self.jobCompany = setup.jobCompany
        self.jobLocation = setup.jobLocation
        self.jobURL = setup.jobURL
        self.interviewRoundRaw = setup.interviewRoundRaw
        self.interviewFormatRaw = setup.interviewFormatRaw
        self.jobSnapshotFile = setup.jobSnapshotFile
        self.jobPostingIDRaw = setup.jobPostingIDRaw
        self.stammtischData = setup.stammtischData
        self.usesResume = setup.usesResume
        self.summaryData = nil
        self.messages = []
    }

    /// The stored setup, for reopening the chat (`ChatSetup.apply`).
    var setup: ChatSetup {
        var s = ChatSetup(modelRaw: modelRaw)
        s.title = title
        s.modeRaw = modeRaw
        s.scenarioRaw = scenarioRaw
        s.customScenario = customScenario
        s.focusRaw = focusRaw
        s.levelRaw = levelRaw
        s.formalityRaw = formalityRaw
        s.strictnessRaw = strictnessRaw
        s.feedbackStyleRaw = feedbackStyleRaw
        s.correctionsEnabled = correctionsEnabled
        s.inputModeRaw = inputModeRaw
        s.autoPlay = autoPlay
        s.deckIDsRaw = deckIDsRaw
        s.deckLabel = deckLabel
        s.paperTitle = paperTitle
        s.paperContext = paperContext
        s.jobTitle = jobTitle
        s.jobContext = jobContext
        s.jobCompany = jobCompany
        s.jobLocation = jobLocation
        s.jobURL = jobURL
        s.interviewRoundRaw = interviewRoundRaw
        s.interviewFormatRaw = interviewFormatRaw
        s.jobSnapshotFile = jobSnapshotFile
        s.jobPostingIDRaw = jobPostingIDRaw
        s.stammtischData = stammtischData
        s.usesResume = usesResume
        return s
    }

    // MARK: Derived

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.sortOrder < $1.sortOrder }
    }

    var mode: ConversationMode { ConversationMode(rawValue: modeRaw) ?? .freestyle }
    var interviewRound: InterviewRound? { interviewRoundRaw.flatMap { InterviewRound(rawValue: $0) } }
    var interviewFormat: InterviewFormat? { interviewFormatRaw.flatMap { InterviewFormat(rawValue: $0) } }
    var jobPostingID: UUID? { jobPostingIDRaw.flatMap { UUID(uuidString: $0) } }
    var scenario: ConversationScenario? { scenarioRaw.flatMap { ConversationScenario(rawValue: $0) } }
    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a2 }
    var formality: Formality { Formality(rawValue: formalityRaw) ?? .du }
    var strictness: CorrectionStrictness { CorrectionStrictness(rawValue: strictnessRaw) ?? .balanced }
    var feedbackStyle: FeedbackStyle { FeedbackStyle(rawValue: feedbackStyleRaw) ?? .tellMe }
    var inputMode: ChatInputMode { ChatInputMode(rawValue: inputModeRaw) ?? .speak }
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
    /// For user messages in "Nudge me" feedback mode: the German elicitation question that points
    /// the learner at their error so they can repair it themselves (the fix stays hidden until they
    /// try or ask to reveal). Default keeps this an additive SwiftData migration.
    var correctionHint: String?
    /// For user messages: whether the learner repaired their own error after a nudge (spoke the
    /// corrected sentence back). Drives the "you fixed this yourself" badge and the session stat.
    var selfCorrected: Bool = false
    /// For user messages: cached English translation of the corrected sentence (filled on demand
    /// when "show English meaning" is on). Default keeps this an additive SwiftData migration.
    var correctionTranslationText: String?
    /// For user messages: target deck words the learner actually used.
    var targetWordsUsed: [String]
    /// For user messages: whether the learner viewed a hint before this turn.
    /// Default value keeps this a lightweight, additive SwiftData migration.
    var usedHint: Bool = false
    /// For user messages: whether this turn came from the "Say it in German" helper.
    var usedPhraseHelper: Bool = false
    /// For user messages: SRS-due words the learner used correctly this turn, advancing their review
    /// schedule (spaced re-encounter). Default keeps this a lightweight, additive SwiftData migration.
    var reviewedWords: [String] = []
    /// For user messages: the correction pass ran and confirmed the sentence clean ("OK").
    /// Distinct from a failed or skipped correction call, which leaves this false.
    var confirmedClean: Bool = false

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
