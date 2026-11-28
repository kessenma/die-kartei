import Foundation
import SwiftData

/// Reads and updates the learner's persistent coaching profile.
///
/// The rules themselves (decay, WEAK/STRONG deltas, slips and self-heal, caps and archiving, the
/// briefing) are `LearnerMemory` (Models/LearnerMemory.swift), shared with the Android app. This
/// is the SwiftData side: read the `LearnerProfile` row into a `LearnerMemory`, apply a rule, write
/// back the sections that changed, and insert what the rule archived as `ArchivedMemoryItem`s.
///
/// - `briefing` / `correctionHint` render the compact, bounded top-slice injected into prompts.
/// - `applySession` folds one finished session into the profile.
/// - `restore` / `forget` / `setPinned` back the Coach's Notes UI.
///
/// All work happens on the caller's actor (the engine is `@MainActor`) against its `ModelContext`.
@MainActor
enum LearnerMemoryService {

    // MARK: - Fetch-or-create

    static func profile(in context: ModelContext) -> LearnerProfile {
        if let existing = try? context.fetch(FetchDescriptor<LearnerProfile>()).first {
            return existing
        }
        let created = LearnerProfile()
        context.insert(created)
        return created
    }

    /// Apply one shared rule to the profile: the sections it changed are written back, and what it
    /// archived is inserted.
    private static func update(in context: ModelContext, _ rule: (inout LearnerMemory) -> [MemoryArchive]) {
        let p = profile(in: context)
        let old = LearnerMemory(profile: p)
        var memory = old
        let archived = rule(&memory)
        memory.write(to: p, from: old)
        for a in archived { context.insert(ArchivedMemoryItem(a)) }
    }

    // MARK: - Read: the injected top-slice

    /// Steering-only memory for the conversation prompt. "" when there's nothing worth injecting.
    static func briefing(in context: ModelContext) -> String {
        LearnerMemory(profile: profile(in: context)).briefing
    }

    /// Watch-for memory for the correction pass. "" when there's nothing to add.
    static func correctionHint(in context: ModelContext) -> String {
        LearnerMemory(profile: profile(in: context)).correctionHint
    }

    /// The structures the coach counts as shaky (`GrammarSkill.shakyThreshold`), worst-first.
    /// No profile yet means nothing is shaky.
    static func shakyFocuses(_ profile: LearnerProfile?) -> [GrammarFocus] {
        guard let profile else { return [] }
        return LearnerMemory(profile: profile).shakyFocuses
    }

    // MARK: - Write: fold one finished session into the profile

    static func applySession(
        summaryRaw: String,
        messages: [ChatMessage],
        savedVocab: [SavedVocabItem],
        wordsPracticed: [String],
        in context: ModelContext
    ) {
        let lines = messages.map { SessionLine(isUser: $0.isUser, text: $0.text, correctedText: $0.correctedText) }
        update(in: context) {
            $0.applySession(summaryRaw: summaryRaw, lines: lines, savedVocab: savedVocab, wordsPracticed: wordsPracticed)
        }
        // Feed the per-day streak the "Today" screen reads from.
        StudyLogService.record(.conversation, in: context)
    }

    /// Fold one finished grammar drill into the profile (`LearnerMemory.applyDrillResult`).
    static func applyDrillResult(focus: GrammarFocus, correct: Int, total: Int, in context: ModelContext) {
        guard total > 0 else { return }
        update(in: context) {
            $0.applyDrillResult(focus: focus, correct: correct, total: total)
            return []
        }
    }

    /// Fold a finished cloze round back into the profile (`LearnerMemory.applyClozeResults`). The
    /// round also counts toward the per-day streak, like any other batch of card reviews.
    static func applyClozeResults(
        mastered: [String], missed: [String], seconds: Int = 0, in context: ModelContext
    ) {
        let answered = mastered.count + missed.count
        guard answered > 0 else { return }
        update(in: context) { $0.applyClozeResults(mastered: mastered, missed: missed) }
        StudyLogService.record(.cards(answered), seconds: seconds, in: context)
    }

    // MARK: - Hand-offs from other screens

    /// Graded written answers (story free responses): `LearnerMemory.noteWrittenCorrections`.
    static func noteWrittenCorrections(
        _ pairs: [(original: String, corrected: String)],
        in context: ModelContext
    ) {
        guard !pairs.isEmpty else { return }
        update(in: context) { $0.noteWrittenCorrections(pairs) }
    }

    /// The journal hand-off: `LearnerMemory.noteSelfReports`.
    static func noteSelfReports(_ notes: [SelfReportNote], in context: ModelContext) {
        guard !notes.isEmpty else { return }
        update(in: context) { $0.noteSelfReports(notes) }
    }

    /// Manually move a note into the archive (the learner removed it).
    static func archiveSelfReport(id: String, in context: ModelContext) {
        update(in: context) { $0.archiveSelfReport(id: id).map { [$0] } ?? [] }
    }

    static func setSelfReportPinned(_ id: String, pinned: Bool, in context: ModelContext) {
        update(in: context) {
            $0.setSelfReportPinned(id, pinned: pinned)
            return []
        }
    }

    /// Pre-built slips (placement, Diktat, teacher corrections): `LearnerMemory.noteSlips`.
    static func noteSlips(_ slips: [LexicalSlip], in context: ModelContext) {
        guard !slips.isEmpty else { return }
        update(in: context) { $0.noteSlips(slips) }
    }

    /// Matching-game hand-off — see `noteVocabEncounters`.
    static func noteMatchingTrouble(_ words: [(german: String, english: String)], in context: ModelContext) {
        noteVocabEncounters(words, in: context)
    }

    /// Words met and being built: `LearnerMemory.noteVocabEncounters`.
    static func noteVocabEncounters(
        _ words: [(german: String, english: String)],
        source: String? = nil,
        in context: ModelContext
    ) {
        guard !words.isEmpty else { return }
        update(in: context) { $0.noteVocabEncounters(words, source: source) }
    }

    // MARK: - Archive management (Coach's Notes UI)

    static func restore(_ item: ArchivedMemoryItem, in context: ModelContext) {
        update(in: context) {
            $0.restore(kindRaw: item.kindRaw, payload: item.payload)
            return []
        }
        context.delete(item)
    }

    static func forget(_ item: ArchivedMemoryItem, in context: ModelContext) {
        context.delete(item)
    }

    /// Manually move an active vocab word into the archive (the learner removed it).
    static func archiveVocab(id: String, in context: ModelContext) {
        update(in: context) { $0.archiveVocab(id: id).map { [$0] } ?? [] }
    }

    /// Manually move an active slip into the archive (the learner removed it).
    static func archiveSlipItem(id: String, in context: ModelContext) {
        update(in: context) { $0.archiveSlip(id: id).map { [$0] } ?? [] }
    }

    static func setVocabPinned(_ id: String, pinned: Bool, in context: ModelContext) {
        update(in: context) {
            $0.setVocabPinned(id, pinned: pinned)
            return []
        }
    }

    static func setSlipPinned(_ id: String, pinned: Bool, in context: ModelContext) {
        update(in: context) {
            $0.setSlipPinned(id, pinned: pinned)
            return []
        }
    }

    /// Wipe everything the coach remembers (active + archive).
    static func reset(in context: ModelContext) {
        let p = profile(in: context)
        p.sessionCount = 0
        p.lastSessionAt = nil
        p.grammar = [:]
        p.vocab = []
        p.slips = []
        p.selfReports = []
        if let archived = try? context.fetch(FetchDescriptor<ArchivedMemoryItem>()) {
            for item in archived { context.delete(item) }
        }
    }

    /// Detects an exactly-one-word difference between two sentences: `LearnerMemory.singleTokenDiff`.
    static func singleTokenDiff(_ original: String, _ corrected: String) -> (wrong: String, right: String, index: Int)? {
        LearnerMemory.singleTokenDiff(original, corrected)
    }
}

// MARK: - SwiftData row ↔ shared value

extension LearnerMemory {
    init(profile p: LearnerProfile) {
        self.init(sessionCount: p.sessionCount, lastSessionAt: p.lastSessionAt, grammar: p.grammar,
                  vocab: p.vocab, slips: p.slips, selfReports: p.selfReports)
    }

    /// Write back only the sections that changed, so an untouched section keeps its exact bytes
    /// (and sync sees no change).
    func write(to p: LearnerProfile, from old: LearnerMemory) {
        if sessionCount != p.sessionCount { p.sessionCount = sessionCount }
        if lastSessionAt != p.lastSessionAt { p.lastSessionAt = lastSessionAt }
        if grammar != old.grammar { p.grammar = grammar }
        if vocab != old.vocab { p.vocab = vocab }
        if slips != old.slips { p.slips = slips }
        if selfReports != old.selfReports { p.selfReports = selfReports }
    }
}

extension ArchivedMemoryItem {
    convenience init(_ a: MemoryArchive) {
        self.init(kind: a.kind, reason: a.reason, title: a.title, subtitle: a.subtitle, payload: a.payload)
    }
}
