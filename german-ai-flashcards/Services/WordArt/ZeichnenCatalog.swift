import Foundation
import SwiftData

/// One word the Zeichnen room can draw: a card, flattened. Value type, so screens snapshot the
/// store once and never read `@Model` cards in `body` (the `@Query` body loop, docs/MEMORY.md).
struct ZeichnenWord: Identifiable, Hashable, Sendable {
    /// The card's id.
    let id: UUID
    let word: GameWord
    let deckID: UUID
    let deckTitle: String

    /// „die Blume“.
    var display: String { word.display }
    var english: String { word.english }
    var key: String { WordArtKey.make(word.german) }
}

/// Where a Quick Draw run's words come from.
enum QuickDrawSource: Hashable {
    /// The coach's pick: the words that most need practice, across every deck.
    case weak
    /// One or more decks.
    case decks(Set<UUID>)
    /// A saved Quick Draw set.
    case set(UUID)
}

/// Reads the store once into `ZeichnenWord`s, and picks words for a run.
@MainActor
enum ZeichnenCatalog {

    /// Every card in every deck, Wortschatz included.
    static func allWords(in context: ModelContext) -> [ZeichnenWord] {
        let decks = (try? context.fetch(FetchDescriptor<SavedDeck>())) ?? []
        return decks.flatMap { deck in
            deck.cards
                .sorted { $0.sortOrder < $1.sortOrder }
                .compactMap { card -> ZeichnenWord? in
                    guard let word = GameWord(card, deckID: deck.id) else { return nil }
                    return ZeichnenWord(id: card.id, word: word, deckID: deck.id, deckTitle: deck.topic)
                }
        }
    }

    /// The decks with at least one card, for a picker: id, title, card count.
    struct DeckRow: Identifiable, Hashable {
        let id: UUID
        let title: String
        let count: Int
    }

    static func deckRows(in context: ModelContext) -> [DeckRow] {
        let decks = (try? context.fetch(FetchDescriptor<SavedDeck>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return decks.compactMap { deck in
            let count = deck.cards.count
            return count > 0 ? DeckRow(id: deck.id, title: deck.topic, count: count) : nil
        }
    }

    /// The words for a run from `source`, at most `limit`, in play order.
    static func words(for source: QuickDrawSource, limit: Int, in context: ModelContext) -> [ZeichnenWord] {
        switch source {
        case .weak:
            return weakest(limit, in: context)
        case .decks(let ids):
            let words = allWords(in: context).filter { ids.contains($0.deckID) }
            return Array(dedupe(words).shuffled().prefix(limit))
        case .set(let id):
            var d = FetchDescriptor<QuickDrawSet>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            guard let set = (try? context.fetch(d))?.first else { return [] }
            let byID = Dictionary(allWords(in: context).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // Cards that are gone are skipped; the set keeps them in case they come back by sync.
            return Array(set.cardIDs.compactMap { byID[$0] }.prefix(limit))
        }
    }

    /// The coach's pick: cards ranked by `SchreibblattPractice`'s "Braucht Übung" lens, keeping
    /// only words with a reason (a lapse, a wrong last answer, overdue, game misses). A learner
    /// with no history gets fewer words, never random ones dressed up as weak.
    static func weakest(_ limit: Int, in context: ModelContext) -> [ZeichnenWord] {
        let decks = (try? context.fetch(FetchDescriptor<SavedDeck>())) ?? []
        var byID: [UUID: ZeichnenWord] = [:]
        var facts: [SchreibblattPractice.CardFacts] = []
        for deck in decks {
            for card in deck.cards {
                guard let word = GameWord(card, deckID: deck.id) else { continue }
                byID[card.id] = ZeichnenWord(id: card.id, word: word, deckID: deck.id, deckTitle: deck.topic)
                facts.append(SchreibblattPractice.CardFacts(
                    id: card.id,
                    german: card.germanWord.withArticle(card.article),
                    english: card.englishTranslation,
                    deckID: deck.id,
                    deckTitle: deck.topic,
                    deckCreatedAt: deck.createdAt,
                    sortOrder: card.sortOrder,
                    lapses: card.lapses,
                    repetitions: card.repetitions,
                    interval: card.interval,
                    lastReviewWasCorrect: card.lastReviewWasCorrect,
                    lastReviewedAt: card.lastReviewedAt,
                    nextReviewDate: card.nextReviewDate
                ))
            }
        }
        let articleStats = ((try? context.fetch(FetchDescriptor<ArticleWordStat>())) ?? []).map {
            SchreibblattPractice.StatFacts(key: SchreibblattPractice.joinKey($0.key), timesMissed: $0.timesMissed,
                                           lastMissedAt: $0.lastMissedAt, isTricky: $0.isTricky)
        }
        let pairStats = ((try? context.fetch(FetchDescriptor<MatchingPairStat>())) ?? []).map {
            SchreibblattPractice.StatFacts(key: SchreibblattPractice.joinKey($0.german), timesMissed: $0.timesMissed,
                                           lastMissedAt: $0.lastMissedAt, isTricky: $0.isTricky)
        }
        let ranked = SchreibblattPractice.ordered(
            SchreibblattPractice.candidates(cards: facts, articleStats: articleStats, pairStats: pairStats),
            by: .uebung
        )
        let needy = ranked.filter { $0.score > 0 }.compactMap { byID[$0.id] }
        return Array(dedupe(needy).prefix(limit))
    }

    /// One card per word: the same word in two decks is drawn once.
    static func dedupe(_ words: [ZeichnenWord]) -> [ZeichnenWord] {
        var seen = Set<String>()
        return words.filter { seen.insert($0.key).inserted }
    }
}
