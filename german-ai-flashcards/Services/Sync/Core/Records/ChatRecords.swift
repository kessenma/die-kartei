import Foundation

// ChatConversation and ChatMessage as plain values. Field names, encodings and merge rules follow
// `ChatConversationCodec` / `ChatMessageCodec` (Codecs/ChatCodecs.swift); defaults for a missing
// field follow `ChatConversation(config: ConversationConfig(model:))` and `ChatMessage.init`.
// The enum raw values below are iOS's (`ConversationMode.freestyle` is "Freestyle", …): this file
// also builds in KarteiSyncCore, which can't see those enums. SyncRecordTests checks a default
// record against the golden row iOS writes for a new chat.

/// A tutor chat's own fields (`ChatConversation`). Messages are records of their own.
nonisolated struct ChatConversationRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.chatConversation }

    var id: UUID
    var title = "Freies Gespräch"
    var createdAt: Date
    /// `.max`: the chat list orders by the latest activity on any device.
    var updatedAt: Date
    /// `.counter`: each device adds its own sitting's time.
    var durationSeconds = 0
    var modeRaw = "Freestyle"
    var scenarioRaw: String? = nil
    var customScenario: String? = nil
    var focusRaw: [String] = []
    var levelRaw = "A2"
    var formalityRaw = "du"
    var strictnessRaw = "Balanced"
    var feedbackStyleRaw = "Tell me"
    var correctionsEnabled = true
    var inputModeRaw = "Speak"
    var autoPlay = true
    /// `MLXModel.rawValue` of the tutor model the chat ran on.
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
    /// A file name; the PDF syncs separately under it.
    var jobSnapshotFile: String? = nil
    var jobPostingIDRaw: String? = nil
    /// `StammtischOptions` JSON, set once at creation, passed through as is.
    var stammtisch: SyncJSON? = nil
    var usesResume = false
    /// `ConversationSummary` JSON; the later analysis wins whole.
    var summary: SyncJSON? = nil
    /// `[SavedVocabItem]` JSON; merges word by word on `german` (lowercased).
    var savedVocab: SyncJSON? = nil
    var extra: SyncPayload = [:]

    init(id: UUID = UUID(), modelRaw: String, createdAt: Date = Date()) {
        self.id = id
        self.modelRaw = modelRaw
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    init(payload p: SyncPayload) {
        id = p.uuid("id") ?? UUID()
        createdAt = p.date("createdAt") ?? Date(timeIntervalSinceReferenceDate: 0)
        updatedAt = p.date("updatedAt") ?? createdAt
        modelRaw = p.string("modelRaw") ?? ""
        if let v = p.string("title") { title = v }
        durationSeconds = p.int("durationSeconds") ?? 0
        if let v = p.string("modeRaw") { modeRaw = v }
        scenarioRaw = p.string("scenarioRaw")
        customScenario = p.string("customScenario")
        if let v = p.strings("focusRaw") { focusRaw = v }
        if let v = p.string("levelRaw") { levelRaw = v }
        if let v = p.string("formalityRaw") { formalityRaw = v }
        if let v = p.string("strictnessRaw") { strictnessRaw = v }
        if let v = p.string("feedbackStyleRaw") { feedbackStyleRaw = v }
        if let v = p.bool("correctionsEnabled") { correctionsEnabled = v }
        if let v = p.string("inputModeRaw") { inputModeRaw = v }
        if let v = p.bool("autoPlay") { autoPlay = v }
        if let v = p.strings("deckIDsRaw") { deckIDsRaw = v }
        if let v = p.string("deckLabel") { deckLabel = v }
        paperTitle = p.string("paperTitle")
        paperContext = p.string("paperContext")
        jobTitle = p.string("jobTitle")
        jobContext = p.string("jobContext")
        jobCompany = p.string("jobCompany")
        jobLocation = p.string("jobLocation")
        jobURL = p.string("jobURL")
        interviewRoundRaw = p.string("interviewRoundRaw")
        interviewFormatRaw = p.string("interviewFormatRaw")
        jobSnapshotFile = p.string("jobSnapshotFile")
        jobPostingIDRaw = p.string("jobPostingIDRaw")
        stammtisch = p.json("stammtisch")
        if let v = p.bool("usesResume") { usesResume = v }
        summary = p.json("summary")
        savedVocab = p.json("savedVocab")
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, id: id) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("id", id)
        f.set("title", title)
        f.set("createdAt", createdAt)
        f.set("updatedAt", updatedAt)
        f.set("durationSeconds", durationSeconds)
        f.set("modeRaw", modeRaw)
        f.set("scenarioRaw", scenarioRaw)
        f.set("customScenario", customScenario)
        f.set("focusRaw", focusRaw)
        f.set("levelRaw", levelRaw)
        f.set("formalityRaw", formalityRaw)
        f.set("strictnessRaw", strictnessRaw)
        f.set("feedbackStyleRaw", feedbackStyleRaw)
        f.set("correctionsEnabled", correctionsEnabled)
        f.set("inputModeRaw", inputModeRaw)
        f.set("autoPlay", autoPlay)
        f.set("modelRaw", modelRaw)
        f.set("deckIDsRaw", deckIDsRaw)
        f.set("deckLabel", deckLabel)
        f.set("paperTitle", paperTitle)
        f.set("paperContext", paperContext)
        f.set("jobTitle", jobTitle)
        f.set("jobContext", jobContext)
        f.set("jobCompany", jobCompany)
        f.set("jobLocation", jobLocation)
        f.set("jobURL", jobURL)
        f.set("interviewRoundRaw", interviewRoundRaw)
        f.set("interviewFormatRaw", interviewFormatRaw)
        f.set("jobSnapshotFile", jobSnapshotFile)
        f.set("jobPostingIDRaw", jobPostingIDRaw)
        f.set("stammtisch", json: stammtisch)
        f.set("usesResume", usesResume)
        f.set("summary", json: summary)
        f.set("savedVocab", json: savedVocab)
        return f.payload
    }

    /// `sort` is `updatedAt`: the chats list reads it newest first.
    var index: RecordIndex {
        RecordIndex(sort: updatedAt.timeIntervalSinceReferenceDate)
    }
}

/// One turn of a chat (`ChatMessage`). Hangs off its conversation: deleting the chat deletes it.
nonisolated struct ChatMessageRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.chatMessage }

    var id: UUID
    /// The conversation's id. iOS only syncs messages that have one.
    var conversation: UUID?
    /// `ChatRole.rawValue`: "user", "assistant" or "system".
    var roleRaw = "assistant"
    var text = ""
    var createdAt: Date
    var sortOrder = 0
    var correctedText: String? = nil
    var correctionNote: String? = nil
    var correctionHint: String? = nil
    /// `.or`: only ever raised.
    var selfCorrected = false
    var correctionTranslationText: String? = nil
    var targetWordsUsed: [String] = []
    /// `.or`: fixed when the turn is written.
    var usedHint = false
    var usedPhraseHelper = false
    var reviewedWords: [String] = []
    var confirmedClean = false
    var translationText: String? = nil
    var translationViewed = false
    var extra: SyncPayload = [:]

    init(id: UUID = UUID(), conversation: UUID, roleRaw: String, text: String, sortOrder: Int,
         createdAt: Date = Date()) {
        self.id = id
        self.conversation = conversation
        self.roleRaw = roleRaw
        self.text = text
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    init(payload p: SyncPayload) {
        id = p.uuid("id") ?? UUID()
        conversation = p.uuid("conversation")
        createdAt = p.date("createdAt") ?? Date(timeIntervalSinceReferenceDate: 0)
        if let v = p.string("roleRaw") { roleRaw = v }
        if let v = p.string("text") { text = v }
        if let v = p.int("sortOrder") { sortOrder = v }
        correctedText = p.string("correctedText")
        correctionNote = p.string("correctionNote")
        correctionHint = p.string("correctionHint")
        if let v = p.bool("selfCorrected") { selfCorrected = v }
        correctionTranslationText = p.string("correctionTranslationText")
        if let v = p.strings("targetWordsUsed") { targetWordsUsed = v }
        if let v = p.bool("usedHint") { usedHint = v }
        if let v = p.bool("usedPhraseHelper") { usedPhraseHelper = v }
        if let v = p.strings("reviewedWords") { reviewedWords = v }
        if let v = p.bool("confirmedClean") { confirmedClean = v }
        translationText = p.string("translationText")
        if let v = p.bool("translationViewed") { translationViewed = v }
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, id: id) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("id", id)
        f.set("conversation", conversation)
        f.set("roleRaw", roleRaw)
        f.set("text", text)
        f.set("createdAt", createdAt)
        f.set("sortOrder", sortOrder)
        f.set("correctedText", correctedText)
        f.set("correctionNote", correctionNote)
        f.set("correctionHint", correctionHint)
        f.set("selfCorrected", selfCorrected)
        f.set("correctionTranslationText", correctionTranslationText)
        f.set("targetWordsUsed", targetWordsUsed)
        f.set("usedHint", usedHint)
        f.set("usedPhraseHelper", usedPhraseHelper)
        f.set("reviewedWords", reviewedWords)
        f.set("confirmedClean", confirmedClean)
        f.set("translationText", translationText)
        f.set("translationViewed", translationViewed)
        return f.payload
    }

    var index: RecordIndex {
        RecordIndex(parent: conversation, sort: Double(sortOrder))
    }
}
