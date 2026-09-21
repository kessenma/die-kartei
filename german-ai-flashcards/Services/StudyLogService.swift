import Foundation
import SwiftData

/// One thing the learner just finished — the unit recorded into the per-day `StudyDay` log.
enum StudyActivity {
    case cards(Int)             // n flashcards reviewed
    case grammar(Int)           // n grammar exercises answered
    case conversation           // one chat finished
    case storyReading(Int)      // n seconds spent reading/listening to a story
    case storyQuestions(Int)    // n story comprehension questions answered

    /// Which time bucket this activity's seconds belong to.
    var timeBucket: StudyTimeBucket {
        switch self {
        case .cards:          return .cards
        case .grammar:        return .grammar
        case .conversation:   return .conversation
        case .storyReading:   return .storyReading
        case .storyQuestions: return .storyQuiz
        }
    }
}

/// The time-on-task buckets a day is split into. Kept separate from `StudyActivity` because time
/// can accrue without anything being *finished* — a conversation drips seconds into the day while
/// it's still running.
enum StudyTimeBucket {
    case cards, grammar, conversation, storyReading, storyQuiz
}

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

        switch activity {
        case .cards(let n):           day.cardsReviewed += max(0, n)
        case .grammar(let n):         day.grammarExercises += max(0, n)
        case .conversation:           day.conversations += 1
        case .storyReading(let s):    day.storySeconds += max(0, s)
        case .storyQuestions(let n):  day.storyQuestions += max(0, n)
        }
        // Story reading's seconds *are* its count, already added above.
        if case .storyReading = activity {} else {
            add(seconds: seconds, to: activity.timeBucket, on: day)
        }
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
        add(seconds: seconds, to: bucket, on: day)
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
        let today = Calendar.current.startOfDay(for: now)
        guard let day = days.first(where: { Calendar.current.startOfDay(for: $0.dayStart) == today }) else {
            return (0, 0)
        }
        return (day.newWordsIntroduced, day.newWordsBonus)
    }

    /// New words still allowed today under `newPerDay`.
    static func newWordBudgetRemaining(_ days: [StudyDay], newPerDay: Int, asOf now: Date = Date()) -> Int {
        let today = todayNewWords(days, asOf: now)
        return max(0, newPerDay + today.bonus - today.introduced)
    }

    private static func add(seconds: Int, to bucket: StudyTimeBucket, on day: StudyDay) {
        let s = max(0, seconds)
        guard s > 0 else { return }
        switch bucket {
        case .cards:        day.cardSeconds += s
        case .grammar:      day.grammarSeconds += s
        case .conversation: day.conversationSeconds += s
        case .storyReading: day.storySeconds += s
        case .storyQuiz:    day.storyQuizSeconds += s
        }
    }

    private static func fetchOrCreate(_ dayStart: Date, in context: ModelContext) -> StudyDay {
        let descriptor = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart == dayStart })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = StudyDay(dayStart: dayStart)
        context.insert(created)
        return created
    }

    // MARK: - Read (pure, over an already-fetched set)

    /// Did the learner study today?
    static func studiedToday(_ days: [StudyDay], asOf now: Date = Date()) -> Bool {
        let today = Calendar.current.startOfDay(for: now)
        return studiedDays(days).contains(today)
    }

    /// The current streak: consecutive days with activity ending today. If today has no activity
    /// yet but yesterday did, the streak is still "alive" (counted from yesterday) so today's chat
    /// can be framed as *keeping* it. Zero once a full day is missed.
    static func currentStreak(_ days: [StudyDay], asOf now: Date = Date()) -> Int {
        let cal = Calendar.current
        let studied = studiedDays(days)
        guard !studied.isEmpty else { return 0 }

        let today = cal.startOfDay(for: now)
        var cursor = today
        if !studied.contains(today) {
            // No activity today — the streak survives only if yesterday counted.
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  studied.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while studied.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Time on task over a date range, plus the context that makes the number mean something:
    /// how many of those days were active, and the average across them.
    struct TimeSummary {
        var totalSeconds: Int
        var activeDays: Int
        /// Average over *active* days only — an average over 365 calendar days would read as zero
        /// for anyone with a normal life.
        var averageSeconds: Int { activeDays > 0 ? totalSeconds / activeDays : 0 }
        var hasTime: Bool { totalSeconds > 0 }
    }

    /// Sum the log over `start ..< end` (both expected at midnight).
    static func timeSummary(_ days: [StudyDay], from start: Date, to end: Date) -> TimeSummary {
        var total = 0
        var active = 0
        for day in days where day.dayStart >= start && day.dayStart < end {
            guard day.hasActivity else { continue }
            active += 1
            total += day.totalSeconds
        }
        return TimeSummary(totalSeconds: total, activeDays: active)
    }

    private static func studiedDays(_ days: [StudyDay]) -> Set<Date> {
        let cal = Calendar.current
        return Set(days.filter(\.hasActivity).map { cal.startOfDay(for: $0.dayStart) })
    }
}
