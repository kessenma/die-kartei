//
//  SchreibblattPractice.swift
//  german-ai-flashcards
//
//  Which words a writing sheet offers, and in what order. Every card on the device, shown four
//  ways: newest first, grouped by deck, alphabetical, and ranked by how much practice it looks
//  like it needs.
//
//  **A lens is a permutation, not a filter.** All four return the same set of candidates in a
//  different order, which is what lets the selection screen keep every tick when the learner
//  switches lens or types in the search field. Searching narrows the rows on screen, never the
//  selection. `SchreibblattPracticeTests` asserts this.
//
//  **The ranking is a sort, not a cutoff.** Every card with any signal is in the list, carrying
//  its reasons *and their counts* so a row can say why it is near the top — the number is evidence
//  shown to the learner, not a threshold applied behind their back. Deliberately not reusing
//  `WortschatzService.isDifficult`, which ANDs in `!isKnown` and needs two misses before it says
//  anything: right for a filter chip, wrong here, because it hides a word that was known three
//  weeks ago and has since been forgotten. `isKnown` only de-emphasizes.
//
//  Everything below takes plain value structs rather than `@Model` types. Two reasons: a filtered
//  `@Query` whose cards are read in `body` re-renders forever once the screen is pushed, and this
//  is the app's largest list, so the screen snapshots once on appear and sorts the snapshot; and
//  `PyramidService.refutedWords` takes model arrays, which is exactly why it has no test.
//
//  See docs/SCHREIBBLATT.md.
//

import Foundation

nonisolated enum SchreibblattPractice {

    // MARK: - Facts

    /// One card, flattened. `german` is the display form with its article, as the sheet prints it.
    struct CardFacts: Identifiable, Hashable, Sendable {
        var id: UUID
        var german: String
        var english: String
        var deckID: UUID
        var deckTitle: String
        /// `SavedDeck.createdAt`. With `sortOrder` it stands in for a card's own added-at date,
        /// which `SavedCard` does not have — see `Lens.neu`.
        var deckCreatedAt: Date
        var sortOrder: Int

        var lapses: Int = 0
        var repetitions: Int = 0
        var interval: Int = 0
        var lastReviewWasCorrect: Bool? = nil
        var lastReviewedAt: Date? = nil
        var nextReviewDate: Date? = nil

        /// Anki's maturity bar, the same test `WortschatzService.isKnown` makes.
        var isKnown: Bool {
            interval >= PyramidService.matureIntervalDays
                || repetitions >= PyramidService.provenRepetitions
        }
    }

    /// A game's per-word record, flattened. One shape for both `MatchingPairStat` and
    /// `ArticleWordStat`, because the ranking wants the same three things from each.
    struct StatFacts: Hashable, Sendable {
        /// Already normalized with `joinKey(_:)`.
        var key: String
        var timesMissed: Int
        var lastMissedAt: Date?
        var isTricky: Bool
    }

    // MARK: - Why a word is in the list

    enum Reason: Hashable, Sendable {
        /// Rated "Again" this many times.
        case lapsed(Int)
        case lastAnswerWrong
        case dueNow(daysOverdue: Int)
        case matchingMisses(Int)
        case articleMisses(Int)
        /// No signal at all. Keeps the lens from being an empty screen on a fresh install, and
        /// still explains the row rather than leaving it unaccounted for.
        case neverPractised

        /// An ordering hint, not a cutoff. Nothing is excluded by these numbers; they only decide
        /// which rows reach the top, so they are safe to nudge once the lens has seen real use.
        var weight: Int {
            switch self {
            case .lapsed(let times): 30 + 10 * min(times, 5)
            case .lastAnswerWrong: 25
            case .dueNow(let days): 5 + min(days, 30)
            case .matchingMisses(let times): 8 * min(times, 5)
            case .articleMisses(let times): 8 * min(times, 5)
            case .neverPractised: 0
            }
        }

        /// What the row says under the word. German identity word, plain English after it.
        var label: String {
            switch self {
            case .lapsed(let times): times == 1 ? "forgotten once" : "forgotten \(times)×"
            case .lastAnswerWrong: "last answer was wrong"
            case .dueNow(let days): days <= 0 ? "due now" : "overdue by \(days)d"
            case .matchingMisses(let times): "missed in Zuordnen \(times)×"
            case .articleMisses(let times): "article wrong \(times)×"
            case .neverPractised: "not practised yet"
            }
        }
    }

    struct Candidate: Identifiable, Hashable, Sendable {
        var id: UUID
        var word: SchreibblattWord
        var deckID: UUID
        var deckTitle: String
        var deckCreatedAt: Date
        var sortOrder: Int
        /// Heaviest first, which is the order a row prints them in.
        var reasons: [Reason]
        var isKnown: Bool
        /// The most recent sign of trouble, for the tie-break.
        var lastTrouble: Date?

        var score: Int { reasons.reduce(0) { $0 + $1.weight } }
        var detail: String { reasons.map(\.label).joined(separator: " · ") }
        /// German without its leading article, which is what `A–Z` sorts on.
        var sortName: String { ArticleGameService.bareNoun(word.german) }
    }

    // MARK: - The join

    /// The one key all three sources can share.
    ///
    /// `ArticleGameService.key(for:)` alone is not enough: it lowercases and trims but keeps a
    /// leading article, and `MatchingPairStat.german` carries one on cards that bake it into
    /// `germanWord` — `MatchingGameView` stores `card.germanWord` verbatim, despite the model's
    /// own comment claiming otherwise. `WortschatzBrowseView.Lookup` gets away without `bareNoun`
    /// because a `GoetheWord` is bare by construction; arbitrary cards are not.
    static func joinKey(_ german: String) -> String {
        ArticleGameService.key(for: ArticleGameService.bareNoun(german))
    }

    /// Fold several rows that share a headword into one: the trickiest wins, then the most-missed.
    /// The same rule `WortschatzBrowseView.Lookup` uses, since one word can own a pair row per
    /// translation.
    static func index(_ stats: [StatFacts]) -> [String: StatFacts] {
        Dictionary(stats.map { ($0.key, $0) }) { a, b in
            if a.isTricky != b.isTricky { return a.isTricky ? a : b }
            return a.timesMissed >= b.timesMissed ? a : b
        }
    }

    // MARK: - Candidates

    /// Every card, with whatever the three sources know about it. The base set every lens orders;
    /// nothing is filtered out here.
    static func candidates(
        cards: [CardFacts],
        articleStats: [StatFacts] = [],
        pairStats: [StatFacts] = [],
        now: Date = Date()
    ) -> [Candidate] {
        let articles = index(articleStats)
        let pairs = index(pairStats)

        return cards.map { card in
            let key = joinKey(card.german)
            let article = articles[key]
            let pair = pairs[key]

            var reasons: [Reason] = []
            if card.lapses > 0 { reasons.append(.lapsed(card.lapses)) }
            if card.lastReviewWasCorrect == false { reasons.append(.lastAnswerWrong) }
            if let due = card.nextReviewDate, due <= now {
                let days = Int(now.timeIntervalSince(due) / 86_400)
                reasons.append(.dueNow(daysOverdue: max(0, days)))
            }
            if let pair, pair.timesMissed > 0 { reasons.append(.matchingMisses(pair.timesMissed)) }
            if let article, article.timesMissed > 0 {
                reasons.append(.articleMisses(article.timesMissed))
            }
            if reasons.isEmpty { reasons.append(.neverPractised) }
            reasons.sort { $0.weight > $1.weight }

            let trouble = [card.lastReviewedAt, pair?.lastMissedAt, article?.lastMissedAt]
                .compactMap(\.self).max()

            return Candidate(
                id: card.id,
                word: SchreibblattWord(id: card.id, german: card.german, english: card.english),
                deckID: card.deckID,
                deckTitle: card.deckTitle,
                deckCreatedAt: card.deckCreatedAt,
                sortOrder: card.sortOrder,
                reasons: reasons,
                isKnown: card.isKnown,
                lastTrouble: trouble
            )
        }
    }

    // MARK: - Lenses

    enum Lens: String, CaseIterable, Identifiable, Sendable {
        case neu, deck, alphabet, uebung

        var id: String { rawValue }

        /// The chip. German, like the rest of the app's headings.
        var title: String {
            switch self {
            case .neu: "Neu"
            case .deck: "Deck"
            case .alphabet: "A–Z"
            case .uebung: "Braucht Übung"
            }
        }

        /// What a row's second line says in this lens. Only `Braucht Übung` explains itself; the
        /// others would just repeat their own sort key on every row.
        var showsReasons: Bool { self == .uebung }

        /// Whether rows are grouped under headings, which is also what gives the `Deck` lens its
        /// select-the-whole-deck toggle.
        var isGrouped: Bool { self == .deck || self == .alphabet }
    }

    /// The same candidates, reordered. Never filtered — see the note at the top of the file.
    static func ordered(_ candidates: [Candidate], by lens: Lens) -> [Candidate] {
        switch lens {
        case .neu:
            // `SavedCard` has no added-at date, so a card's deck's age plus its position within
            // that deck stands in: exact for cards that arrived with their deck, close enough for
            // ones appended later. A real `addedAt` would cost a `SavedCardCodec` change.
            candidates.sorted {
                if $0.deckCreatedAt != $1.deckCreatedAt { return $0.deckCreatedAt > $1.deckCreatedAt }
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder > $1.sortOrder }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .deck:
            candidates.sorted {
                if $0.deckCreatedAt != $1.deckCreatedAt { return $0.deckCreatedAt > $1.deckCreatedAt }
                if $0.deckID != $1.deckID { return $0.deckID.uuidString < $1.deckID.uuidString }
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .alphabet:
            candidates.sorted {
                let left = $0.sortName.localizedCaseInsensitiveCompare($1.sortName)
                if left != .orderedSame { return left == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
        case .uebung:
            candidates.sorted {
                // Known words sink: a word proven three weeks ago is worth less of the page than
                // one still being learned, but it is never hidden.
                if $0.isKnown != $1.isKnown { return !$0.isKnown }
                if $0.score != $1.score { return $0.score > $1.score }
                // The same tie-break `MatchingStatsService.trickyPairs` uses: most recent trouble.
                switch ($0.lastTrouble, $1.lastTrouble) {
                case let (a?, b?) where a != b: return a > b
                case (nil, _?): return false
                case (_?, nil): return true
                default: break
                }
                let name = $0.sortName.localizedCaseInsensitiveCompare($1.sortName)
                if name != .orderedSame { return name == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    /// The heading a row sits under in a grouped lens, or nil when the lens is flat.
    static func group(for candidate: Candidate, lens: Lens) -> String? {
        switch lens {
        case .deck: candidate.deckTitle
        case .alphabet: String(candidate.sortName.prefix(1)).uppercased(with: Locale(identifier: "de_DE"))
        case .neu, .uebung: nil
        }
    }

    // MARK: - Search

    /// The rows worth showing for `search`. This narrows what is *visible*; the caller's selection
    /// is untouched, so a ticked word that the query does not match stays ticked.
    static func matching(_ candidates: [Candidate], search: String) -> [Candidate] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.word.german.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.word.english.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
