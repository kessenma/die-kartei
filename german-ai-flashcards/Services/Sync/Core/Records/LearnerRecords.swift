import Foundation

// LearnerProfile, ArchivedMemoryItem and LearnedPhrase as plain values. Field names, encodings and
// merge rules follow `LearnerProfileCodec`, `ArchivedMemoryItemCodec` (Codecs/LearnerCodecs.swift)
// and `LearnedPhraseCodec`.

/// The coach's memory of the learner (`LearnerProfile`). A singleton: every device's profile is
/// the one record `SyncKinds.learnerProfileName`, and the payload carries no id.
///
/// The sections stay JSON here; `LearnerMemory(record:)` and `write(to:from:)` (Models/LearnerMemory.swift)
/// read and write them as the shared value types:
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

/// How the coach's memories are told apart: `VocabTouch.id`, `LexicalSlip.id` and
/// `SelfReportNote.id` (Models/LearnerMemory.swift) are these, and sync names archived rows and
/// merges the profile's lists by them.
nonisolated enum MemoryItemID {
    /// A word is the same word however the learner met it: German, lowercased.
    static func vocab(german: String) -> String { german.lowercased() }

    /// `wrong→right`, plus `@source` for slips that didn't come from the learner's own production.
    static func slip(wrong: String, right: String, source: String?) -> String {
        (wrong + "→" + right + (source.map { "@" + $0 } ?? "")).lowercased()
    }

    /// Letters and single spaces, lowercased, first 60: the same thought written twice is one note.
    static func note(text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0 == " " }
            .split(separator: " ").joined(separator: " ").prefix(60))
    }
}

/// A memory that left the active profile (`ArchivedMemoryItem`): mastered, pushed out by newer
/// ones past a cap, or removed by the learner. Named after what it holds, so the same word
/// archived on two devices is one record: `kindRaw|<item id>` (`VocabTouch.id`, `LexicalSlip.id`,
/// `SelfReportNote.id`), or the row's own id when the payload won't decode. `archivedAt` keeps the
/// earlier date.
nonisolated struct ArchivedMemoryRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.archivedMemoryItem }

    var id: UUID
    var kindRaw: String
    var reasonRaw: String
    var archivedAt: Date
    var title: String
    var subtitle: String
    /// The encoded item, as parsed JSON (default `JSONEncoder` dates: numbers).
    var payload: SyncJSON?
    var extra: SyncPayload = [:]

    init(id: UUID = UUID(), kindRaw: String, reasonRaw: String, archivedAt: Date = Date(), title: String,
         subtitle: String, payload: SyncJSON?) {
        self.id = id
        self.kindRaw = kindRaw
        self.reasonRaw = reasonRaw
        self.archivedAt = archivedAt
        self.title = title
        self.subtitle = subtitle
        self.payload = payload
    }

    init(payload p: SyncPayload) {
        id = p.uuid("id") ?? UUID()
        kindRaw = p.string("kindRaw") ?? "vocab"
        reasonRaw = p.string("reasonRaw") ?? "agedOut"
        archivedAt = p.date("archivedAt") ?? Date(timeIntervalSinceReferenceDate: 0)
        title = p.string("title") ?? ""
        subtitle = p.string("subtitle") ?? ""
        payload = p.json("payload")
        keepExtra(from: p)
    }

    /// The encoded item, for `LearnerMemory.restore`.
    var payloadData: Data? { payload?.canonicalData }

    /// The id of the memory it holds (iOS `ArchivedMemoryItemCodec.itemID` calls this): nil when
    /// the payload isn't a whole item of its kind, i.e. when a default `JSONDecoder` would fail on it.
    static func itemID(kindRaw: String, payload: SyncJSON?) -> String? {
        guard let o = payload?.objectValue else { return nil }
        func string(_ k: String) -> String? { if case .string(let v)? = o[k] { v } else { nil } }
        func number(_ k: String) -> Bool { switch o[k] { case .int?, .double?: true; default: false } }
        func bool(_ k: String) -> Bool { if case .bool? = o[k] { true } else { false } }
        switch kindRaw {
        case "vocab":
            guard let german = string("german"), string("english") != nil, number("lastSeen"), number("timesUsed"),
                  bool("pinned") else { return nil }
            return MemoryItemID.vocab(german: german)
        case "slip":
            guard let wrong = string("wrong"), let right = string("right"), string("note") != nil,
                  number("lastSeen"), number("timesSeen"), bool("pinned") else { return nil }
            return MemoryItemID.slip(wrong: wrong, right: right, source: string("source"))
        case "selfReport":
            guard let text = string("text"), number("notedAt"), number("timesNoted"), bool("pinned") else { return nil }
            return MemoryItemID.note(text: text)
        default:
            return nil
        }
    }

    var key: String { kindRaw + "|" + (Self.itemID(kindRaw: kindRaw, payload: payload) ?? id.uuidString) }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, naturalKey: key) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("id", id)
        f.set("kindRaw", kindRaw)
        f.set("reasonRaw", reasonRaw)
        f.set("archivedAt", archivedAt)
        f.set("title", title)
        f.set("subtitle", subtitle)
        f.set("payload", json: payload)
        return f.payload
    }

    /// Listed newest first by `archivedAt`; found by kind.
    var index: RecordIndex { RecordIndex(naturalKey: kindRaw, sort: archivedAt.timeIntervalSinceReferenceDate) }
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
