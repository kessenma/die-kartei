//
//  GameWordRequirements.swift
//  german-ai-flashcards
//
//  What a game needs from a word list, split deliberately in two.
//
//  The cheap, shared, explainable limits are fields — they are what the setup screen turns into
//  „8–12 Wörter, 3–10 Buchstaben · dieses Deck hat 6“ without building anything. The expensive
//  game-only question — do these words actually interlock? — is not a field at all; it is one
//  function the generator answers by attempting a build. That split is what keeps this type from
//  growing into a description of all three games at once.
//

import Foundation

nonisolated struct GameWordRequirements: Hashable, Sendable {
    /// Playable word lengths, in letters.
    var lengthRange: ClosedRange<Int> = 3...12
    /// How many words one round needs: the lower bound gates the source, the upper bound is what a
    /// full round uses.
    var wordCount: ClosedRange<Int> = 1...1
    var singleTokenOnly = true
    var eszett: EszettPolicy = .keep
    /// Hangman needs a clue, so it needs the English. A grid game can hide a word without one.
    var needsEnglish = true
    var alphabet: Set<Character> = GameLetters.alphabet
    /// One sentence, learner-facing, printed under a source that doesn't have enough.
    var blurb: String

    var allowsEszett: Bool { eszett == .keep || eszett == .expandToSS }
}

/// A game's shape: its limits, plus the only question the limits can't answer.
nonisolated protocol GameRoundShape {
    static var requirements: GameWordRequirements { get }

    /// Can a round actually be built from these words? The grid games answer by *attempting* a
    /// build under a probe seed, which is the only honest answer — interlocking is not a property
    /// of any one word. Defaults to `true` for games where having enough words is the whole story.
    static func canBuild(_ words: [GameWord], seed: UInt64) -> Bool
}

nonisolated extension GameRoundShape {
    static func canBuild(_ words: [GameWord], seed: UInt64) -> Bool { true }
}
