//
//  GameLetters.swift
//  german-ai-flashcards
//
//  The alphabet the games play in, and the one place that decides what a letter *is*.
//
//  Ä, Ö, Ü and ß are their own letters here, deliberately: a learner has to know the word really
//  is „Mädchen“ and not „Madchen“, so nothing in the games folds them onto a base letter. That
//  single decision is why this file exists rather than a few calls to `uppercased()`.
//

import Foundation

/// What a game does with ß. The grid games exclude those words rather than respell them — a tray
/// tile reading „Straße“ laid over seven cells as `S T R A S S E` teaches the wrong spelling.
nonisolated enum EszettPolicy: Hashable, Sendable {
    /// ß stays one letter with its own key. Hangman's policy.
    case keep
    /// Words containing ß are not offered at all. Both grid games' policy.
    case exclude
    /// ß becomes SS, lengthening the word. Built and tested, deliberately unused — here for the
    /// day a grid game wants to make the ß/ss contrast the teaching point.
    case expandToSS
}

nonisolated enum GameLetters {

    /// German uppercase without ß, which is handled separately because it has no single-character
    /// uppercase form anyone writes by hand.
    static let alphabet: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ")

    static let eszett: Character = "ß"

    /// The Hangman keyboard, in reading order: 26 + ÄÖÜ + ß = 30 keys.
    static let hangmanKeys: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜß")

    private static let german = Locale(identifier: "de_DE")

    /// The playable spelling of a word: uppercase, one element per letter, **ß preserved**.
    ///
    /// Per character, not per string, because `"Straße".uppercased()` is `"STRASSE"` — it silently
    /// adds a letter, which would make the blanks row and the keyboard disagree about the word.
    static func letters(_ word: String) -> [Character] {
        word.trimmingCharacters(in: .whitespacesAndNewlines).compactMap { character in
            if character == eszett { return eszett }
            let upper = String(character).uppercased(with: german)
            // A character whose uppercase form is several characters (ﬁ, ﬀ) can't be one cell or
            // one key, so it is dropped here and the alphabet check rejects the word downstream.
            return upper.count == 1 ? Character(upper) : nil
        }
    }

    /// One word, not a phrase: a game can only ask for a single token. Rejects spaces, hyphens,
    /// slashes, digits and sentence punctuation, which is what separates „Blume“ from
    /// „sich erinnern an“ and „Hund/Katze“.
    static func isSingleToken(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.contains { $0.isWhitespace || $0.isNumber || "-–—/\\,.;:!?()[]'\"„“".contains($0) }
    }

    /// Letter identity for every game. Ä is never A — stated as a function so the rule has one
    /// home and a test can pin it.
    static func equal(_ a: Character, _ b: Character) -> Bool { a == b }

    /// Applies a ß policy to a spelling. `nil` means "this word is not playable under that
    /// policy", which is how `.exclude` refuses a word.
    static func applying(_ policy: EszettPolicy, to letters: [Character]) -> [Character]? {
        guard letters.contains(eszett) else { return letters }
        switch policy {
        case .keep:       return letters
        case .exclude:    return nil
        case .expandToSS: return letters.flatMap { $0 == eszett ? ["S", "S"] : [$0] }
        }
    }

    /// Whether every letter is one a grid cell or a key can show.
    static func firstUnplayable(in letters: [Character], alphabet: Set<Character>,
                                allowsEszett: Bool) -> Character? {
        letters.first { !alphabet.contains($0) && !(allowsEszett && $0 == eszett) }
    }
}
