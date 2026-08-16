//
//  MatchingSession.swift
//  german-ai-flashcards
//
//  The payload for launching the card-matching game — a fast, gamified recognition drill over a
//  deck. Mirrors `StudySession` but carries only what the grid needs: a grid-friendly cap of
//  pairs plus the deck identity for stat/streak persistence (via `DeckStore.saveQuizResult`).
//

import Foundation
import SwiftData
import SwiftUI

/// One entry in the board's color legend (see `MatchingSession.germanTileTints`).
struct MatchingTintLegendItem: Identifiable, Hashable {
    var label: String
    var color: Color
    var id: String { label }
}

struct MatchingSession: Identifiable {
    let id = UUID()

    /// The pairs shown this round (German ↔ English). Capped to a grid-friendly size by the
    /// `DeckStore` builder so the board always fits and stays "snackable".
    var cards: [VocabCard]
    var topic: String
    /// Backing `SavedDeck` id — enables result saving via `DeckStore.saveQuizResult`. `nil` only
    /// for throwaway sessions with no backing deck.
    var deckID: PersistentIdentifier?
    /// `MLXModel.rawValue` (or "goethe"/"" for bundled content) — drives brand theming, exactly
    /// like a `StudySession`.
    var generatorRaw: String = ""
    /// Label stamped onto the saved `QuizResult` (e.g. "Matching · 8 pairs").
    var subDeckLabel: String?

    /// Optional color coding for the **German column only**, keyed by the lowercased German word.
    /// The preposition round uses it to tint each word by the case it governs, so the color link
    /// built in the Kasus drill carries over here.
    ///
    /// German-only on purpose: tinting both columns would let a learner pair tiles by color
    /// without reading them, which is the one thing this game exists to make you do.
    var germanTileTints: [String: Color] = [:]
    /// What those colors mean. Shown as a compact legend above the board when non-empty.
    var tintLegend: [MatchingTintLegendItem] = []

    /// The model that generated this deck, when known — used for the deck's brand tint.
    var generatorModel: MLXModel? { MLXModel(rawValue: generatorRaw) }

    /// Number of pairs in the round.
    var pairCount: Int { cards.count }
}
