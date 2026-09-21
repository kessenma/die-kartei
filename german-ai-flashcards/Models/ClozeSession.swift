//
//  ClozeSession.swift
//  german-ai-flashcards
//
//  The payload for a "fix your sentences" cloze round — personalized fill-in-the-blank cards
//  built from the slip-ups the coach has recorded (see `LexicalSlip`). Each card is the learner's
//  own corrected sentence with the fixed word blanked out, so retrieval practice happens on
//  exactly the gap that tripped them up (FUTURE #3).
//
//  Ephemeral and built from the profile at launch — no schema change — mirroring `MatchingSession`.
//  Presented immersively via `ActivityRouter` (`.cloze`), exactly like `.matching` / `.cardDeck`.
//

import Foundation

/// One personalized fill-in-the-blank card, built from a `LexicalSlip`.
struct ClozeCard: Identifiable {
    let id = UUID()
    /// The originating slip's id — so a correct answer can retire that slip.
    let slipID: String
    /// The corrected sentence with the target word replaced by a blank.
    let prompt: String
    /// The correct word that fills the blank (the answer).
    let answer: String
    /// What the learner originally wrote there — shown after the reveal.
    let wrong: String

    /// The learner's own sentence with the answer restored — used for read-aloud after the reveal.
    var fullSentence: String { prompt.replacingOccurrences(of: ClozeCard.blank, with: answer) }

    /// The blank marker rendered in the prompt.
    static let blank = "＿＿＿"

    /// Builds a card from a slip, or nil when the slip has no usable sentence / blank position.
    static func make(from slip: LexicalSlip) -> ClozeCard? {
        guard let sentence = slip.sentence, let blankIndex = slip.blankIndex else { return nil }
        var tokens = sentence.split(separator: " ").map(String.init)
        guard tokens.indices.contains(blankIndex) else { return nil }

        // Blank only the word itself, preserving any surrounding punctuation ("dem." -> "＿＿＿.").
        let raw = tokens[blankIndex]
        guard let first = raw.firstIndex(where: { $0.isLetter }),
              let last = raw.lastIndex(where: { $0.isLetter }) else { return nil }
        let leading = String(raw[raw.startIndex..<first])
        let trailing = String(raw[raw.index(after: last)..<raw.endIndex])
        tokens[blankIndex] = leading + blank + trailing

        return ClozeCard(
            slipID: slip.id,
            prompt: tokens.joined(separator: " "),
            answer: slip.right,
            wrong: slip.wrong
        )
    }
}

/// A short round of the learner's own sentences to fix.
struct ClozeSession: Identifiable {
    let id = UUID()
    var cards: [ClozeCard]
    var topic: String = "Fix your sentences"

    var cardCount: Int { cards.count }

    /// Build a round from cloze-ready slips, most-repeated first, capped so it stays "snackable".
    static func build(from slips: [LexicalSlip], limit: Int = 12) -> ClozeSession {
        let cards = slips
            .filter(\.isClozeReady)
            .sorted { $0.timesSeen > $1.timesSeen }
            .compactMap { ClozeCard.make(from: $0) }
            .prefix(limit)
        return ClozeSession(cards: Array(cards))
    }
}
