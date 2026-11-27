//
//  JobVocabCoverage.swift
//  german-ai-flashcards
//
//  How much of a job ad the learner's decks already cover: of the ad's words (basic words left
//  out, every use counted), the share that is a card somewhere, in any form („Kenntnissen“ counts
//  for a „die Kenntnis“ card). Shown on the posting as a readiness number, and used by the word
//  count to hide what is already in a deck.
//

import Foundation
import SwiftData

/// The words in the learner's decks, by spelling and by stem.
nonisolated struct JobVocabDeckWords: Sendable {
    /// `CardKind.matchKey` of every card.
    var keys: Set<String> = []
    /// `JobVocabTerm.key` shapes: „N:“ + stem for a capitalised word, the stem for the rest.
    var stemKeys: Set<String> = []

    init() {}

    init(germanWords: [String]) {
        for german in germanWords {
            keys.insert(CardKind.matchKey(german))
            let split = CardKind.split(german)
            guard !split.isPhrase else { continue }
            stemKeys.insert(Self.stemKey(split.word))
        }
    }

    static func stemKey(_ word: String) -> String {
        (word.first?.isUppercase == true ? "N:" : "") + GermanStem.stem(word)
    }

    var isEmpty: Bool { keys.isEmpty }

    /// A word or phrase of the count is in a deck: one of its spellings, or for a word its stem.
    func contains(_ term: JobVocabTerm) -> Bool {
        if !term.matchKeys.isDisjoint(with: keys) { return true }
        return !term.isPhrase && stemKeys.contains(term.key)
    }
}

extension JobVocabDeckWords {
    /// Every card of every deck a learner studies (not the Goethe or grammar bookkeeping decks).
    @MainActor
    static func from(_ decks: [SavedDeck]) -> JobVocabDeckWords {
        JobVocabDeckWords(germanWords: decks.filter(\.isBrowsableContent).flatMap { $0.cards.map(\.germanWord) })
    }

    @MainActor
    static func fetch(in context: ModelContext) -> JobVocabDeckWords {
        from((try? context.fetch(FetchDescriptor<SavedDeck>())) ?? [])
    }
}

nonisolated struct JobVocabCoverage: Equatable, Sendable {
    /// Of the ad's word uses, basic words left out, the share in a deck. 0…1.
    let share: Double
    /// Different words (not basic) that are in no deck yet.
    let missing: Int
    /// Different words, basic ones left out.
    let distinct: Int

    var percent: Int { Int((share * 100).rounded()) }

    static func of(_ sources: [JobVocabSource], deckWords: JobVocabDeckWords) -> JobVocabCoverage {
        of(JobVocabAnalyzer.words(in: sources), deckWords: deckWords)
    }

    static func of(_ words: [JobVocabTerm], deckWords: JobVocabDeckWords) -> JobVocabCoverage {
        let content = words.filter { !$0.isBasic }
        let total = content.reduce(0) { $0 + $1.total }
        let known = content.filter { deckWords.contains($0) }
        let covered = known.reduce(0) { $0 + $1.total }
        return JobVocabCoverage(
            share: total == 0 ? 0 : Double(covered) / Double(total),
            missing: content.count - known.count,
            distinct: content.count
        )
    }
}
