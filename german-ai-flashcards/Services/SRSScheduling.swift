//
//  SRSScheduling.swift
//  german-ai-flashcards
//
//  The review math behind both study modes, SM-2 (Anki-style ratings) and the Leitner boxes,
//  written against `SRSCardState` instead of the SwiftData card. `SpacedRepetitionService` and
//  `LeitnerService` call it with a `SavedCard`; the Android app calls it with its own card.
//

import Foundation

/// The fields a card's review schedule lives in. `SavedCard` conforms on iOS.
protocol SRSCardState: AnyObject {
    var sortOrder: Int { get }
    var easeFactor: Double { get set }
    var interval: Int { get set }
    var repetitions: Int { get set }
    var nextReviewDate: Date? { get set }
    var totalReviews: Int { get set }
    var lapses: Int { get set }
    var leitnerBox: Int { get set }
    /// Stamps the review (first/last seen, last result); see `SavedCard.noteReview`.
    func noteReview(correct: Bool, at now: Date)
}

/// User rating for an Anki-style review.
enum AnkiRating: Int, CaseIterable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    /// Button titles. "Didn't know" rather than Anki's "Again": learners pressed Hard when they
    /// had no idea, because nothing said Hard still counts as knowing it.
    var label: String {
        switch self {
        case .again: "Didn't know"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    /// One-line meaning, for the legend above the buttons.
    var meaning: String {
        switch self {
        case .again: "no idea, or wrong"
        case .hard: "knew it, slowly"
        case .good: "knew it"
        case .easy: "instant"
        }
    }

    var color: String {
        switch self {
        case .again: "red"
        case .hard: "orange"
        case .good: "green"
        case .easy: "blue"
        }
    }
}

enum SRSScheduling {

    /// The top Leitner box (5, "mastered"); `LeitnerService.maxBox` reads it.
    static let leitnerMaxBox = 5

    /// Apply a rating to a card and update its SRS fields in-place.
    static func apply(rating: AnkiRating, to card: some SRSCardState) {
        card.totalReviews += 1
        card.noteReview(correct: rating != .again, at: .now)

        switch rating {
        case .again:
            // Lapse: reset repetitions, reduce ease, short interval
            card.lapses += 1
            card.repetitions = 0
            card.easeFactor = max(1.3, card.easeFactor - 0.2)
            card.interval = 1

        case .hard:
            // Slightly reduce ease, increase interval conservatively
            card.easeFactor = max(1.3, card.easeFactor - 0.15)
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 4
            } else {
                card.interval = Int(ceil(Double(card.interval) * 1.2))
            }
            card.repetitions += 1

        case .good:
            // Standard progression — ease stays the same
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 6
            } else {
                card.interval = Int(ceil(Double(card.interval) * card.easeFactor))
            }
            card.repetitions += 1

        case .easy:
            // Boost ease, jump interval
            card.easeFactor += 0.15
            if card.repetitions == 0 {
                card.interval = 4
            } else if card.repetitions == 1 {
                card.interval = 10
            } else {
                card.interval = Int(ceil(Double(card.interval) * card.easeFactor * 1.3))
            }
            card.repetitions += 1
        }

        // Cap interval at ~1 year
        card.interval = min(card.interval, 365)

        // Schedule next review
        card.nextReviewDate = Calendar.current.date(byAdding: .day, value: card.interval, to: .now)
    }

    /// Describes the next interval for each rating option, given the card's current state.
    static func previewIntervals(for card: some SRSCardState) -> [(rating: AnkiRating, label: String)] {
        AnkiRating.allCases.map { rating in
            let days = previewInterval(rating: rating, card: card)
            return (rating, formatInterval(days))
        }
    }

    private static func previewInterval(rating: AnkiRating, card: some SRSCardState) -> Int {
        switch rating {
        case .again:
            return 1
        case .hard:
            if card.repetitions <= 1 { return card.repetitions == 0 ? 1 : 4 }
            return Int(ceil(Double(card.interval) * 1.2))
        case .good:
            if card.repetitions == 0 { return 1 }
            if card.repetitions == 1 { return 6 }
            return Int(ceil(Double(card.interval) * card.easeFactor))
        case .easy:
            if card.repetitions == 0 { return 4 }
            if card.repetitions == 1 { return 10 }
            return min(Int(ceil(Double(card.interval) * card.easeFactor * 1.3)), 365)
        }
    }

    private static func formatInterval(_ days: Int) -> String {
        if days == 1 { return "1d" }
        if days < 30 { return "\(days)d" }
        if days < 365 { return "\(days / 30)mo" }
        return "1y"
    }

    // MARK: - Leitner

    /// Promote a card after a correct answer.
    ///
    /// Leitner study counts as learned the same way Anki study does: a run of correct answers
    /// bumps `repetitions` (the bar `PyramidService.provenRepetitions` reads), and the box's own
    /// spacing stands in for an interval, so a word drilled only in Leitner can reach "bekannt".
    static func leitnerCorrect(_ card: some SRSCardState) {
        card.leitnerBox = min(card.leitnerBox + 1, leitnerMaxBox)
        card.totalReviews += 1
        card.noteReview(correct: true, at: .now)
        card.repetitions += 1
        card.interval = max(card.interval, 1 << (card.leitnerBox - 1))
    }

    /// Demote a card after a wrong answer (back to Box 1). The correct-run resets with it.
    static func leitnerWrong(_ card: some SRSCardState) {
        card.leitnerBox = 1
        card.totalReviews += 1
        card.noteReview(correct: false, at: .now)
        card.lapses += 1
        card.repetitions = 0
    }
}
