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

    /// How many days the window covers — 7 by default, or whatever a custom from–until range spans.
    /// The comparison window is always the same length immediately before it.
    var dayCount: Int = 7

    /// How to *name* the window in prose: "this week", or "in this range" for a custom one. Lives on
    /// the summary so `headline` can't claim "this week" about a window that isn't one.
    var periodLabel: String = "this week"

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
            return "\(wordsRetained) words retained \(periodLabel)"
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
            return "\(best.name) up \(factor)× \(periodLabel)"
        }

        if wordsRetained > 0 {
            return "\(wordsRetained) word\(wordsRetained == 1 ? "" : "s") retained \(periodLabel)"
        }
        return nil
    }
}

/// Aggregates the per-day `StudyDay` log and finished conversations into a `WeekInReview`. Pure over
/// already-fetched models (mirroring `StudyLogService`) so the Home section computes it straight from
/// its `@Query`s and stays reactive.
enum WeekInReviewService {

    /// The default window: today and the six days before it, against the seven before that.
    static func summary(
        days: [StudyDay],
        conversations: [ChatConversation],
        asOf now: Date = Date()
    ) -> WeekInReview {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let endExclusive  = cal.date(byAdding: .day, value: 1,  to: today) ?? today
        let thisWeekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
        return summary(
            days: days, conversations: conversations,
            from: thisWeekStart, to: endExclusive, periodLabel: "this week"
        )
    }

    /// An arbitrary half-open window `[start, endExclusive)`, compared against the window of the
    /// **same length** immediately before it — so a learner who picks "the last 30 days" gets the
    /// same growth framing a week does, measured against the 30 days before that. Backs the
    /// from–until picker on the Home review section.
    static func summary(
        days: [StudyDay],
        conversations: [ChatConversation],
        from start: Date,
        to endExclusive: Date,
        periodLabel: String = "in this range"
    ) -> WeekInReview {
        let cal = Calendar.current
        let length = max(1, cal.dateComponents([.day], from: start, to: endExclusive).day ?? 7)
        let priorStart = cal.date(byAdding: .day, value: -length, to: start) ?? start

        let currentDays = days.filter { $0.hasActivity && $0.dayStart >= start && $0.dayStart < endExclusive }
        let priorDays   = days.filter { $0.hasActivity && $0.dayStart >= priorStart && $0.dayStart < start }

        let currentChats = conversations.filter { $0.createdAt >= start && $0.createdAt < endExclusive }
        let priorChats   = conversations.filter { $0.createdAt >= priorStart && $0.createdAt < start }

        let this = totals(currentDays)
        let prev = totals(priorDays)

        return WeekInReview(
            activeDays:           this.activeDays,
            cardsReviewed:        this.cards,
            grammarExercises:     this.grammar,
            conversations:        this.conversations,
            wordsRetained:        retainedWordCount(currentChats),
            prevActiveDays:       prev.activeDays,
            prevCardsReviewed:    prev.cards,
            prevGrammarExercises: prev.grammar,
            prevConversations:    prev.conversations,
            prevWordsRetained:    retainedWordCount(priorChats),
            dayCount:             length,
            periodLabel:          periodLabel
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
