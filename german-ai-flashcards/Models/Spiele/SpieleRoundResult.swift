//
//  SpieleRoundResult.swift
//  german-ai-flashcards
//
//  What a finished game hands to persistence. One shape for all three Spiele, so there is one
//  scoring service rather than three.
//
//  `clean` is the field that matters and the one worth being careful with: it means the learner
//  produced the word unaided — no miss, no hint, answer hidden. It is the only evidence in the
//  room strong enough to move a card's review schedule, and only Galgenmännchen can ever set it
//  (a word you *found* in a grid was visible on screen the whole time).
//

import Foundation
import SwiftData

struct SpieleWordOutcome: Identifiable {
    var word: GameWord
    var solved: Bool
    /// Solved with no miss and no hint.
    var clean: Bool
    var misses: Int

    var id: String { word.id }
}

struct SpieleRoundResult {
    var kind: SpielKind
    /// Source label, stamped on the saved round.
    var topic: String
    var deckID: PersistentIdentifier?
    var outcomes: [SpieleWordOutcome]
    var durationSeconds: Int
    /// Set when the source was topped up, so the summary can say so.
    var toppedUp: GameTopUp?

    var attempted: Int { outcomes.count }
    var solved: Int { outcomes.count { $0.solved } }
    var cleanWins: [GameWord] { outcomes.filter(\.clean).map(\.word) }
    var missedWords: [GameWord] { outcomes.filter { !$0.solved }.map(\.word) }

    var accuracy: Double {
        guard attempted > 0 else { return 0 }
        return Double(solved) / Double(attempted)
    }
}
