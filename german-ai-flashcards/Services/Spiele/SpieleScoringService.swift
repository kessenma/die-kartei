//
//  SpieleScoringService.swift
//  german-ai-flashcards
//
//  Where a finished game goes. One funnel for all three Spiele.
//
//  Two deliberate limits, both about not overclaiming what a game proves:
//
//  - XP and time go into the room's **own** `StudyActivity.games` bucket, not `.cards`. The Today
//    screen reports `cardsReviewed` as flashcards reviewed, and a word game is not a flashcard
//    review; folding them together would inflate a number the learner reads as study.
//  - Words the learner failed on go to `LearnerMemoryService.noteVocabEncounters`, the rail for
//    weak evidence. They are words the app watched them struggle with, not words it watched them
//    fail to produce — a word search shows the answer the whole time.
//
//  Review credit (SM-2) and pyramid credit are opt-in and land with the per-word stats; see
//  docs/SPIELE.md.
//

import Foundation
import SwiftData

@MainActor
enum SpieleScoringService {

    /// Records a finished round. Safe to call with nothing solved — an abandoned round still
    /// banks the time the learner actually spent.
    static func record(_ result: SpieleRoundResult, in context: ModelContext) {
        guard result.attempted > 0 || result.durationSeconds > 0 else { return }

        StudyLogService.record(.games(result.solved), seconds: result.durationSeconds, in: context)

        // Only the words that beat them, and only as an encounter — no production claim.
        let missed = result.missedWords
        if !missed.isEmpty {
            LearnerMemoryService.noteVocabEncounters(
                missed.map { (german: $0.german, english: $0.english) },
                source: "spiel.\(result.kind.rawValue)",
                in: context
            )
        }
    }
}
