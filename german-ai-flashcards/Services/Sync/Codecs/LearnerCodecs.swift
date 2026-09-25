import Foundation
import SwiftData

// MARK: - LearnerProfile

/// The coach's memory of the learner. A singleton: every device's profile row is the same record,
/// whatever its own id, so two devices that each made a profile before sync merge into one.
/// - `sessionCount` is a per-device counter, so sessions on both devices all count. A reset zeroes
///   it, which takes back everything counted so far.
/// - `lastSessionAt` keeps the later date. A three-way merge would let a new device's empty profile
///   (`nil`, stamped later) wipe the date on its first sync. After the merge, `lastSessionAt` is
///   cleared when the merged session count is 0. The app only sets it together with a session and
///   only clears it in a reset, so a count of 0 means a reset took back every session. The other
///   device's older date then can't undo the reset.
/// - The three JSON sections merge item by item. When both devices touched an item, the copy with
///   the later `lastSeen` wins:
///   - grammar is keyed by structure;
///   - vocab is matched on `german`, lowercased. `VocabTouch.id` is exactly that, but it is
///     computed, so the encoder never writes it;
///   - slips are matched on `LexicalSlip.id`, which comes from wrong, right and source and is
///     computed too. No single stored field names a slip, so the codec writes the id into each
///     slip as `"id"`. It is left in the stored blob, where `LexicalSlip`'s decoder ignores it.
///   The sections are written by a default `JSONEncoder`, so `lastSeen` is a number and compares
///   as one. Items travel whole, so the losing copy's `timesUsed`/`timesSeen` bump or pin is lost.
/// - The merge never enforces the 60-word and 20-slip caps. `LearnerMemoryService` re-applies them
///   on its next write and archives the overflow.
/// - `id` never travels, because the record name is fixed. Each device keeps its own row's id.
/// - If a device ever holds two profile rows, only the one `find` picks syncs (smallest id).
///   Otherwise the two would take turns writing the same record.
enum LearnerProfileCodec: SyncCodec {
    typealias Model = LearnerProfile

    static let spec = SyncKindSpec(
        kind: "LearnerProfile",
        rules: [
            "sessionCount": .counter,
            "lastSessionAt": .max,
            "grammar": .keyed(item: .lwwBy("lastSeen")),
            "vocab": .set(idField: "german", lowercasedID: true, item: .lwwBy("lastSeen"), sortBy: "lastSeen"),
            "slips": .set(idField: "id", item: .lwwBy("lastSeen"), sortBy: "lastSeen"),
        ],
        normalize: LearnerProfileCodec.normalize
    )

    /// No sessions left after the merge means no last session: a reset on either device wins over
    /// the other device's older date. Deterministic, so both devices normalize to the same bytes.
    nonisolated static func normalize(_ payload: SyncPayload) -> SyncPayload {
        guard payload["lastSessionAt"] != nil, SyncCounter(json: payload["sessionCount"]).value <= 0 else {
            return payload
        }
        var out = payload
        out["lastSessionAt"] = nil
        return out
    }

    /// The one name every device's profile row goes by.
    static let singletonName = SyncRecordName(kind: "LearnerProfile", id: SyncNameUUID.make("learner-profile"))

    static func recordName(for model: LearnerProfile) -> SyncRecordName { singletonName }

    static func includes(_ p: LearnerProfile) -> Bool {
        guard let context = p.modelContext else { return true }
        return canonical(in: context).map { $0.persistentModelID == p.persistentModelID } ?? true
    }

    static func bootstrap(for model: LearnerProfile) -> SyncBootstrap { .perStore }

    static func known(_ p: LearnerProfile) -> SyncPayload {
        var f = SyncFields()
        f.set("sessionCount", p.sessionCount)
        f.set("lastSessionAt", p.lastSessionAt)
        f.set("grammar", jsonData: p.grammarData)
        f.set("vocab", jsonData: p.vocabData)
        if let slips = taggedSlips(p.slipsData) {
            f.set("slips", json: slips)
        } else {
            f.set("slips", jsonData: p.slipsData)
        }
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> LearnerProfile? {
        canonical(in: context)
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> LearnerProfile? {
        let profile = LearnerProfile()
        context.insert(profile)
        update(profile, from: flat, in: context)
        return profile
    }

    static func update(_ p: LearnerProfile, from flat: SyncPayload, in context: ModelContext) {
        p.sessionCount = flat.int("sessionCount") ?? 0
        p.lastSessionAt = flat.date("lastSessionAt")
        p.grammarData = flat.jsonData("grammar")
        p.vocabData = flat.jsonData("vocab")
        p.slipsData = flat.jsonData("slips")
    }

    /// The profile row sync reads and writes: the smallest id, so the choice never depends on
    /// fetch order.
    static func canonical(in context: ModelContext) -> LearnerProfile? {
        let rows = (try? context.fetch(FetchDescriptor<LearnerProfile>())) ?? []
        return rows.min { $0.id.uuidString < $1.id.uuidString }
    }

    /// `slipsData` as JSON, with each slip's `LexicalSlip.id` written in as `"id"`. Nil when the blob
    /// is missing or isn't a JSON array (`SyncFields` then writes it as usual).
    static func taggedSlips(_ data: Data?) -> SyncJSON? {
        guard let data, let items = (try? SyncJSON(data: data))?.arrayValue else { return nil }
        return .array(items.map { (item: SyncJSON) -> SyncJSON in
            guard var object = item.objectValue,
                  let slip = try? JSONDecoder().decode(LexicalSlip.self, from: item.canonicalData)
            else { return item }
            object["id"] = .string(slip.id)
            return .object(object)
        })
    }
}

// MARK: - ArchivedMemoryItem

/// One archived word or slip. The record is named after what it holds (`kindRaw` plus the vocab or
/// slip id decoded from `payload`), not after the row's random id. The same word archived on two
/// devices is then one record, not two entries in the archive.
/// - `archivedAt` keeps the earlier date. Every other field merges three-way.
/// - One device can hold several rows for one item: a word archived, met again, then archived again.
///   Only the earliest syncs and the rest stay on this device. Otherwise they would take turns
///   writing the same record.
/// - A row whose payload won't decode is named by its own id. `id` travels so that the copy on
///   another device gets the same name.
/// - `payload` is written by a default `JSONEncoder`, so its dates are numbers. It travels as parsed
///   JSON under `payload` and merges as one value.
enum ArchivedMemoryItemCodec: SyncCodec {
    typealias Model = ArchivedMemoryItem

    static let spec = SyncKindSpec(kind: "ArchivedMemoryItem", rules: ["archivedAt": .min])

    static func recordName(for model: ArchivedMemoryItem) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: naturalKey(for: model))
    }

    static func includes(_ a: ArchivedMemoryItem) -> Bool {
        guard let context = a.modelContext else { return true }
        let twins = rows(named: recordName(for: a), kindRaw: a.kindRaw, title: a.title, in: context)
        return earliest(twins).map { $0.persistentModelID == a.persistentModelID } ?? true
    }

    static func bootstrap(for model: ArchivedMemoryItem) -> SyncBootstrap { .perStore }

    static func known(_ a: ArchivedMemoryItem) -> SyncPayload {
        var f = SyncFields()
        f.set("id", a.id)
        f.set("kindRaw", a.kindRaw)
        f.set("reasonRaw", a.reasonRaw)
        f.set("archivedAt", a.archivedAt)
        f.set("title", a.title)
        f.set("subtitle", a.subtitle)
        f.set("payload", jsonData: a.payload)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ArchivedMemoryItem? {
        guard let kindRaw = flat.string("kindRaw") else { return nil }
        return earliest(rows(named: name, kindRaw: kindRaw, title: flat.string("title"), in: context))
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ArchivedMemoryItem? {
        // Placeholder kind and reason: update writes the raw strings, including kinds a newer build added.
        let item = ArchivedMemoryItem(kind: .vocab, reason: .agedOut,
                                      title: flat.string("title") ?? "", subtitle: flat.string("subtitle") ?? "",
                                      payload: nil)
        item.id = name.id
        context.insert(item)
        update(item, from: flat, in: context)
        return item
    }

    static func update(_ a: ArchivedMemoryItem, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.uuid("id") { a.id = v }
        if let v = flat.string("kindRaw") { a.kindRaw = v }
        if let v = flat.string("reasonRaw") { a.reasonRaw = v }
        if let v = flat.date("archivedAt") { a.archivedAt = v }
        if let v = flat.string("title") { a.title = v }
        if let v = flat.string("subtitle") { a.subtitle = v }
        a.payload = flat.jsonData("payload")
    }

    /// `kindRaw|<item id>`, falling back to the row's own id when the payload won't decode.
    static func naturalKey(for a: ArchivedMemoryItem) -> String {
        a.kindRaw + "|" + (itemID(kindRaw: a.kindRaw, payload: a.payload) ?? a.id.uuidString)
    }

    /// The id of the memory an archived row holds: `VocabTouch.id` or `LexicalSlip.id`.
    static func itemID(kindRaw: String, payload: Data?) -> String? {
        guard let payload else { return nil }
        switch MemoryKind(rawValue: kindRaw) {
        case .vocab: return (try? JSONDecoder().decode(VocabTouch.self, from: payload))?.id
        case .slip: return (try? JSONDecoder().decode(LexicalSlip.self, from: payload))?.id
        case nil: return nil
        }
    }

    /// Local rows a record name points at. The title always names the item (the German word, or
    /// "wrong → right"), so a case-insensitive title match narrows the fetch before any payload is
    /// decoded. The exact match is on the decoded id.
    private static func rows(
        named name: SyncRecordName, kindRaw: String, title: String?, in context: ModelContext
    ) -> [ArchivedMemoryItem] {
        let d: FetchDescriptor<ArchivedMemoryItem>
        if let title, !title.isEmpty {
            d = FetchDescriptor<ArchivedMemoryItem>(predicate: #Predicate {
                $0.kindRaw == kindRaw && $0.title.localizedStandardContains(title)
            })
        } else {
            d = FetchDescriptor<ArchivedMemoryItem>(predicate: #Predicate { $0.kindRaw == kindRaw })
        }
        return ((try? context.fetch(d)) ?? []).filter { recordName(for: $0) == name }
    }

    /// Of several local rows for one item, the one that syncs: the earliest archived, then the
    /// smaller id.
    private static func earliest(_ twins: [ArchivedMemoryItem]) -> ArchivedMemoryItem? {
        twins.min { ($0.archivedAt, $0.id.uuidString) < ($1.archivedAt, $1.id.uuidString) }
    }
}

// Field coverage:
//
// LearnerProfile
//   id             EXCLUDED: the record name is fixed ("learner-profile"); each device keeps its own row id
//   sessionCount   "sessionCount"   .counter
//   lastSessionAt  "lastSessionAt"  .max, then normalize clears it when the merged sessionCount is 0 (a reset)
//   grammarData    "grammar"        .keyed(item: .lwwBy("lastSeen"))  [String: GrammarSkill]: struggle, lastSeen, samples
//   vocabData      "vocab"          .set(idField: "german", lowercasedID: true, item: .lwwBy("lastSeen"), sortBy: "lastSeen")
//                                   [VocabTouch]: german, english, lastSeen, timesUsed, pinned, source?  (id is computed)
//   slipsData      "slips"          .set(idField: "id", item: .lwwBy("lastSeen"), sortBy: "lastSeen")
//                                   [LexicalSlip]: wrong, right, note, lastSeen, timesSeen, pinned, sentence?,
//                                   blankIndex?, source?, plus "id" written in by the codec (id is computed)
//
// ArchivedMemoryItem
//   id             "id"             .lww (names the record only when the payload won't decode)
//   kindRaw        "kindRaw"        .lww (part of the record name; never changes after creation)
//   reasonRaw      "reasonRaw"      .lww
//   archivedAt     "archivedAt"     .min
//   title          "title"          .lww
//   subtitle       "subtitle"       .lww
//   payload        "payload"        .lww (jsonData: the encoded VocabTouch / LexicalSlip, merged as one value)
