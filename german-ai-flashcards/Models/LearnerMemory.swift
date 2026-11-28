//
//  LearnerMemory.swift
//  german-ai-flashcards
//
//  The coach's memory of the learner as plain values, and every rule that changes it: how a
//  finished conversation, a drill, a cloze round or a hand-off from another screen folds in, what
//  gets archived when a list is full, and the short briefing the model sees. Foundation only, so
//  the Android app (DieKarteiCore) runs exactly these rules on its own store; iOS's
//  `LearnerMemoryService` reads a `LearnerProfile` into a `LearnerMemory`, applies a rule and
//  writes back. `LearnerMemoryParityTests` (iOS) and `LearnerMemoryTests` (core) replay one script
//  against learner_memory_golden.json.
//

import Foundation

// MARK: - Value types (the "sections" inside the profile)

/// How shaky the learner is on one fixed grammar structure (keyed by `GrammarFocus.rawValue`).
nonisolated struct GrammarSkill: Codable, Equatable {
    /// 0 = solid, 1 = very shaky. Decays toward 0 each session so old weaknesses fade.
    var struggle: Double
    var lastSeen: Date
    /// Up to `LearnerMemory.sampleCap` recent "you said → better" examples, for the coach screen.
    var samples: [String]

    /// At or above this struggle level a structure counts as "shaky" — worth surfacing a
    /// just-in-time lesson / drill for. Matches the coach's briefing threshold so the Today
    /// plan and Coach's Notes agree on what's weak.
    static let shakyThreshold = 0.2
}

/// A word the learner has been exposed to and is working to retain.
nonisolated struct VocabTouch: Codable, Identifiable, Hashable {
    var german: String
    var english: String
    var lastSeen: Date
    var timesUsed: Int
    /// Pinned items are exempt from automatic cleaning.
    var pinned: Bool = false
    /// Where this came from, when it wasn't a conversation — currently only
    /// `MemorySource.placement`. Optional so items stored before it existed decode unchanged, and
    /// deliberately *not* part of `id`: a word is the same word however the learner met it, so a
    /// placement miss should merge with a matching-game touch rather than sit beside it.
    var source: String? = nil
    var id: String { MemoryItemID.vocab(german: german) }
}

/// A recurring word-level slip (wrong form → right form) — e.g. a case or gender error.
nonisolated struct LexicalSlip: Codable, Identifiable, Hashable {
    var wrong: String
    var right: String
    var note: String
    var lastSeen: Date
    var timesSeen: Int
    /// Pinned items are exempt from automatic cleaning.
    var pinned: Bool = false
    /// The learner's own corrected sentence this slip came from — the seed for a personalized
    /// cloze ("fill in the blank") card. Optional so slips recorded before this was captured
    /// (and any that weren't single-sentence swaps) decode cleanly and are simply not drillable.
    var sentence: String? = nil
    /// Word index (into `sentence` split on spaces) of the token to blank — the corrected form.
    var blankIndex: Int? = nil
    /// Where this came from, when it wasn't the learner's own production — currently only
    /// `MemorySource.placement`. Optional so items stored before it existed decode unchanged.
    var source: String? = nil

    /// Unlike `VocabTouch`, the source **is** part of the identity here, and it has to be.
    ///
    /// Placement distractors are generic function words — "der", "die", "kein" — so a placement
    /// `die→der` would otherwise share an id with a real conversation `die→der`, and the merge
    /// branch in `LearnerMemoryService` overwrites `sentence`/`blankIndex`. That would replace the
    /// learner's own corrected sentence (and the personalized cloze card built from it) with a
    /// bank sentence. Existing slips have `source == nil`, so their ids stay byte-identical and
    /// pins, archives and self-heal keep working untouched.
    var id: String { MemoryItemID.slip(wrong: wrong, right: right, source: source) }

    /// True when this slip carries enough context to build a fill-in-the-blank card.
    var isClozeReady: Bool { sentence != nil && blankIndex != nil }
}

/// Something the learner said, in their own words, that they find hard about German: "mixing up
/// dem and den after mit". Handed over from a journal entry on the learner's explicit button, read
/// by the tutor from what they wrote (never inferred from a mistake) and edited by them before it
/// is saved. Steers the coach's briefing; never touches the grammar bars (docs/SCHREIBEN.md).
nonisolated struct SelfReportNote: Codable, Identifiable, Hashable {
    /// At most `maxLength` characters, the learner's own words.
    var text: String
    /// `GrammarFocus` raw value when the note is about one structure.
    var focus: String? = nil
    var notedAt: Date
    var timesNoted: Int = 1
    /// Pinned items are exempt from automatic cleaning.
    var pinned: Bool = false
    var source: String? = MemorySource.journal
    /// The entry it came from, for a "from your journal" caption.
    var entryID: UUID? = nil

    static let maxLength = 80

    /// The words of the note, lowercased, letters only: the same thought written twice merges.
    var id: String { MemoryItemID.note(text: text) }

    var grammarFocus: GrammarFocus? { focus.flatMap(GrammarFocus.init(rawValue:)) }
}

/// Where a memory came from, when it wasn't the learner's own conversation. Absent means the
/// ordinary path — a chat turn, a saved word, a story lookup.
nonisolated enum MemorySource {
    /// Handed over from the placement check by the explicit button on the review screen.
    static let placement = "placement"
    /// Handed over from a journal entry by the explicit button on the entry.
    static let journal = "journal"
    /// A Hören ▸ Diktat miss: an ending the learner did not hear, or a headword they missed.
    /// Kept out of the coach's correction hint like every sourced slip: it was heard, not said.
    static let diktat = "diktat"
    /// A correction the learner's teacher made in class (Korrekturen der Lehrerin). Produced by the
    /// learner and confirmed by a teacher, so unlike other sourced slips it reaches the correction hint.
    static let teacher = "teacher"
}

// MARK: - Archive kinds

nonisolated enum MemoryKind: String, Codable {
    case vocab
    case slip
    /// A `SelfReportNote`. A build from before the journal decodes it as `.vocab` and cannot
    /// restore it; harmless, and the row still reads.
    case selfReport
}

/// Why an item left the active profile — shown on the archive screen.
nonisolated enum ArchiveReason: String, Codable {
    case mastered        // the learner used it correctly, so the coach let it go
    case agedOut         // grew stale
    case replacedByLRU   // pushed out by newer items past the cap
    case removedByUser

    var label: String {
        switch self {
        case .mastered:      "Mastered"
        case .agedOut:       "Aged out"
        case .replacedByLRU: "Made room for newer"
        case .removedByUser: "Removed by you"
        }
    }
}

/// One cleaned-out memory the learner can review and restore. Stored as its own row so the
/// history can grow freely and be paged lazily — it never touches a prompt.

/// A memory that just left the active profile: what each app stores as an archived row
/// (`ArchivedMemoryItem` on iOS, `ArchivedMemoryRecord` on Android).
nonisolated struct MemoryArchive: Equatable {
    var kind: MemoryKind
    var reason: ArchiveReason
    var title: String
    var subtitle: String
    /// The encoded item (default `JSONEncoder`), for restore.
    var payload: Data?
}

/// One line of a finished conversation, as the memory reads it.
nonisolated struct SessionLine {
    var isUser: Bool
    var text: String
    var correctedText: String?

    var hasCorrection: Bool { correctedText?.isEmpty == false }
}

// MARK: - The profile

/// The active profile: bounded, and the only memory ever shown to the model.
struct LearnerMemory: Equatable {
    var sessionCount = 0
    var lastSessionAt: Date? = nil
    var grammar: [String: GrammarSkill] = [:]
    var vocab: [VocabTouch] = []
    var slips: [LexicalSlip] = []
    var selfReports: [SelfReportNote] = []

    /// Settings ▸ Conversation ▸ Personalized coaching, on by default: off, chats neither read
    /// nor write the memory.
    static let personalizedCoachingKey = "chatPersonalizedCoaching"

    // Bounds
    static let vocabCap = 60
    static let slipCap = 20
    static let selfReportCap = 10
    static let sampleCap = 2

    // Tuning
    static let decayFactor = 0.9      // weaknesses fade this much each session
    static let weakBump = 0.3         // a WEAK tag raises struggle by this (capped at 1)
    static let strongDrop = 0.4       // a STRONG tag lowers struggle by this (floored at 0)
    static let drillWeakBump = 0.2    // a poor drill score raises struggle by this
    static let drillStrongDrop = 0.25 // a strong drill score lowers struggle by this
    static let drillWeakScore = 0.6   // below this fraction correct, a drill counts as weak
    static let drillStrongScore = 0.85 // at/above this fraction correct, it counts as strong
    static let briefingThreshold = 0.2 // grammar shown as "shaky" at/above this
    static let solidThreshold = 0.1    // grammar shown as "getting comfortable" below this
}

// MARK: - Read: the injected top-slice

extension LearnerMemory {
    /// Steering-only memory for the conversation prompt. Must NOT ask the model to correct —
    /// correction is a separate pass. "" when there's nothing worth injecting.
    var briefing: String {
        // A learner who has never chatted but told their journal what they find hard still gets
        // that steer in their first conversation.
        guard sessionCount > 0 || !selfReports.isEmpty else { return "" }

        var lines: [String] = []

        // In their own words, at most one line: pinned first, then the newest.
        let said = selfReports
            .sorted { ($0.pinned ? 1 : 0, $0.notedAt) > ($1.pinned ? 1 : 0, $1.notedAt) }
            .prefix(2)
            .map { "\"" + ($0.text.count > 40 ? String($0.text.prefix(39)) + "…" : $0.text) + "\"" }
        if !said.isEmpty {
            lines.append("- They say they find hard: \(said.joined(separator: "; ")).")
        }

        let shaky = sortedGrammar(minStruggle: Self.briefingThreshold).prefix(3).map(\.label)
        if !shaky.isEmpty {
            lines.append("- Give them natural openings to use: \(shaky.joined(separator: ", ")).")
        }

        let comfortable = grammar
            .filter { $0.value.struggle < Self.solidThreshold }
            .compactMap { GrammarFocus(rawValue: $0.key)?.germanLabel }
            .sorted()
            .prefix(2)
        if !comfortable.isEmpty {
            lines.append("- They're getting comfortable with: \(comfortable.joined(separator: ", ")).")
        }

        let words = vocab.sorted { $0.lastSeen > $1.lastSeen }.prefix(8).map(\.german)
        if !words.isEmpty {
            lines.append("- Naturally work in words they're learning: \(words.joined(separator: ", ")).")
        }

        guard !lines.isEmpty else { return "" }
        let history = sessionCount > 0
            ? "you've practiced with them \(sessionCount) time\(sessionCount == 1 ? "" : "s") before"
            : "this is your first conversation, but they have told the app about their German"
        let header = "COACH MEMORY about this specific learner (\(history)). Use it to steer the "
            + "conversation naturally — but keep it a normal chat and do NOT correct, translate, or "
            + "mention any of this:"
        return header + "\n" + lines.joined(separator: "\n")
    }

    /// Watch-for memory for the correction pass. "" when there's nothing to add.
    var correctionHint: String {
        guard sessionCount > 0 else { return "" }

        var bits: [String] = []
        let weak = sortedGrammar(minStruggle: 0.25).prefix(3).map(\.label)
        if !weak.isEmpty { bits.append("often struggles with \(weak.joined(separator: ", "))") }

        // Production only. A placement-sourced slip's `wrong` side is an authored *distractor* —
        // a form the app put on screen and the learner tapped, never one they produced. Telling the
        // coach to watch for it would be inventing a mistake they've never made.
        let slipForms = slips
            .filter { $0.source == nil || $0.source == MemorySource.teacher }
            .sorted { $0.timesSeen > $1.timesSeen }
            .prefix(3)
            .map(\.wrong)
        if !slipForms.isEmpty { bits.append("has repeatedly slipped on \(slipForms.joined(separator: ", "))") }

        // What they said themselves, but only the structures named, to keep the hint short.
        let saidFocuses = selfReports
            .sorted { $0.notedAt > $1.notedAt }
            .compactMap(\.grammarFocus)
            .reduce(into: [GrammarFocus]()) { if !$0.contains($1) { $0.append($1) } }
            .prefix(2)
            .map(\.germanLabel)
        if !saidFocuses.isEmpty { bits.append("says they find \(saidFocuses.joined(separator: " and ")) hard") }

        guard !bits.isEmpty else { return "" }
        return "For context, this learner " + bits.joined(separator: "; ") + " — pay extra attention to these, but only flag what's actually wrong in this sentence."
    }

    /// The structures the coach counts as shaky (`GrammarSkill.shakyThreshold`), worst-first.
    /// The one shared reading of "needs work", so a flame on one screen means what it means on
    /// the next.
    var shakyFocuses: [GrammarFocus] {
        grammar
            .compactMap { key, skill -> (GrammarFocus, Double)? in
                guard skill.struggle >= GrammarSkill.shakyThreshold,
                      let focus = GrammarFocus(rawValue: key) else { return nil }
                return (focus, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func sortedGrammar(minStruggle: Double) -> [(label: String, struggle: Double)] {
        grammar
            .compactMap { key, skill -> (String, Double)? in
                guard skill.struggle >= minStruggle, let f = GrammarFocus(rawValue: key) else { return nil }
                return (f.germanLabel, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .map { (label: $0.0, struggle: $0.1) }
    }
}

// MARK: - Write: what folds in

extension LearnerMemory {
    /// Fold one finished conversation in: decay plus the summary's WEAK/STRONG tags, the words
    /// saved and practiced, single-token slips (and slips the learner has since produced cleanly
    /// leave as mastered). Returns what was archived.
    mutating func applySession(
        summaryRaw: String, lines: [SessionLine], savedVocab: [SavedVocabItem], wordsPracticed: [String],
        now: Date = Date()
    ) -> [MemoryArchive] {
        sessionCount += 1
        lastSessionAt = now

        // Correction pairs (original → corrected) and clean user lines (for slip self-heal).
        let corrections: [(original: String, corrected: String)] = lines.compactMap { m in
            guard m.isUser, let fixed = m.correctedText, !fixed.isEmpty else { return nil }
            return (m.text, fixed)
        }
        let cleanLines: [String] = lines
            .filter { $0.isUser && !$0.hasCorrection }
            .map { Self.normalize($0.text) }

        applyGrammar(summaryRaw: summaryRaw, corrections: corrections, now: now)
        var archived = applyVocab(savedVocab: savedVocab, wordsPracticed: wordsPracticed, now: now)
        archived += applySlips(corrections: corrections, cleanLines: cleanLines, now: now)
        return archived
    }

    /// Fold one finished grammar drill in. A drill is direct evidence about a single structure,
    /// so it moves just that key: a strong score lowers its struggle, a poor one raises it, and a
    /// middling one only refreshes `lastSeen`. Drill nudges are smaller than conversation
    /// WEAK/STRONG tags, and drills don't count as coaching sessions.
    mutating func applyDrillResult(focus: GrammarFocus, correct: Int, total: Int, now: Date = Date()) {
        guard total > 0 else { return }
        let score = Double(correct) / Double(total)
        var skill = grammar[focus.rawValue] ?? GrammarSkill(struggle: 0, lastSeen: now, samples: [])
        if score >= Self.drillStrongScore {
            skill.struggle = max(0.0, skill.struggle - Self.drillStrongDrop)
        } else if score < Self.drillWeakScore {
            skill.struggle = min(1.0, skill.struggle + Self.drillWeakBump)
        }
        skill.lastSeen = now
        grammar[focus.rawValue] = skill
    }

    /// Fold a finished cloze round in. Filling a blank correctly retires that slip as mastered
    /// (restorable); a missed slip stays, its `lastSeen` refreshed so it doesn't age out.
    mutating func applyClozeResults(mastered: [String], missed: [String], now: Date = Date()) -> [MemoryArchive] {
        guard mastered.count + missed.count > 0 else { return [] }
        var list = slips
        let masteredIDs = Set(mastered)
        var retired: [LexicalSlip] = []
        list.removeAll { slip in
            guard !slip.pinned, masteredIDs.contains(slip.id) else { return false }
            retired.append(slip)
            return true
        }
        let missedIDs = Set(missed)
        for i in list.indices where missedIDs.contains(list[i].id) {
            list[i].lastSeen = now
        }
        slips = list
        return retired.map { Self.archive($0, reason: .mastered) }
    }

    /// "You wrote → better" pairs from graded written answers, as slips. Same extraction as a
    /// conversation turn, but no self-heal (one answer isn't evidence a slip is gone) and no
    /// session count (coaching sessions stay conversation-only).
    mutating func noteWrittenCorrections(_ pairs: [(original: String, corrected: String)], now: Date = Date()) -> [MemoryArchive] {
        guard !pairs.isEmpty else { return [] }
        var list = slips
        for pair in pairs {
            guard let diff = Self.singleTokenDiff(pair.original, pair.corrected) else { continue }
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
        let (kept, archived) = Self.evict(list, cap: Self.slipCap) { Self.archive($0, reason: .replacedByLRU) }
        slips = kept
        return archived
    }

    /// What the learner said they find hard. The same thought written twice becomes one note seen
    /// twice; a focus fills in when the old note had none. A note is a steer, not evidence: no
    /// session count, nothing written to `grammar`.
    mutating func noteSelfReports(_ notes: [SelfReportNote], now: Date = Date()) -> [MemoryArchive] {
        guard !notes.isEmpty else { return [] }
        var list = selfReports
        for note in notes {
            var fresh = note
            fresh.text = String(fresh.text.prefix(SelfReportNote.maxLength))
            fresh.notedAt = now
            if let i = list.firstIndex(where: { $0.id == fresh.id }) {
                list[i].notedAt = now
                list[i].timesNoted += 1
                if list[i].focus == nil { list[i].focus = fresh.focus }
                if list[i].entryID == nil { list[i].entryID = fresh.entryID }
            } else {
                list.append(fresh)
            }
        }
        let (kept, archived) = Self.evict(list, cap: Self.selfReportCap) { Self.archive($0, reason: .replacedByLRU) }
        selfReports = kept
        return archived
    }

    /// Already-formed slips (the placement bank knows the wrong form, the right one and why).
    /// No self-heal and no session count: a quiz is not a coaching session. Sourced slips are
    /// their own id namespace, so nothing here overwrites a sentence the learner wrote.
    mutating func noteSlips(_ incoming: [LexicalSlip], now: Date = Date()) -> [MemoryArchive] {
        guard !incoming.isEmpty else { return [] }
        var list = slips
        for slip in incoming {
            if let i = list.firstIndex(where: { $0.id == slip.id }) {
                list[i].lastSeen = now
                list[i].timesSeen += 1
                if list[i].note.isEmpty, !slip.note.isEmpty { list[i].note = slip.note }
                if list[i].sentence == nil { list[i].sentence = slip.sentence }
                if list[i].blankIndex == nil { list[i].blankIndex = slip.blankIndex }
            } else {
                var fresh = slip
                fresh.lastSeen = now
                list.append(fresh)
            }
        }
        let (kept, archived) = Self.evict(list, cap: Self.slipCap) { Self.archive($0, reason: .replacedByLRU) }
        slips = kept
        return archived
    }

    /// Words the learner met and is building (matching-game misses, words saved or missed while
    /// reading), never production slips. `source` says where, when that isn't the ordinary path;
    /// it never affects merging, and an existing touch keeps its own source.
    mutating func noteVocabEncounters(_ words: [(german: String, english: String)], source: String? = nil,
                                      now: Date = Date()) -> [MemoryArchive] {
        guard !words.isEmpty else { return [] }
        var list = vocab
        for word in words {
            let touch = VocabTouch(german: word.german, english: word.english, lastSeen: now, timesUsed: 1, source: source)
            if let i = list.firstIndex(where: { $0.id == touch.id }) {
                list[i].lastSeen = now
                list[i].timesUsed += 1
                if list[i].english.isEmpty, !touch.english.isEmpty { list[i].english = touch.english }
            } else {
                list.append(touch)
            }
        }
        let (kept, archived) = Self.evict(list, cap: Self.vocabCap) { Self.archive($0, reason: .replacedByLRU) }
        vocab = kept
        return archived
    }

    // MARK: Grammar

    private mutating func applyGrammar(summaryRaw: String, corrections: [(original: String, corrected: String)], now: Date) {
        let (weak, strong) = ConversationPrompts.parseProfileSignals(summaryRaw)
        var g = grammar

        // Decay every tracked weakness so old struggles fade if not reinforced.
        for key in g.keys { g[key]?.struggle *= Self.decayFactor }

        // Attribute this session's example corrections only when there's a single weak focus.
        let samples: [String] = weak.count == 1
            ? corrections.prefix(Self.sampleCap).map { "\(Self.trimSample($0.original)) → \(Self.trimSample($0.corrected))" }
            : []

        for f in weak {
            var skill = g[f.rawValue] ?? GrammarSkill(struggle: 0, lastSeen: now, samples: [])
            skill.struggle = min(1.0, skill.struggle + Self.weakBump)
            skill.lastSeen = now
            if !samples.isEmpty { skill.samples = Array(samples.prefix(Self.sampleCap)) }
            g[f.rawValue] = skill
        }
        for f in strong {
            var skill = g[f.rawValue] ?? GrammarSkill(struggle: 0, lastSeen: now, samples: [])
            skill.struggle = max(0.0, skill.struggle - Self.strongDrop)
            skill.lastSeen = now
            g[f.rawValue] = skill
        }
        grammar = g
    }

    // MARK: Vocabulary

    private mutating func applyVocab(savedVocab: [SavedVocabItem], wordsPracticed: [String], now: Date) -> [MemoryArchive] {
        var list = vocab
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
        let (kept, archived) = Self.evict(list, cap: Self.vocabCap) { Self.archive($0, reason: .replacedByLRU) }
        vocab = kept
        return archived
    }

    // MARK: Slips

    private mutating func applySlips(corrections: [(original: String, corrected: String)], cleanLines: [String],
                                     now: Date) -> [MemoryArchive] {
        var list = slips

        // Add / bump single-token slips. The corrected sentence + blank position ride along so
        // the slip can seed a personalized cloze card.
        for c in corrections {
            guard let diff = Self.singleTokenDiff(c.original, c.corrected) else { continue }
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
            let mastered = cleanLines.contains { Self.containsWord($0, Self.normalize(slip.right)) }
            if mastered { healed.append(slip) }
            return mastered
        }
        var archived = healed.map { Self.archive($0, reason: .mastered) }

        // LRU-cap the rest.
        let (kept, dropped) = Self.evict(list, cap: Self.slipCap) { Self.archive($0, reason: .replacedByLRU) }
        archived += dropped
        slips = kept
        return archived
    }
}

// MARK: - Coach's Notes: the learner's own edits

extension LearnerMemory {
    /// Move an active word into the archive (the learner removed it).
    mutating func archiveVocab(id: String) -> MemoryArchive? {
        guard let i = vocab.firstIndex(where: { $0.id == id }) else { return nil }
        return Self.archive(vocab.remove(at: i), reason: .removedByUser)
    }

    mutating func archiveSlip(id: String) -> MemoryArchive? {
        guard let i = slips.firstIndex(where: { $0.id == id }) else { return nil }
        return Self.archive(slips.remove(at: i), reason: .removedByUser)
    }

    mutating func archiveSelfReport(id: String) -> MemoryArchive? {
        guard let i = selfReports.firstIndex(where: { $0.id == id }) else { return nil }
        return Self.archive(selfReports.remove(at: i), reason: .removedByUser)
    }

    mutating func setVocabPinned(_ id: String, pinned: Bool) {
        if let i = vocab.firstIndex(where: { $0.id == id }) { vocab[i].pinned = pinned }
    }

    mutating func setSlipPinned(_ id: String, pinned: Bool) {
        if let i = slips.firstIndex(where: { $0.id == id }) { slips[i].pinned = pinned }
    }

    mutating func setSelfReportPinned(_ id: String, pinned: Bool) {
        if let i = selfReports.firstIndex(where: { $0.id == id }) { selfReports[i].pinned = pinned }
    }

    /// Put an archived item back, pinned (a manual restore implies "keep this"). The caller then
    /// deletes the archived row.
    mutating func restore(kindRaw: String, payload: Data?) {
        guard let data = payload else { return }
        switch MemoryKind(rawValue: kindRaw) ?? .vocab {
        case .vocab:
            if var v = try? JSONDecoder().decode(VocabTouch.self, from: data) {
                v.pinned = true
                if !vocab.contains(where: { $0.id == v.id }) { vocab.append(v) }
            }
        case .slip:
            if var s = try? JSONDecoder().decode(LexicalSlip.self, from: data) {
                s.pinned = true
                if !slips.contains(where: { $0.id == s.id }) { slips.append(s) }
            }
        case .selfReport:
            if var n = try? JSONDecoder().decode(SelfReportNote.self, from: data) {
                n.pinned = true
                if !selfReports.contains(where: { $0.id == n.id }) { selfReports.append(n) }
            }
        }
    }

    /// Everything the coach remembers, gone (the caller also clears the archive).
    mutating func reset() {
        self = LearnerMemory()
    }
}

// MARK: - Helpers

extension LearnerMemory {
    static func archive(_ v: VocabTouch, reason: ArchiveReason) -> MemoryArchive {
        MemoryArchive(kind: .vocab, reason: reason, title: v.german, subtitle: v.english,
                      payload: try? JSONEncoder().encode(v))
    }

    static func archive(_ s: LexicalSlip, reason: ArchiveReason) -> MemoryArchive {
        MemoryArchive(kind: .slip, reason: reason, title: "\(s.wrong) → \(s.right)", subtitle: s.note,
                      payload: try? JSONEncoder().encode(s))
    }

    static func archive(_ n: SelfReportNote, reason: ArchiveReason) -> MemoryArchive {
        MemoryArchive(kind: .selfReport, reason: reason, title: n.text, subtitle: n.grammarFocus?.germanLabel ?? "",
                      payload: try? JSONEncoder().encode(n))
    }

    /// Drop least-recently-seen unpinned items past `cap`, archiving each.
    static func evict<T: Timestamped & Pinnable & Identifiable>(
        _ items: [T], cap: Int, makeArchive: (T) -> MemoryArchive
    ) -> (kept: [T], archived: [MemoryArchive]) {
        guard items.count > cap else { return (items, []) }
        // Oldest unpinned items are the eviction candidates (pinned ones are protected).
        let unpinnedOldest = items
            .filter { !$0.isPinned }
            .sorted { $0.seenAt < $1.seenAt }
        let overflow = items.count - cap
        let toDrop = Array(unpinnedOldest.prefix(overflow))
        let dropIDs = Set(toDrop.map(\.id))
        return (items.filter { !dropIDs.contains($0.id) }, toDrop.map(makeArchive))
    }

    /// Detects an exactly-one-word difference between two sentences (case/punct-insensitive
    /// comparison, original display forms preserved). Nil if 0 or more than 1 tokens differ.
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

    static func normalize(_ s: String) -> String {
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

/// Conformances that let `evict` treat vocab, slips and notes uniformly.
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
extension SelfReportNote: Timestamped, Pinnable {
    var seenAt: Date { notedAt }
    var isPinned: Bool { pinned }
}

// MARK: - On the wire

extension ArchivedMemoryRecord {
    init(id: UUID = UUID(), _ a: MemoryArchive, archivedAt: Date = Date()) {
        self.init(id: id, kindRaw: a.kind.rawValue, reasonRaw: a.reason.rawValue, archivedAt: archivedAt,
                  title: a.title, subtitle: a.subtitle, payload: a.payload.flatMap { try? SyncJSON(data: $0) })
    }

    var kind: MemoryKind { MemoryKind(rawValue: kindRaw) ?? .vocab }
    var reason: ArchiveReason { ArchiveReason(rawValue: reasonRaw) ?? .agedOut }
}

extension LearnerMemory {
    /// The sync payload's sections (`LearnerProfileRecord`, iOS `LearnerProfileCodec`): default
    /// `JSONEncoder` dates, and each slip and note carrying its computed `"id"`.
    init(record r: LearnerProfileRecord) {
        sessionCount = r.sessionCount
        lastSessionAt = r.lastSessionAt
        grammar = (try? r.grammar?.decoded(as: [String: GrammarSkill].self)) ?? [:]
        vocab = (try? r.vocab?.decoded(as: [VocabTouch].self)) ?? []
        slips = (try? r.slips?.decoded(as: [LexicalSlip].self)) ?? []
        selfReports = (try? r.selfReports?.decoded(as: [SelfReportNote].self)) ?? []
    }

    /// Write the sections into `record`, leaving untouched ones as they were (and every field
    /// this build doesn't know).
    func write(to r: inout LearnerProfileRecord, from old: LearnerMemory) {
        r.sessionCount = sessionCount
        r.lastSessionAt = lastSessionAt
        if grammar != old.grammar { r.grammar = grammar.isEmpty ? nil : Self.json(grammar) }
        if vocab != old.vocab { r.vocab = vocab.isEmpty ? nil : Self.json(vocab) }
        if slips != old.slips { r.slips = slips.isEmpty ? nil : Self.tagged(Self.json(slips), ids: slips.map(\.id)) }
        if selfReports != old.selfReports {
            r.selfReports = selfReports.isEmpty ? nil : Self.tagged(Self.json(selfReports), ids: selfReports.map(\.id))
        }
    }

    private static func json<T: Encodable>(_ value: T) -> SyncJSON? {
        (try? JSONEncoder().encode(value)).flatMap { try? SyncJSON(data: $0) }
    }

    /// Each item with its id written in as `"id"`, as `LearnerProfileCodec.taggedSlips` does.
    static func tagged(_ json: SyncJSON?, ids: [String]) -> SyncJSON? {
        guard let items = json?.arrayValue, items.count == ids.count else { return json }
        return .array(zip(items, ids).map { item, id in
            guard var object = item.objectValue else { return item }
            object["id"] = .string(id)
            return .object(object)
        })
    }
}
