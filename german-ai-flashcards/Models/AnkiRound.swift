//
//  AnkiRound.swift
//  german-ai-flashcards
//
//  How a spaced-repetition card session runs and what it adds up to: which cards are due, where a
//  "Didn't know" card comes back, each card's first rating, and the session's score. Foundation
//  only and shared with the Android app (DieKarteiCore). iOS's player (`CardDeckView`) keeps its
//  own state and calls `AnkiSessionRules`; Android runs a whole session in `AnkiRound`.
//

import Foundation

nonisolated enum AnkiSessionRules {
    /// A card rated Again comes back a few cards later in the same session (Settings ▸ Cards).
    static let repeatMissedKey = "cards.repeatMissed"
    /// Cards between a missed card and its return.
    static let requeueGap = 3
    /// A card comes back at most this many times in one session.
    static let maxRequeues = 2

    static func repeatMissed(_ defaults: UserDefaults = SharedDefaults.store) -> Bool {
        defaults.object(forKey: repeatMissedKey) == nil ? true : defaults.bool(forKey: repeatMissedKey)
    }

    /// Due for review: never reviewed, or its date has come.
    static func isDue(nextReviewDate: Date?, now: Date) -> Bool {
        guard let next = nextReviewDate else { return true }
        return next <= now
    }

    /// An Anki session's cards (indices into the deck's cards in deck order): the due ones, dealt
    /// at random when Shuffle is on.
    static func dueOrder(_ nextReviewDates: [Date?], now: Date, shuffle: Bool) -> [Int] {
        var order = nextReviewDates.indices.filter { isDue(nextReviewDate: nextReviewDates[$0], now: now) }
        if shuffle { order.shuffle() }
        return order
    }

    /// A Classic session's cards: all of them, in deck order or at random.
    static func classicOrder(count: Int, shuffle: Bool) -> [Int] {
        shuffle ? Array(0..<count).shuffled() : Array(0..<count)
    }

    /// A miss: the card is a lapse of this session and, while it may, comes back `requeueGap`
    /// cards later. True when it was put back in.
    static func requeue(_ index: Int, into order: inout [Int], after position: Int,
                        lapses: inout Set<Int>, counts: inout [Int: Int], repeatMissed: Bool) -> Bool {
        lapses.insert(index)
        guard repeatMissed, counts[index, default: 0] < maxRequeues else { return false }
        counts[index, default: 0] += 1
        order.insert(index, at: min(position + 1 + requeueGap, order.count))
        return true
    }

    /// Each card's first rating this session, so the breakdown adds up to the cards reviewed.
    /// Only Didn't know re-queues a card, so a lapsed card's first rating was Didn't know; every
    /// other card was rated exactly once (`last` holds a re-queued card's *last* rating).
    static func firstRatings(_ last: [Int: AnkiRating], lapses: Set<Int>) -> [Int: AnkiRating] {
        var first = last.filter { !lapses.contains($0.key) }
        for index in lapses { first[index] = .again }
        return first
    }

    /// Deal the cards in a fresh random order every session (Settings ▸ Cards; off by default).
    static let shuffleKey = "cards.shuffle"
    /// The card style a deck opens in (Settings ▸ Cards; Classic by default).
    static let flashcardStyleKey = "flashcardStyle"

    static func shuffle(_ defaults: UserDefaults = SharedDefaults.store) -> Bool {
        defaults.bool(forKey: shuffleKey)
    }

    static func flashcardStyle(_ defaults: UserDefaults = SharedDefaults.store) -> FlashcardStyle {
        FlashcardStyle(rawValue: defaults.string(forKey: flashcardStyleKey) ?? "") ?? .default
    }

    /// A Classic session's score: the cards it played, the ones marked known, the ones missed.
    static func classicTally(results: [Int: Bool], played: Int) -> (correct: Int, total: Int, missed: [Int]) {
        (results.values.filter { $0 }.count, played, results.filter { !$0.value }.map(\.key).sorted())
    }

    /// The session's score: every distinct card it set out to review, less the ones missed.
    static func tally(dueCount: Int, lapses: Set<Int>) -> (correct: Int, total: Int, missed: [Int]) {
        let missed = lapses.sorted()
        return (max(0, dueCount - missed.count), dueCount, missed)
    }
}

/// One session over a deck's cards (indices into the session's card list), rated with the four
/// Anki buttons, as iOS's player runs it.
nonisolated struct AnkiRound: Equatable {
    private(set) var order: [Int]
    private(set) var position = 0
    /// Distinct cards the session set out to review.
    let dueCount: Int
    private(set) var lapses: Set<Int> = []
    private var requeueCounts: [Int: Int] = [:]
    /// A card's latest rating (a re-queued card's is cleared until it comes back).
    private(set) var ratings: [Int: AnkiRating] = [:]

    init(order: [Int]) {
        self.order = order
        dueCount = order.count
    }

    /// The card on screen, or nil once the session is done.
    var current: Int? { order.indices.contains(position) ? order[position] : nil }
    var isFinished: Bool { current == nil }
    /// Cards left to show, returns included.
    var remaining: Int { max(0, order.count - position) }

    /// Rate the card on screen and move on. True when it was a miss that will come back.
    @discardableResult
    mutating func rate(_ rating: AnkiRating, repeatMissed: Bool) -> Bool {
        guard let index = current else { return false }
        ratings[index] = rating
        var requeued = false
        if rating == .again {
            requeued = AnkiSessionRules.requeue(index, into: &order, after: position, lapses: &lapses,
                                                counts: &requeueCounts, repeatMissed: repeatMissed)
            if requeued { ratings[index] = nil }
        }
        position += 1
        return requeued
    }

    var firstRatings: [Int: AnkiRating] { AnkiSessionRules.firstRatings(ratings, lapses: lapses) }
    var tally: (correct: Int, total: Int, missed: [Int]) { AnkiSessionRules.tally(dueCount: dueCount, lapses: lapses) }
}

/// A Classic session: every card once, in deck order (or shuffled), marked known or not.
nonisolated struct ClassicRound: Equatable {
    let order: [Int]
    private(set) var position = 0
    private(set) var results: [Int: Bool] = [:]

    init(order: [Int]) { self.order = order }

    var current: Int? { order.indices.contains(position) ? order[position] : nil }
    var isFinished: Bool { current == nil }

    mutating func answer(knewIt: Bool) {
        guard let index = current else { return }
        results[index] = knewIt
        position += 1
    }

    var tally: (correct: Int, total: Int, missed: [Int]) {
        AnkiSessionRules.classicTally(results: results, played: order.count)
    }
}

extension QuizResultRecord {
    /// A finished card session's result on its deck (iOS `DeckStore.saveQuizResult`). The
    /// ratings breakdown is kept for Anki sessions only, stored as iOS stores it.
    static func cardSession(deck: UUID, correct: Int, total: Int, missed: [Int], seconds: Int,
                            mode: FlashcardStyle, ankiRatings: [Int: AnkiRating]?, subDeckLabel: String?,
                            date: Date = Date(), id: UUID = UUID()) -> QuizResultRecord {
        var result = QuizResultRecord(id: id, deck: deck, date: date)
        result.totalCards = total
        result.correctCount = correct
        result.incorrectCardIndices = missed
        result.durationSeconds = seconds
        result.studyModeRaw = mode.rawValue
        result.subDeckLabel = subDeckLabel
        if mode == .anki, let ankiRatings {
            let raw: [Int: Int] = Dictionary(uniqueKeysWithValues: ankiRatings.map { ($0.key, $0.value.rawValue) })
            if let data = try? JSONEncoder().encode(raw) {
                result.ankiRatings = try? SyncJSON(data: data)
            }
        }
        return result
    }
}
