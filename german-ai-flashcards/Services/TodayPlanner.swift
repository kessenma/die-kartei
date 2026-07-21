import SwiftUI

/// What a Today recommendation does when tapped. The view resolves each into a concrete
/// action (a `router` launch, a tab switch, a pushed screen, or a lesson sheet) so this stays
/// UI-framework-light and easy to reason about / test.
enum TodayIntent: Equatable {
    /// Review the SRS cards that have come due, across every deck.
    case reviewDueCards
    /// Practice one shaky grammar structure (a multiple-choice drill when one exists for it,
    /// otherwise a 30-second mini-lesson from `GrammarFocus.explanation`).
    case grammar(GrammarFocus)
    /// A short conversation — the streak-keeper.
    case chat
    /// Turn the coach's remembered words / slip-ups into a drill deck.
    case buildDrillDeck
    /// Generate a fresh vocabulary deck.
    case generateDeck
    /// Pick up a flashcard session the learner paused mid-deck.
    case resumePausedDeck
}

/// One ordered item in the Today plan.
struct TodayRecommendation: Identifiable {
    let intent: TodayIntent
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var id: String {
        switch intent {
        case .reviewDueCards:   return "review"
        case .grammar(let f):   return "grammar-\(f.rawValue)"
        case .chat:             return "chat"
        case .buildDrillDeck:   return "drill"
        case .generateDeck:     return "generate"
        case .resumePausedDeck: return "resume"
        }
    }
}

/// The live facts the plan is built from — gathered by the view from its `@Query`s so the
/// planner itself is a pure function (same snapshot → same plan).
struct TodaySnapshot {
    var dueCardCount: Int
    /// Shaky grammar structures, worst-first (already thresholded).
    var weaknesses: [GrammarFocus]
    /// The coach has remembered words or slip-ups that could become a drill deck.
    var hasCoachContent: Bool
    var streak: Int
    var studiedToday: Bool
    /// Has the learner ever done anything (studied, chatted, or made a deck)? Drives cold-start.
    var hasStartedLearning: Bool
    /// A day-of-year index used to rotate/interleave which weak spot is surfaced, so the plan
    /// isn't the identical three items every day.
    var dayIndex: Int
    /// An in-progress (paused) flashcard session to offer resuming, if any.
    var resume: ResumeInfo? = nil

    struct ResumeInfo: Equatable {
        var topic: String
        var cardIndex: Int
        var cardCount: Int
    }
}

/// Builds the short, ordered "here's the one next thing" plan from a snapshot of the learner's
/// state. Deliberately opinionated and capped — the whole point is to *remove* the decision.
enum TodayPlanner {

    static func plan(_ s: TodaySnapshot) -> [TodayRecommendation] {
        // Cold start: don't invent SRS/grammar work the learner hasn't generated yet.
        guard s.hasStartedLearning else {
            return [generate(cold: true), chat(streak: s.streak, studiedToday: s.studiedToday)]
        }

        var recs: [TodayRecommendation] = []

        // 0. Resume an unfinished session first — the learner was literally mid-deck.
        if let resume = s.resume {
            recs.append(resumeRec(resume))
        }

        // 1. Clear the spaced-repetition backlog first — it's time-sensitive by design.
        if s.dueCardCount > 0 {
            recs.append(review(count: s.dueCardCount))
        } else if s.hasCoachContent {
            // Nothing due, but there's remembered material worth turning into review.
            recs.append(drill())
        }

        // 2. Target a weak spot, rotating through the shaky ones for interleaving.
        if !s.weaknesses.isEmpty {
            let focus = s.weaknesses[s.dayIndex % s.weaknesses.count]
            recs.append(grammar(focus))
        }

        // 3. Keep (or kindle) the streak with a short chat — always on the plan.
        recs.append(chat(streak: s.streak, studiedToday: s.studiedToday))

        // Never leave a returning learner with a single lonely item.
        if recs.count < 2 {
            recs.append(generate(cold: false))
        }

        return Array(recs.prefix(3))
    }

    // MARK: - Builders

    private static func review(count: Int) -> TodayRecommendation {
        let minutes = max(1, Int((Double(count) * 7.0 / 60.0).rounded()))
        return TodayRecommendation(
            intent: .reviewDueCards,
            title: "Review \(count) due card\(count == 1 ? "" : "s")",
            subtitle: "Spaced repetition · ~\(minutes) min",
            systemImage: "rectangle.stack.badge.play.fill",
            accent: .blue
        )
    }

    private static func grammar(_ focus: GrammarFocus) -> TodayRecommendation {
        TodayRecommendation(
            intent: .grammar(focus),
            title: "\(focus.germanLabel) practice",
            subtitle: "\(focus.englishLabel) · a recurring weak spot",
            systemImage: "checklist",
            accent: .orange
        )
    }

    private static func chat(streak: Int, studiedToday: Bool) -> TodayRecommendation {
        let title: String
        let subtitle: String
        if streak <= 0 {
            title = "Start a streak today"
            subtitle = "A short chat gets you going"
        } else if studiedToday {
            title = "Keep the momentum going"
            subtitle = "A 5-min chat · 🔥 \(streak)-day streak"
        } else {
            title = "Keep your \(streak)-day streak"
            subtitle = "A 5-min chat keeps 🔥 \(streak) alive"
        }
        return TodayRecommendation(
            intent: .chat,
            title: title,
            subtitle: subtitle,
            systemImage: "bubble.left.and.bubble.right.fill",
            accent: .green
        )
    }

    private static func drill() -> TodayRecommendation {
        TodayRecommendation(
            intent: .buildDrillDeck,
            title: "Build a drill deck",
            subtitle: "Your words & slip-ups → flashcards",
            systemImage: "rectangle.stack.badge.plus",
            accent: .purple
        )
    }

    private static func generate(cold: Bool) -> TodayRecommendation {
        TodayRecommendation(
            intent: .generateDeck,
            title: cold ? "Create your first deck" : "Generate flashcards",
            subtitle: "AI vocabulary on any topic",
            systemImage: "sparkles",
            accent: .pink
        )
    }

    private static func resumeRec(_ r: TodaySnapshot.ResumeInfo) -> TodayRecommendation {
        TodayRecommendation(
            intent: .resumePausedDeck,
            title: "Resume \(r.topic)",
            subtitle: "Card \(r.cardIndex + 1) of \(r.cardCount) · pick up where you left off",
            systemImage: "play.circle.fill",
            accent: .teal
        )
    }
}
