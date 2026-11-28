//
//  DeckTransferParityTests.swift
//  german-ai-flashcardsTests
//
//  A `.kartei` deck means the same thing to both apps: the rows iOS makes from a file
//  (`DeckImporter.insert`) sync exactly like the records Android makes from it
//  (`DeckTransferRecords.records`), and the file each app writes for that deck is the same. Plus
//  a card session's result: iOS's `QuizResult` and Android's `QuizResultRecord.cardSession` sync
//  as the same payload.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct DeckTransferParityTests {
    static let day = Date(timeIntervalSinceReferenceDate: 815_000_000) // whole seconds, as in a file

    /// A file with what can vary: progress on some cards, conjugations, cards out of order, a
    /// filter iOS doesn't know.
    static func envelope(filter: String = "Nouns") -> DeckTransferEnvelope {
        let conj = [StoredConjugation(from: Conjugation(tense: "Präsens", ich: "gehe", du: "gehst", erSieEs: "geht",
                                                         wir: "gehen", ihr: "geht", sieSie: "gehen"))]
        let studied = DeckTransferEnvelope.Progress(
            easeFactor: 2.36, interval: 6, repetitions: 2, nextReviewDate: day.addingTimeInterval(6 * 86_400),
            totalReviews: 3, lapses: 1, leitnerBox: 2, lastReviewedAt: day, lastReviewWasCorrect: true,
            firstReviewedAt: day.addingTimeInterval(-86_400))
        return DeckTransferEnvelope(
            exportedAt: day,
            app: .init(name: "Die Kartei", version: "1.0", build: "1"),
            deck: .init(
                id: "8F14E45F-CEEA-467A-9575-2B5F8C3A5E11", topic: "Im Café", wordCount: 3,
                includeExamples: true, includeGender: true, wordTypeFilter: filter, includeConjugations: true,
                selectedTenses: ["Präsens"], createdAt: day.addingTimeInterval(-7 * 86_400),
                generationTimeSeconds: 12.5, generator: "gemma-4-e4b",
                cards: [
                    .init(id: "1B9D6BCD-BBFD-4B2D-9B5D-AB8DFBBD4BED", germanWord: "gehen", englishTranslation: "to go",
                          wordType: "verb", article: nil, exampleSentence: "Wir gehen ins Café.", conjugations: conj,
                          sortOrder: 2, progress: studied),
                    .init(id: "6EC0BD7F-11C0-43DA-975E-2A8AD9EBAE0B", germanWord: "Kaffee", englishTranslation: "coffee",
                          wordType: "noun", article: "der", exampleSentence: nil, conjugations: nil,
                          sortOrder: 0, progress: nil),
                    .init(id: "C2D6A4F1-5E3B-4C7A-8F9E-0A1B2C3D4E5F", germanWord: "Kuchen", englishTranslation: "cake",
                          wordType: "noun", article: "der", exampleSentence: "Der Kuchen ist frisch.", conjugations: [],
                          sortOrder: 1, progress: nil),
                ]))
    }

    func iOSImport(_ envelope: DeckTransferEnvelope, mode: DeckImporter.Mode) -> (ModelContext, SavedDeck) {
        let context = ModelContext(ModelContainer.inMemory([SavedDeck.self, SavedCard.self, QuizResult.self]))
        return (context, DeckImporter.insert(envelope, mode: mode, into: context))
    }

    @Test(arguments: ["Nouns", "Something new"])
    func importedDecksSyncTheSame(filter: String) {
        let file = Self.envelope(filter: filter)
        let (_, deck) = iOSImport(file, mode: .replace)
        let android = DeckTransferRecords.records(from: file, mode: .replace)

        #expect(SavedDeckCodec.known(deck) == android.deck.payload)
        let iosCards = deck.cards.sorted { $0.sortOrder < $1.sortOrder }
        #expect(iosCards.count == android.cards.count)
        for (ios, record) in zip(iosCards, android.cards) {
            #expect(SavedCardCodec.known(ios) == record.payload, "\(ios.germanWord)")
        }
    }

    @Test func keepingBothForksEveryID() {
        let file = Self.envelope()
        let android = DeckTransferRecords.records(from: file, mode: .keepBoth)
        #expect(android.deck.id.uuidString != file.deck.id)
        #expect(Set(android.cards.map(\.id.uuidString)).isDisjoint(with: file.deck.cards.map(\.id)))
        #expect(android.cards.allSatisfy { $0.deck == android.deck.id })
    }

    @Test func bothAppsWriteTheSameFile() throws {
        let (_, deck) = iOSImport(Self.envelope(), mode: .replace)
        let ios = try #require(DeckTransfer.envelope(for: deck, exportedAt: Self.day))
        let records = DeckTransferRecords.records(from: Self.envelope(), mode: .replace)
        let android = try #require(DeckTransferRecords.envelope(deck: records.deck, cards: records.cards,
                                                                 app: ios.app, exportedAt: Self.day))
        #expect(ios == android)
        #expect(try DeckTransferFormat.encode(ios) == DeckTransferFormat.encode(android))
        // And what either writes reads back as what was sent.
        #expect(try DeckTransferFormat.decode(DeckTransferFormat.encode(android)) == android)
    }

    @Test func theWortschatzBoxNeverTravels() {
        var file = Self.envelope()
        file.deck.generator = "goethe-srs"
        let data = try? DeckTransferFormat.encode(file)
        #expect(throws: DeckTransferFailure.wortschatz) { try DeckTransferFormat.decode(data ?? Data()) }
        #expect(DeckTransferRecords.envelope(deck: .wortschatz(wordCount: 1), cards: [],
                                             app: file.app) == nil)
        #expect(DeckKind.verbPrepositionGenerator == VerbPrepositionService.deckGenerator)
    }

    @Test(arguments: [FlashcardStyle.anki, .leitner, .default])
    func cardSessionResultsSyncTheSame(mode: FlashcardStyle) throws {
        let context = ModelContext(ModelContainer.inMemory([SavedDeck.self, SavedCard.self, QuizResult.self]))
        let deck = SavedDeck(topic: "Im Café", wordCount: 3, includeExamples: false)
        context.insert(deck)
        let ratings: [Int: AnkiRating] = [0: .good, 1: .again, 2: .easy]
        let ios = QuizResult(totalCards: 3, correctCount: 2, incorrectCardIndices: [1], durationSeconds: 95,
                             date: Self.day, studyMode: mode, ankiRatings: mode == .anki ? ratings : nil,
                             subDeckLabel: "1 due · 2 new · A1 · all word types")
        ios.deck = deck
        context.insert(ios)
        let android = QuizResultRecord.cardSession(
            deck: deck.id, correct: 2, total: 3, missed: [1], seconds: 95, mode: mode, ankiRatings: ratings,
            subDeckLabel: "1 due · 2 new · A1 · all word types", date: Self.day, id: ios.id)
        #expect(QuizResultCodec.known(ios) == android.payload)
    }

    @Test func phraseDecksSyncTheSame() {
        let phrases = [PhraseCards.Phrase(german: "Sonst noch etwas?", english: "Anything else?"),
                       PhraseCards.Phrase(german: "die Rechnung", english: "the bill")]
        let context = ModelContext(ModelContainer.inMemory([SavedDeck.self, SavedCard.self, QuizResult.self]))
        // As PhraseToDeckSheet makes a new deck.
        let vocab = PhraseCards.newDeck(phrases).map {
            VocabCard(germanWord: $0.german, englishTranslation: $0.english, wordType: $0.wordType, article: nil,
                      exampleSentence: nil, conjugations: nil)
        }
        let deck = SavedDeck(topic: PhraseCards.deckName(" "), wordCount: vocab.count, includeExamples: false,
                             includeGender: false, vocabCards: vocab)
        deck.generatorRaw = PhraseCards.generator
        context.insert(deck)
        let android = PhraseCards.newDeckRecords(phrases, name: " ", createdAt: deck.createdAt, id: deck.id)
        #expect(SavedDeckCodec.known(deck) == android.deck.payload)
        for (ios, record) in zip(deck.cards.sorted { $0.sortOrder < $1.sortOrder }, android.cards) {
            var record = record
            record.id = ios.id
            #expect(SavedCardCodec.known(ios) == record.payload)
        }
        // Merging skips what's there.
        let merged = PhraseCards.merge(phrases + [.init(german: "Zahlen, bitte", english: "Check, please")],
                                       intoDeckWith: ["Sonst noch etwas?"], lastOrder: 4)
        #expect(merged.map(\.german) == ["die Rechnung", "Zahlen, bitte"])
        #expect(merged.map(\.sortOrder) == [5, 6])
    }
}
