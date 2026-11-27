import Foundation
@testable import DieKarteiCore

/// Moves the Wortschatz progress Android kept before the database (UserDefaults
/// `studyProgress.v1`: `[String: LegacyCardProgress]` keyed `"<A1|A2|B1>:<word>"`) onto the
/// record store, as iOS keeps it: one Wortschatz deck, one card per exact word with the iOS ids.
///
/// A word on two level lists had its own progress per level. Those copies are merged with the
/// card's sync rules (`SyncKinds.savedCard`), as two devices' copies would be: reviews and lapses
/// add up, the schedule comes whole from the later review, the first review is the earlier.
/// Runs once (a `meta` flag); the old blob is left alone so a rollback still finds it.
enum WortschatzMigration {
    static let defaultsKey = "studyProgress.v1"
    static let flag = "migrated.studyProgress.v1"

    /// The fields Android's `StudyStore` saved per word and level.
    struct LegacyCardProgress: Codable, Hashable {
        var sortOrder: Int
        var easeFactor = 2.5
        var interval = 0
        var repetitions = 0
        var nextReviewDate: Date?
        var totalReviews = 0
        var lapses = 0
        var leitnerBox = 0
        var firstReviewedAt: Date?
        var lastReviewedAt: Date?
        var lastReviewWasCorrect: Bool?
    }

    struct Outcome: Equatable {
        var cards = 0
        /// Words iOS has no card for (no translation in the lists), left behind.
        var dropped: [String] = []
        var alreadyDone = false
    }

    /// - `card`: the fresh Wortschatz card for a word (`WortschatzRecords.card(for:)`), nil if
    ///   iOS has none.
    @discardableResult
    static func run(blob: Data?, into store: RecordStore, deck: DeckRecord,
                    card: (String) -> CardRecord?, now: Date = Date()) throws -> Outcome {
        if try store.database.meta(flag) != nil { return Outcome(alreadyDone: true) }
        var outcome = Outcome()
        let legacy = blob.flatMap { try? JSONDecoder().decode([String: LegacyCardProgress].self, from: $0) } ?? [:]
        let merged = mergeByWord(legacy, card: card, dropped: &outcome.dropped)
        try store.transaction {
            if store.record(DeckRecord.self, id: deck.id) == nil { try store.put(deck, now: now) }
            // Progress already in the store (a second device's sync, later) wins over nothing:
            // only words without a record are written.
            let fresh = merged.filter { store.record(CardRecord.self, id: $0.id) == nil }
            try store.put(fresh, now: now)
            outcome.cards = fresh.count
            try store.database.setMeta(flag, "\(Int(now.timeIntervalSince1970))")
        }
        return outcome
    }

    /// One card per exact word (never lowercased: `sie` and `Sie` are two cards).
    static func mergeByWord(_ legacy: [String: LegacyCardProgress], card: (String) -> CardRecord?,
                            dropped: inout [String]) -> [CardRecord] {
        var byWord: [String: [(level: String, progress: LegacyCardProgress)]] = [:]
        for (key, progress) in legacy {
            guard let colon = key.firstIndex(of: ":") else { continue }
            let level = String(key[..<colon])
            let word = String(key[key.index(after: colon)...])
            byWord[word, default: []].append((level, progress))
        }
        let spec = SyncKinds.savedCard
        var out: [CardRecord] = []
        for (word, copies) in byWord.sorted(by: { $0.key < $1.key }) {
            guard let base = card(word) else { dropped.append(word); continue }
            // Each level's copy as if it came from its own device, merged by the card's rules.
            var merged: SyncPayload?
            for (level, progress) in copies.sorted(by: { $0.level < $1.level }) {
                let payload = SyncMerge.compose(base: nil, known: apply(progress, to: base).payload,
                                                spec: spec, slot: "level-" + level, now: 0)
                merged = merged.map { SyncMerge.merge(ancestor: nil, local: $0, remote: payload, spec: spec) } ?? payload
            }
            guard let merged else { continue }
            var record = CardRecord(payload: SyncMerge.flatten(merged, spec: spec))
            // Content and order always come from the bundle (iOS: the lists own a Wortschatz
            // card's content), never from whichever level's copy won.
            record.germanWord = base.germanWord
            record.englishTranslation = base.englishTranslation
            record.wordType = base.wordType
            record.article = base.article
            record.exampleSentence = base.exampleSentence
            record.sortOrder = base.sortOrder
            out.append(record)
        }
        return out
    }

    static func apply(_ p: LegacyCardProgress, to card: CardRecord) -> CardRecord {
        var c = card
        c.easeFactor = p.easeFactor
        c.interval = p.interval
        c.repetitions = p.repetitions
        c.nextReviewDate = p.nextReviewDate
        c.totalReviews = p.totalReviews
        c.lapses = p.lapses
        c.leitnerBox = p.leitnerBox
        c.firstReviewedAt = p.firstReviewedAt
        c.lastReviewedAt = p.lastReviewedAt
        c.lastReviewWasCorrect = p.lastReviewWasCorrect
        return c
    }
}
