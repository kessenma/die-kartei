//
//  DeckTransferRecords.swift
//  german-ai-flashcards
//
//  A `.kartei` file to and from records (`DeckRecord`, `CardRecord`): Android's import and export.
//  Foundation only and shared (DieKarteiCore). iOS reads and writes the same file through
//  SwiftData (DeckImporter, DeckTransfer); `DeckTransferParityTests` checks that the records made
//  here sync exactly like the rows iOS makes from the same file, and that both write the same file.
//

import Foundation

nonisolated enum DeckTransferRecords {
    /// How an arriving deck that's already here is taken in (iOS `DeckImporter.Mode`).
    enum Mode: Equatable {
        /// Take the file's ids: the deck already here is replaced, and the next send of it from
        /// the other device is still recognised.
        case replace
        /// Fresh ids throughout, so both copies survive side by side.
        case keepBoth
    }

    /// The deck and cards a file becomes (iOS `DeckImporter.insert`). Links to things on the
    /// sending device (its course) are dropped; results never travel.
    static func records(from envelope: DeckTransferEnvelope, mode: Mode) -> (deck: DeckRecord, cards: [CardRecord]) {
        let source = envelope.deck
        let keepIDs = mode == .replace
        let deckID = keepIDs ? (UUID(uuidString: source.id) ?? UUID()) : UUID()
        var deck = DeckRecord(id: deckID, topic: source.topic, generatorRaw: source.generator, createdAt: source.createdAt)
        deck.wordCount = source.wordCount
        deck.includeExamples = source.includeExamples
        deck.includeGender = source.includeGender
        // An unknown filter reads as "All", as iOS's `WordTypeFilter(rawValue:) ?? .all`.
        deck.wordTypeFilterRaw = (WordTypeFilter(rawValue: source.wordTypeFilter) ?? .all).rawValue
        deck.includeConjugations = source.includeConjugations
        deck.selectedTenses = source.selectedTenses
        deck.generationTimeSeconds = source.generationTimeSeconds
        deck.courseIDRaw = nil

        let cards = source.cards
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { card($0, deck: deckID, keepID: keepIDs) }
        return (deck, cards)
    }

    private static func card(_ source: DeckTransferEnvelope.Card, deck: UUID, keepID: Bool) -> CardRecord {
        let id = keepID ? (UUID(uuidString: source.id) ?? UUID()) : UUID()
        var card = CardRecord(id: id, deck: deck, germanWord: source.germanWord,
                              englishTranslation: source.englishTranslation, sortOrder: source.sortOrder)
        card.wordType = source.wordType
        card.article = source.article
        card.exampleSentence = source.exampleSentence
        // iOS stores the list as a default `JSONEncoder`'s bytes, and only when it has entries.
        if let conjugations = source.conjugations, !conjugations.isEmpty,
           let data = try? JSONEncoder().encode(conjugations) {
            card.conjugations = try? SyncJSON(data: data)
        }
        if let p = source.progress {
            card.easeFactor = p.easeFactor
            card.interval = p.interval
            card.repetitions = p.repetitions
            card.nextReviewDate = p.nextReviewDate
            card.totalReviews = p.totalReviews
            card.lapses = p.lapses
            card.leitnerBox = p.leitnerBox
            card.lastReviewedAt = p.lastReviewedAt
            card.lastReviewWasCorrect = p.lastReviewWasCorrect
            card.firstReviewedAt = p.firstReviewedAt
        }
        return card
    }

    /// The file for a deck (iOS `DeckTransfer.envelope(for:)`), or nil for one that can't travel.
    static func envelope(deck: DeckRecord, cards: [CardRecord], app: DeckTransferEnvelope.App,
                         exportedAt: Date = Date()) -> DeckTransferEnvelope? {
        guard DeckTransferFormat.canExport(generatorRaw: deck.generatorRaw) else { return nil }
        return DeckTransferEnvelope(
            exportedAt: exportedAt,
            app: app,
            deck: .init(
                id: deck.id.uuidString,
                topic: deck.topic,
                wordCount: deck.wordCount,
                includeExamples: deck.includeExamples,
                includeGender: deck.includeGender,
                wordTypeFilter: deck.wordTypeFilterRaw,
                includeConjugations: deck.includeConjugations,
                selectedTenses: deck.selectedTenses,
                createdAt: deck.createdAt,
                generationTimeSeconds: deck.generationTimeSeconds,
                generator: deck.generatorRaw,
                cards: cards.sorted { $0.sortOrder < $1.sortOrder }.map(transferCard)
            )
        )
    }

    private static func transferCard(_ card: CardRecord) -> DeckTransferEnvelope.Card {
        DeckTransferEnvelope.Card(
            id: card.id.uuidString,
            germanWord: card.germanWord,
            englishTranslation: card.englishTranslation,
            wordType: card.wordType,
            article: card.article,
            exampleSentence: card.exampleSentence,
            conjugations: card.conjugations.flatMap { try? $0.decoded(as: [StoredConjugation].self) },
            sortOrder: card.sortOrder,
            progress: DeckTransferEnvelope.Progress(
                easeFactor: card.easeFactor,
                interval: card.interval,
                repetitions: card.repetitions,
                nextReviewDate: card.nextReviewDate,
                totalReviews: card.totalReviews,
                lapses: card.lapses,
                leitnerBox: card.leitnerBox,
                lastReviewedAt: card.lastReviewedAt,
                lastReviewWasCorrect: card.lastReviewWasCorrect,
                firstReviewedAt: card.firstReviewedAt
            ).ifStudied
        )
    }
}
