import Foundation

/// A rolling seven-day snapshot of what the learner accomplished, paired with the prior seven days
/// so every figure can be framed as *growth* rather than a vanity total (see
/// `docs/FUTURE_FEATURES.md` #6 — "Progress & streaks over time"). Rolling windows (not calendar
/// weeks) keep the numbers meaningful early in the week instead of resetting to zero every Monday.
///
/// The `wordsRetained` field is the honest "words retained" signal the roadmap asks for: SRS-due
/// words the learner *re-used correctly* in conversation, which advanced their real review schedule
/// (`ConversationSummary.spacedReviews`). The roadmap's other example — "self-corrections up 3×" —
/// waits on the elicitation-feedback feature (#2), which doesn't yet track self-repairs; until then
/// the growth headline draws only on figures the app genuinely records.
struct WeekInReview {
    // The last 7 days (today and the six before it).
    var activeDays: Int
    var cardsReviewed: Int
    var grammarExercises: Int
    var conversations: Int
    /// Distinct SRS-due words re-used correctly in conversation this week — the "words retained" stat.
    var wordsRetained: Int

    // The 7 days before that, for the deltas.
    var prevActiveDays: Int
    var prevCardsReviewed: Int
    var prevGrammarExercises: Int
    var prevConversations: Int
    var prevWordsRetained: Int

    /// Did the learner do anything at all in the last 7 days?
    var hasActivity: Bool {
        activeDays > 0 || cardsReviewed > 0 || grammarExercises > 0 || conversations > 0
    }

    /// Was there activity in the prior 7 days? (Lets the section show even on a quiet current week,
    /// so a dip is still framed against last week rather than vanishing.)
    var hadPriorActivity: Bool {
        prevActiveDays > 0 || prevCardsReviewed > 0 || prevGrammarExercises > 0 || prevConversations > 0
    }

    /// A single upbeat, honest growth line — the "up 3× this week" / "12 words retained" framing.
    /// Prefers an absolute retention win (the stickiest signal), then the biggest multiplicative
    /// jump in effort, and stays silent when there's no clear positive story to tell.
    var headline: String? {
        if wordsRetained >= 3 {
            return "\(wordsRetained) words retained this week"
        }

        let gains: [(name: String, now: Int, before: Int)] = [
            ("Cards reviewed", cardsReviewed, prevCardsReviewed),
            ("Grammar drills", grammarExercises, prevGrammarExercises),
            ("Conversations", conversations, prevConversations),
        ]
        let best = gains
            .filter { $0.before > 0 && $0.now >= $0.before * 2 }
            .max { ($0.now / max(1, $0.before)) < ($1.now / max(1, $1.before)) }
        if let best {
            let factor = best.now / max(1, best.before)
            return "\(best.name) up \(factor)× this week"
        }

        if wordsRetained > 0 {
            return "\(wordsRetained) word\(wordsRetained == 1 ? "" : "s") retained this week"
        }
        return nil
    }
}

/// Aggregates the per-day `StudyDay` log and finished conversations into a `WeekInReview`. Pure over
/// already-fetched models (mirroring `StudyLogService`) so the Home section computes it straight from
/// its `@Query`s and stays reactive.
enum WeekInReviewService {

    static func summary(
        days: [StudyDay],
        conversations: [ChatConversation],
        asOf now: Date = Date()
    ) -> WeekInReview {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // [thisWeekStart, endExclusive) is the last 7 days; [lastWeekStart, thisWeekStart) the 7 before.
        let endExclusive   = cal.date(byAdding: .day, value: 1,   to: today) ?? today
        let thisWeekStart  = cal.date(byAdding: .day, value: -6,  to: today) ?? today
        let lastWeekStart  = cal.date(byAdding: .day, value: -13, to: today) ?? today

        let thisWeekDays = days.filter { $0.hasActivity && $0.dayStart >= thisWeekStart && $0.dayStart < endExclusive }
        let lastWeekDays = days.filter { $0.hasActivity && $0.dayStart >= lastWeekStart && $0.dayStart < thisWeekStart }

        let thisWeekChats = conversations.filter { $0.createdAt >= thisWeekStart && $0.createdAt < endExclusive }
        let lastWeekChats = conversations.filter { $0.createdAt >= lastWeekStart && $0.createdAt < thisWeekStart }

        let this = totals(thisWeekDays)
        let prev = totals(lastWeekDays)

        return WeekInReview(
            activeDays:           this.activeDays,
            cardsReviewed:        this.cards,
            grammarExercises:     this.grammar,
            conversations:        this.conversations,
            wordsRetained:        retainedWordCount(thisWeekChats),
            prevActiveDays:       prev.activeDays,
            prevCardsReviewed:    prev.cards,
            prevGrammarExercises: prev.grammar,
            prevConversations:    prev.conversations,
            prevWordsRetained:    retainedWordCount(lastWeekChats)
        )
    }

    /// Folds one window of active `StudyDay`s into its component sums.
    private static func totals(_ days: [StudyDay]) -> (activeDays: Int, cards: Int, grammar: Int, conversations: Int) {
        var cards = 0, grammar = 0, conversations = 0
        for day in days {
            cards += day.cardsReviewed
            grammar += day.grammarExercises
            conversations += day.conversations
        }
        return (days.count, cards, grammar, conversations)
    }

    /// Distinct (case-insensitive) SRS-due words the learner re-used correctly across the given
    /// conversations — pulled from each chat's persisted `ConversationSummary.spacedReviews`.
    private static func retainedWordCount(_ conversations: [ChatConversation]) -> Int {
        var words = Set<String>()
        for convo in conversations {
            for word in convo.summary?.spacedReviews ?? [] {
                words.insert(word.lowercased())
            }
        }
        return words.count
    }
}
