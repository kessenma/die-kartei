import Foundation
import SwiftData

/// The calendar date a `StudyDay` belongs to, as `yyyy-MM-dd`.
///
/// `dayStart` is an absolute instant: local midnight wherever the row was written. Formatting it
/// directly would put a Berlin row on the previous date when read in New York. Formatting
/// `dayStart + 12 h` lands mid-day, which reads as the same date in any time zone less than 12 hours
/// away.
enum SyncDayKey {
    static func key(for dayStart: Date, calendar: Calendar = .current) -> String {
        formatter(calendar).string(from: dayStart.addingTimeInterval(12 * 3600))
    }

    /// Local midnight of the date a key names, in this device's calendar.
    static func dayStart(for key: String, calendar: Calendar = .current) -> Date? {
        guard let noon = formatter(calendar).date(from: key)?.addingTimeInterval(12 * 3600) else { return nil }
        return calendar.startOfDay(for: noon)
    }

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

/// One study day: every activity tally is a per-device counter, so two devices studying the same
/// day add up instead of overwriting each other. That makes XP, the streak and the daily goal right.
enum StudyDayCodec: SyncCodec {
    typealias Model = StudyDay

    static let counterFields = [
        "cardsReviewed", "grammarExercises", "conversations", "storySeconds", "storyQuestions",
        "cardSeconds", "grammarSeconds", "conversationSeconds", "storyQuizSeconds",
        "newWordsIntroduced", "newWordsBonus",
    ]

    static let spec: SyncKindSpec = {
        var rules = Dictionary(uniqueKeysWithValues: counterFields.map { ($0, SyncFieldRule.counter) })
        rules["lastActivityAt"] = .max
        return SyncKindSpec(kind: "StudyDay", rules: rules)
    }()

    static func recordName(for model: StudyDay) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: SyncDayKey.key(for: model.dayStart))
    }

    static func bootstrap(for model: StudyDay) -> SyncBootstrap { .perStore }

    static func known(_ d: StudyDay) -> SyncPayload {
        var f = SyncFields()
        f.set("day", SyncDayKey.key(for: d.dayStart))
        f.set("cardsReviewed", d.cardsReviewed)
        f.set("grammarExercises", d.grammarExercises)
        f.set("conversations", d.conversations)
        f.set("storySeconds", d.storySeconds)
        f.set("storyQuestions", d.storyQuestions)
        f.set("cardSeconds", d.cardSeconds)
        f.set("grammarSeconds", d.grammarSeconds)
        f.set("conversationSeconds", d.conversationSeconds)
        f.set("storyQuizSeconds", d.storyQuizSeconds)
        f.set("newWordsIntroduced", d.newWordsIntroduced)
        f.set("newWordsBonus", d.newWordsBonus)
        f.set("lastActivityAt", d.lastActivityAt)
        return f.payload
    }

    /// The local row for a date. Matches by key rather than exact `dayStart`, so a row written in
    /// another time zone (travel) is still found.
    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> StudyDay? {
        guard let key = flat.string("day"), let start = SyncDayKey.dayStart(for: key) else { return nil }
        let lo = start.addingTimeInterval(-14 * 3600), hi = start.addingTimeInterval(14 * 3600)
        let d = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart >= lo && $0.dayStart <= hi })
        return (try? context.fetch(d))?.first { SyncDayKey.key(for: $0.dayStart) == key }
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> StudyDay? {
        guard let key = flat.string("day"), let start = SyncDayKey.dayStart(for: key) else { return nil }
        let day = StudyDay(dayStart: start)
        context.insert(day)
        update(day, from: flat, in: context)
        return day
    }

    static func update(_ d: StudyDay, from flat: SyncPayload, in context: ModelContext) {
        d.cardsReviewed = flat.int("cardsReviewed") ?? 0
        d.grammarExercises = flat.int("grammarExercises") ?? 0
        d.conversations = flat.int("conversations") ?? 0
        d.storySeconds = flat.int("storySeconds") ?? 0
        d.storyQuestions = flat.int("storyQuestions") ?? 0
        d.cardSeconds = flat.int("cardSeconds") ?? 0
        d.grammarSeconds = flat.int("grammarSeconds") ?? 0
        d.conversationSeconds = flat.int("conversationSeconds") ?? 0
        d.storyQuizSeconds = flat.int("storyQuizSeconds") ?? 0
        d.newWordsIntroduced = flat.int("newWordsIntroduced") ?? 0
        d.newWordsBonus = flat.int("newWordsBonus") ?? 0
        if let t = flat.date("lastActivityAt") { d.lastActivityAt = t }
    }
}
