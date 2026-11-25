//
//  JournalDeckStore.swift
//  german-ai-flashcards
//
//  The flashcard deck of words looked up while writing. One deck for the whole room, not one per
//  entry: a page's three lookups would never be worth a review session. The writing twin of
//  `ClassDeckStore` and `JobDeckStore`, with a fixed id (like the learner profile's record), so
//  both devices' first lookup lands in the same deck.
//
//  Saving a word here does not tell the coach: the journal reaches the coach only through the
//  learner's "Share with the coach" on the entry (`JournalCoachExport`).
//

import Foundation
import SwiftData

@MainActor
enum JournalDeckStore {
    static let generatorRaw = "journal"
    static let topic = "Schreiben · Nachgeschlagen"
    static let deckID = SyncNameUUID.make("journal-deck")

    static func deck(context: ModelContext) -> SavedDeck? {
        let id = deckID
        var d = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// The room's deck, created now if there is none yet.
    static func orCreateDeck(context: ModelContext) -> SavedDeck {
        if let existing = deck(context: context) { return existing }
        let created = SavedDeck(topic: topic, wordCount: 0, includeExamples: false, includeGender: true)
        created.generatorRaw = generatorRaw
        created.id = deckID
        context.insert(created)
        return created
    }

    static func isWordSaved(_ german: String, context: ModelContext) -> Bool {
        guard let deck = deck(context: context) else { return false }
        let key = CardKind.matchKey(german)
        return deck.cards.contains { CardKind.matchKey($0.germanWord) == key }
    }

    /// Save a looked-up word into the room's deck. Returns false when it was already there.
    @discardableResult
    static func saveWord(german: String, english: String, article: GermanArticle?, context: ModelContext) -> Bool {
        guard !isWordSaved(german, context: context) else { return false }
        let target = orCreateDeck(context: context)
        let split = CardKind.split(german)
        let word = split.word
        // A phrase keeps no article, even when the lookup offered one.
        let articleText = split.isPhrase ? nil : (article?.rawValue ?? split.article)
        target.cards.append(SavedCard(
            germanWord: word,
            englishTranslation: english,
            wordType: split.isPhrase ? CardKind.phrase : (articleText != nil ? "noun" : nil),
            article: articleText,
            exampleSentence: nil,
            conjugations: nil,
            sortOrder: target.cards.count
        ))
        target.wordCount = target.cards.count
        try? context.save()
        return true
    }
}
