//
//  PhraseRepair.swift
//  german-ai-flashcards
//
//  Cards saved before the phrase rule (`CardKind`) can hold a phrase that was taken for a noun:
//  "der Meinung sein" stored as "Meinung sein" + der, quizzed on its article and given a gender
//  by the dictionary check. Run when a deck opens, before that check, it puts the article back in
//  front and tags the card a phrase. Idempotent; a changed card syncs like any other edit.
//

import Foundation
import SwiftData

enum PhraseRepair {
    /// Retags this deck's phrase cards. Returns how many changed; the caller saves.
    /// Decks whose card ids derive from the German (Goethe, past tense — `SyncSingletonDecks`)
    /// are left alone; their lists hold no phrases anyway.
    @discardableResult
    static func apply(to deck: SavedDeck) -> Int {
        guard !SyncSingletonDecks.isSingleton(deck) else { return 0 }
        var changed = 0
        for card in deck.cards {
            guard let german = repaired(
                germanWord: card.germanWord,
                article: card.article,
                wordType: card.wordType,
                hasConjugations: card.conjugationsData != nil
            ) else { continue }
            card.germanWord = german
            card.article = nil
            card.wordType = CardKind.phrase
            changed += 1
        }
        return changed
    }

    /// The German a card should hold once it is tagged a phrase, or nil when it needs nothing.
    /// A verb that came with its conjugation table is left as it is: it was generated as a verb.
    nonisolated static func repaired(germanWord: String, article: String?, wordType: String?,
                                     hasConjugations: Bool) -> String? {
        guard wordType != CardKind.phrase else { return nil }
        if wordType?.lowercased() == "verb", hasConjugations { return nil }
        let whole = CardKind.joined(germanWord, article: article)
        guard CardKind.isPhrase(whole) else { return nil }
        return whole
    }
}

extension CardKind {
    /// Whether a card holds a phrase (`isPhrase(germanWord:article:wordType:)`). Here rather than in
    /// CardKind.swift, which compiles on its own for the probes and so knows no app types.
    @MainActor static func isPhrase(_ card: VocabCard) -> Bool {
        isPhrase(germanWord: card.germanWord, article: card.article, wordType: card.wordType)
    }
}
