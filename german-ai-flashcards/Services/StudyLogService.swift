import Foundation
import SwiftData

/// One thing the learner just finished — the unit recorded into the per-day `StudyDay` log.
enum StudyActivity {
    case cards(Int)             // n flashcards reviewed
    case grammar(Int)           // n grammar exercises answered
    case conversation           // one chat finished
    case storyReading(Int)      // n seconds spent reading/listening to a story
    case storyQuestions(Int)    // n story comprehension questions answered
}

/// Records daily study activity and derives the streak the "Today" screen shows.
///
/// Writing goes through `record(_:in:)` from the app's activity-completion points
/// (`DeckStore.saveQuizResult` / `saveGrammarQuizResult`, `LearnerMemoryService.applySession`).
/// Reading is pure over an already-fetched `[StudyDay]` so the Today view can compute the streak
/// straight from its `@Query` and stay reactive.
enum StudyLogService {

    // MARK: - Write

    /// Fold one finished activity into today's row (creating it on the first activity of the day).
    static func record(_ activity: StudyActivity, in context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let day = fetchOrCreate(dayStart, in: context)

        switch activity {
        case .cards(let n):           day.cardsReviewed += max(0, n)
        case .grammar(let n):         day.grammarExercises += max(0, n)
        case .conversation:           day.conversations += 1
        case .storyReading(let s):    day.storySeconds += max(0, s)
        case .storyQuestions(let n):  day.storyQuestions += max(0, n)
        }
        day.lastActivityAt = Date()
        try? context.save()
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

    private static func studiedDays(_ days: [StudyDay]) -> Set<Date> {
        let cal = Calendar.current
        return Set(days.filter(\.hasActivity).map { cal.startOfDay(for: $0.dayStart) })
    }
}
