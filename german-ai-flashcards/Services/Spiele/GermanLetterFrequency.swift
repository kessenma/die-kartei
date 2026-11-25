//
//  GermanLetterFrequency.swift
//  german-ai-flashcards
//
//  How often each letter turns up in written German, used to fill the empty cells of a word-search
//  grid. Uniform random letters read as noise and make the hidden words stand out; weighted
//  filler makes the grid look like German, which is the whole difficulty of the game.
//
//  Percentages are the standard frequencies for German text, ß excluded (the grid games never
//  place a ß word, so they never need a ß filler).
//

import Foundation

nonisolated enum GermanLetterFrequency {

    /// Letter → relative weight. Q, X and Y are present but rare, so a grid can still contain one.
    static let weights: [(letter: Character, weight: Double)] = [
        ("E", 17.40), ("N", 9.78), ("I", 7.55), ("S", 7.27), ("R", 7.00), ("A", 6.51),
        ("T", 6.15), ("D", 5.08), ("H", 4.76), ("U", 4.35), ("L", 3.44), ("C", 3.06),
        ("G", 3.01), ("M", 2.53), ("O", 2.51), ("B", 1.89), ("W", 1.92), ("F", 1.66),
        ("K", 1.21), ("Z", 1.13), ("P", 0.79), ("V", 0.67), ("Ü", 0.65), ("Ä", 0.58),
        ("J", 0.27), ("Ö", 0.24), ("Y", 0.04), ("X", 0.03), ("Q", 0.02),
    ]

    private static let total = weights.reduce(0) { $0 + $1.weight }

    /// A weighted letter. Takes the generator `inout` so a seed reproduces a whole grid.
    static func letter<G: RandomNumberGenerator>(using generator: inout G) -> Character {
        var roll = Double.random(in: 0..<total, using: &generator)
        for entry in weights {
            roll -= entry.weight
            if roll < 0 { return entry.letter }
        }
        return "E"
    }

    /// The rarest letters, used when the filler has to be rewritten to hide an umlaut without
    /// disturbing the grid's overall texture.
    static func rarest(_ count: Int) -> [Character] {
        weights.sorted { $0.weight < $1.weight }.prefix(count).map(\.letter)
    }
}
