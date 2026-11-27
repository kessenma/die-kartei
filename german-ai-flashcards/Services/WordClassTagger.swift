//
//  WordClassTagger.swift
//  german-ai-flashcards
//
//  Runs `WordClassInference` over a list of rows without blocking the list that is drawing them.
//
//  The dictionary lookup stays on the main actor: `WiktionaryValidator` is not thread-safe (mutable
//  caches, one set of prepared statements reused with `sqlite3_reset`, opened `SQLITE_OPEN_NOMUTEX`),
//  which `NounGenderTinter` documents for the same reason. So the work is cut into chunks with a
//  yield between them — the rows keep drawing, and the tags appear a handful at a time.
//
//  Results come back as `[UUID: WordClass]` deltas rather than a rebuilt row array, so a batch
//  landing while the learner is typing cannot overwrite what they typed.
//

import Foundation
import Observation

@MainActor
@Observable
final class WordClassTagger {
    private(set) var isRunning = false

    /// Tags every row that has no class yet, calling `onBatch` after each chunk. Rows that already
    /// carry one are skipped, so a tag the learner corrected by hand is never overwritten.
    func tag(_ rows: [VocabListRow], chunk: Int = 20,
             onBatch: @MainActor ([UUID: WordClass]) -> Void) async {
        // A phrase has no word class: its first word would decide it ("gute Kenntnisse" → adjective),
        // and `DocumentDeckService.merge` tags it a phrase anyway.
        let pending = rows.filter {
            $0.wordClass == nil && !$0.german.trimmingCharacters(in: .whitespaces).isEmpty
                && !CardKind.isPhrase($0.german)
        }
        guard !pending.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }

        var batch: [UUID: WordClass] = [:]
        for (index, row) in pending.enumerated() {
            let pos = WordClassInference.headword(row.german)
                .flatMap { WiktionaryValidator.shared.partsOfSpeech(of: $0) }
            if let wordClass = WordClassInference.classify(german: row.german, english: row.english,
                                                          partsOfSpeech: pos) {
                batch[row.id] = wordClass
            }
            if (index + 1) % chunk == 0 {
                if !batch.isEmpty { onBatch(batch); batch = [:] }
                await Task.yield()
                if Task.isCancelled { return }
            }
        }
        if !batch.isEmpty { onBatch(batch) }
    }
}
