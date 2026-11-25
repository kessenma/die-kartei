//
//  HangmanSession.swift
//  german-ai-flashcards
//
//  The payload for launching Galgenmännchen via `Activity.hangman`. Mirrors `MatchingSession`:
//  the words for the round plus the deck identity results are credited against.
//
//  The round's words are chosen at setup and carried here, so the player never has to decide
//  whether it has enough to play — that question is answered on the screen that can do something
//  about it.
//

import Foundation
import SwiftData

struct HangmanSession: Identifiable {
    let id = UUID()

    /// The words for the round, in the order they'll be asked.
    var words: [GameWord]
    /// Source label for the top bar and the saved result („Goethe A1“, a deck topic, a theme).
    var topic: String
    /// Backing `SavedDeck` id, so results can be credited. `nil` for bundled or generated sources.
    var deckID: PersistentIdentifier?
    /// `MLXModel.rawValue`, or "goethe" / "" for bundled content — drives the brand tint, exactly
    /// like a `StudySession`.
    var generatorRaw: String = ""

    var motif: HangmanMotif = .default
    var clueMode: HangmanClue.Mode = .pictureFirst
    /// Whether the hint button is offered at all. Off unless the learner opted in *and* a tutor
    /// is actually on the device.
    var allowsHint: Bool = false
    /// Fixed per round so a resumed or screenshotted round is the same round.
    var seed: UInt64 = UInt64.random(in: 0..<UInt64.max)

    /// Set when the source was topped up, so the summary can be honest about it.
    var toppedUp: GameTopUp?

    var wordCount: Int { words.count }

    /// One line for the summary when words were borrowed, else nil.
    var topUpNote: String? {
        guard let toppedUp else { return nil }
        return "\(topic) · \(toppedUp.englishLabel)"
    }

    var generatorModel: MLXModel? { MLXModel(rawValue: generatorRaw) }
}
