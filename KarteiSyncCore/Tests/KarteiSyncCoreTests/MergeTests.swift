import Foundation
import Testing
@testable import KarteiSyncCore

// Named cases for the merge engine. Property-style convergence lives in SimulationTests.

private let cardSpec = SyncKindSpec(
    kind: "SavedCard",
    rules: [
        "totalReviews": .counter,
        "lapses": .counter,
        "firstReviewedAt": .min,
    ],
    groups: [
        SyncFieldGroup(
            fields: ["easeFactor", "interval", "repetitions", "nextReviewDate", "leitnerBox",
                     "lastReviewedAt", "lastReviewWasCorrect"],
            orderBy: ["lastReviewedAt", "repetitions", "interval", "easeFactor"]
        )
    ]
)

private let daySpec = SyncKindSpec(
    kind: "StudyDay",
    rules: ["cardsReviewed": .counter, "cardSeconds": .counter, "lastActivityAt": .max]
)

private func compose(_ base: SyncPayload?, _ known: SyncPayload, _ spec: SyncKindSpec,
                     slot: String, now: Double = 100) -> SyncPayload {
    SyncMerge.compose(base: base, known: known, spec: spec, slot: slot, now: now)
}

private func value(_ p: SyncPayload, _ key: String, _ spec: SyncKindSpec) -> SyncJSON? {
    SyncMerge.flatten(p, spec: spec)[key]
}

@Suite struct CounterTests {
    @Test func pointwiseMaxIsIdempotentAndCommutative() {
        let a = SyncCounter(p: ["x": 3, "y": 1])
        let b = SyncCounter(p: ["x": 2, "z": 5], n: ["y": 1])
        #expect(a.merged(with: b) == b.merged(with: a))
        #expect(a.merged(with: a) == a)
        #expect(a.merged(with: b).value == 3 + 1 + 5 - 1)
    }

    @Test func absorbCreditsOnlyTheDifference() {
        var c = SyncCounter(p: ["other": 10])
        c.absorb(localValue: 14, slot: "me")
        #expect(c.p["me"] == 4)
        c.absorb(localValue: 12, slot: "me")
        #expect(c.n["me"] == 2)
        #expect(c.value == 12)
    }

    @Test func legacyNumberReadsAsOneSlot() {
        #expect(SyncCounter(json: .int(7)).value == 7)
    }
}

@Suite struct StudyDayTests {
    @Test func twoDevicesStudyingTheSameDaySum() {
        // Both start from the same server copy (cards 10 on the iPhone's slot).
        let server = compose(nil, ["cardsReviewed": .int(10)], daySpec, slot: "phone")
        let phone = compose(server, ["cardsReviewed": .int(30)], daySpec, slot: "phone")  // +20
        let pad = compose(server, ["cardsReviewed": .int(40)], daySpec, slot: "pad")      // +30
        let merged = SyncMerge.merge(ancestor: server, local: phone, remote: pad, spec: daySpec)
        #expect(value(merged, "cardsReviewed", daySpec) == .int(60))
        #expect(merged == SyncMerge.merge(ancestor: server, local: pad, remote: phone, spec: daySpec))
    }

    @Test func reuploadAfterZoneResetDoesNotDouble() {
        // In sync: 50 cards, all credited to the phone.
        let synced = compose(nil, ["cardsReviewed": .int(50)], daySpec, slot: "phone")
        // Zone deleted; both devices re-upload with no ancestor. The iPad's copy carries the same slots.
        let phoneAgain = compose(synced, ["cardsReviewed": .int(50)], daySpec, slot: "phone")
        let padAgain = compose(synced, ["cardsReviewed": .int(50)], daySpec, slot: "pad")
        let merged = SyncMerge.merge(ancestor: nil, local: padAgain, remote: phoneAgain, spec: daySpec)
        #expect(value(merged, "cardsReviewed", daySpec) == .int(50))
    }

    @Test func independentPreSyncHistoriesSumAndACopyMaxes() {
        let phone = compose(nil, ["cardsReviewed": .int(20)], daySpec, slot: "store-A")
        let pad = compose(nil, ["cardsReviewed": .int(15)], daySpec, slot: "store-B")
        let merged = SyncMerge.merge(ancestor: nil, local: phone, remote: pad, spec: daySpec)
        #expect(value(merged, "cardsReviewed", daySpec) == .int(35))
        // A restored backup of the same pre-sync store lands in the same slot: max, not sum.
        let restored = compose(nil, ["cardsReviewed": .int(20)], daySpec, slot: "store-A")
        let again = SyncMerge.merge(ancestor: nil, local: merged, remote: restored, spec: daySpec)
        #expect(value(again, "cardsReviewed", daySpec) == .int(35))
    }

    @Test func lastActivityTakesTheLater() {
        let a = compose(nil, ["lastActivityAt": .int(1000)], daySpec, slot: "a")
        let b = compose(nil, ["lastActivityAt": .int(2000)], daySpec, slot: "b")
        let merged = SyncMerge.merge(ancestor: nil, local: a, remote: b, spec: daySpec)
        #expect(merged["lastActivityAt"] == .int(2000))
    }
}

@Suite struct CardTests {
    private func card(reps: Int, interval: Int, reviewedAt: Double, total: Int, lapses: Int,
                      base: SyncPayload?, slot: String, now: Double) -> SyncPayload {
        compose(base, [
            "germanWord": .string("der Tisch"),
            "easeFactor": .number(2.5), "interval": .int(Int64(interval)), "repetitions": .int(Int64(reps)),
            "nextReviewDate": .number(reviewedAt + Double(interval) * 86_400), "leitnerBox": .int(1),
            "lastReviewedAt": .number(reviewedAt), "lastReviewWasCorrect": .bool(reps > 0),
            "totalReviews": .int(Int64(total)), "lapses": .int(Int64(lapses)),
        ], cardSpec, slot: slot, now: now)
    }

    @Test func sameCardReviewedOnBothTakesTheLaterScheduleAndCountsBoth() {
        let server = card(reps: 2, interval: 6, reviewedAt: 1_000, total: 5, lapses: 0, base: nil, slot: "pre", now: 1)
        let good = card(reps: 3, interval: 15, reviewedAt: 2_000, total: 6, lapses: 0, base: server, slot: "A", now: 2_000)
        let again = card(reps: 0, interval: 1, reviewedAt: 3_000, total: 6, lapses: 1, base: server, slot: "B", now: 3_000)
        let merged = SyncMerge.merge(ancestor: server, local: good, remote: again, spec: cardSpec)
        let flat = SyncMerge.flatten(merged, spec: cardSpec)
        #expect(flat["repetitions"] == .int(0))       // the later review (a lapse) sets the schedule
        #expect(flat["interval"] == .int(1))
        #expect(flat["totalReviews"] == .int(7))      // both reviews counted
        #expect(flat["lapses"] == .int(1))
        #expect(merged == SyncMerge.merge(ancestor: server, local: again, remote: good, spec: cardSpec))
    }

    @Test func scheduleIsNeverHalfOfEach() {
        let server = card(reps: 2, interval: 6, reviewedAt: 1_000, total: 5, lapses: 0, base: nil, slot: "pre", now: 1)
        let a = card(reps: 3, interval: 15, reviewedAt: 2_000, total: 6, lapses: 0, base: server, slot: "A", now: 2_000)
        let b = card(reps: 3, interval: 12, reviewedAt: 1_500, total: 6, lapses: 0, base: server, slot: "B", now: 1_500)
        let flat = SyncMerge.flatten(SyncMerge.merge(ancestor: server, local: b, remote: a, spec: cardSpec), spec: cardSpec)
        #expect(flat["interval"] == .int(15))
        #expect(flat["lastReviewedAt"] == .int(2_000))
    }

    @Test func karteiReplaceCopyInSharedPreSlotMaxesInsteadOfSumming() {
        let phone = card(reps: 4, interval: 20, reviewedAt: 1_000, total: 12, lapses: 1, base: nil, slot: "pre", now: 1)
        let pad = card(reps: 4, interval: 20, reviewedAt: 1_000, total: 12, lapses: 1, base: nil, slot: "pre", now: 1)
        let flat = SyncMerge.flatten(SyncMerge.merge(ancestor: nil, local: phone, remote: pad, spec: cardSpec), spec: cardSpec)
        #expect(flat["totalReviews"] == .int(12))
    }

    @Test func contentEditOnOneSideAndReviewOnTheOtherBothSurvive() {
        let server = card(reps: 2, interval: 6, reviewedAt: 1_000, total: 5, lapses: 0, base: nil, slot: "pre", now: 1)
        var edited = SyncMerge.flatten(server, spec: cardSpec)
        edited["englishTranslation"] = .string("the table")
        let a = compose(server, edited, cardSpec, slot: "A", now: 500)
        let b = card(reps: 3, interval: 15, reviewedAt: 2_000, total: 6, lapses: 0, base: server, slot: "B", now: 2_000)
        let flat = SyncMerge.flatten(SyncMerge.merge(ancestor: server, local: a, remote: b, spec: cardSpec), spec: cardSpec)
        #expect(flat["englishTranslation"] == .string("the table"))
        #expect(flat["repetitions"] == .int(3))
        #expect(flat["totalReviews"] == .int(6))
    }
}

@Suite struct SetAndFieldTests {
    private let spec = SyncKindSpec(kind: "Profile", rules: [
        "vocab": .set(idField: "id", item: .lwwBy("lastSeen"), sortBy: nil),
        "grammar": .keyed(item: .lwwBy("lastSeen")),
        "seen": .or,
    ])

    private func item(_ id: String, _ lastSeen: Double, _ uses: Int) -> SyncJSON {
        .object(["id": .string(id), "lastSeen": .number(lastSeen), "uses": .int(Int64(uses))])
    }

    @Test func addsFromBothSidesAreKeptAndRemovalsHonoured() {
        let server = compose(nil, ["vocab": .array([item("hund", 1, 1), item("katze", 1, 1)])], spec, slot: "x", now: 1)
        let a = compose(server, ["vocab": .array([item("hund", 1, 1), item("katze", 1, 1), item("maus", 2, 1)])], spec, slot: "A", now: 2)
        let b = compose(server, ["vocab": .array([item("hund", 1, 1)])], spec, slot: "B", now: 3)  // removed katze
        let merged = SyncMerge.merge(ancestor: server, local: a, remote: b, spec: spec)
        let ids = merged["vocab"]?.arrayValue?.compactMap { $0["id"]?.stringValue }
        #expect(ids == ["hund", "maus"])
        #expect(merged == SyncMerge.merge(ancestor: server, local: b, remote: a, spec: spec))
    }

    @Test func anEditBeatsAConcurrentRemoval() {
        let server = compose(nil, ["vocab": .array([item("hund", 1, 1)])], spec, slot: "x", now: 1)
        let a = compose(server, ["vocab": .array([item("hund", 5, 2)])], spec, slot: "A", now: 5)
        let b = compose(server, ["vocab": .array([])], spec, slot: "B", now: 6)
        let merged = SyncMerge.merge(ancestor: server, local: a, remote: b, spec: spec)
        #expect(merged["vocab"]?.arrayValue?.count == 1)
    }

    @Test func unknownFieldsFromANewerBuildSurvive() {
        // The server copy has "newField" (written by a newer build); this build doesn't know it.
        var server = compose(nil, ["seen": .bool(false)], spec, slot: "x", now: 1)
        server["newField"] = .string("keep me")
        let older = compose(server, ["seen": .bool(true)], spec, slot: "old", now: 2)
        #expect(older["newField"] == .string("keep me"))
        let merged = SyncMerge.merge(ancestor: server, local: older, remote: server, spec: spec)
        #expect(merged["newField"] == .string("keep me"))
        #expect(merged["seen"] == .bool(true))
    }

    @Test func newerGenerationIsHeldBack() {
        var p = compose(nil, ["seen": .bool(true)], spec, slot: "x", now: 1)
        p[SyncPayloadKey.generation] = .int(2)
        #expect(!spec.canRead(p))
    }

    @Test func nameUUIDIsStableAndVersion5() {
        let a = SyncNameUUID.make("goethe-srs", "Goethe Vocabulary")
        #expect(a == SyncNameUUID.make("goethe-srs", "Goethe Vocabulary"))
        #expect(a != SyncNameUUID.make("goethe-srsG", "oethe Vocabulary"))
        #expect(a.uuidString[a.uuidString.index(a.uuidString.startIndex, offsetBy: 14)] == "5")
        let name = SyncRecordName(kind: "ArticleWordStat", naturalKey: "die männer")
        let ascii = name.description.allSatisfy { $0.isASCII }
        #expect(ascii)
        #expect(SyncRecordName(name.description) == name)
    }
}

@Suite struct UnionAndMinMapTests {
    private let spec = SyncKindSpec(kind: "Progress", rules: ["fired": .union, "badges": .minMap])

    @Test func firedCelebrationsUnionAndBadgesKeepTheEarliestDate() {
        let a = SyncMerge.compose(base: nil, known: [
            "fired": .array([.string("streak.7"), .string("layer.a1")]),
            "badges": .object(["first-deck": .int(100), "week": .int(500)]),
        ], spec: spec, slot: "a", now: 1)
        let b = SyncMerge.compose(base: nil, known: [
            "fired": .array([.string("streak.7"), .string("streak.14")]),
            "badges": .object(["first-deck": .int(80), "story": .int(300)]),
        ], spec: spec, slot: "b", now: 2)
        let merged = SyncMerge.merge(ancestor: nil, local: a, remote: b, spec: spec)
        #expect(merged["fired"] == .array([.string("layer.a1"), .string("streak.14"), .string("streak.7")]))
        #expect(merged["badges"] == .object(["first-deck": .int(80), "week": .int(500), "story": .int(300)]))
        #expect(merged == SyncMerge.merge(ancestor: nil, local: b, remote: a, spec: spec))
    }
}
