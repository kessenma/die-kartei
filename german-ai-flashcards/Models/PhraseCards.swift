//
//  PhraseCards.swift
//  german-ai-flashcards
//
//  Saved phrases as flashcards: one card per phrase (the whole phrase on the German side), into a
//  new "Sätze" deck or merged into one the learner has, skipping phrases already in it. Foundation
//  only and shared with the Android app (DieKarteiCore): iOS's `PhraseToDeckSheet` and Android's
//  `PhraseDeckSheet` make the same cards.
//

import Foundation

nonisolated enum PhraseCards {
    static let newDeckName = "Sätze"
    static let generator = "phrase"

    struct Card: Equatable {
        var german: String
        var english: String
        var wordType: String?
        var sortOrder: Int
    }

    struct Phrase: Equatable {
        var german: String
        var english: String
    }

    /// A new deck's cards: every phrase, in order.
    static func newDeck(_ phrases: [Phrase]) -> [Card] {
        phrases.enumerated().map { card($0.element, order: $0.offset) }
    }

    /// Merging into a deck: the phrases not already in it (by `CardKind.matchKey`), numbered after
    /// its last card.
    static func merge(_ phrases: [Phrase], intoDeckWith words: [String], lastOrder: Int?) -> [Card] {
        let existing = Set(words.map(CardKind.matchKey))
        var order = (lastOrder ?? -1) + 1
        var cards: [Card] = []
        for phrase in phrases where !existing.contains(CardKind.matchKey(phrase.german)) {
            cards.append(card(phrase, order: order))
            order += 1
        }
        return cards
    }

    static func deckName(_ typed: String) -> String {
        let name = typed.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? newDeckName : name
    }

    static func addedSummary(_ added: Int, deck: String) -> String {
        added == 0
            ? "Those phrases are already in “\(deck)”."
            : "Added \(added) phrase\(added == 1 ? "" : "s") to “\(deck)”."
    }

    static func createdSummary(_ count: Int, deck: String) -> String {
        "Created “\(deck)” with \(count) card\(count == 1 ? "" : "s")."
    }

    private static func card(_ phrase: Phrase, order: Int) -> Card {
        Card(german: phrase.german, english: phrase.english,
             wordType: CardKind.isPhrase(phrase.german) ? CardKind.phrase : nil, sortOrder: order)
    }

    /// Android: the records a new phrase deck is (iOS `SavedDeck(… vocabCards:)`, generator "phrase").
    static func newDeckRecords(_ phrases: [Phrase], name: String, createdAt: Date = Date(),
                               id: UUID = UUID()) -> (deck: DeckRecord, cards: [CardRecord]) {
        let cards = newDeck(phrases)
        var deck = DeckRecord(id: id, topic: deckName(name), generatorRaw: generator, createdAt: createdAt)
        deck.wordCount = cards.count
        deck.includeExamples = false
        deck.includeGender = false
        return (deck, cards.map { record($0, deck: id) })
    }

    static func record(_ card: Card, deck: UUID, id: UUID = UUID()) -> CardRecord {
        var record = CardRecord(id: id, deck: deck, germanWord: card.german, englishTranslation: card.english,
                                sortOrder: card.sortOrder)
        record.wordType = card.wordType
        return record
    }
}
