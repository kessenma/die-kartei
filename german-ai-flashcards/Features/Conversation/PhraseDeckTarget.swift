//
//  PhraseDeckTarget.swift
//  german-ai-flashcards
//
//  Where "Save phrase" also puts a phrase as a flashcard, so a phrase from a story, a chat or a job
//  ad ends up somewhere it can be studied (with a gap: docs/PHRASES.md), not only in the chat
//  phrase library. The place that opens the save sheet supplies its own deck: the story's, the
//  job posting's, or for a chat the one "Phrasen" deck.
//

import Foundation
import SwiftData

struct PhraseDeckTarget {
    /// "this story's deck", "Phrasen": what the sheet's toggle names.
    let label: String
    /// Adds the checked phrase and its English. Already there is fine: nothing happens.
    let save: (_ german: String, _ english: String) -> Void
}

/// The one deck chats' saved phrases go to. Its id is derived from its generator and topic, so two
/// devices that create it offline create the same deck (`SyncSingletonDecks.deckID`).
enum PhraseDeckStore {
    static let generatorRaw = "phrase"
    static let topic = "Phrasen"

    static var deckID: UUID { SyncSingletonDecks.deckID(generatorRaw: generatorRaw, topic: topic) }

    static func orCreateDeck(context: ModelContext) -> SavedDeck {
        let id = deckID
        var descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let created = SavedDeck(topic: topic, wordCount: 0, includeExamples: false, includeGender: false)
        created.generatorRaw = generatorRaw
        created.id = id
        context.insert(created)
        return created
    }

    static func target(context: ModelContext) -> PhraseDeckTarget {
        PhraseDeckTarget(label: topic) { german, english in
            DeckCardAdder.add(german: german, english: english, to: orCreateDeck(context: context), context: context)
        }
    }
}

/// Adds one card to an existing deck: deduped by `CardKind.matchKey`, at the end of the deck, its
/// kind decided by `CardKind` (a phrase stays whole, a noun keeps its article apart).
enum DeckCardAdder {
    @discardableResult
    static func add(german: String, english: String, example: String? = nil, to deck: SavedDeck,
                    context: ModelContext) -> Bool {
        let key = CardKind.matchKey(german)
        guard !key.isEmpty, !deck.cards.contains(where: { CardKind.matchKey($0.germanWord) == key }) else { return false }
        let split = CardKind.split(german)
        let card = SavedCard(
            germanWord: split.word,
            englishTranslation: english,
            wordType: split.wordType,
            article: split.article,
            exampleSentence: example,
            sortOrder: (deck.cards.map(\.sortOrder).max() ?? -1) + 1
        )
        card.deck = deck
        deck.cards.append(card)
        context.insert(card)
        deck.wordCount = deck.cards.count
        try? context.save()
        return true
    }
}
