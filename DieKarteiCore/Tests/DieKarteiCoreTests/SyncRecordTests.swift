import Foundation
import Testing
@testable import DieKarteiCore

/// The Android side of the iOS ⇄ Android record contract: every shared record reads and writes
/// the golden payloads the iOS codecs produce (`sync_golden.json`, written and checked by the
/// iOS `SyncGoldenTests`). If this passes and the iOS suite passes, a record written on Android
/// is a row iOS applies, and the other way round.
@Suite struct SyncRecordTests {
    struct Golden {
        let kind: String
        let label: String
        let name: String
        let payload: SyncPayload
    }

    static let document: [String: SyncJSON] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("sync_golden.json")
        return (try? SyncJSON(data: Data(contentsOf: url)))?.objectValue ?? [:]
    }()

    static let records: [Golden] = (document["records"]?.arrayValue ?? []).compactMap { r in
        guard let kind = r["kind"]?.stringValue, let label = r["label"]?.stringValue,
              let name = r["name"]?.stringValue, let payload = r["payload"]?.objectValue else { return nil }
        return Golden(kind: kind, label: label, name: name, payload: payload)
    }

    static func golden(_ kind: String, _ label: String) -> SyncPayload {
        records.first { $0.kind == kind && $0.label == label }?.payload ?? [:]
    }

    static func id(_ key: String) -> String? { document["ids"]?[key]?.stringValue }

    /// Decode with the record type for the kind, then write back out.
    static func roundTrip(_ g: Golden) -> (name: String, payload: SyncPayload)? {
        switch g.kind {
        case "SavedDeck": let r = DeckRecord(payload: g.payload); return (r.name.description, r.payload)
        case "SavedCard": let r = CardRecord(payload: g.payload); return (r.name.description, r.payload)
        case "QuizResult": let r = QuizResultRecord(payload: g.payload); return (r.name.description, r.payload)
        case "StudyDay": let r = StudyDayRecord(payload: g.payload); return (r.name.description, r.payload)
        default: return nil
        }
    }

    static func t(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    /// A flattened server copy read into its record and written back out.
    static func roundTripFlat(_ kind: String, _ flat: SyncPayload) -> SyncPayload? {
        roundTrip(Golden(kind: kind, label: "", name: "", payload: flat))?.payload
    }

    @Test func theGoldenFileIsThere() {
        #expect(Self.records.count >= 10)
        #expect(Set(Self.records.map(\.kind)) == ["SavedDeck", "SavedCard", "QuizResult", "StudyDay"])
    }

    @Test(arguments: records.indices)
    func recordsReadAndWriteTheIOSPayloads(_ i: Int) {
        let g = Self.records[i]
        let out = Self.roundTrip(g)
        #expect(out?.name == g.name, "\(g.kind) \(g.label)")
        #expect(out?.payload == g.payload, "\(g.kind) \(g.label)")
    }

    @Test func idsMatchIOS() {
        let deck = SyncSingletonDecks.wortschatzDeckID
        #expect(deck.uuidString == Self.id("wortschatzDeck"))
        #expect(SyncSingletonDecks.cardID(deckID: deck, germanWord: "Sie").uuidString == Self.id("card:Sie"))
        #expect(SyncSingletonDecks.cardID(deckID: deck, germanWord: "sie").uuidString == Self.id("card:sie"))
        #expect(Self.id("card:Sie") != Self.id("card:sie"))
        #expect(SyncKinds.learnerProfileName.description == Self.id("learnerProfile"))
        #expect(StudyDayRecord(day: "2026-11-27").name.description == Self.id("studyDay:2026-11-27"))
    }

    /// Records built the way Android code builds them (not decoded) come out as iOS's rows do.
    @Test func recordsBuiltOnAndroidMatchIOSRows() {
        #expect(DeckRecord.wortschatz(wordCount: 2825, createdAt: Self.t(815_000_200)).payload
                == Self.golden("SavedDeck", "wortschatz"))

        var sie = CardRecord.wortschatz(word: "Sie", translation: "you (formal)", wordType: "pronoun", article: nil,
                                        example: "Kommen Sie aus Berlin?", sortOrder: 41)
        sie.easeFactor = 2.6
        sie.interval = 1
        sie.repetitions = 1
        sie.nextReviewDate = Self.t(815_086_800)
        sie.totalReviews = 1
        sie.leitnerBox = 1
        sie.noteReview(correct: true, at: Self.t(815_000_400))
        #expect(sie.payload == Self.golden("SavedCard", "wortschatz"))

        let bare = CardRecord(id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
                              deck: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                              germanWord: "leer", englishTranslation: "empty")
        #expect(bare.payload == Self.golden("SavedCard", "bare"))

        var day = StudyDayRecord(day: "2026-11-28", lastActivityAt: Self.t(816_100_000))
        #expect(day.payload == Self.golden("StudyDay", "bare"))
        for (i, field) in SyncKinds.studyDayCounterFields.enumerated() { day[field] = i + 1 }
        day.day = "2026-11-27"
        day.lastActivityAt = Self.t(816_000_000.75)
        #expect(day.payload == Self.golden("StudyDay", "full"))
    }

    /// A field a newer build added survives a read and a write on an older one.
    @Test func unknownFieldsPassThrough() {
        var p = Self.golden("SavedCard", "full")
        p["futureField"] = .string("from a newer iOS build")
        var card = CardRecord(payload: p)
        card.interval = 9
        #expect(card.payload["futureField"] == .string("from a newer iOS build"))
        #expect(card.payload["interval"] == .int(9))
    }

    /// What travels: composed on this device's slot, flattened on the other side, it is the
    /// same record (counters credited to the slot, nothing else changed).
    @Test(arguments: records.indices)
    func composedCopiesFlattenBackToTheRecord(_ i: Int) throws {
        let g = Self.records[i]
        let spec = try #require(SyncKinds.byKind[g.kind])
        let composed = SyncMerge.compose(base: nil, known: g.payload, spec: spec, slot: "android-1", now: 1)
        let flat = SyncMerge.flatten(composed, spec: spec)
        // Nulls and zero counters don't travel; readers take them as nil and 0 (as the codecs do).
        let expected = g.payload.filter { key, value in
            value != .null && !(spec.rule(for: key) == .counter && value.int64Value == 0)
        }
        #expect(flat == expected, "\(g.kind) \(g.label)")
        #expect(Self.roundTripFlat(g.kind, flat) == g.payload, "\(g.kind) \(g.label) reads back whole")
        for (field, rule) in spec.rules where rule == .counter {
            let value = g.payload[field]?.int64Value ?? 0
            if value > 0 { #expect(SyncCounter(json: composed[field]).p["android-1"] == value) }
        }
    }
}
