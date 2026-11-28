import Foundation
import Testing
@testable import DieKarteiCore

/// The shared card-session rules (`AnkiRound`) and the `.kartei` file checks, as both apps run them.
@MainActor
@Suite struct DeckSharedRulesTests {
    /// `#expect` can't take a mutating call, so rate through this.
    func rated(_ round: inout AnkiRound, _ rating: AnkiRating, repeatMissed: Bool) -> Bool {
        round.rate(rating, repeatMissed: repeatMissed)
    }

    @Test("A missed card comes back three cards later, at most twice")
    func requeue() {
        var round = AnkiRound(order: Array(0..<6))
        #expect(rated(&round, .again, repeatMissed: true))          // card 0 → back after 3
        #expect(Array(round.order.dropFirst(round.position)) == [1, 2, 3, 0, 4, 5])
        round.rate(.good, repeatMissed: true)
        round.rate(.good, repeatMissed: true)
        round.rate(.good, repeatMissed: true)
        #expect(round.current == 0)
        #expect(rated(&round, .again, repeatMissed: true))          // second return
        #expect(round.order.filter { $0 == 0 }.count == 3)
        while round.current != 0 { round.rate(.good, repeatMissed: true) }
        #expect(!rated(&round, .again, repeatMissed: true), "no third return")
        while !round.isFinished { round.rate(.good, repeatMissed: true) }
        let tally = round.tally
        #expect(tally.total == 6 && tally.correct == 5 && tally.missed == [0])
        #expect(round.firstRatings[0] == .again && round.firstRatings.count == 6)
    }

    @Test("Without repeats, a miss counts but doesn't come back")
    func noRepeat() {
        var round = AnkiRound(order: [4, 7])
        #expect(!rated(&round, .again, repeatMissed: false))
        round.rate(.hard, repeatMissed: false)
        #expect(round.isFinished)
        #expect(round.tally.missed == [4] && round.tally.correct == 1)
        #expect(round.firstRatings == [4: .again, 7: .hard])
    }

    @Test("A card is due when never reviewed or its date has come")
    func due() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(AnkiSessionRules.isDue(nextReviewDate: nil, now: now))
        #expect(AnkiSessionRules.isDue(nextReviewDate: now, now: now))
        #expect(!AnkiSessionRules.isDue(nextReviewDate: now.addingTimeInterval(1), now: now))
    }

    @Test("Only decks of this app, of this or an older version, are taken in")
    func fileChecks() throws {
        #expect(throws: DeckTransferFailure.notADeck) { try DeckTransferFormat.decode(Data("{}".utf8)) }
        let file = DeckTransferEnvelope(
            exportedAt: Date(timeIntervalSinceReferenceDate: 815_000_000),
            app: .init(name: "Die Kartei", version: nil, build: nil),
            deck: .init(id: UUID().uuidString, topic: "Café / Bäckerei", wordCount: 0, includeExamples: false,
                        includeGender: true, wordTypeFilter: "All", includeConjugations: false, selectedTenses: [],
                        createdAt: Date(timeIntervalSinceReferenceDate: 815_000_000), generationTimeSeconds: 0,
                        generator: "", cards: []))
        var newer = file
        newer.schemaVersion = DeckTransferFormat.schemaVersion + 1
        #expect(throws: DeckTransferFailure.fromANewerVersion(2)) {
            try DeckTransferFormat.decode(DeckTransferFormat.encode(newer))
        }
        #expect(try DeckTransferFormat.decode(DeckTransferFormat.encode(file)) == file)
        #expect(DeckTransferFormat.fileName(topic: file.deck.topic) == "Café-Bäckerei.kartei")
        #expect(DeckKind(generatorRaw: "").isBrowsableContent && !DeckKind(generatorRaw: "grammar").isBrowsableContent)
    }
}
