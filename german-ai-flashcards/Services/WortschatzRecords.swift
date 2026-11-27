import Foundation

/// The Wortschatz deck as records: the deck and card values iOS's
/// `DeckStore.fetchOrCreateWortschatzDeck` builds, for stores that keep records instead of
/// SwiftData rows (Android). `SyncGoldenTests` on iOS checks every card against that method.
///
/// One deck for all three levels, one card per exact headword in the merged Goethe index, ids
/// from `SyncSingletonDecks`, `sortOrder` = the word's index in `GoetheVocabService.orderedWords`.
/// Words without a translation get no card (iOS skips them too).
enum WortschatzRecords {
    static func deck(createdAt: Date = Date()) -> DeckRecord {
        DeckRecord.wortschatz(wordCount: GoetheVocabService.orderedWords.count, createdAt: createdAt)
    }

    /// The word's index in introduction order (A1, then what A2 adds, then B1's).
    static let sortOrder: [String: Int] = {
        var out: [String: Int] = [:]
        for (i, word) in GoetheVocabService.orderedWords.enumerated() { out[word.word] = i }
        return out
    }()

    /// A fresh, unreviewed card for a Goethe headword; nil for a word iOS has no card for.
    static func card(for germanWord: String) -> CardRecord? {
        guard let word = GoetheVocabService.index[germanWord], let order = sortOrder[germanWord] else { return nil }
        return card(for: word, sortOrder: order)
    }

    static func card(for word: GoetheWord, sortOrder: Int) -> CardRecord? {
        guard let translation = word.translation, !translation.isEmpty else { return nil }
        return CardRecord.wortschatz(word: word.word, translation: translation, wordType: word.rawWordType,
                                     article: word.article, example: word.example, sortOrder: sortOrder)
    }
}
