import SwiftUI
import SwiftData

extension CardDeckView {

    // MARK: - Deck mix

    /// Splits a finished deck-mix session by deck and saves each deck's share, so every deck's
    /// stats and Leitner count move as if it had been studied alone. Does nothing outside a mix.
    /// Counts the way `quizSummaryTally` does: SRS modes the distinct cards set out for review
    /// and their lapses, plain mode the whole deal and its right/wrong marks.
    func creditDeckMix(mode: FlashcardStyle) {
        guard isDeckMix else { return }
        let studied = isSRSMode ? Set(ankiDueIndices) : Set(cards.indices)
        let missed = isSRSMode ? sessionLapses : Set(cardResults.filter { !$0.value }.keys)

        var decks: [UUID: SavedDeck] = [:]
        var indicesByDeck: [UUID: [Int]] = [:]
        for index in studied.sorted() where savedCards.indices.contains(index) {
            guard let deck = savedCards[index].deck else { continue }
            decks[deck.id] = deck
            indicesByDeck[deck.id, default: []].append(index)
        }

        let shares = indicesByDeck.compactMap { id, indices -> DeckMixShare? in
            guard let deck = decks[id] else { return nil }
            // A single-deck result names missed cards by their place in the deck.
            let positions = Dictionary(
                deck.cards.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { ($1.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let missedHere = indices.filter(missed.contains)
            let correct = isSRSMode
                ? indices.count - missedHere.count
                : indices.filter { cardResults[$0] == true }.count
            return DeckMixShare(
                deck: deck,
                correct: max(0, correct),
                total: indices.count,
                missedIndices: missedHere.compactMap { positions[savedCards[$0].id] }.sorted()
            )
        }
        DeckStore(modelContext: modelContext).saveDeckMixResults(shares, durationSeconds: elapsedSeconds, mode: mode)
    }
}
