import Foundation
import OSLog
import SwiftData

/// Gives rows that exist once per learner (the Wortschatz deck, the stats and SRS decks, their
/// cards) the ids every device derives from the same name. Two devices then hold the same records
/// instead of two copies that `.first` picks between at random.
///
/// New rows get these ids at creation (`DeckStore`). This pass fixes rows made before that, and
/// folds any duplicates a device already had. It runs once per store, before the first sync scan,
/// and writes as an ordinary local change. Any fold's deletes are tracked like any other delete.
@MainActor
enum SyncCanonicalizer {
    /// Bump to run the pass again after adding a canonical kind.
    /// 2: exact-word card ids (1 lowercased them) and one StudyDay row per date.
    static let version = 2
    private static let log = Logger(subsystem: "kyle-essenmacher.german-ai-flashcards", category: "sync")

    static func runIfNeeded(in context: ModelContext) {
        let meta = SyncStoreMeta.meta(in: context)
        guard meta.canonicalizedVersion < version else { return }
        let synced = Set(SyncStoreMeta.allStates(in: context).map(\.recordName))
        var changes = 0

        let generators = Array(SyncSingletonDecks.generators)
        let decks = (try? context.fetch(FetchDescriptor<SavedDeck>(
            predicate: #Predicate { generators.contains($0.generatorRaw) }
        ))) ?? []
        let groups = Dictionary(grouping: decks) { "\($0.generatorRaw)\u{1F}\($0.topic)" }

        for group in groups.values {
            guard let first = group.first else { continue }
            let canonical = SyncSingletonDecks.deckID(generatorRaw: first.generatorRaw, topic: first.topic)
            // Keep the canonical one if present, else the deck with the most progress.
            let keeper = group.first { $0.id == canonical }
                ?? group.max { reviewed($0) < reviewed($1) }!
            for extra in group where extra !== keeper {
                fold(extra, into: keeper, in: context)
                changes += 1
            }
            if keeper.id != canonical, !synced.contains(SyncRecordName(kind: "SavedDeck", id: keeper.id).description) {
                keeper.id = canonical
                changes += 1
            }
            changes += canonicalizeCards(of: keeper, synced: synced, in: context)
        }

        changes += foldStudyDayTwins(in: context)

        meta.canonicalizedVersion = version
        try? context.save()
        if changes > 0 { log.notice("Canonicalized \(changes) singleton deck/card ids") }
    }

    /// One card per German word, each with its canonical id. Duplicates keep the most advanced
    /// schedule, the same rule `fetchOrCreateWortschatzDeck` uses.
    private static func canonicalizeCards(of deck: SavedDeck, synced: Set<String>, in context: ModelContext) -> Int {
        var changes = 0
        var byWord: [String: SavedCard] = [:]
        for card in deck.cards.sorted(by: { ($1.interval, $1.repetitions) < ($0.interval, $0.repetitions) }) {
            let word = card.germanWord  // exact: sie and Sie are two cards
            if byWord[word] != nil {
                context.delete(card)
                changes += 1
                continue
            }
            byWord[word] = card
            let canonical = SyncSingletonDecks.cardID(deckID: deck.id, germanWord: card.germanWord)
            if card.id != canonical, !synced.contains(SyncRecordName(kind: "SavedCard", id: card.id).description) {
                card.id = canonical
                changes += 1
            }
        }
        return changes
    }

    /// One StudyDay per calendar date. A time-zone change used to start a second row for the same
    /// date; both map to one sync record, so fold them: counts add, the latest activity wins.
    private static func foldStudyDayTwins(in context: ModelContext) -> Int {
        let days = (try? context.fetch(FetchDescriptor<StudyDay>(sortBy: [SortDescriptor(\.dayStart)]))) ?? []
        var changes = 0
        for group in Dictionary(grouping: days, by: { SyncDayKey.key(for: $0.dayStart) }).values where group.count > 1 {
            let keeper = group[0]
            for twin in group.dropFirst() {
                keeper.cardsReviewed += twin.cardsReviewed
                keeper.grammarExercises += twin.grammarExercises
                keeper.conversations += twin.conversations
                keeper.storySeconds += twin.storySeconds
                keeper.storyQuestions += twin.storyQuestions
                keeper.cardSeconds += twin.cardSeconds
                keeper.grammarSeconds += twin.grammarSeconds
                keeper.conversationSeconds += twin.conversationSeconds
                keeper.storyQuizSeconds += twin.storyQuizSeconds
                keeper.newWordsIntroduced += twin.newWordsIntroduced
                keeper.newWordsBonus += twin.newWordsBonus
                keeper.lastActivityAt = max(keeper.lastActivityAt, twin.lastActivityAt)
                context.delete(twin)
                changes += 1
            }
        }
        return changes
    }

    /// Move a duplicate deck's progress into the keeper, then delete it.
    private static func fold(_ extra: SavedDeck, into keeper: SavedDeck, in context: ModelContext) {
        var keeperWords = Dictionary(keeper.cards.map { ($0.germanWord, $0) }, uniquingKeysWith: { a, _ in a })
        for card in extra.cards {
            let word = card.germanWord
            if let existing = keeperWords[word] {
                if (card.interval, card.repetitions) > (existing.interval, existing.repetitions) {
                    existing.easeFactor = card.easeFactor
                    existing.interval = card.interval
                    existing.repetitions = card.repetitions
                    existing.nextReviewDate = card.nextReviewDate
                    existing.leitnerBox = card.leitnerBox
                    existing.lastReviewedAt = card.lastReviewedAt
                    existing.lastReviewWasCorrect = card.lastReviewWasCorrect
                }
                existing.totalReviews += card.totalReviews
                existing.lapses += card.lapses
                if let first = card.firstReviewedAt, first < (existing.firstReviewedAt ?? .distantFuture) {
                    existing.firstReviewedAt = first
                }
            } else {
                card.deck = keeper
                keeperWords[word] = card
            }
        }
        for result in extra.quizResults { result.deck = keeper }
        context.delete(extra)
    }

    private static func reviewed(_ deck: SavedDeck) -> Int {
        deck.cards.reduce(0) { $0 + $1.totalReviews }
    }
}
