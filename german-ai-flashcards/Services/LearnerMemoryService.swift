import Foundation
import SwiftData

/// Reads and updates the learner's persistent coaching profile.
///
/// - `briefing` / `correctionHint` render the compact, bounded top-slice injected into prompts.
/// - `applySession` folds one finished session into the profile (decay + WEAK/STRONG delta,
///   vocabulary, single-token slips), cleaning by *archiving* rather than deleting.
/// - `restore` / `forget` / `setPinned` back the Coach's Notes UI (Phase 2).
///
/// All work happens on the caller's actor (the engine is `@MainActor`) against its `ModelContext`.
@MainActor
enum LearnerMemoryService {

    // Tuning
    private static let decayFactor = 0.9      // weaknesses fade this much each session
    private static let weakBump = 0.3         // a WEAK tag raises struggle by this (capped at 1)
    private static let strongDrop = 0.4       // a STRONG tag lowers struggle by this (floored at 0)
    private static let drillWeakBump = 0.2    // a poor drill score raises struggle by this
    private static let drillStrongDrop = 0.25 // a strong drill score lowers struggle by this
    private static let drillWeakScore = 0.6   // below this fraction correct, a drill counts as weak
    private static let drillStrongScore = 0.85 // at/above this fraction correct, it counts as strong
    private static let briefingThreshold = 0.2 // grammar shown as "shaky" at/above this
    private static let solidThreshold = 0.1    // grammar shown as "getting comfortable" below this

    // MARK: - Fetch-or-create

    static func profile(in context: ModelContext) -> LearnerProfile {
        if let existing = try? context.fetch(FetchDescriptor<LearnerProfile>()).first {
            return existing
        }
        let created = LearnerProfile()
        context.insert(created)
        return created
    }

    // MARK: - Read: the injected top-slice

    /// Steering-only memory for the conversation prompt. Must NOT ask the model to correct —
    /// correction is a separate pass. Returns "" when there's nothing worth injecting.
    static func briefing(in context: ModelContext) -> String {
        let p = profile(in: context)
        guard p.sessionCount > 0 else { return "" }

        var lines: [String] = []

        let shaky = sortedGrammar(p, minStruggle: briefingThreshold).prefix(3).map(\.label)
        if !shaky.isEmpty {
            lines.append("- Give them natural openings to use: \(shaky.joined(separator: ", ")).")
        }

        let comfortable = p.grammar
            .filter { $0.value.struggle < solidThreshold }
            .compactMap { GrammarFocus(rawValue: $0.key)?.germanLabel }
            .sorted()
            .prefix(2)
        if !comfortable.isEmpty {
            lines.append("- They're getting comfortable with: \(comfortable.joined(separator: ", ")).")
        }

        let words = p.vocab.sorted { $0.lastSeen > $1.lastSeen }.prefix(8).map(\.german)
        if !words.isEmpty {
            lines.append("- Naturally work in words they're learning: \(words.joined(separator: ", ")).")
        }

        guard !lines.isEmpty else { return "" }
        let header = "COACH MEMORY about this specific learner (you've practiced with them "
            + "\(p.sessionCount) time\(p.sessionCount == 1 ? "" : "s") before). Use it to steer the "
            + "conversation naturally — but keep it a normal chat and do NOT correct, translate, or "
            + "mention any of this:"
        return header + "\n" + lines.joined(separator: "\n")
    }

    /// Watch-for memory for the correction pass. Returns "" when there's nothing to add.
    static func correctionHint(in context: ModelContext) -> String {
        let p = profile(in: context)
        guard p.sessionCount > 0 else { return "" }

        var bits: [String] = []
        let weak = sortedGrammar(p, minStruggle: 0.25).prefix(3).map(\.label)
        if !weak.isEmpty { bits.append("often struggles with \(weak.joined(separator: ", "))") }

        let slipForms = p.slips.sorted { $0.timesSeen > $1.timesSeen }.prefix(3).map(\.wrong)
        if !slipForms.isEmpty { bits.append("has repeatedly slipped on \(slipForms.joined(separator: ", "))") }

        guard !bits.isEmpty else { return "" }
        return "For context, this learner " + bits.joined(separator: "; ") + " — pay extra attention to these, but only flag what's actually wrong in this sentence."
    }

    private static func sortedGrammar(_ p: LearnerProfile, minStruggle: Double) -> [(label: String, struggle: Double)] {
        p.grammar
            .compactMap { key, skill -> (String, Double)? in
                guard skill.struggle >= minStruggle, let f = GrammarFocus(rawValue: key) else { return nil }
                return (f.germanLabel, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .map { (label: $0.0, struggle: $0.1) }
    }

    // MARK: - Write: fold one finished session into the profile

    static func applySession(
        summaryRaw: String,
        messages: [ChatMessage],
        savedVocab: [SavedVocabItem],
        wordsPracticed: [String],
        in context: ModelContext
    ) {
        let p = profile(in: context)
        p.sessionCount += 1
        p.lastSessionAt = Date()
        let now = Date()

        // Correction pairs (original → corrected) and clean user lines (for slip self-heal).
        let corrections: [(original: String, corrected: String)] = messages.compactMap { m in
            guard m.isUser, let fixed = m.correctedText, !fixed.isEmpty else { return nil }
            return (m.text, fixed)
        }
        let cleanLines: [String] = messages
            .filter { $0.isUser && !$0.hasCorrection }
            .map { normalize($0.text) }

        applyGrammar(summaryRaw: summaryRaw, corrections: corrections, now: now, to: p)
        applyVocab(savedVocab: savedVocab, wordsPracticed: wordsPracticed, now: now, to: p, in: context)
        applySlips(corrections: corrections, cleanLines: cleanLines, now: now, to: p, in: context)

        // Feed the per-day streak the "Today" screen reads from.
        StudyLogService.record(.conversation, in: context)
    }

    /// Fold one finished grammar drill into the profile. A drill is direct evidence about a
    /// single structure, so it moves just that key: a strong score lowers its struggle, a poor
    /// one raises it, and a middling one only refreshes `lastSeen`. Drill nudges are smaller
    /// than conversation WEAK/STRONG tags, and drills don't count as coaching sessions
    /// (`sessionCount` stays conversation-only).
    static func applyDrillResult(focus: GrammarFocus, correct: Int, total: Int, in context: ModelContext) {
        guard total > 0 else { return }
        let p = profile(in: context)
        let score = Double(correct) / Double(total)

        var grammar = p.grammar
        var skill = grammar[focus.rawValue] ?? GrammarSkill(struggle: 0, lastSeen: Date(), samples: [])
        if score >= drillStrongScore {
            skill.struggle = max(0.0, skill.struggle - drillStrongDrop)
        } else if score < drillWeakScore {
            skill.struggle = min(1.0, skill.struggle + drillWeakBump)
        }
        skill.lastSeen = Date()
        grammar[focus.rawValue] = skill
        p.grammar = grammar
    }

    /// Fold a finished cloze round back into the profile. Filling a blank correctly is direct
    /// evidence the gap has closed, so that slip is retired the same way a clean production is —
    /// archived as `.mastered` (restorable), not deleted. A missed slip stays put; its `lastSeen`
    /// is refreshed so it doesn't age out while it's still fresh. The round also counts toward the
    /// per-day streak, like any other batch of card reviews.
    static func applyClozeResults(mastered: [String], missed: [String], in context: ModelContext) {
        let answered = mastered.count + missed.count
        guard answered > 0 else { return }
        let p = profile(in: context)
        var list = p.slips
        let now = Date()

        let masteredIDs = Set(mastered)
        var retired: [LexicalSlip] = []
        list.removeAll { slip in
            guard !slip.pinned, masteredIDs.contains(slip.id) else { return false }
            retired.append(slip)
            return true
        }
        for slip in retired { archiveSlip(slip, reason: .mastered, in: context) }

        let missedIDs = Set(missed)
        for i in list.indices where missedIDs.contains(list[i].id) {
            list[i].lastSeen = now
        }
        p.slips = list

        StudyLogService.record(.cards(answered), in: context)
    }

    // MARK: Grammar

    private static func applyGrammar(
        summaryRaw: String,
        corrections: [(original: String, corrected: String)],
        now: Date,
        to p: LearnerProfile
    ) {
        let (weak, strong) = ConversationPrompts.parseProfileSignals(summaryRaw)
        var grammar = p.grammar

        // Decay every tracked weakness so old struggles fade if not reinforced.
        for key in grammar.keys { grammar[key]?.struggle *= decayFactor }

        // Attribute this session's example corrections only when there's a single weak focus.
        let samples: [String] = weak.count == 1
            ? corrections.prefix(LearnerProfile.sampleCap).map { "\(trimSample($0.original)) → \(trimSample($0.corrected))" }
            : []

        for f in weak {
            var skill = grammar[f.rawValue] ?? GrammarSkill(struggle: 0, lastSeen: now, samples: [])
            skill.struggle = min(1.0, skill.struggle + weakBump)
            skill.lastSeen = now
            if !samples.isEmpty { skill.samples = Array(samples.prefix(LearnerProfile.sampleCap)) }
            grammar[f.rawValue] = skill
        }
        for f in strong {
            var skill = grammar[f.rawValue] ?? GrammarSkill(struggle: 0, lastSeen: now, samples: [])
            skill.struggle = max(0.0, skill.struggle - strongDrop)
            skill.lastSeen = now
            grammar[f.rawValue] = skill
        }
        p.grammar = grammar
    }

    // MARK: Vocabulary

    private static func applyVocab(
        savedVocab: [SavedVocabItem],
        wordsPracticed: [String],
        now: Date,
        to p: LearnerProfile,
        in context: ModelContext
    ) {
        var list = p.vocab
        var incoming: [VocabTouch] = savedVocab.map {
            VocabTouch(german: $0.german, english: $0.english, lastSeen: now, timesUsed: 1)
        }
        incoming += wordsPracticed.map {
            VocabTouch(german: $0, english: "", lastSeen: now, timesUsed: 1)
        }

        for item in incoming {
            if let i = list.firstIndex(where: { $0.id == item.id }) {
                list[i].lastSeen = now
                list[i].timesUsed += 1
                if list[i].english.isEmpty, !item.english.isEmpty { list[i].english = item.english }
            } else {
                list.append(item)
            }
        }

        list = evict(list, cap: LearnerProfile.vocabCap, in: context) { dropped in
            ArchivedMemoryItem(
                kind: .vocab, reason: .replacedByLRU,
                title: dropped.german, subtitle: dropped.english,
                payload: try? JSONEncoder().encode(dropped)
            )
        }
        p.vocab = list
    }

    // MARK: Slips

    private static func applySlips(
        corrections: [(original: String, corrected: String)],
        cleanLines: [String],
        now: Date,
        to p: LearnerProfile,
        in context: ModelContext
    ) {
        var list = p.slips

        // Add / bump single-token slips (precise article/case/gender/word swaps). The corrected
        // sentence + blank position ride along so the slip can seed a personalized cloze card.
        for c in corrections {
            guard let diff = singleTokenDiff(c.original, c.corrected) else { continue }
            let slip = LexicalSlip(
                wrong: diff.wrong, right: diff.right, note: "", lastSeen: now, timesSeen: 1,
                sentence: c.corrected, blankIndex: diff.index
            )
            if let i = list.firstIndex(where: { $0.id == slip.id }) {
                list[i].lastSeen = now
                list[i].timesSeen += 1
                // Refresh with the most recent sentence context so the cloze stays current.
                list[i].sentence = slip.sentence
                list[i].blankIndex = slip.blankIndex
            } else {
                list.append(slip)
            }
        }

        // Self-heal: a slip whose correct form the learner produced cleanly this session is mastered.
        var healed: [LexicalSlip] = []
        list.removeAll { slip in
            guard !slip.pinned else { return false }
            let mastered = cleanLines.contains { containsWord($0, normalize(slip.right)) }
            if mastered { healed.append(slip) }
            return mastered
        }
        for slip in healed { archiveSlip(slip, reason: .mastered, in: context) }

        // LRU-cap the rest.
        list = evict(list, cap: LearnerProfile.slipCap, in: context) { dropped in
            ArchivedMemoryItem(
                kind: .slip, reason: .replacedByLRU,
                title: "\(dropped.wrong) → \(dropped.right)", subtitle: dropped.note,
                payload: try? JSONEncoder().encode(dropped)
            )
        }
        p.slips = list
    }

    private static func archiveSlip(_ slip: LexicalSlip, reason: ArchiveReason, in context: ModelContext) {
        context.insert(ArchivedMemoryItem(
            kind: .slip, reason: reason,
            title: "\(slip.wrong) → \(slip.right)", subtitle: slip.note,
            payload: try? JSONEncoder().encode(slip)
        ))
    }

    // MARK: - Written corrections outside conversation (story free-response answers)

    /// Fold "you wrote → better" pairs from graded written answers into the profile's slips.
    ///
    /// Same extraction as a conversation turn (single-token swaps only, with the corrected
    /// sentence kept so the slip can seed a cloze card), but deliberately without the rest of
    /// `applySession`: no self-heal pass (one answer isn't evidence a slip is gone) and no
    /// `sessionCount` bump (coaching sessions stay conversation-only, like drills).
    static func noteWrittenCorrections(
        _ pairs: [(original: String, corrected: String)],
        in context: ModelContext
    ) {
        guard !pairs.isEmpty else { return }
        let p = profile(in: context)
        let now = Date()
        var list = p.slips

        for pair in pairs {
            guard let diff = singleTokenDiff(pair.original, pair.corrected) else { continue }
            let slip = LexicalSlip(
                wrong: diff.wrong, right: diff.right, note: "", lastSeen: now, timesSeen: 1,
                sentence: pair.corrected, blankIndex: diff.index
            )
            if let i = list.firstIndex(where: { $0.id == slip.id }) {
                list[i].lastSeen = now
                list[i].timesSeen += 1
                list[i].sentence = slip.sentence
                list[i].blankIndex = slip.blankIndex
            } else {
                list.append(slip)
            }
        }

        list = evict(list, cap: LearnerProfile.slipCap, in: context) { dropped in
            ArchivedMemoryItem(
                kind: .slip, reason: .replacedByLRU,
                title: "\(dropped.wrong) → \(dropped.right)", subtitle: dropped.note,
                payload: try? JSONEncoder().encode(dropped)
            )
        }
        p.slips = list
    }

    // MARK: - Vocabulary encounters (matching game, story reading)

    /// Matching-game hand-off — see `noteVocabEncounters`.
    static func noteMatchingTrouble(_ words: [(german: String, english: String)], in context: ModelContext) {
        noteVocabEncounters(words, in: context)
    }

    /// Fold encountered words into the profile's vocabulary, so the coach starts working them
    /// into conversations and they show up (and are drillable) in Coach's Notes. Used for words
    /// the learner keeps missing in the matching game, words they save or miss while reading a
    /// story, and similar "a word they're building" moments — never production slips.
    static func noteVocabEncounters(_ words: [(german: String, english: String)], in context: ModelContext) {
        guard !words.isEmpty else { return }
        let p = profile(in: context)
        let now = Date()
        var list = p.vocab

        for word in words {
            let touch = VocabTouch(german: word.german, english: word.english, lastSeen: now, timesUsed: 1)
            if let i = list.firstIndex(where: { $0.id == touch.id }) {
                list[i].lastSeen = now
                list[i].timesUsed += 1
                if list[i].english.isEmpty, !touch.english.isEmpty { list[i].english = touch.english }
            } else {
                list.append(touch)
            }
        }

        list = evict(list, cap: LearnerProfile.vocabCap, in: context) { dropped in
            ArchivedMemoryItem(
                kind: .vocab, reason: .replacedByLRU,
                title: dropped.german, subtitle: dropped.english,
                payload: try? JSONEncoder().encode(dropped)
            )
        }
        p.vocab = list
    }

    // MARK: - Archive management (Coach's Notes UI, Phase 2)

    static func restore(_ item: ArchivedMemoryItem, in context: ModelContext) {
        let p = profile(in: context)
        switch item.kind {
        case .vocab:
            if let data = item.payload, var v = try? JSONDecoder().decode(VocabTouch.self, from: data) {
                v.pinned = true // a manual restore implies "keep this"
                var list = p.vocab
                if !list.contains(where: { $0.id == v.id }) { list.append(v) }
                p.vocab = list
            }
        case .slip:
            if let data = item.payload, var s = try? JSONDecoder().decode(LexicalSlip.self, from: data) {
                s.pinned = true
                var list = p.slips
                if !list.contains(where: { $0.id == s.id }) { list.append(s) }
                p.slips = list
            }
        }
        context.delete(item)
    }

    static func forget(_ item: ArchivedMemoryItem, in context: ModelContext) {
        context.delete(item)
    }

    /// Manually move an active vocab word into the archive (the learner removed it).
    static func archiveVocab(id: String, in context: ModelContext) {
        let p = profile(in: context)
        var list = p.vocab
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let item = list.remove(at: idx)
        context.insert(ArchivedMemoryItem(
            kind: .vocab, reason: .removedByUser,
            title: item.german, subtitle: item.english,
            payload: try? JSONEncoder().encode(item)
        ))
        p.vocab = list
    }

    /// Manually move an active slip into the archive (the learner removed it).
    static func archiveSlipItem(id: String, in context: ModelContext) {
        let p = profile(in: context)
        var list = p.slips
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let item = list.remove(at: idx)
        context.insert(ArchivedMemoryItem(
            kind: .slip, reason: .removedByUser,
            title: "\(item.wrong) → \(item.right)", subtitle: item.note,
            payload: try? JSONEncoder().encode(item)
        ))
        p.slips = list
    }

    static func setVocabPinned(_ id: String, pinned: Bool, in context: ModelContext) {
        let p = profile(in: context)
        var list = p.vocab
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].pinned = pinned; p.vocab = list }
    }

    static func setSlipPinned(_ id: String, pinned: Bool, in context: ModelContext) {
        let p = profile(in: context)
        var list = p.slips
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].pinned = pinned; p.slips = list }
    }

    /// Wipe everything the coach remembers (active + archive).
    static func reset(in context: ModelContext) {
        let p = profile(in: context)
        p.sessionCount = 0
        p.lastSessionAt = nil
        p.grammar = [:]
        p.vocab = []
        p.slips = []
        if let archived = try? context.fetch(FetchDescriptor<ArchivedMemoryItem>()) {
            for item in archived { context.delete(item) }
        }
    }

    // MARK: - Helpers

    /// Drop least-recently-seen unpinned items past `cap`, archiving each via `makeArchive`.
    private static func evict<T: Timestamped & Pinnable & Identifiable>(
        _ items: [T],
        cap: Int,
        in context: ModelContext,
        makeArchive: (T) -> ArchivedMemoryItem
    ) -> [T] {
        guard items.count > cap else { return items }
        // Oldest unpinned items are the eviction candidates (pinned ones are protected).
        let unpinnedOldest = items
            .filter { !$0.isPinned }
            .sorted { $0.seenAt < $1.seenAt }
        let overflow = items.count - cap
        let toDrop = Array(unpinnedOldest.prefix(overflow))
        let dropIDs = Set(toDrop.map(\.id))
        for item in toDrop { context.insert(makeArchive(item)) }
        return items.filter { !dropIDs.contains($0.id) }
    }

    /// Detects an exactly-one-word difference between two sentences (case/punct-insensitive
    /// comparison, original display forms preserved). Returns nil if 0 or >1 tokens differ.
    /// `index` is the differing token's position in `corrected` split on spaces — the blank
    /// position for a cloze card built from the corrected sentence.
    static func singleTokenDiff(_ original: String, _ corrected: String) -> (wrong: String, right: String, index: Int)? {
        let a = original.split(separator: " ").map(String.init)
        let b = corrected.split(separator: " ").map(String.init)
        guard a.count == b.count, !a.isEmpty else { return nil }

        var diffIndex: Int?
        for i in a.indices where core(a[i]) != core(b[i]) {
            if diffIndex != nil { return nil } // more than one token differs
            diffIndex = i
        }
        guard let idx = diffIndex else { return nil }
        let wrong = trimToken(a[idx]), right = trimToken(b[idx])
        guard !wrong.isEmpty, !right.isEmpty, core(wrong) != core(right) else { return nil }
        return (wrong, right, idx)
    }

    private static func core(_ token: String) -> String {
        token.lowercased(with: Locale(identifier: "de_DE"))
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
    }

    private static func trimToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    }

    private static func trimSample(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 60 ? String(t.prefix(59)) + "…" : t
    }

    private static func normalize(_ s: String) -> String {
        " " + s.lowercased(with: Locale(identifier: "de_DE"))
            .map { CharacterSet.letters.contains($0.unicodeScalars.first!) || $0 == " " ? $0 : " " }
            .reduce(into: "") { $0.append($1) } + " "
    }

    /// Whole-word-ish containment against an already-`normalize`d haystack.
    private static func containsWord(_ haystack: String, _ needleNormalizedCore: String) -> Bool {
        let needle = needleNormalizedCore.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return false }
        return haystack.contains(" " + needle + " ")
    }
}

// MARK: - Eviction protocols

/// Conformances that let `evict` treat vocab and slips uniformly.
protocol Timestamped { var seenAt: Date { get } }
protocol Pinnable { var isPinned: Bool { get } }

extension VocabTouch: Timestamped, Pinnable {
    var seenAt: Date { lastSeen }
    var isPinned: Bool { pinned }
}
extension LexicalSlip: Timestamped, Pinnable {
    var seenAt: Date { lastSeen }
    var isPinned: Bool { pinned }
}
