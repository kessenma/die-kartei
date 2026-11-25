//
//  WortschatzMergeService.swift
//  german-ai-flashcards
//
//  One-time merge of the per-level Goethe SRS decks ("A1 Vocabulary", "A2 Vocabulary",
//  "B1 Vocabulary", all `generatorRaw == "goethe-srs"`) into the single Wortschatz deck.
//
//  The Goethe lists are cumulative, so before the merge a word studied at A1 and again at A2 had
//  two unrelated SRS records. Afterwards it has one: the most advanced schedule any copy reached,
//  with the review and lapse counts of every copy added up, so no history is lost. The per-level
//  stats decks (`generatorRaw == "goethe"`) are untouched — the matching game still writes there.
//
//  Runs once, gated on `flagKey`, in the shape of `StudyTimeBackfillService`: the flag is set
//  before the pass so a crash can't loop it, and `run(in:)` is idempotent because the old decks
//  are gone once it finishes.
//

import Foundation
import SwiftData

enum WortschatzMergeService {

    static let flagKey = "wortschatz.merge.v1"

    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: flagKey) else { return }
        defaults.set(true, forKey: flagKey)
        run(in: context)
    }

    /// The merge itself, exposed for the developer re-run (`-wortschatz.debugMerge 1`).
    @discardableResult
    static func run(in context: ModelContext) -> String {
        let mergedTopic = DeckStore.wortschatzTopic
        let descriptor = FetchDescriptor<SavedDeck>(
            predicate: #Predicate { $0.generatorRaw == "goethe-srs" && $0.topic != mergedTopic }
        )
        let old = (try? context.fetch(descriptor)) ?? []
        guard !old.isEmpty else { return "nothing to merge" }

        let store = DeckStore(modelContext: context)
        guard let merged = store.fetchOrCreateWortschatzDeck() else { return "could not create the Wortschatz deck" }
        let byWord = Dictionary(merged.cards.map { ($0.germanWord, $0) }, uniquingKeysWith: { first, _ in first })

        // Group every old row by word — across decks, and within a deck for the few words the A1
        // list carries twice.
        let groups = Dictionary(grouping: old.flatMap(\.cards), by: \.germanWord)
        var mergedWords = 0
        var skipped = 0
        for (word, copies) in groups {
            guard let target = byWord[word] else { skipped += 1; continue }
            guard let base = copies.max(by: {
                ($0.interval, $0.repetitions, $0.totalReviews) < ($1.interval, $1.repetitions, $1.totalReviews)
            }) else { continue }
            target.easeFactor = base.easeFactor
            target.interval = base.interval
            target.repetitions = base.repetitions
            target.nextReviewDate = base.nextReviewDate
            target.totalReviews = copies.reduce(0) { $0 + $1.totalReviews }
            target.lapses = copies.reduce(0) { $0 + $1.lapses }
            target.leitnerBox = copies.map(\.leitnerBox).max() ?? 0
            mergedWords += 1
        }

        // Keep the review history: reparent results before the cascade delete can take them.
        var results = 0
        for deck in old {
            for result in deck.quizResults {
                result.deck = merged
                results += 1
            }
            deck.quizResults = []
            deck.pausedProgressData = nil
            deck.pausedAt = nil
        }
        try? context.save()
        for deck in old {
            context.delete(deck)
        }
        try? context.save()

        let summary = "merged \(mergedWords) words from \(old.count) decks, moved \(results) results, skipped \(skipped) words no longer listed"
        print("[wortschatz] \(summary)")
        return summary
    }
}
