import Foundation
import SwiftData

// MARK: - ChatConversation

/// A tutor chat's own fields. Messages sync as their own records.
/// - `durationSeconds` is a per-device counter: continuing a chat on a second device adds that
///   sitting's time instead of overwriting the first device's total.
/// - `updatedAt` takes the later time, so the chat list orders by the latest activity on either device.
/// - Saved words merge word by word, matched on the German case-insensitively: a word saved on
///   either device is kept, a word removed on one is removed. They carry no time, so a merged list
///   is in alphabetical order rather than the order they were saved.
/// - The coaching summary is one value: the later analysis wins whole.
/// - `jobSnapshotFile` travels as a name; the PDF itself syncs separately under the same name.
enum ChatConversationCodec: SyncCodec {
    typealias Model = ChatConversation

    static let spec = SyncKindSpec(
        kind: "ChatConversation",
        rules: [
            "durationSeconds": .counter,
            "updatedAt": .max,
            "savedVocab": .set(idField: "german", lowercasedID: true),
        ]
    )

    static func recordName(for model: ChatConversation) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ c: ChatConversation) -> SyncPayload {
        var f = SyncFields()
        f.set("id", c.id)
        f.set("title", c.title)
        f.set("createdAt", c.createdAt)
        f.set("updatedAt", c.updatedAt)
        f.set("durationSeconds", c.durationSeconds)
        f.set("modeRaw", c.modeRaw)
        f.set("scenarioRaw", c.scenarioRaw)
        f.set("customScenario", c.customScenario)
        f.set("focusRaw", c.focusRaw)
        f.set("levelRaw", c.levelRaw)
        f.set("formalityRaw", c.formalityRaw)
        f.set("strictnessRaw", c.strictnessRaw)
        f.set("feedbackStyleRaw", c.feedbackStyleRaw)
        f.set("correctionsEnabled", c.correctionsEnabled)
        f.set("inputModeRaw", c.inputModeRaw)
        f.set("autoPlay", c.autoPlay)
        f.set("modelRaw", c.modelRaw)
        f.set("deckIDsRaw", c.deckIDsRaw)
        f.set("deckLabel", c.deckLabel)
        f.set("paperTitle", c.paperTitle)
        f.set("paperContext", c.paperContext)
        f.set("jobTitle", c.jobTitle)
        f.set("jobContext", c.jobContext)
        f.set("jobCompany", c.jobCompany)
        f.set("jobLocation", c.jobLocation)
        f.set("jobURL", c.jobURL)
        f.set("interviewRoundRaw", c.interviewRoundRaw)
        f.set("interviewFormatRaw", c.interviewFormatRaw)
        f.set("jobSnapshotFile", c.jobSnapshotFile)
        f.set("jobPostingIDRaw", c.jobPostingIDRaw)
        f.set("summary", jsonData: c.summaryData)
        f.set("savedVocab", jsonData: c.savedVocabData)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ChatConversation? {
        fetchConversation(id: name.id, in: context)
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ChatConversation? {
        let conversation = ChatConversation(config: ConversationConfig(model: .hero))
        conversation.id = name.id
        context.insert(conversation)
        update(conversation, from: flat, in: context)
        return conversation
    }

    static func update(_ c: ChatConversation, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("title") { c.title = v }
        if let v = flat.date("createdAt") { c.createdAt = v }
        if let v = flat.date("updatedAt") { c.updatedAt = v }
        c.durationSeconds = flat.int("durationSeconds") ?? 0
        if let v = flat.string("modeRaw") { c.modeRaw = v }
        c.scenarioRaw = flat.string("scenarioRaw")
        c.customScenario = flat.string("customScenario")
        if let v = flat.strings("focusRaw") { c.focusRaw = v }
        if let v = flat.string("levelRaw") { c.levelRaw = v }
        if let v = flat.string("formalityRaw") { c.formalityRaw = v }
        if let v = flat.string("strictnessRaw") { c.strictnessRaw = v }
        if let v = flat.string("feedbackStyleRaw") { c.feedbackStyleRaw = v }
        if let v = flat.bool("correctionsEnabled") { c.correctionsEnabled = v }
        if let v = flat.string("inputModeRaw") { c.inputModeRaw = v }
        if let v = flat.bool("autoPlay") { c.autoPlay = v }
        if let v = flat.string("modelRaw") { c.modelRaw = v }
        if let v = flat.strings("deckIDsRaw") { c.deckIDsRaw = v }
        if let v = flat.string("deckLabel") { c.deckLabel = v }
        c.paperTitle = flat.string("paperTitle")
        c.paperContext = flat.string("paperContext")
        c.jobTitle = flat.string("jobTitle")
        c.jobContext = flat.string("jobContext")
        c.jobCompany = flat.string("jobCompany")
        c.jobLocation = flat.string("jobLocation")
        c.jobURL = flat.string("jobURL")
        c.interviewRoundRaw = flat.string("interviewRoundRaw")
        c.interviewFormatRaw = flat.string("interviewFormatRaw")
        c.jobSnapshotFile = flat.string("jobSnapshotFile")
        c.jobPostingIDRaw = flat.string("jobPostingIDRaw")
        c.summaryData = flat.jsonData("summary")
        c.savedVocabData = flat.jsonData("savedVocab")
    }

    static func cascadeChildren(of model: ChatConversation) -> [any PersistentModel] {
        model.messages
    }

    static func fetchConversation(id: UUID, in context: ModelContext) -> ChatConversation? {
        var d = FetchDescriptor<ChatConversation>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
}

// MARK: - ChatMessage

/// One turn of a chat. Hangs off its conversation, and waits for it if the message arrives first.
/// - The correction, its nudge and both translations are filled in after the turn is written. A
///   field only one device filled in is kept (three-way), so a late translation isn't lost.
/// - `selfCorrected`, `confirmedClean` and `translationViewed` are only ever raised, and `usedHint`
///   and `usedPhraseHelper` are fixed when the turn is written and never lowered, so each is true
///   if either device says so.
/// - Messages that lost their conversation stay here: there is nothing to hang them off elsewhere.
enum ChatMessageCodec: SyncCodec {
    typealias Model = ChatMessage

    static let spec = SyncKindSpec(
        kind: "ChatMessage",
        rules: [
            "selfCorrected": .or,
            "usedHint": .or,
            "usedPhraseHelper": .or,
            "confirmedClean": .or,
            "translationViewed": .or,
        ]
    )

    static func recordName(for model: ChatMessage) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func includes(_ message: ChatMessage) -> Bool { message.conversation != nil }

    static func known(_ m: ChatMessage) -> SyncPayload {
        var f = SyncFields()
        f.set("id", m.id)
        f.set("conversation", m.conversation?.id)
        f.set("roleRaw", m.roleRaw)
        f.set("text", m.text)
        f.set("createdAt", m.createdAt)
        f.set("sortOrder", m.sortOrder)
        f.set("correctedText", m.correctedText)
        f.set("correctionNote", m.correctionNote)
        f.set("correctionHint", m.correctionHint)
        f.set("selfCorrected", m.selfCorrected)
        f.set("correctionTranslationText", m.correctionTranslationText)
        f.set("targetWordsUsed", m.targetWordsUsed)
        f.set("usedHint", m.usedHint)
        f.set("usedPhraseHelper", m.usedPhraseHelper)
        f.set("reviewedWords", m.reviewedWords)
        f.set("confirmedClean", m.confirmedClean)
        f.set("translationText", m.translationText)
        f.set("translationViewed", m.translationViewed)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ChatMessage? {
        let id = name.id
        var d = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func parent(of flat: SyncPayload) -> SyncRecordName? {
        flat.uuid("conversation").map { SyncRecordName(kind: ChatConversationCodec.spec.kind, id: $0) }
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ChatMessage? {
        guard let conversationID = flat.uuid("conversation"),
              let conversation = ChatConversationCodec.fetchConversation(id: conversationID, in: context)
        else {
            return nil
        }
        let message = ChatMessage(role: ChatRole(rawValue: flat.string("roleRaw") ?? "") ?? .assistant,
                                  text: flat.string("text") ?? "",
                                  sortOrder: flat.int("sortOrder") ?? 0)
        message.id = name.id
        context.insert(message)
        message.conversation = conversation
        update(message, from: flat, in: context)
        return message
    }

    static func update(_ m: ChatMessage, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("roleRaw") { m.roleRaw = v }
        if let v = flat.string("text") { m.text = v }
        if let v = flat.date("createdAt") { m.createdAt = v }
        if let v = flat.int("sortOrder") { m.sortOrder = v }
        m.correctedText = flat.string("correctedText")
        m.correctionNote = flat.string("correctionNote")
        m.correctionHint = flat.string("correctionHint")
        if let v = flat.bool("selfCorrected") { m.selfCorrected = v }
        m.correctionTranslationText = flat.string("correctionTranslationText")
        if let v = flat.strings("targetWordsUsed") { m.targetWordsUsed = v }
        if let v = flat.bool("usedHint") { m.usedHint = v }
        if let v = flat.bool("usedPhraseHelper") { m.usedPhraseHelper = v }
        if let v = flat.strings("reviewedWords") { m.reviewedWords = v }
        if let v = flat.bool("confirmedClean") { m.confirmedClean = v }
        m.translationText = flat.string("translationText")
        if let v = flat.bool("translationViewed") { m.translationViewed = v }
    }
}

// MARK: - JobPosting

/// A job ad the learner studies.
/// - `readingSeconds` is a per-device counter: reading the ad on both devices adds up.
/// - `updatedAt` and `lastOpenedAt` take the later time; both are only ever bumped to now.
/// - Looked-up words merge word by word, matched on the German case-insensitively: a lookup on
///   either device is kept, a removal on one is removed. They carry no time, so a merged list is in
///   alphabetical order rather than newest first.
/// - `snapshotFile` travels as a name; the PDF itself syncs separately under the same name.
/// - `deckIDRaw` and `adoptedFromChatIDRaw` travel as they are: the deck and the chat keep their
///   ids on every device. If both devices create the linked deck before either syncs, the later
///   link wins and the other deck stays in the library on its own, with its words.
enum JobPostingCodec: SyncCodec {
    typealias Model = JobPosting

    static let spec = SyncKindSpec(
        kind: "JobPosting",
        rules: [
            "readingSeconds": .counter,
            "updatedAt": .max,
            "lastOpenedAt": .max,
            "lookups": .set(idField: "german", lowercasedID: true),
        ]
    )

    static func recordName(for model: JobPosting) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ p: JobPosting) -> SyncPayload {
        var f = SyncFields()
        f.set("id", p.id)
        f.set("createdAt", p.createdAt)
        f.set("updatedAt", p.updatedAt)
        f.set("title", p.title)
        f.set("company", p.company)
        f.set("location", p.location)
        f.set("sourceURL", p.sourceURL)
        f.set("sourceKindRaw", p.sourceKindRaw)
        f.set("text", p.text)
        f.set("snapshotFile", p.snapshotFile)
        f.set("lookups", jsonData: p.lookupsData)
        f.set("deckIDRaw", p.deckIDRaw)
        f.set("modelRaw", p.modelRaw)
        f.set("readingSeconds", p.readingSeconds)
        f.set("lastOpenedAt", p.lastOpenedAt)
        f.set("adoptedFromChatIDRaw", p.adoptedFromChatIDRaw)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> JobPosting? {
        let id = name.id
        var d = FetchDescriptor<JobPosting>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> JobPosting? {
        let posting = JobPosting(title: flat.string("title") ?? "", text: flat.string("text") ?? "")
        posting.id = name.id
        context.insert(posting)
        update(posting, from: flat, in: context)
        return posting
    }

    static func update(_ p: JobPosting, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("createdAt") { p.createdAt = v }
        if let v = flat.date("updatedAt") { p.updatedAt = v }
        if let v = flat.string("title") { p.title = v }
        p.company = flat.string("company")
        p.location = flat.string("location")
        p.sourceURL = flat.string("sourceURL")
        if let v = flat.string("sourceKindRaw") { p.sourceKindRaw = v }
        if let v = flat.string("text") { p.text = v }
        p.snapshotFile = flat.string("snapshotFile")
        p.lookupsData = flat.jsonData("lookups")
        p.deckIDRaw = flat.string("deckIDRaw")
        p.modelRaw = flat.string("modelRaw")
        p.readingSeconds = flat.int("readingSeconds") ?? 0
        p.lastOpenedAt = flat.date("lastOpenedAt")
        p.adoptedFromChatIDRaw = flat.string("adoptedFromChatIDRaw")
    }
}

// Field coverage:
//
// ChatConversation (record ChatConversation:<id>, bootstrap .shared)
//   id                  -> "id" (.lww; also the record name)
//   title               -> "title" .lww
//   createdAt           -> "createdAt" .lww
//   updatedAt           -> "updatedAt" .max
//   durationSeconds     -> "durationSeconds" .counter
//   modeRaw             -> "modeRaw" .lww
//   scenarioRaw         -> "scenarioRaw" .lww
//   customScenario      -> "customScenario" .lww
//   focusRaw            -> "focusRaw" .lww
//   levelRaw            -> "levelRaw" .lww
//   formalityRaw        -> "formalityRaw" .lww
//   strictnessRaw       -> "strictnessRaw" .lww
//   feedbackStyleRaw    -> "feedbackStyleRaw" .lww
//   correctionsEnabled  -> "correctionsEnabled" .lww
//   inputModeRaw        -> "inputModeRaw" .lww
//   autoPlay            -> "autoPlay" .lww
//   modelRaw            -> "modelRaw" .lww
//   deckIDsRaw          -> "deckIDsRaw" .lww
//   deckLabel           -> "deckLabel" .lww
//   paperTitle          -> "paperTitle" .lww
//   paperContext        -> "paperContext" .lww
//   jobTitle            -> "jobTitle" .lww
//   jobContext          -> "jobContext" .lww
//   jobCompany          -> "jobCompany" .lww
//   jobLocation         -> "jobLocation" .lww
//   jobURL              -> "jobURL" .lww
//   interviewRoundRaw   -> "interviewRoundRaw" .lww
//   interviewFormatRaw  -> "interviewFormatRaw" .lww
//   jobSnapshotFile     -> "jobSnapshotFile" .lww (the file syncs separately)
//   jobPostingIDRaw     -> "jobPostingIDRaw" .lww
//   summaryData         -> "summary" jsonData .lww (ConversationSummary, whole)
//   savedVocabData      -> "savedVocab" jsonData .set(idField: "german", lowercasedID: true)
//   messages            -> not a field: each ChatMessage carries "conversation"; cascadeChildren
//
// ChatMessage (record ChatMessage:<id>, parent ChatConversation:<conversation.id>, bootstrap .shared)
//   id                         -> "id" (.lww; also the record name)
//   conversation               -> "conversation" (conversation.id) .lww; parent(of:)
//   roleRaw                    -> "roleRaw" .lww
//   text                       -> "text" .lww
//   createdAt                  -> "createdAt" .lww
//   sortOrder                  -> "sortOrder" .lww
//   correctedText              -> "correctedText" .lww
//   correctionNote             -> "correctionNote" .lww
//   correctionHint             -> "correctionHint" .lww
//   selfCorrected              -> "selfCorrected" .or (only ever set true)
//   correctionTranslationText  -> "correctionTranslationText" .lww
//   targetWordsUsed            -> "targetWordsUsed" .lww
//   usedHint                   -> "usedHint" .or (fixed when the turn is written)
//   usedPhraseHelper           -> "usedPhraseHelper" .or (fixed when the turn is written)
//   reviewedWords              -> "reviewedWords" .lww
//   confirmedClean             -> "confirmedClean" .or (only ever set true)
//   translationText            -> "translationText" .lww
//   translationViewed          -> "translationViewed" .or (only ever set true)
//
// JobPosting (record JobPosting:<id>, bootstrap .shared)
//   id                    -> "id" (.lww; also the record name)
//   createdAt             -> "createdAt" .lww
//   updatedAt             -> "updatedAt" .max
//   title                 -> "title" .lww
//   company               -> "company" .lww
//   location              -> "location" .lww
//   sourceURL             -> "sourceURL" .lww
//   sourceKindRaw         -> "sourceKindRaw" .lww
//   text                  -> "text" .lww
//   snapshotFile          -> "snapshotFile" .lww (the file syncs separately)
//   lookupsData           -> "lookups" jsonData .set(idField: "german", lowercasedID: true)
//   deckIDRaw             -> "deckIDRaw" .lww
//   modelRaw              -> "modelRaw" .lww
//   readingSeconds        -> "readingSeconds" .counter
//   lastOpenedAt          -> "lastOpenedAt" .max
//   adoptedFromChatIDRaw  -> "adoptedFromChatIDRaw" .lww
//
// EXCLUDED: none. Every stored property of the three models travels.
