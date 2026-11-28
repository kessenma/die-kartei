import Foundation
import SwiftData

/// Implements a simplified SM-2 spaced repetition algorithm.
enum SpacedRepetitionService {

    /// Apply a rating to a card and update its SRS fields in-place.
    static func apply(rating: AnkiRating, to card: SavedCard) {
        SRSScheduling.apply(rating: rating, to: card)
    }

    /// Returns cards from the deck that are due for review (nextReviewDate <= now, or never reviewed).
    static func dueCards(in deck: SavedDeck) -> [SavedCard] {
        let now = Date.now
        return deck.cards
            .filter { AnkiSessionRules.isDue(nextReviewDate: $0.nextReviewDate, now: now) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Spaced re-encounter (conversation)

    /// A card genuinely due for a spaced *re*-encounter: it has been scheduled (reviewed at least
    /// once) and that date has passed. Excludes never-scheduled cards so a fresh deck's whole
    /// backlog doesn't flood the conversation's due list.
    static func isDueForReview(_ card: SavedCard, now: Date = .now) -> Bool {
        guard let next = card.nextReviewDate else { return false }
        return next <= now
    }

    /// Due cards restricted to the given decks, most-overdue first.
    static func dueCards(forDeckIDs ids: [UUID], in context: ModelContext) -> [SavedCard] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let decks = (try? context.fetch(FetchDescriptor<SavedDeck>())) ?? []
        let cards = decks.filter { idSet.contains($0.id) }.flatMap(\.cards)
        return sortedByDueDate(cards)
    }

    /// Due cards across the whole saved library, most-overdue first.
    static func allDueCards(in context: ModelContext) -> [SavedCard] {
        let cards = (try? context.fetch(FetchDescriptor<SavedCard>())) ?? []
        return sortedByDueDate(cards)
    }

    private static func sortedByDueDate(_ cards: [SavedCard]) -> [SavedCard] {
        let now = Date.now
        return cards
            .filter { isDueForReview($0, now: now) }
            .sorted { ($0.nextReviewDate ?? .distantFuture) < ($1.nextReviewDate ?? .distantFuture) }
    }

    /// Describes the next interval for each rating option, given the card's current state.
    static func previewIntervals(for card: SavedCard) -> [(rating: AnkiRating, label: String)] {
        SRSScheduling.previewIntervals(for: card)
    }


}

/// `SavedCard` already carries every scheduling field (see `SRSScheduling`).
extension SavedCard: SRSCardState {}
