//
//  PlacementCoachExport.swift
//  german-ai-flashcards
//
//  The one path from the placement check into the coach's memory — and it only ever runs when the
//  learner taps the button on the review screen.
//
//  ## What this may and may not touch
//
//  `LearnerProfile.grammar` is **off limits**, and not for philosophical reasons.
//  `PyramidService` counts a focus toward the pyramid's *earned* fill once its struggle sits below
//  `GrammarSkill.shakyThreshold`, and it skips *provisional* credit for any focus already present in
//  the profile. So writing a grammar key here would let a three-minute quiz complete a pyramid layer
//  (confetti included) and simultaneously shrink the very outline the quiz produced. Estimated and
//  earned have to stay separate channels, and the way to keep them separate is to never write there.
//
//  `.vocab` and `.slips` are read by neither pyramid channel, so they're safe — and they're where
//  this belongs anyway: only the *misses* cross over, never the level estimate. The coach learns
//  what the learner got wrong, and nothing about what the app guessed they are.
//
//  ## How each block maps
//
//  * **Words, der/die/das, prepositions → vocabulary.** All three are 3-or-4-option recognition, the
//    same signal the matching game and article game hand over (Phases 5/8/10), which the learner
//    model treats as "a word they're building" rather than a production slip.
//  * **Grammar and cloze → slips**, tagged `MemorySource.placement`. These are the one part of the
//    probe where the learner picked a specific wrong *form* inside a sentence, which is what a slip
//    is. The tag keeps them in their own id namespace (so they can't overwrite a sentence the
//    learner actually wrote) and keeps them out of `correctionHint` (so an authored distractor is
//    never fed back as a mistake they made).
//

import Foundation
import SwiftData

@MainActor
enum PlacementCoachExport {

    /// The gap marker used throughout `placement_grammar.json`.
    private static let gapMarker = "______"

    /// Only attempts finished after this have anything left to give.
    private static let highWaterKey = "placement.handoff.lastAttemptAt"

    // MARK: - Plan

    /// What a hand-off would write, worked out before anything is written so the button can say so.
    struct Plan {
        var words: [(german: String, english: String)] = []
        var slips: [LexicalSlip] = []
        /// The newest attempt this plan covers — the new high-water mark once it's sent.
        var throughDate: Date?
        /// How many checks contributed.
        var checkCount: Int = 0

        var isEmpty: Bool { words.isEmpty && slips.isEmpty }

        var buttonTitle: String {
            guard !isEmpty else { return "Everything's been sent" }
            var parts: [String] = []
            if !words.isEmpty { parts.append("\(words.count) word\(words.count == 1 ? "" : "s")") }
            if !slips.isEmpty { parts.append("\(slips.count) sentence\(slips.count == 1 ? "" : "s")") }
            return "Send \(parts.joined(separator: " and ")) to the coach"
        }
    }

    /// What's left to hand over: everything missed in checks the learner hasn't sent yet.
    ///
    /// The high-water mark matters because both `note*` entry points merge by id, so a second tap
    /// with no new data wouldn't duplicate anything — it would quietly inflate `timesSeen`, which
    /// reads as "they missed this again" when they didn't.
    static func pendingPlan(in attempts: [PlacementAttempt]) -> Plan {
        let sent = UserDefaults.standard.object(forKey: highWaterKey) as? Date
        let fresh = attempts.filter { attempt in
            guard !attempt.records.isEmpty else { return false }
            guard let sent else { return true }
            return attempt.takenAt > sent
        }
        var plan = plan(for: fresh)
        plan.checkCount = fresh.count
        plan.throughDate = fresh.map(\.takenAt).max()
        return plan
    }

    /// The misses in a set of attempts, mapped to what the coach can use. Pure — writes nothing.
    static func plan(for attempts: [PlacementAttempt]) -> Plan {
        var plan = Plan()
        var seenWords = Set<String>()
        var seenSlips = Set<String>()

        for record in attempts.flatMap(\.records) where !record.isCorrect {
            switch record.block {
            case .vocab, .gender, .preposition:
                guard let word = word(from: record), seenWords.insert(word.german.lowercased()).inserted else { continue }
                plan.words.append(word)
            case .grammar, .cloze:
                guard let slip = slip(from: record), seenSlips.insert(slip.id).inserted else { continue }
                plan.slips.append(slip)
            }
        }
        return plan
    }

    // MARK: - Send

    /// Writes the plan and advances the high-water mark. Returns a line for the screen to show.
    @discardableResult
    static func send(_ plan: Plan, in context: ModelContext) -> String {
        guard !plan.isEmpty else { return "" }

        LearnerMemoryService.noteVocabEncounters(
            plan.words,
            source: MemorySource.placement,
            in: context
        )
        LearnerMemoryService.noteSlips(plan.slips, in: context)
        try? context.save()

        if let throughDate = plan.throughDate {
            UserDefaults.standard.set(throughDate, forKey: highWaterKey)
        }

        var parts: [String] = []
        if !plan.words.isEmpty { parts.append("\(plan.words.count) in “Words you're building”") }
        if !plan.slips.isEmpty { parts.append("\(plan.slips.count) in “Slip-ups it's watching”") }
        return "Sent — " + parts.joined(separator: ", ") + "."
    }

#if DEBUG
    /// Lets a debug run hand over the same material twice.
    static func resetHighWaterMark() {
        UserDefaults.standard.removeObject(forKey: highWaterKey)
    }

    /// `-placement.debugVerify 1` — runs the hand-off and dumps the export beside `attempts.json`.
    ///
    /// Both actions sit behind buttons that a simulator can't press, and both are exactly what has
    /// to be checked after touching this file: the hand-off is the only code path that can move a
    /// pyramid number it must not move, and the export is the only one that leaves the device.
    /// Returns a one-line summary for the run log.
    @discardableResult
    static func runDebugVerification(in context: ModelContext) -> String {
        let attempts = PlacementAttemptStore.attempts()
        let plan = pendingPlan(in: attempts)
        let sent = send(plan, in: context)

        if let document = PlacementExport.document(
            attempts: attempts,
            visible: attempts.flatMap { attempt in
                attempt.records.enumerated().map { index, record in
                    PlacementReviewItem(
                        attemptID: attempt.id,
                        attemptAt: attempt.takenAt,
                        index: index,
                        record: record
                    )
                }
            },
            filter: PlacementReviewFilter()
        ) {
            let url = URL.applicationSupportDirectory
                .appendingPathComponent("Placement")
                .appendingPathComponent("export-preview.json")
            try? document.data.write(to: url, options: .atomic)
        }

        return "[placement] handoff: \(plan.words.count) words, \(plan.slips.count) slips — \(sent)"
    }
#endif

    // MARK: - Mapping

    private static func word(from record: PlacementRecord) -> (german: String, english: String)? {
        let german = record.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !german.isEmpty else { return nil }
        switch record.block {
        case .vocab:
            // The correct choice *is* the translation.
            return (german: german, english: record.correctChoice)
        case .gender, .preposition:
            // The gender block's prompt is the bare noun, never "die Lampe" — `VocabTouch.id` is
            // the lowercased German, so an articled form would never merge with the same word met
            // in the matching game and Coach's Notes would grow a duplicate.
            return (german: german, english: record.subtitle ?? "")
        default:
            return nil
        }
    }

    private static func slip(from record: PlacementRecord) -> LexicalSlip? {
        let right = record.correctChoice
        guard !right.isEmpty else { return nil }
        // A skipped item has no wrong form — the learner never claimed anything. Recording one
        // would put a word in their mouth.
        guard let wrong = record.chosenChoice, wrong != right else { return nil }

        let cloze = clozeSeed(for: record, answer: right)
        return LexicalSlip(
            wrong: wrong,
            right: right,
            note: note(for: record),
            lastSeen: Date(),
            timesSeen: 1,
            sentence: cloze?.sentence,
            blankIndex: cloze?.index,
            source: MemorySource.placement
        )
    }

    /// The sentence with the gap filled, plus the word index of the answer — what makes a slip
    /// `isClozeReady` and so drillable from Coach's Notes' "Fix your sentences".
    ///
    /// Nil for the four bank items whose answer is two words (`"krank bin"`, `"auf dem"`,
    /// `"an die"`, `"fahre ich"` — the first of which is an anchor, so it appears in *every* run).
    /// `blankIndex` addresses one token, so a two-word answer would build a card that hides half of
    /// itself. Leaving both nil is a supported state: the slip still reaches the coach and still
    /// shows in Coach's Notes, it just isn't drillable — exactly how `LexicalSlip` already handles
    /// corrections that weren't single-word swaps.
    private static func clozeSeed(for record: PlacementRecord, answer: String) -> (sentence: String, index: Int)? {
        guard !answer.contains(" ") else { return nil }

        let (template, marker): (String, String) = switch record.block {
        case .grammar: (PlacementGrammarBank.item(id: record.sourceID ?? "")?.sentence ?? "", gapMarker)
        case .cloze:   (record.context ?? "", ClozeCard.blank)
        default:       ("", gapMarker)
        }
        guard !template.isEmpty, template.contains(marker) else { return nil }

        // Locate the gap by position in the template rather than by searching the filled sentence:
        // the answer word can legitimately occur earlier in the sentence, and matching on text
        // would blank the wrong one.
        let tokens = template.split(separator: " ").map(String.init)
        guard let index = tokens.firstIndex(where: { $0.contains(marker) }) else { return nil }
        return (sentence: template.replacingOccurrences(of: marker, with: answer), index: index)
    }

    /// The bank's authored explanation, which is exactly the note a slip wants.
    private static func note(for record: PlacementRecord) -> String {
        guard let sourceID = record.sourceID else { return "" }
        switch record.block {
        case .grammar:
            return PlacementGrammarBank.item(id: sourceID)?.why ?? ""
        case .cloze:
            guard let gap = record.gap else { return "" }
            return PlacementGrammarBank.clozeGap(paragraphID: sourceID, gap: gap)?.why ?? ""
        default:
            return ""
        }
    }
}
