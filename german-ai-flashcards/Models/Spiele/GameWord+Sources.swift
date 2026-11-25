//
//  GameWord+Sources.swift
//  german-ai-flashcards
//
//  Every way a word reaches a game. Kept apart from `GameWord` so the pure type — and the whole
//  generator layer — stays free of SwiftData and of the app's other models.
//
//  Note the asymmetry between the two deck paths, which is load-bearing: `SavedCard` carries
//  `imageFileName` and `VocabCard` does not. A deck must therefore be read through its `SavedCard`s
//  if the picture clue is ever to appear, which is why `init(_: SavedCard)` exists at all rather
//  than everything going through `SavedDeck.vocabCards`.
//

import Foundation

extension GameWord {

    /// The full path: the only one that can carry a picture.
    ///
    /// `deckID` is passed in rather than read off `card.deck` so the caller's already-loaded deck
    /// is used instead of faulting the back-reference for every card in the round.
    init?(_ card: SavedCard, deckID: UUID?) {
        self.init(german: card.germanWord,
                  english: card.englishTranslation,
                  article: card.article,
                  forms: card.formsLine,
                  wordType: card.wordType,
                  imageFileName: card.imageFileName,
                  imageDeckID: deckID)
    }

    /// The value-type path, for sources that never had a picture to begin with.
    init?(_ card: VocabCard) {
        self.init(german: card.germanWord,
                  english: card.englishTranslation,
                  article: card.article,
                  forms: card.forms,
                  wordType: card.wordType,
                  imageFileName: nil)
    }

    /// A bundled Goethe headword. Skipped when no list has a translation for it, the same rule
    /// `GoetheVocabService.toVocabCards` applies.
    init?(_ word: GoetheWord) {
        guard let translation = word.translation, !translation.isEmpty else { return nil }
        self.init(german: word.word,
                  english: translation,
                  article: word.article,
                  forms: word.formsLine,
                  wordType: word.rawWordType,
                  imageFileName: nil)
    }

    /// A noun the tutor suggested, already checked against the on-device dictionary by
    /// `MLXGenerationService.generateArticleNouns`.
    init?(_ question: ArticleQuestion) {
        self.init(german: question.noun,
                  english: question.english,
                  article: question.article.rawValue,
                  forms: nil,
                  wordType: "Nomen",
                  imageFileName: nil)
    }
}

extension SavedDeck {
    /// The deck's words for a game, in the deck's own order. Goes through `SavedCard` rather than
    /// `vocabCards` so the picture clue survives.
    var gameWords: [GameWord] {
        let deckID = id
        return cards.sorted { $0.sortOrder < $1.sortOrder }.compactMap { GameWord($0, deckID: deckID) }
    }
}
