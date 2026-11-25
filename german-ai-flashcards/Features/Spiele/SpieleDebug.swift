//
//  SpieleDebug.swift
//  german-ai-flashcards
//
//  Launch arguments for the Spiele room. The simulator can neither drag nor run a tutor, so every
//  screen in here needs a way in that isn't a gesture.
//
//  `-spiele.debugOpen hangman|hangmanPlay|hangmanWin|hangmanLose`
//

import Foundation

enum SpieleDebugOpen: String, Identifiable, CaseIterable {
    /// The setup screen, with its source rows.
    case hangman
    /// Straight into a round on bundled Goethe words.
    case hangmanPlay
    /// A round seeded to be one correct letter from a win.
    case hangmanWin
    /// A round seeded to be one miss from a loss.
    case hangmanLose

    var id: String { rawValue }

    init?(argument: String) {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        // Accept the lowercased spelling too, so the argument is forgiving to type.
        guard let match = Self.allCases.first(where: {
            $0.rawValue.lowercased() == trimmed.lowercased()
        }) else { return nil }
        self = match
    }

    var startsRound: Bool { self != .hangman }

    /// Letters pressed before the round is shown, to park it in an interesting state.
    var openingGuesses: [Character] {
        switch self {
        case .hangmanLose: ["X", "Y", "Q", "J", "V"]   // five misses: one from the end
        default:           []
        }
    }
}

/// A fixed word list for the debug rounds, so a screenshot is the same every time.
enum SpieleDebugWords {
    static let words: [GameWord] = [
        "Blume", "Tisch", "Fenster", "Mädchen", "Straße", "Brot", "Wasser", "Stuhl",
    ].compactMap { GameWord(german: $0, english: english[$0] ?? "word") }

    private static let english: [String: String] = [
        "Blume": "flower", "Tisch": "table", "Fenster": "window", "Mädchen": "girl",
        "Straße": "street", "Brot": "bread", "Wasser": "water", "Stuhl": "chair",
    ]

    static func session(_ open: SpieleDebugOpen, motif: HangmanMotif = .turm) -> HangmanSession {
        HangmanSession(words: words, topic: "Debug · \(open.rawValue)", deckID: nil,
                       generatorRaw: "", motif: motif, clueMode: .englishOnly,
                       allowsHint: false, seed: 42)
    }
}
