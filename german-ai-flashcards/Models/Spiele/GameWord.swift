//
//  GameWord.swift
//  german-ai-flashcards
//
//  One word a game plays with, whatever it came from — a deck card, a Goethe headword, a noun the
//  tutor suggested. The games never see `SavedCard` or `GoetheWord`, so a new source is one
//  initializer here and nothing else.
//
//  `letters` is stored, not computed, because every game asks for it on every keystroke and every
//  grid cell. It is uppercased with the German locale and **ß survives as its own letter** —
//  Swift's `uppercased()` turns „Straße“ into „STRASSE“, which would quietly respell the word the
//  learner is being taught.
//

import Foundation

nonisolated struct GameWord: Hashable, Identifiable, Sendable {
    /// The word as the learner should spell it, without its article.
    let german: String
    let english: String
    /// „der“ / „die“ / „das“ when the source knows it — used for the gender tint, never guessed.
    let article: String?
    /// The plural or verb-forms caption, when the source carries one. A late clue fallback.
    let forms: String?
    let wordType: String?
    /// A file in `CardImageStore`'s directory. **May name a file that is gone** after a sync or a
    /// restore, so every reader checks before trusting it — see `HangmanClue`.
    let imageFileName: String?
    /// The `SavedDeck.id` the picture is filed under. Required: `CardImageStore` keys its
    /// directories by deck, so a file name on its own cannot be loaded.
    let imageDeckID: UUID?
    /// The playable spelling: uppercase, umlauts and ß intact.
    let letters: [Character]

    init?(german: String, english: String, article: String? = nil, forms: String? = nil,
          wordType: String? = nil, imageFileName: String? = nil, imageDeckID: UUID? = nil) {
        let word = german.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        self.german = word
        self.english = meaning
        self.article = article?.isEmpty == false ? article : nil
        self.forms = forms?.isEmpty == false ? forms : nil
        self.wordType = wordType?.isEmpty == false ? wordType : nil
        // A file name without a deck can't be loaded, so it isn't kept — that keeps
        // `HangmanClue` from offering a picture clue it could never show.
        let hasPicture = imageFileName?.isEmpty == false && imageDeckID != nil
        self.imageFileName = hasPicture ? imageFileName : nil
        self.imageDeckID = hasPicture ? imageDeckID : nil
        self.letters = GameLetters.letters(word)
    }

    /// Case- and source-insensitive, so the same word from a deck and from the Goethe list is one
    /// word to a round and to the per-word stats.
    var id: String { german.lowercased() }

    var length: Int { letters.count }

    /// „die Blume“ for a display line; the bare word is what the learner has to spell.
    var display: String { german.withArticle(article) }
}
