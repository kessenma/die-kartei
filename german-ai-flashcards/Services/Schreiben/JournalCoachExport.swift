//
//  JournalCoachExport.swift
//  german-ai-flashcards
//
//  The one path from a journal entry into the coach's memory, and it only runs when the learner
//  taps the button on the entry. Three things cross over, every one reviewable on the share
//  sheet first:
//
//  * **Corrected sentences → slips.** A one-word fix the tutor made and the learner left standing
//    ("mit meine Eltern" → "mit meinen Eltern") goes through `noteWrittenCorrections`, the same
//    rail as a graded story answer: cloze-ready, no self-heal pass, no session bump.
//  * **Words looked up → vocabulary.** `noteVocabEncounters`, tagged `MemorySource.journal`.
//  * **What they said they find hard → self-report notes.** `noteSelfReports`: the learner's own
//    words, read out of the entry by the tutor or typed by them, edited before they go.
//
//  `LearnerProfile.grammar` is never written (the pyramid reads it as earned fill; see
//  `PlacementCoachExport`), and the entry's `sharedWithCoachAt` is the high-water mark: the plan
//  offers only what is newer, so a second tap cannot inflate `timesSeen`.
//

import Foundation
import SwiftData

@MainActor
enum JournalCoachExport {

    struct Plan {
        var slips: [(original: String, corrected: String)] = []
        var words: [(german: String, english: String)] = []
        var notes: [SelfReportNote] = []

        var isEmpty: Bool { slips.isEmpty && words.isEmpty && notes.isEmpty }

        var buttonTitle: String {
            guard !isEmpty else { return "Nothing new to send" }
            var parts: [String] = []
            if !slips.isEmpty { parts.append("\(slips.count) sentence\(slips.count == 1 ? "" : "s")") }
            if !words.isEmpty { parts.append("\(words.count) word\(words.count == 1 ? "" : "s")") }
            if !notes.isEmpty { parts.append("\(notes.count) note\(notes.count == 1 ? "" : "s")") }
            let list = parts.count > 1
                ? parts.dropLast().joined(separator: ", ") + " and " + parts.last!
                : parts[0]
            return "Send \(list) to the coach"
        }
    }

    /// Everything the entry has that the coach has not seen: one-word fixes from a check made
    /// after the last hand-off, and words looked up since. Notes are the share sheet's to add.
    static func pendingPlan(for entry: JournalEntry) -> Plan {
        var plan = Plan()
        let since = entry.sharedWithCoachAt ?? .distantPast
        if let check = entry.check, (entry.checkedAt ?? check.checkedAt) > since {
            var seen = Set<String>()
            for sentence in check.sentences where sentence.outcome == .fix {
                guard let corrected = sentence.corrected,
                      LearnerMemoryService.singleTokenDiff(sentence.original, corrected) != nil,
                      seen.insert(corrected.lowercased()).inserted else { continue }
                plan.slips.append((original: sentence.original, corrected: corrected))
            }
        }
        var seenWords = Set<String>()
        for lookup in entry.lookups where lookup.at > since {
            guard seenWords.insert(lookup.id).inserted else { continue }
            plan.words.append((german: lookup.german, english: lookup.english))
        }
        return plan
    }

    /// Writes the plan and moves the high-water mark. Returns a line for the screen.
    @discardableResult
    static func send(_ plan: Plan, for entry: JournalEntry, in context: ModelContext) -> String {
        guard !plan.isEmpty else { return "" }
        LearnerMemoryService.noteWrittenCorrections(plan.slips, in: context)
        LearnerMemoryService.noteVocabEncounters(plan.words, source: MemorySource.journal, in: context)
        LearnerMemoryService.noteSelfReports(plan.notes.map { note in
            var n = note
            n.entryID = entry.id
            n.source = MemorySource.journal
            return n
        }, in: context)
        entry.sharedWithCoachAt = .now
        entry.touch()
        try? context.save()
        return "Sent. The coach reads this before your next conversation."
    }
}
