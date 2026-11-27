import Foundation

/// One played Kasus round, or a lesson read (`KasusRound`), as a plain value. Field names and
/// encodings follow `KasusRoundCodec` (Codecs/KasusCodecs.swift). Append-only; named by
/// `SyncNaturalKeys.kasusRoundKey` (its `roundKey` when set).
nonisolated struct KasusRoundRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.kasusRound }

    var date: Date
    /// The story id, or a drill's filing id (`KasusRoundStep.roundID`, e.g. `concept-akkusativ-lesson`).
    var storyID = ""
    /// `KasusUnit` / `GrammarTopic` key.
    var unitRaw = ""
    /// `KasusRoundStep.rawValue`.
    var stepRaw = ""
    var hintLevelRaw = ""
    var askedCount = 0
    var firstTryCount = 0
    var durationSeconds = 0
    /// `[GrammarCase: CaseTally]` JSON, passed through. A new iOS round writes `{}`.
    var perCase: SyncJSON? = .object([:])
    /// The round's items JSON, passed through.
    var items: SyncJSON? = nil
    var feedbackModeRaw = ""
    var markCaseRaw = ""
    var wrongCount = 0
    /// `.or`: only ever raised.
    var revealedAnswers = false
    /// A random id given at creation (empty on rows from before it existed).
    var roundKey = ""
    var extra: SyncPayload = [:]

    init(date: Date = Date(), storyID: String, unitRaw: String, stepRaw: String, roundKey: String = UUID().uuidString) {
        self.date = date
        self.storyID = storyID
        self.unitRaw = unitRaw
        self.stepRaw = stepRaw
        self.roundKey = roundKey
    }

    /// The `lesson` step's raw value and filing id (`KasusRoundStep.lesson`, a concept-filed
    /// step: `concept-<topic>-lesson`). iOS's StudyDayParityTests checks both against the enum.
    static let lessonStep = "lesson"
    static func lessonStoryID(topicKey: String) -> String { "concept-\(topicKey)-lesson" }

    /// "The lesson was read through": what `KasusService.recordLessonRead` inserts, one per topic.
    static func lessonRead(topicKey: String, seconds: Int, at date: Date = Date()) -> KasusRoundRecord {
        var r = KasusRoundRecord(date: date, storyID: lessonStoryID(topicKey: topicKey), unitRaw: topicKey,
                                 stepRaw: lessonStep)
        r.durationSeconds = max(0, seconds)
        return r
    }

    init(payload p: SyncPayload) {
        date = p.date("date") ?? Date(timeIntervalSinceReferenceDate: 0)
        if let v = p.string("storyID") { storyID = v }
        if let v = p.string("unitRaw") { unitRaw = v }
        if let v = p.string("stepRaw") { stepRaw = v }
        if let v = p.string("hintLevelRaw") { hintLevelRaw = v }
        if let v = p.int("askedCount") { askedCount = v }
        if let v = p.int("firstTryCount") { firstTryCount = v }
        if let v = p.int("durationSeconds") { durationSeconds = v }
        perCase = p.json("perCase")
        items = p.json("items")
        if let v = p.string("feedbackModeRaw") { feedbackModeRaw = v }
        if let v = p.string("markCaseRaw") { markCaseRaw = v }
        if let v = p.int("wrongCount") { wrongCount = v }
        if let v = p.bool("revealedAnswers") { revealedAnswers = v }
        if let v = p.string("roundKey") { roundKey = v }
        keepExtra(from: p)
    }

    var key: String {
        SyncNaturalKeys.kasusRoundKey(roundKey: roundKey, date: date, storyID: storyID, unitRaw: unitRaw, stepRaw: stepRaw)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, naturalKey: key) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("key", key)
        f.set("date", date)
        f.set("storyID", storyID)
        f.set("unitRaw", unitRaw)
        f.set("stepRaw", stepRaw)
        f.set("hintLevelRaw", hintLevelRaw)
        f.set("askedCount", askedCount)
        f.set("firstTryCount", firstTryCount)
        f.set("durationSeconds", durationSeconds)
        f.set("perCase", json: perCase)
        f.set("items", json: items)
        f.set("feedbackModeRaw", feedbackModeRaw)
        f.set("markCaseRaw", markCaseRaw)
        f.set("wrongCount", wrongCount)
        f.set("revealedAnswers", revealedAnswers)
        f.set("roundKey", roundKey)
        return f.payload
    }

    /// Found by its story (or filing) id; listed by date.
    var index: RecordIndex {
        RecordIndex(naturalKey: storyID, sort: date.timeIntervalSinceReferenceDate)
    }
}
