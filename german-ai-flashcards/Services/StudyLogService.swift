import Foundation
import SwiftData

// `StudyActivity`, `StudyTimeBucket` and the day rules live in StudyDayCounts.swift (shared
// with Android); this file is the SwiftData side.

/// Records daily study activity and derives the streak the "Today" screen shows.
///
/// Writing goes through `record(_:seconds:in:)` from the app's activity-completion points
/// (`DeckStore.saveQuizResult` / `saveGrammarQuizResult`, `LearnerMemoryService.applySession`),
/// or `recordTime(_:seconds:in:)` where time accrues without anything finishing (a live chat).
/// Reading is pure over an already-fetched `[StudyDay]` so the Today view can compute the streak
/// straight from its `@Query` and stay reactive.
enum StudyLogService {

    // MARK: - Write

    /// Fold one finished activity into today's row (creating it on the first activity of the day).
    /// `seconds` is how long it took, banked into the activity's time bucket — pass it wherever the
    /// caller has a duration, so the calendar can total time as well as items. `.storyReading`
    /// carries its own seconds and ignores this.
    static func record(_ activity: StudyActivity, seconds: Int = 0, in context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let day = fetchOrCreate(dayStart, in: context)
        day.add(StudyDayTally.increments(for: activity, seconds: seconds))
        day.lastActivityAt = Date()
        try? context.save()
    }

    /// Bank time with nothing finished — the live drip from an in-progress conversation, which
    /// should colour the day even if the chat is never summarized. Sub-minute noise is dropped by
    /// `StudyDay.hasActivity`, not here, so short stretches still sum into a real total.
    static func recordTime(_ bucket: StudyTimeBucket, seconds: Int, in context: ModelContext) {
        guard seconds > 0 else { return }
        let dayStart = Calendar.current.startOfDay(for: Date())
        let day = fetchOrCreate(dayStart, in: context)
        day.add(StudyDayTally.increments(time: bucket, seconds: seconds))
        day.lastActivityAt = Date()
        try? context.save()
    }

    // MARK: New-word budget (Wortschatz)

    /// A Goethe word got its first rating. Counts against today's new-word budget; does not mark
    /// the day active on its own (the review that produced it already did).
    static func recordNewWords(_ n: Int, in context: ModelContext) {
        guard n > 0 else { return }
        let day = fetchOrCreate(Calendar.current.startOfDay(for: Date()), in: context)
        day.newWordsIntroduced += n
        try? context.save()
    }

    /// "Learn 10 more": widen today's budget without touching the daily setting.
    static func addNewWordBonus(_ n: Int, in context: ModelContext) {
        guard n > 0 else { return }
        let day = fetchOrCreate(Calendar.current.startOfDay(for: Date()), in: context)
        day.newWordsBonus += n
        try? context.save()
    }

    /// Today's introduced count and bonus, read off an already-fetched set.
    static func todayNewWords(_ days: [StudyDay], asOf now: Date = Date()) -> (introduced: Int, bonus: Int) {
        StudyStreak.todayNewWords(days, asOf: now)
    }

    /// New words still allowed today under `newPerDay`.
    static func newWordBudgetRemaining(_ days: [StudyDay], newPerDay: Int, asOf now: Date = Date()) -> Int {
        StudyStreak.newWordBudgetRemaining(days, newPerDay: newPerDay, asOf: now)
    }

    private static func fetchOrCreate(_ dayStart: Date, in context: ModelContext) -> StudyDay {
        // Match the calendar date, not the exact instant: after a time-zone change, today's
        // midnight is a different instant than the one the row was made with, and a second row
        // for the same date would split the day (and, with iCloud Sync, share one record).
        let key = SyncDayKey.key(for: dayStart)
        let lo = dayStart.addingTimeInterval(-14 * 3600), hi = dayStart.addingTimeInterval(14 * 3600)
        let descriptor = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart >= lo && $0.dayStart <= hi })
        if let existing = (try? context.fetch(descriptor))?.first(where: { SyncDayKey.key(for: $0.dayStart) == key }) {
            return existing
        }
        let created = StudyDay(dayStart: dayStart)
        context.insert(created)
        return created
    }

    // MARK: - Read (pure, over an already-fetched set; the rules are `StudyStreak`'s)

    /// Did the learner study today?
    static func studiedToday(_ days: [StudyDay], asOf now: Date = Date()) -> Bool {
        StudyStreak.studiedToday(days, asOf: now)
    }

    /// The current streak: consecutive days with activity ending today, still "alive" from
    /// yesterday until today ends.
    static func currentStreak(_ days: [StudyDay], asOf now: Date = Date()) -> Int {
        StudyStreak.currentStreak(days, asOf: now)
    }

    typealias TimeSummary = StudyTimeSummary

    /// Sum the log over `start ..< end` (both expected at midnight).
    static func timeSummary(_ days: [StudyDay], from start: Date, to end: Date) -> TimeSummary {
        StudyStreak.timeSummary(days, from: start, to: end)
    }
}
