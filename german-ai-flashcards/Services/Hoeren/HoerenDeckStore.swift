//
//  HoerenDeckStore.swift
//  german-ai-flashcards
//
//  The "Hören" deck: words a learner missed in a Diktat and chose to keep. One deck, with the
//  canonical id every device derives the same way (the `PhraseDeckStore` pattern), so two devices
//  saving offline end up with one deck after sync.
//

import Foundation
import SwiftData

@MainActor
enum HoerenDeckStore {
    static let generatorRaw = "hoeren"
    static let topic = "Hören"

    static var deckID: UUID { SyncSingletonDecks.deckID(generatorRaw: generatorRaw, topic: topic) }

    static func orCreateDeck(context: ModelContext) -> SavedDeck {
        let id = deckID
        var descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let created = SavedDeck(topic: topic, wordCount: 0, includeExamples: true, includeGender: true)
        created.generatorRaw = generatorRaw
        created.id = id
        context.insert(created)
        return created
    }

    /// Saves a word with the sentence it was heard in. False when the deck already has it.
    @discardableResult
    static func save(german: String, english: String, sentence: String, context: ModelContext) -> Bool {
        DeckCardAdder.add(german: german, english: english, example: sentence,
                          to: orCreateDeck(context: context), context: context)
    }

    static func contains(_ german: String, context: ModelContext) -> Bool {
        let id = deckID
        var descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let deck = (try? context.fetch(descriptor))?.first else { return false }
        let key = CardKind.matchKey(german)
        return deck.cards.contains { CardKind.matchKey($0.germanWord) == key }
    }
}
