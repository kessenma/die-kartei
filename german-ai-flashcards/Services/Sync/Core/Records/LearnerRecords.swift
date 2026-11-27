import Foundation

// LearnerProfile and LearnedPhrase as plain values. Field names, encodings and merge rules follow
// `LearnerProfileCodec` (Codecs/LearnerCodecs.swift) and `LearnedPhraseCodec`.

/// The coach's memory of the learner (`LearnerProfile`). A singleton: every device's profile is
/// the one record `SyncKinds.learnerProfileName`, and the payload carries no id.
///
/// The sections stay JSON here (their Swift types live next to the SwiftData model on iOS):
/// - `grammar`: `[GrammarFocus.rawValue: GrammarSkill]`, merged per key by the later `lastSeen`.
/// - `vocab`: `[VocabTouch]`, merged on `german` lowercased.
/// - `slips` and `selfReports`: `[LexicalSlip]` / `[SelfReportNote]`, merged on an `"id"` the
///   iOS codec writes into each item (the types compute it). Android code that adds an item must
///   write the same id: a slip's is `(wrong + "→" + right + ("@" + source)?)`, lowercased.
/// - Dates inside are seconds since 2001 (a default `JSONEncoder`), so `lastSeen` compares as a number.
nonisolated struct LearnerProfileRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.learnerProfile }

    /// `.counter`: sessions on every device count. A reset zeroes it.
    var sessionCount = 0
    /// `.max`; cleared by the kind's normalize when the merged session count is 0.
    var lastSessionAt: Date? = nil
    var grammar: SyncJSON? = nil
    var vocab: SyncJSON? = nil
    var slips: SyncJSON? = nil
    var selfReports: SyncJSON? = nil
    /// `FoerderplanRecord` JSON, last writer wins.
    var foerderplan: SyncJSON? = nil
    var extra: SyncPayload = [:]

    init() {}

    init(payload p: SyncPayload) {
        sessionCount = p.int("sessionCount") ?? 0
        lastSessionAt = p.date("lastSessionAt")
        grammar = p.json("grammar")
        vocab = p.json("vocab")
        slips = p.json("slips")
        selfReports = p.json("selfReports")
        foerderplan = p.json("foerderplan")
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncKinds.learnerProfileName }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("sessionCount", sessionCount)
        f.set("lastSessionAt", lastSessionAt)
        f.set("grammar", json: grammar)
        f.set("vocab", json: vocab)
        f.set("slips", json: slips)
        f.set("selfReports", json: selfReports)
        f.set("foerderplan", json: foerderplan)
        return f.payload
    }

    var index: RecordIndex { RecordIndex() }
}

/// A phrase from the phrase library (`LearnedPhrase`). Plain content; the rotation bookkeeping
/// (`surfacedCount`, `lastSurfacedAt`) takes the larger / later value.
nonisolated struct LearnedPhraseRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.learnedPhrase }

    var id: UUID
    var german: String
    var english: String
    /// `ConversationScenario` raw values.
    var scenarioTagsRaw: [String] = []
    /// `GrammarFocus` raw values.
    var focusAreasRaw: [String] = []
    var creatorModelRaw = ""
    var isActive = true
    var surfacedCount = 0
    var lastSurfacedAt: Date? = nil
    var createdAt: Date
    var note: String? = nil
    var extra: SyncPayload = [:]

    init(id: UUID = UUID(), german: String, english: String, createdAt: Date = Date()) {
        self.id = id
        self.german = german
        self.english = english
        self.createdAt = createdAt
    }

    init(payload p: SyncPayload) {
        id = p.uuid("id") ?? UUID()
        german = p.string("german") ?? ""
        english = p.string("english") ?? ""
        createdAt = p.date("createdAt") ?? Date(timeIntervalSinceReferenceDate: 0)
        scenarioTagsRaw = p.strings("scenarioTagsRaw") ?? []
        focusAreasRaw = p.strings("focusAreasRaw") ?? []
        if let v = p.string("creatorModelRaw") { creatorModelRaw = v }
        if let v = p.bool("isActive") { isActive = v }
        if let v = p.int("surfacedCount") { surfacedCount = v }
        lastSurfacedAt = p.date("lastSurfacedAt")
        note = p.string("note")
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, id: id) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("id", id)
        f.set("german", german)
        f.set("english", english)
        f.set("scenarioTagsRaw", scenarioTagsRaw)
        f.set("focusAreasRaw", focusAreasRaw)
        f.set("creatorModelRaw", creatorModelRaw)
        f.set("isActive", isActive)
        f.set("surfacedCount", surfacedCount)
        f.set("lastSurfacedAt", lastSurfacedAt)
        f.set("createdAt", createdAt)
        f.set("note", note)
        return f.payload
    }

    var index: RecordIndex {
        RecordIndex(naturalKey: german, sort: createdAt.timeIntervalSinceReferenceDate)
    }
}
