import Foundation
import SwiftData

/// Fills in the per-day time buckets on `StudyDay` for days logged before time tracking existed.
///
/// Every activity already stored its own duration on its own record (`QuizResult`, `ArticleRound`,
/// `ChatConversation`, `StoryQuizAttempt`) — the day log just never rolled them up. This walks that
/// history once and banks each record's seconds into its day, so the calendar's time totals mean
/// something on day one instead of starting from an empty year.
///
/// Two rules keep the pass honest:
/// - **Only existing `StudyDay` rows are touched.** A record on a day the streak never counted
///   stays uncounted; the backfill adds time to history, never new streak days.
/// - **Reading sessions are skipped.** `storySeconds` was already live-logged from day one, and
///   `StoryReadingSession` rows can't tell which of them were counted, so re-summing would double.
///
/// Runs once, gated on `backfillKey`; bump the key's version to re-run after changing the sources.
enum StudyTimeBackfillService {

    private static let backfillKey = "studyTime.backfill.v1"

    /// Roll historical durations into `StudyDay`. Cheap no-op after the first run.
    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: backfillKey) else { return }
        defaults.set(true, forKey: backfillKey)
        run(in: context)
    }

    /// The pass itself, exposed for a manual re-run (Settings ▸ debug) and tests.
    static func run(in context: ModelContext) {
        let cal = Calendar.current
        var cardSeconds: [Date: Int] = [:]
        var grammarSeconds: [Date: Int] = [:]
        var conversationSeconds: [Date: Int] = [:]
        var storyQuizSeconds: [Date: Int] = [:]

        // Flashcards, matching (which persists as a QuizResult too), and grammar drills — told
        // apart by the stats deck the result hangs off.
        for q in fetchAll(QuizResult.self, in: context) where q.durationSeconds > 0 {
            let day = cal.startOfDay(for: q.date)
            if q.deck?.generatorRaw == "grammar" {
                grammarSeconds[day, default: 0] += q.durationSeconds
            } else {
                cardSeconds[day, default: 0] += q.durationSeconds
            }
        }

        // Der/die/das rounds count as grammar practice, exactly as they do live.
        for r in fetchAll(ArticleRound.self, in: context) where r.durationSeconds > 0 {
            grammarSeconds[cal.startOfDay(for: r.date), default: 0] += r.durationSeconds
        }

        // A conversation's duration is one running total for the whole chat; attribute it to the
        // day it was started, which is the day it was almost always held.
        for c in fetchAll(ChatConversation.self, in: context) where c.durationSeconds > 0 {
            conversationSeconds[cal.startOfDay(for: c.createdAt), default: 0] += c.durationSeconds
        }

        for a in fetchAll(StoryQuizAttempt.self, in: context) where a.durationSeconds > 0 {
            storyQuizSeconds[cal.startOfDay(for: a.date), default: 0] += a.durationSeconds
        }

        // Take the larger of what's there and what history says, rather than adding: a re-run
        // stays idempotent instead of doubling every day it touches, and anything already logged
        // live today survives the pass.
        for day in fetchAll(StudyDay.self, in: context) {
            let key = cal.startOfDay(for: day.dayStart)
            day.cardSeconds = max(day.cardSeconds, cardSeconds[key] ?? 0)
            day.grammarSeconds = max(day.grammarSeconds, grammarSeconds[key] ?? 0)
            day.conversationSeconds = max(day.conversationSeconds, conversationSeconds[key] ?? 0)
            day.storyQuizSeconds = max(day.storyQuizSeconds, storyQuizSeconds[key] ?? 0)
        }

        try? context.save()
    }

    private static func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}
