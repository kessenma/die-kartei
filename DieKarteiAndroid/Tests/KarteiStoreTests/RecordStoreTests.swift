import Foundation
import Testing
@testable import DieKarteiCore
@testable import KarteiStore

@MainActor
@Suite("RecordStore")
struct RecordStoreTests {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kartei-\(UUID().uuidString)")
    }

    func open(_ dir: URL, replica: String = "android-a") throws -> RecordStore {
        RecordStore(database: try KarteiDatabase(url: dir.appendingPathComponent("kartei.sqlite")), replica: replica)
    }

    static let golden: [String: SyncJSON] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DieKarteiCore/Tests/DieKarteiCoreTests/sync_golden.json")
        return (try? SyncJSON(data: Data(contentsOf: url)))?.objectValue ?? [:]
    }()

    static func golden(_ kind: String, _ label: String) -> SyncPayload {
        (golden["records"]?.arrayValue ?? []).first {
            $0["kind"]?.stringValue == kind && $0["label"]?.stringValue == label
        }?["payload"]?.objectValue ?? [:]
    }

    static func t(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }

    @Test("iOS's golden records go in and come out byte for byte, and survive a reopen")
    func storesTheIOSShape() throws {
        let dir = tempDir()
        var store = try open(dir)
        let decks = ["full", "bare", "wortschatz"].map { DeckRecord(payload: Self.golden("SavedDeck", $0)) }
        let cards = ["full", "bare", "wortschatz"].map { CardRecord(payload: Self.golden("SavedCard", $0)) }
        let results = ["full", "bare"].map { QuizResultRecord(payload: Self.golden("QuizResult", $0)) }
        let days = ["full", "bare"].map { StudyDayRecord(payload: Self.golden("StudyDay", $0)) }
        try store.transaction {
            try store.put(decks); try store.put(cards); try store.put(results); try store.put(days)
        }
        try store.database.close()

        store = try open(dir)
        #expect(store.database.schemaVersion == Int64(KarteiDatabase.migrations.count))
        for label in ["full", "bare", "wortschatz"] {
            let deck = DeckRecord(payload: Self.golden("SavedDeck", label))
            #expect(store.record(DeckRecord.self, id: deck.id)?.payload == Self.golden("SavedDeck", label))
            let card = CardRecord(payload: Self.golden("SavedCard", label))
            #expect(store.record(CardRecord.self, id: card.id)?.payload == Self.golden("SavedCard", label))
        }
        #expect(store.records(StudyDayRecord.self, days: "2026-11-01", "2026-11-30").map(\.payload)
                == [Self.golden("StudyDay", "full"), Self.golden("StudyDay", "bare")])
        #expect(store.records(QuizResultRecord.self).count == 2)
        // Everything is waiting for a transport, none of it sent.
        #expect(store.pendingUploads().count == 10)
    }

    @Test("Counters are credited to this install's slot from the first write")
    func countersArePerDevice() throws {
        let store = try open(tempDir(), replica: "phone-1")
        var card = WortschatzRecordsFixture.sie
        card.totalReviews = 1
        try store.put(card, now: Self.t(10))
        card.totalReviews = 3
        card.lapses = 1
        try store.put(card, now: Self.t(20))
        let pending = try #require(store.copies(of: card.name)?.pending)
        #expect(SyncCounter(json: pending["totalReviews"]).p == ["phone-1": 3])
        #expect(SyncCounter(json: pending["lapses"]).p == ["phone-1": 1])
        #expect(store.record(CardRecord.self, id: card.id)?.totalReviews == 3)
    }

    @Test("Two phones review the same word offline: reviews add up, the later schedule wins, the first review is the earlier")
    func twoDevicesMerge() throws {
        let a = try open(tempDir(), replica: "phone-a")
        let b = try open(tempDir(), replica: "phone-b")

        var onA = WortschatzRecordsFixture.fresh
        onA.totalReviews = 2
        onA.interval = 3
        onA.repetitions = 2
        onA.nextReviewDate = Self.t(1_000_300)
        onA.noteReview(correct: true, at: Self.t(1_000_000))
        try a.put(onA)

        var onB = WortschatzRecordsFixture.fresh
        onB.totalReviews = 1
        onB.lapses = 1
        onB.interval = 1
        onB.nextReviewDate = Self.t(2_000_100)
        onB.noteReview(correct: false, at: Self.t(900_000))   // first seen earlier on B…
        onB.lastReviewedAt = Self.t(2_000_000)                // …and reviewed last there too
        try b.put(onB)

        // Same record name on both: the canonical Wortschatz id.
        #expect(onA.name == onB.name)
        let spec = SyncKinds.savedCard
        let pa = try #require(a.copies(of: onA.name)?.pending)
        let pb = try #require(b.copies(of: onB.name)?.pending)
        let merged = SyncMerge.merge(ancestor: nil, local: pa, remote: pb, spec: spec)
        #expect(merged == SyncMerge.merge(ancestor: nil, local: pb, remote: pa, spec: spec))
        let card = CardRecord(payload: SyncMerge.flatten(merged, spec: spec))
        #expect(card.totalReviews == 3)
        #expect(card.lapses == 1)
        #expect(card.interval == 1)                                  // B's schedule, whole
        #expect(card.nextReviewDate == Self.t(2_000_100))
        #expect(card.lastReviewWasCorrect == false)
        #expect(card.firstReviewedAt == Self.t(900_000))
        #expect(card.germanWord == "Sie")
    }

    @Test("Deleting a deck takes its cards and results; only records the server has leave tombstones")
    func cascadeAndTombstones() throws {
        let store = try open(tempDir())
        let deck = DeckRecord(topic: "Reise", createdAt: Self.t(1))
        let cards = (0..<3).map { CardRecord(deck: deck.id, germanWord: "w\($0)", englishTranslation: "e", sortOrder: $0) }
        let result = QuizResultRecord(deck: deck.id, date: Self.t(5))
        let other = DeckRecord(topic: "Andere", createdAt: Self.t(2))
        try store.transaction {
            try store.put(deck); try store.put(cards); try store.put(result); try store.put(other)
        }
        // A transport sent the deck and the first card.
        for name in [deck.name, cards[0].name] {
            let sent = try #require(store.copies(of: name)?.pending)
            try store.didSend(name, sent: sent)
        }
        #expect(store.copies(of: deck.name)?.pending == nil)
        #expect(store.pendingUploads().count == 4)

        try store.delete(deck)
        #expect(store.record(DeckRecord.self, id: deck.id) == nil)
        #expect(store.records(CardRecord.self, parent: deck.id).isEmpty)
        #expect(store.records(QuizResultRecord.self).isEmpty)
        #expect(store.records(DeckRecord.self).map(\.id) == [other.id])
        #expect(Set(store.tombstones()) == [deck.name, cards[0].name])
    }

    @Test("Due cards come oldest first, per deck; list order follows sortOrder")
    func queries() throws {
        let store = try open(tempDir())
        let deck = DeckRecord(topic: "D", createdAt: Self.t(1))
        var cards: [CardRecord] = []
        for (i, due) in [Self.t(300), nil, Self.t(100), Self.t(9_000)].enumerated() {
            var c = CardRecord(deck: deck.id, germanWord: "w\(i)", englishTranslation: "e", sortOrder: 10 - i)
            c.nextReviewDate = due
            cards.append(c)
        }
        try store.put(deck)
        try store.put(cards)
        #expect(store.due(CardRecord.self, parent: deck.id, asOf: Self.t(500)).map(\.germanWord) == ["w2", "w0"])
        #expect(store.records(CardRecord.self, parent: deck.id).map(\.germanWord) == ["w3", "w2", "w1", "w0"])
        #expect(store.records(CardRecord.self, naturalKey: "w1").count == 1)
        #expect(store.count(kind: "SavedCard", parent: deck.id) == 4)
    }

    @Test("Revisions bump once per committed transaction, not on a rollback")
    func revisions() throws {
        let store = try open(tempDir())
        try store.transaction {
            try store.put(DeckRecord(topic: "a"))
            try store.put(DeckRecord(topic: "b"))
        }
        #expect(store.revisions["SavedDeck"] == 1)
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try store.transaction {
                try store.put(DeckRecord(topic: "c"))
                throw Boom()
            }
        }
        #expect(store.revisions["SavedDeck"] == 1)
        #expect(store.records(DeckRecord.self).count == 2)
    }

    @Test("The replica id is made once and kept outside the database")
    func replicaID() throws {
        let dir = tempDir()
        let first = try ReplicaID.load(directory: dir)
        #expect(UUID(uuidString: first) != nil)
        #expect(try ReplicaID.load(directory: dir) == first)
        #expect(try ReplicaID.load(directory: tempDir()) != first)
    }
}

/// The reviewed Wortschatz card from the golden file, and the same word unreviewed.
@MainActor
enum WortschatzRecordsFixture {
    static var sie: CardRecord { CardRecord(payload: RecordStoreTests.golden("SavedCard", "wortschatz")) }
    static var fresh: CardRecord {
        CardRecord.wortschatz(word: "Sie", translation: "you (formal)", wordType: "pronoun", article: nil,
                              example: "Kommen Sie aus Berlin?", sortOrder: 41)
    }
}
