//
//  ChatSetup.swift
//  german-ai-flashcards
//
//  What a saved chat keeps of the setup it was started with, and how a reopened chat gets it
//  back. Foundation only and shared with the Android app (DieKarteiCore): iOS's
//  `ChatConversation(config:)` and `makeConfig` and Android's `ChatConversationRecord` all go
//  through it, so a chat is stored and resumed the same way on both.
//

import Foundation

/// The stored setup of one chat: the `ChatConversation` columns (and sync fields) a
/// `ConversationConfig` fills. App settings (hint count, translations, the learner's name), the
/// deck's words, the coach's briefing and the résumé are not kept: a reopened chat reads them
/// fresh.
struct ChatSetup: Equatable {
    var title = "Freies Gespräch"
    var modeRaw = ConversationMode.freestyle.rawValue
    var scenarioRaw: String? = nil
    var customScenario: String? = nil
    var focusRaw: [String] = []
    var levelRaw = CEFRLevel.a2.rawValue
    var formalityRaw = Formality.du.rawValue
    var strictnessRaw = CorrectionStrictness.balanced.rawValue
    var feedbackStyleRaw = FeedbackStyle.tellMe.rawValue
    var correctionsEnabled = true
    var inputModeRaw = ChatInputMode.speak.rawValue
    var autoPlay = true
    var modelRaw: String
    var deckIDsRaw: [String] = []
    var deckLabel = ""
    var paperTitle: String? = nil
    var paperContext: String? = nil
    var jobTitle: String? = nil
    var jobContext: String? = nil
    var jobCompany: String? = nil
    var jobLocation: String? = nil
    var jobURL: String? = nil
    var interviewRoundRaw: String? = nil
    var interviewFormatRaw: String? = nil
    var jobSnapshotFile: String? = nil
    var jobPostingIDRaw: String? = nil
    /// Encoded `StammtischOptions` (`encoder`: default dates, sorted keys).
    var stammtischData: Data? = nil
    var usesResume = false

    init(modelRaw: String) {
        self.modelRaw = modelRaw
    }

    /// What a new chat stores of its config.
    init(config: ConversationConfig) {
        title = config.displayTitle
        modeRaw = config.mode.rawValue
        scenarioRaw = config.scenario?.rawValue
        customScenario = config.customScenario.isEmpty ? nil : config.customScenario
        focusRaw = config.focusAreas.map { $0.rawValue }
        levelRaw = config.level.rawValue
        formalityRaw = config.formality.rawValue
        strictnessRaw = config.strictness.rawValue
        feedbackStyleRaw = config.feedbackStyle.rawValue
        correctionsEnabled = config.correctionsEnabled
        inputModeRaw = config.inputMode.rawValue
        autoPlay = config.autoPlay
        modelRaw = config.model.rawValue
        deckIDsRaw = config.deckIDs.map { $0.uuidString }
        deckLabel = config.deckLabel
        paperTitle = config.paperTitle
        paperContext = config.paperContext
        jobTitle = config.jobTitle
        jobContext = config.jobContext
        jobCompany = config.jobCompany
        jobLocation = config.jobLocation
        jobURL = config.jobURL
        interviewRoundRaw = config.interviewRound?.rawValue
        interviewFormatRaw = config.interviewFormat?.rawValue
        jobSnapshotFile = config.jobSnapshotFile
        jobPostingIDRaw = config.jobPostingID?.uuidString
        stammtischData = config.stammtisch.flatMap { try? Self.encoder.encode($0) }
        usesResume = config.resumeProfile != nil
    }

    /// Sorted keys, so the same options are always the same bytes (sync reads them as JSON).
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    var mode: ConversationMode { ConversationMode(rawValue: modeRaw) ?? .freestyle }
    var scenario: ConversationScenario? { scenarioRaw.flatMap { ConversationScenario(rawValue: $0) } }
    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a2 }
    var formality: Formality { Formality(rawValue: formalityRaw) ?? .du }
    var strictness: CorrectionStrictness { CorrectionStrictness(rawValue: strictnessRaw) ?? .balanced }
    var feedbackStyle: FeedbackStyle { FeedbackStyle(rawValue: feedbackStyleRaw) ?? .tellMe }
    var inputMode: ChatInputMode { ChatInputMode(rawValue: inputModeRaw) ?? .speak }
    var focusAreas: [GrammarFocus] { focusRaw.compactMap { GrammarFocus(rawValue: $0) } }
    var interviewRound: InterviewRound? { interviewRoundRaw.flatMap { InterviewRound(rawValue: $0) } }
    var interviewFormat: InterviewFormat? { interviewFormatRaw.flatMap { InterviewFormat(rawValue: $0) } }
    var jobPostingID: UUID? { jobPostingIDRaw.flatMap { UUID(uuidString: $0) } }
    /// The model used, or nil if the stored model no longer exists.
    var model: MLXModel? { MLXModel(rawValue: modelRaw) }

    /// A reopened chat's setup onto `c` (whose model, settings and deck words the caller chose).
    func apply(to c: inout ConversationConfig) {
        c.mode = mode
        c.deckIDs = deckIDsRaw.compactMap { UUID(uuidString: $0) }
        c.deckLabel = deckLabel
        c.scenario = scenario
        c.customScenario = customScenario ?? ""
        c.focusAreas = focusAreas
        c.level = level
        c.formality = formality
        c.correctionsEnabled = correctionsEnabled
        c.strictness = strictness
        c.feedbackStyle = feedbackStyle
        c.autoPlay = autoPlay
        c.inputMode = inputMode
        c.paperTitle = paperTitle
        c.paperContext = paperContext
        c.jobTitle = jobTitle
        c.jobContext = jobContext
        c.jobCompany = jobCompany
        c.jobLocation = jobLocation
        c.jobURL = jobURL
        c.interviewRound = interviewRound
        c.interviewFormat = interviewFormat
        c.jobSnapshotFile = jobSnapshotFile
        c.jobPostingID = jobPostingID
        c.stammtisch = stammtischData.flatMap { try? JSONDecoder().decode(StammtischOptions.self, from: $0) }
    }
}

// MARK: - On the wire

extension ChatConversationRecord {
    /// A new chat's record (`ChatConversationCodec.known` of `ChatConversation(config:)`).
    init(id: UUID = UUID(), setup s: ChatSetup, createdAt: Date = Date()) {
        self.init(id: id, modelRaw: s.modelRaw, createdAt: createdAt)
        self.setup = s
    }

    var setup: ChatSetup {
        get {
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
            s.stammtischData = (try? stammtisch?.decoded(as: StammtischOptions.self)).flatMap { try? ChatSetup.encoder.encode($0) }
            s.usesResume = usesResume
            return s
        }
        set {
            title = newValue.title
            modeRaw = newValue.modeRaw
            scenarioRaw = newValue.scenarioRaw
            customScenario = newValue.customScenario
            focusRaw = newValue.focusRaw
            levelRaw = newValue.levelRaw
            formalityRaw = newValue.formalityRaw
            strictnessRaw = newValue.strictnessRaw
            feedbackStyleRaw = newValue.feedbackStyleRaw
            correctionsEnabled = newValue.correctionsEnabled
            inputModeRaw = newValue.inputModeRaw
            autoPlay = newValue.autoPlay
            modelRaw = newValue.modelRaw
            deckIDsRaw = newValue.deckIDsRaw
            deckLabel = newValue.deckLabel
            paperTitle = newValue.paperTitle
            paperContext = newValue.paperContext
            jobTitle = newValue.jobTitle
            jobContext = newValue.jobContext
            jobCompany = newValue.jobCompany
            jobLocation = newValue.jobLocation
            jobURL = newValue.jobURL
            interviewRoundRaw = newValue.interviewRoundRaw
            interviewFormatRaw = newValue.interviewFormatRaw
            jobSnapshotFile = newValue.jobSnapshotFile
            jobPostingIDRaw = newValue.jobPostingIDRaw
            stammtisch = newValue.stammtischData.flatMap { try? SyncJSON(data: $0) }
            usesResume = newValue.usesResume
        }
    }
}
