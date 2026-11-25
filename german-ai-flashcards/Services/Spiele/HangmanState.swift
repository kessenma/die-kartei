//
//  HangmanState.swift
//  german-ai-flashcards
//
//  The guessing machine: one word, the letters tried, and how many misses are left. Pure, so the
//  whole game can be played through in a test and the 3D canvas is only ever a rendering of this.
//
//  Ä is not A here, as everywhere in the games — guessing A on „Mädchen“ is a miss.
//

import Foundation

nonisolated struct HangmanState: Hashable, Sendable {

    /// Six misses, which is how many parts every motif has.
    static let maxMisses = 6

    let word: GameWord
    /// Every letter tried, hit or miss.
    private(set) var guessed: Set<Character> = []
    /// The misses in the order they were made, which is the order the motif comes apart.
    private(set) var misses: [Character] = []
    /// Whether the learner asked for a hint. Kept because it disqualifies the round from counting
    /// as recall — see `isCleanWin`.
    private(set) var usedHint = false

    init(word: GameWord) { self.word = word }

    var letters: [Character] { word.letters }

    /// What the blanks row shows: the letter once guessed, nil while still hidden.
    var revealed: [Character?] { letters.map { guessed.contains($0) ? $0 : nil } }

    var missCount: Int { misses.count }
    var remaining: Int { max(0, Self.maxMisses - missCount) }

    var isWon: Bool { letters.allSatisfy { guessed.contains($0) } }
    var isLost: Bool { missCount >= Self.maxMisses }
    var isOver: Bool { isWon || isLost }

    /// The letters still worth trying, for the keyboard.
    var untried: [Character] { GameLetters.hangmanKeys.filter { !guessed.contains($0) } }

    /// A win with no misses and no hint — the learner produced the spelling unaided. The only
    /// result in any of the games strong enough to move a card's review schedule.
    var isCleanWin: Bool { isWon && misses.isEmpty && !usedHint }

    /// What a keypress did.
    enum Guess: Hashable, Sendable {
        case hit(count: Int)
        case miss
        /// Already tried, or the round is over — the keyboard should have prevented it.
        case ignored
    }

    @discardableResult
    mutating func guess(_ letter: Character) -> Guess {
        guard !isOver, GameLetters.hangmanKeys.contains(letter), guessed.insert(letter).inserted else {
            return .ignored
        }
        let hits = letters.count { GameLetters.equal($0, letter) }
        guard hits > 0 else {
            misses.append(letter)
            return .miss
        }
        return .hit(count: hits)
    }

    mutating func noteHint() { usedHint = true }

    /// Gives up: reveals the word and ends the round as a loss.
    mutating func reveal() {
        guessed.formUnion(letters)
        while misses.count < Self.maxMisses { misses.append(" ") }
    }
}

/// Hangman's word limits. Any single word with a translation will do — the clue needs the English,
/// and a word under four letters is over before the motif has shown anything.
nonisolated enum HangmanRound: GameRoundShape {
    static var requirements: GameWordRequirements {
        GameWordRequirements(
            lengthRange: 4...14,
            wordCount: 8...20,
            singleTokenOnly: true,
            eszett: .keep,
            needsEnglish: true,
            alphabet: GameLetters.alphabet,
            blurb: "Needs at least 8 single words of 4–14 letters, each with its English."
        )
    }
}
