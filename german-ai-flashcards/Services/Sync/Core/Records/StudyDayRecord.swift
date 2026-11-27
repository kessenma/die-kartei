import Foundation

/// One study day (`StudyDay`): every activity tally is a per-device counter
/// (`SyncKinds.studyDayCounterFields`), so two devices studying the same day add up. The record
/// is named after its date key, so every device's row for a date is the same record.
///
/// Field names and encodings follow `StudyDayCodec` (Codecs/StudyDayCodec.swift).
nonisolated struct StudyDayRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.studyDay }

    /// `yyyy-MM-dd`, from `SyncDayKey.key(for: dayStart)`.
    var day: String
    /// Every counter in `SyncKinds.studyDayCounterFields`; a missing one is 0.
    var counts: [String: Int] = [:]
    var lastActivityAt: Date
    var extra: SyncPayload = [:]

    init(day: String, lastActivityAt: Date = Date()) {
        self.day = day
        self.lastActivityAt = lastActivityAt
    }

    /// The record for the day `dayStart` (local midnight) belongs to.
    init(dayStart: Date, calendar: Calendar = .current) {
        self.init(day: SyncDayKey.key(for: dayStart, calendar: calendar), lastActivityAt: dayStart)
    }

    subscript(counter: String) -> Int {
        get { counts[counter] ?? 0 }
        set { counts[counter] = newValue }
    }

    var cardsReviewed: Int { get { self["cardsReviewed"] } set { self["cardsReviewed"] = newValue } }
    var cardSeconds: Int { get { self["cardSeconds"] } set { self["cardSeconds"] = newValue } }
    var newWordsIntroduced: Int { get { self["newWordsIntroduced"] } set { self["newWordsIntroduced"] = newValue } }

    init(payload p: SyncPayload) {
        day = p.string("day") ?? ""
        // `StudyDay(dayStart:)` starts `lastActivityAt` at the day itself.
        lastActivityAt = p.date("lastActivityAt") ?? SyncDayKey.dayStart(for: day) ?? Date(timeIntervalSinceReferenceDate: 0)
        for field in SyncKinds.studyDayCounterFields {
            counts[field] = p.int(field) ?? 0
        }
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, naturalKey: day) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("day", day)
        for field in SyncKinds.studyDayCounterFields {
            f.set(field, counts[field] ?? 0)
        }
        f.set("lastActivityAt", lastActivityAt)
        return f.payload
    }

    var index: RecordIndex { RecordIndex(naturalKey: day, day: day) }
}
