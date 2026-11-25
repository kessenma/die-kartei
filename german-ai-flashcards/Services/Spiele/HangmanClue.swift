//
//  HangmanClue.swift
//  german-ai-flashcards
//
//  What tells the learner which word they are guessing, resolved here rather than in the view.
//
//  It lives in the pure layer for one reason: `imageFileName` routinely points at a file that is
//  **gone** — after an iCloud restore, after a deck arrives by AirDrop, after the picture cache is
//  cleared. A view that trusted the field would show an empty frame and no clue at all, so the
//  fallback chain is resolved up front against a real existence check, and tested.
//

import Foundation

nonisolated enum HangmanClue {

    /// What the learner is shown, best available first.
    enum Resolved: Hashable, Sendable {
        case picture(fileName: String, deckID: UUID)
        case english(String)
        /// „Plural: -en“ — thin, but it narrows the word and keeps the English hidden.
        case forms(String)
        /// „Nomen“ — last resort before showing nothing.
        case wordType(String)
        /// Only when the word has no translation, no forms and no type.
        case none
    }

    /// The learner's choice at setup.
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// A picture when the card has one, the English otherwise.
        case pictureFirst
        /// Always the English, even when a picture exists.
        case englishOnly

        var id: String { rawValue }

        var germanTitle: String {
            switch self {
            case .pictureFirst: "Bild, sonst Englisch"
            case .englishOnly:  "Immer Englisch"
            }
        }

        var englishTitle: String {
            switch self {
            case .pictureFirst: "Picture, else English"
            case .englishOnly:  "Always English"
            }
        }
    }

    /// Picture → English → forms → word type → nothing.
    ///
    /// `imageExists` is injected so this is testable and so the caller decides how expensive the
    /// check is; in the app it is `CardImageStore`'s file check.
    static func resolve(for word: GameWord, mode: Mode,
                        imageExists: (String) -> Bool) -> Resolved {
        if mode == .pictureFirst, let file = word.imageFileName, let deck = word.imageDeckID,
           imageExists(file) {
            return .picture(fileName: file, deckID: deck)
        }
        if !word.english.isEmpty { return .english(word.english) }
        if let forms = word.forms, !forms.isEmpty { return .forms(forms) }
        if let type = word.wordType, !type.isEmpty { return .wordType(type) }
        return .none
    }
}
