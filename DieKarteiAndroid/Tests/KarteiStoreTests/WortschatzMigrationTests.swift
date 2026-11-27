import Foundation
import Testing
@testable import DieKarteiCore
@testable import KarteiStore

@MainActor
@Suite("WortschatzMigration")
struct WortschatzMigrationTests {
    typealias Legacy = WortschatzMigration.LegacyCardProgress

    static func t(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }

    /// A stand-in for the bundled lists: the words iOS has cards for, in introduction order.
    static let bundle = ["Sie", "sie", "essen", "um 3:00 Uhr"]
    static func card(_ word: String) -> CardRecord? {
        guard let i = bundle.firstIndex(of: word) else { return nil }
        return CardRecord.wortschatz(word: word, translation: "t-\(word)", wordType: nil, article: nil,
                                     example: nil, sortOrder: i)
    }

    func store() throws -> RecordStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kartei-\(UUID().uuidString)")
        return RecordStore(database: try KarteiDatabase(url: dir.appendingPathComponent("kartei.sqlite")), replica: "phone")
    }

    static let blob: Data = {
        var a1 = Legacy(sortOrder: 7)                        // essen, studied on A1…
        a1.totalReviews = 2; a1.lapses = 1; a1.interval = 3; a1.repetitions = 2
        a1.firstReviewedAt = t(100); a1.lastReviewedAt = t(500); a1.nextReviewDate = t(800)
        var a2 = Legacy(sortOrder: 2)                        // …and again on A2, later
        a2.totalReviews = 1; a2.interval = 1; a2.repetitions = 1
        a2.firstReviewedAt = t(300); a2.lastReviewedAt = t(900); a2.nextReviewDate = t(1_000)
        var formal = Legacy(sortOrder: 0); formal.totalReviews = 1; formal.lastReviewedAt = t(50)
        var plain = Legacy(sortOrder: 1); plain.totalReviews = 4; plain.lastReviewedAt = t(60)
        var colon = Legacy(sortOrder: 3); colon.totalReviews = 1; colon.lastReviewedAt = t(70)
        var nope = Legacy(sortOrder: 4); nope.totalReviews = 1
        let legacy: [String: Legacy] = [
            "A1:essen": a1, "A2:essen": a2, "A1:Sie": formal, "A1:sie": plain,
            "B1:um 3:00 Uhr": colon, "A1:gibtsnicht": nope,
        ]
        return try! JSONEncoder().encode(legacy)
    }()

    @Test("Progress moves to iOS ids: one card per exact word, level copies merged by the sync rules")
    func migrates() throws {
        let store = try store()
        let deck = DeckRecord.wortschatz(wordCount: Self.bundle.count, createdAt: Self.t(1))
        let outcome = try WortschatzMigration.run(blob: Self.blob, into: store, deck: deck, card: Self.card, now: Self.t(2))
        #expect(outcome.cards == 4)
        #expect(outcome.dropped == ["gibtsnicht"])

        let cards = store.records(CardRecord.self, parent: SyncSingletonDecks.wortschatzDeckID)
        #expect(cards.map(\.germanWord) == ["Sie", "sie", "essen", "um 3:00 Uhr"])   // bundle order
        for card in cards {
            #expect(card.id == SyncSingletonDecks.cardID(deckID: SyncSingletonDecks.wortschatzDeckID, germanWord: card.germanWord))
        }
        let essen = try #require(cards.first { $0.germanWord == "essen" })
        #expect(essen.totalReviews == 3)                 // summed
        #expect(essen.lapses == 1)
        #expect(essen.interval == 1)                     // the A2 schedule: reviewed later
        #expect(essen.nextReviewDate == Self.t(1_000))
        #expect(essen.firstReviewedAt == Self.t(100))    // the earlier
        #expect(essen.sortOrder == 2)                    // the bundle's order, not a level index
        #expect(essen.englishTranslation == "t-essen")
        #expect(cards.first { $0.germanWord == "sie" }?.totalReviews == 4)
        #expect(cards.first { $0.germanWord == "Sie" }?.totalReviews == 1)

        // Credited to this install, as a review on this phone would be.
        let pending = try #require(store.copies(of: essen.name)?.pending)
        #expect(SyncCounter(json: pending["totalReviews"]).p == ["phone": 3])
        #expect(store.record(DeckRecord.self, id: SyncSingletonDecks.wortschatzDeckID)?.payload == deck.payload)
    }

    @Test("Running it twice changes nothing")
    func idempotent() throws {
        let store = try store()
        let deck = DeckRecord.wortschatz(wordCount: 4, createdAt: Self.t(1))
        try WortschatzMigration.run(blob: Self.blob, into: store, deck: deck, card: Self.card, now: Self.t(2))
        var card = try #require(store.records(CardRecord.self, naturalKey: "essen").first)
        card.totalReviews = 10
        try store.put(card)
        let again = try WortschatzMigration.run(blob: Self.blob, into: store, deck: deck, card: Self.card, now: Self.t(3))
        #expect(again.alreadyDone)
        #expect(store.records(CardRecord.self, naturalKey: "essen").first?.totalReviews == 10)
        #expect(store.count(kind: "SavedCard") == 4)
    }

    @Test("No old progress: just the deck")
    func empty() throws {
        let store = try store()
        let outcome = try WortschatzMigration.run(blob: nil, into: store, deck: DeckRecord.wortschatz(wordCount: 4),
                                                  card: Self.card)
        #expect(outcome.cards == 0)
        #expect(store.records(DeckRecord.self).count == 1)
    }
}
