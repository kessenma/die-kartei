//
//  SpielKind.swift
//  german-ai-flashcards
//
//  The three games in the Spiele room. The raw values are stored on every round and every
//  per-word stat, so they are never renamed — the German titles can change freely, these can't.
//

import Foundation

nonisolated enum SpielKind: String, CaseIterable, Identifiable, Sendable {
    case hangman
    case wordSearch
    case fillIn

    var id: String { rawValue }

    /// The German identity word, which is what the learner sees as the heading.
    var germanTitle: String {
        switch self {
        case .hangman:    "Galgenmännchen"
        case .wordSearch: "Wortsuche"
        case .fillIn:     "Einsetz-Kreuzworträtsel"
        }
    }

    var englishTitle: String {
        switch self {
        case .hangman:    "Hangman"
        case .wordSearch: "Word search"
        case .fillIn:     "Fill-in crossword"
        }
    }

    /// One line on the launcher row: what the learner does.
    var blurb: String {
        switch self {
        case .hangman:    "Guess the word letter by letter"
        case .wordSearch: "Find the hidden words in the grid"
        case .fillIn:     "Fit the words into the grid"
        }
    }

    var symbol: String {
        switch self {
        case .hangman:    "figure.stand"
        case .wordSearch: "square.grid.3x3.square"
        case .fillIn:     "square.grid.3x3.topleft.filled"
        }
    }

    /// How long a round takes, for the launcher row.
    var minutes: Int {
        switch self {
        case .hangman:    3
        case .wordSearch: 5
        case .fillIn:     6
        }
    }

    var requirements: GameWordRequirements {
        switch self {
        case .hangman:    HangmanRound.requirements
        case .wordSearch: WordSearchRound.requirements
        case .fillIn:     FillInRound.requirements
        }
    }

    /// Whether this game can actually build a round from these words. For the grid games this
    /// attempts a real build, so it is not cheap — call it when composing a round, not in a body.
    func canBuild(_ words: [GameWord], seed: UInt64) -> Bool {
        switch self {
        case .hangman:    HangmanRound.canBuild(words, seed: seed)
        case .wordSearch: WordSearchRound.canBuild(words, seed: seed)
        case .fillIn:     FillInRound.canBuild(words, seed: seed)
        }
    }
}
