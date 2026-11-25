import Foundation
import SwiftUI

/// Implements the Leitner box system for spaced repetition.
///
/// Cards live in boxes 0–5:
/// - Box 0: New / unseen cards.
/// - Box 1: Reviewed once or failed from a higher box.
/// - Box 2–5: Progressively longer review intervals.
///
/// Rules:
/// - **Correct** → card moves up one box (max 5).
/// - **Wrong** → card drops back to Box 1.
enum LeitnerService {

    static let maxBox = 5

    /// Promote a card after a correct answer.
    ///
    /// Leitner study counts as learned the same way Anki study does: a run of correct answers
    /// bumps `repetitions` (the bar `PyramidService.provenRepetitions` reads), and the box's own
    /// spacing stands in for an interval, so a word drilled only in Leitner can reach "bekannt".
    static func markCorrect(_ card: SavedCard) {
        card.leitnerBox = min(card.leitnerBox + 1, maxBox)
        card.totalReviews += 1
        card.noteReview(correct: true)
        card.repetitions += 1
        card.interval = max(card.interval, 1 << (card.leitnerBox - 1))
    }

    /// Demote a card after a wrong answer (back to Box 1). The correct-run resets with it.
    static func markWrong(_ card: SavedCard) {
        card.leitnerBox = 1
        card.totalReviews += 1
        card.noteReview(correct: false)
        card.lapses += 1
        card.repetitions = 0
    }

    /// Returns cards that should be reviewed this session.
    ///
    /// The Leitner schedule: Box *n* is reviewed every 2^(n-1) sessions.
    /// We approximate this by looking at the deck's total quiz count as
    /// the "session number", and include a box when
    /// `sessionNumber % interval == 0`.
    ///
    /// Box 0 cards (new) are always included.
    static func dueCards(in cards: [SavedCard], sessionNumber: Int) -> [SavedCard] {
        cards.filter { card in
            isDue(box: card.leitnerBox, sessionNumber: sessionNumber)
        }
        .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Check if a given box should be reviewed this session.
    static func isDue(box: Int, sessionNumber: Int) -> Bool {
        guard box > 0 else { return true } // Box 0 always due
        let interval = 1 << (box - 1) // 1, 2, 4, 8, 16
        return sessionNumber % interval == 0
    }

    /// Human-readable label for a box number.
    static func boxLabel(_ box: Int) -> String {
        switch box {
        case 0: "New"
        case 1: "Box 1"
        case 2: "Box 2"
        case 3: "Box 3"
        case 4: "Box 4"
        case 5: "Box 5 (Mastered)"
        default: "Box \(box)"
        }
    }

    /// Color name for a box (used for tinting).
    static func boxColor(_ box: Int) -> String {
        switch box {
        case 0: "gray"
        case 1: "red"
        case 2: "orange"
        case 3: "yellow"
        case 4: "green"
        case 5: "blue"
        default: "gray"
        }
    }

    /// The box's tint, shared by the player's box badge and the Wortschatz chart.
    static func boxSwiftUIColor(_ box: Int) -> Color {
        switch box {
        case 0: .gray
        case 1: .red
        case 2: .orange
        case 3: .yellow
        case 4: .green
        case 5: .blue
        default: .gray
        }
    }

    /// Returns the distribution of cards across boxes for display.
    static func boxDistribution(_ cards: [SavedCard]) -> [(box: Int, count: Int)] {
        (0...maxBox).map { box in
            (box, cards.filter { $0.leitnerBox == box }.count)
        }
        .filter { $0.count > 0 }
    }
}
