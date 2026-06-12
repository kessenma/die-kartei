import Foundation
import SwiftData

/// User rating for an Anki-style review.
enum AnkiRating: Int, CaseIterable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
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

/// Implements a simplified SM-2 spaced repetition algorithm.
enum SpacedRepetitionService {

    /// Apply a rating to a card and update its SRS fields in-place.
    static func apply(rating: AnkiRating, to card: SavedCard) {
        card.totalReviews += 1

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

    /// Returns cards from the deck that are due for review (nextReviewDate <= now, or never reviewed).
    static func dueCards(in deck: SavedDeck) -> [SavedCard] {
        let now = Date.now
        return deck.cards
            .filter { card in
                guard let next = card.nextReviewDate else { return true } // never reviewed
                return next <= now
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Describes the next interval for each rating option, given the card's current state.
    static func previewIntervals(for card: SavedCard) -> [(rating: AnkiRating, label: String)] {
        AnkiRating.allCases.map { rating in
            let days = previewInterval(rating: rating, card: card)
            return (rating, formatInterval(days))
        }
    }

    private static func previewInterval(rating: AnkiRating, card: SavedCard) -> Int {
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
}
