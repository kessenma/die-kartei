import Foundation
import SwiftData

// MARK: - JournalEntry

/// One piece of the learner's writing. Its ink syncs as files under the `Journal` root
/// (`JournalInkStore`), named by the entry's id, so no field here points at them.
/// - The text, title and prompt are last-writer-wins per field: two devices editing one entry at
///   once keep the later save whole. `updatedAt` takes the later time.
/// - The check and the tutor that made it travel as one group, taken whole from one side, so a
///   check is never credited to the other device's tutor; the text hash travels with them so a
///   check made on one device is stale on the other exactly when the text differs.
/// - `sharedWithCoachAt` and `creditedWords` take the larger value: both are high-water marks,
///   and a hand-off or a day credit made on either device must not be made again.
/// - `lookups` merge word by word (keyed on the German, case-insensitively), the later lookup of
///   one word winning.
/// Nothing is left out.
enum JournalEntryCodec: SyncCodec {
    typealias Model = JournalEntry

    static let spec = SyncKindSpec(
        kind: "JournalEntry",
        rules: [
            "updatedAt": .max,
            "sharedWithCoachAt": .max,
            "creditedWords": .max,
            "lookups": .set(idField: "german", lowercasedID: true, item: .lwwBy("at")),
        ],
        groups: [SyncFieldGroup(fields: ["check", "checkedAt", "checkedModelID", "checkedTextHash"], orderBy: [])]
    )

    static func recordName(for model: JournalEntry) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ e: JournalEntry) -> SyncPayload {
        var f = SyncFields()
        f.set("id", e.id)
        f.set("createdAt", e.createdAt)
        f.set("updatedAt", e.updatedAt)
        f.set("day", SyncDayKey.key(for: e.day))
        f.set("kindRaw", e.kindRaw)
        f.set("title", e.title)
        f.set("text", e.text)
        f.set("levelRaw", e.levelRaw)
        f.set("promptID", e.promptID)
        f.set("promptDE", e.promptDE)
        f.set("promptEN", e.promptEN)
        f.set("promptSourceRaw", e.promptSourceRaw)
        f.set("promptFocusRaw", e.promptFocusRaw)
        f.set("targetMin", e.targetMin)
        f.set("targetMax", e.targetMax)
        f.set("inkHeight", e.inkHeight)
        f.set("inkStrokeCount", e.inkStrokeCount)
        f.set("inkPaperRaw", e.inkPaperRaw)
        f.set("transcriptConfirmedAt", e.transcriptConfirmedAt)
        f.set("check", jsonData: e.checkData)
        f.set("checkedAt", e.checkedAt)
        f.set("checkedModelID", e.checkedModelID)
        f.set("checkedTextHash", e.checkedTextHash)
        f.set("sharedWithCoachAt", e.sharedWithCoachAt)
        f.set("lookups", jsonData: e.lookupsData)
        f.set("creditedWords", e.creditedWords)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> JournalEntry? {
        JournalEntryStore.fetch(id: name.id, in: context)
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> JournalEntry? {
        let entry = JournalEntry()
        entry.id = name.id
        context.insert(entry)
        update(entry, from: flat, in: context)
        return entry
    }

    static func update(_ e: JournalEntry, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("createdAt") { e.createdAt = v }
        if let v = flat.date("updatedAt") { e.updatedAt = v }
        // Stored values are local midnight where they were written; `SyncDayKey` keeps them on
        // the same date read in another time zone.
        if let v = flat.string("day").flatMap({ SyncDayKey.dayStart(for: $0) }) { e.day = v }
        if let v = flat.string("kindRaw") { e.kindRaw = v }
        if let v = flat.string("title") { e.title = v }
        if let v = flat.string("text") { e.text = v }
        if let v = flat.string("levelRaw") { e.levelRaw = v }
        e.promptID = flat.string("promptID")
        e.promptDE = flat.string("promptDE")
        e.promptEN = flat.string("promptEN")
        e.promptSourceRaw = flat.string("promptSourceRaw")
        e.promptFocusRaw = flat.string("promptFocusRaw")
        if let v = flat.int("targetMin") { e.targetMin = v }
        if let v = flat.int("targetMax") { e.targetMax = v }
        if let v = flat.int("inkHeight") { e.inkHeight = v }
        if let v = flat.int("inkStrokeCount") { e.inkStrokeCount = v }
        if let v = flat.string("inkPaperRaw") { e.inkPaperRaw = v }
        e.transcriptConfirmedAt = flat.date("transcriptConfirmedAt")
        e.checkData = flat.jsonData("check")
        e.checkedAt = flat.date("checkedAt")
        e.checkedModelID = flat.string("checkedModelID")
        e.checkedTextHash = flat.string("checkedTextHash")
        e.sharedWithCoachAt = flat.date("sharedWithCoachAt")
        e.lookupsData = flat.jsonData("lookups")
        if let v = flat.int("creditedWords") { e.creditedWords = v }
    }

    // Field coverage: id, createdAt, updatedAt, day, kindRaw, title, text, levelRaw, promptID,
    // promptDE, promptEN, promptSourceRaw, promptFocusRaw, targetMin, targetMax, inkHeight,
    // inkStrokeCount, inkPaperRaw, transcriptConfirmedAt, checkData (as "check"), checkedAt,
    // checkedModelID, checkedTextHash, sharedWithCoachAt, lookupsData (as "lookups"), creditedWords.
}
