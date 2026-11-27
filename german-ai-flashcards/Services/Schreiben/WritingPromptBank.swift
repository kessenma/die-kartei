//
//  WritingPromptBank.swift
//  german-ai-flashcards
//
//  The bundled writing prompts (`writing_prompts.json`): hand-written, one German question or
//  instruction with its English, a level, a kind (Tagebuch or Aufsatz), topics, and for an essay a
//  target length and a few sentence starters. Loaded once, like `StoryStarters`.
//
//  Content pack rules (docs/GRAMMAR_EXERCISES.md): a gate with stable codes, asserted in DEBUG at
//  first use and run by `-schreiben.debugVerify 1`; golden counts per level and kind in
//  `WritingPromptFixtures`, checked by the tests; and `scripts/check_content.py` reads the same
//  file. No model writes prompts into the bank; a tutor may write one at runtime, through
//  `WritingPromptGate`, and it is never stored here.
//

import Foundation

struct WritingPrompt: Codable, Identifiable, Hashable {
    struct Target: Codable, Hashable {
        var min: Int
        var max: Int
    }

    let id: String
    let de: String
    let en: String
    /// `CEFRLevel` raw value.
    let level: String
    /// `JournalKind` raw value.
    let kind: String
    let topics: [String]
    /// `GrammarFocus` raw value the prompt elicits, if any.
    var focus: String? = nil
    var targetWords: Target? = nil
    var scaffold: [String]? = nil

    var cefr: CEFRLevel { CEFRLevel(rawValue: level) ?? .a2 }
    var journalKind: JournalKind { JournalKind(rawValue: kind) ?? .aufsatz }
    var grammarFocus: GrammarFocus? { focus.flatMap(GrammarFocus.init(rawValue:)) }
}

extension CEFRLevel {
    /// How long an essay at this level should be, in words: the written-task lengths of the
    /// level's exam, give or take.
    var essayWordRange: ClosedRange<Int> {
        switch self {
        case .a1: 30...60
        case .a2: 60...110
        case .b1: 110...180
        case .b2: 180...280
        case .c1: 250...400
        }
    }
}

nonisolated enum WritingPromptBank {
    private struct File: Decodable {
        var version: Int
        var prompts: [WritingPrompt]
    }

    private static let cache: [WritingPrompt] = {
        guard let url = AppResources.url("writing_prompts", "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        #if DEBUG
        let issues = validate(file.prompts)
        assert(issues.isEmpty, "writing_prompts.json: \(issues.joined(separator: "; "))")
        #endif
        return file.prompts
    }()

    /// Every prompt, in file order.
    static var all: [WritingPrompt] { cache }

    static func find(id: String) -> WritingPrompt? { cache.first { $0.id == id } }

    static func prompts(level: CEFRLevel? = nil, kind: JournalKind? = nil) -> [WritingPrompt] {
        cache.filter { (level == nil || $0.level == level!.rawValue) && (kind == nil || $0.kind == kind!.rawValue) }
    }

    /// Topic names in first-appearance order, for the browse list.
    static func topics(level: CEFRLevel? = nil, kind: JournalKind? = nil) -> [String] {
        var seen = Set<String>()
        return prompts(level: level, kind: kind).flatMap(\.topics).filter { seen.insert($0).inserted }
    }

    /// The learner's level, or the nearest the bank has (the bank stops at B2).
    static func bankLevel(for level: CEFRLevel) -> CEFRLevel { level == .c1 ? .b2 : level }

    /// A prompt that practises one of the learner's shaky structures at their level (worst-first),
    /// else nil.
    static func coachPick(level: CEFRLevel, kind: JournalKind, shaky: [GrammarFocus], excluding: Set<String> = []) -> WritingPrompt? {
        let pool = prompts(level: bankLevel(for: level), kind: kind).filter { !excluding.contains($0.id) }
        for focus in shaky {
            if let hit = pool.filter({ $0.focus == focus.rawValue }).randomElement() { return hit }
        }
        return nil
    }

    /// A random prompt at the level, avoiding `excluding` when possible.
    static func random(level: CEFRLevel, kind: JournalKind, excluding: Set<String> = []) -> WritingPrompt? {
        let pool = prompts(level: bankLevel(for: level), kind: kind)
        let fresh = pool.filter { !excluding.contains($0.id) }
        return (fresh.isEmpty ? pool : fresh).randomElement()
    }

    /// A stable pick for a day: the same prompt all day, a different one tomorrow.
    static func daily(level: CEFRLevel, kind: JournalKind, dayIndex: Int) -> WritingPrompt? {
        let pool = prompts(level: bankLevel(for: level), kind: kind)
        guard !pool.isEmpty else { return nil }
        return pool[((dayIndex % pool.count) + pool.count) % pool.count]
    }

    // MARK: - The gate

    static let scaffoldCap = 4

    /// A1 < A2 < B1 < B2 < C1, for "introduced at or below the prompt's level".
    static func rank(_ level: CEFRLevel) -> Int { CEFRLevel.allCases.firstIndex(of: level) ?? 0 }

    /// Every way a prompt can be wrong, as `id: code` lines. Empty when the bank is sound.
    static func validate(_ prompts: [WritingPrompt]) -> [String] {
        var issues: [String] = []
        var ids = Set<String>()
        for p in prompts {
            func flag(_ code: String) { issues.append("\(p.id): \(code)") }
            if p.id.isEmpty { flag("empty-id") }
            if !ids.insert(p.id).inserted { flag("duplicate-id") }
            guard let level = CEFRLevel(rawValue: p.level) else { flag("bad-level"); continue }
            if level == .c1 { flag("level-above-bank") }
            guard let kind = JournalKind(rawValue: p.kind) else { flag("bad-kind"); continue }
            let de = p.de.trimmingCharacters(in: .whitespacesAndNewlines)
            if de.isEmpty { flag("empty-de") }
            if de != p.de { flag("whitespace") }
            if let last = de.last, !"?.!".contains(last) { flag("no-final-punctuation") }
            if WritingSentences.split(de).count > 2 { flag("too-many-sentences") }
            if p.en.trimmingCharacters(in: .whitespaces).isEmpty { flag("empty-en") }
            if p.topics.isEmpty || p.topics.contains(where: { $0.isEmpty }) { flag("no-topics") }
            if let focus = p.focus {
                if let f = GrammarFocus(rawValue: focus) {
                    if rank(f.introducedAt) > rank(level) { flag("focus-above-level") }
                } else {
                    flag("unknown-focus")
                }
            }
            switch kind {
            case .aufsatz:
                guard let t = p.targetWords else { flag("missing-target"); break }
                if t.min >= t.max { flag("target-order") }
                let range = level.essayWordRange
                if t.min < range.lowerBound || t.max > range.upperBound { flag("target-outside-level") }
            case .tagebuch:
                if p.targetWords != nil { flag("tagebuch-with-target") }
            }
            if let s = p.scaffold {
                if s.count > scaffoldCap { flag("too-much-scaffold") }
                if s.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) { flag("empty-scaffold") }
            }
        }
        return issues
    }

    #if DEBUG
    /// `-schreiben.debugVerify 1`: the gate over the shipped file, the golden counts, and the
    /// prompt gate on a few fixtures.
    static func runDebugVerification() -> String {
        var lines: [String] = []
        let issues = validate(all)
        lines.append(issues.isEmpty ? "pass  bank gate (\(all.count) prompts)" : "FAIL  bank gate: " + issues.joined(separator: "; "))
        for (key, expected) in WritingPromptFixtures.golden.sorted(by: { $0.key < $1.key }) {
            let parts = key.split(separator: "/")
            let n = all.filter { $0.level == parts[0] && $0.kind == parts[1] }.count
            lines.append(n == expected ? "pass  \(key): \(n)" : "FAIL  \(key): \(n), golden \(expected)")
        }
        for (text, ok) in WritingPromptFixtures.gateCases {
            let accepted = WritingPromptGate.accept(text) != nil
            lines.append(accepted == ok ? "pass  gate \(ok ? "accepts" : "rejects") \(text.prefix(30))…"
                                        : "FAIL  gate \(ok ? "rejected" : "accepted") \(text.prefix(30))…")
        }
        let failed = lines.contains { $0.hasPrefix("FAIL") }
        return (failed ? "Schreiben FAILED\n" : "Schreiben ALL OK\n") + lines.joined(separator: "\n")
    }
    #endif
}

// MARK: - Golden numbers

enum WritingPromptFixtures {
    /// Prompts per level and kind in the shipped bank. A change here is a content decision.
    static let golden: [String: Int] = [
        "A1/aufsatz": 10, "A2/aufsatz": 12, "B1/aufsatz": 10, "B2/aufsatz": 8,
        "A1/tagebuch": 6, "A2/tagebuch": 8, "B1/tagebuch": 6, "B2/tagebuch": 4,
    ]

    static var total: Int { golden.values.reduce(0, +) }

    /// Tutor-written prompts and whether the gate should take them.
    static let gateCases: [(String, Bool)] = [
        ("Beschreibe deinen letzten Urlaub. Was hat dir am besten gefallen?", true),
        ("Was würdest du machen, wenn du einen freien Tag hättest?", true),
        ("Describe your last holiday and what you liked best.", false),
        ("Prompt: Beschreibe deinen Urlaub. Antwort: Ich war am Meer.", false),
        ("Ja.", false),
        ("Beschreibe deinen Urlaub, deine Familie, dein Haus, deine Stadt, deine Arbeit, deine Freunde, dein Essen, deine Hobbys, deine Pläne, deine Träume, deine Sorgen, deine Wünsche und deine Ziele für das nächste Jahr und erkläre alles", false),
    ]
}

// MARK: - The gate on a tutor-written prompt

/// A prompt the tutor wrote at runtime passes only when it looks like one of the bank's: German,
/// one or two sentences, a question or an instruction, nothing leaked from the instructions.
nonisolated enum WritingPromptGate {
    static let imperatives: Set<String> = [
        "beschreibe", "beschreib", "erzähl", "erzähle", "schreib", "schreibe", "erkläre", "erklär",
        "berichte", "vergleiche", "begründe", "nimm", "erörtere", "stell", "stelle", "nenne", "überlege",
    ]

    static let englishTells: Set<String> = ["the", "and", "you", "your", "write", "describe", "about", "what", "would"]

    /// The accepted prompt, cleaned, or nil.
    static func accept(_ reply: String) -> String? {
        let cleaned = ConversationPrompts.stripThinkBlocks(reply)
        guard let first = cleaned.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*-• \"„“”")) })
            .first(where: { !$0.isEmpty }) else { return nil }
        var text = first
        for label in ["Prompt:", "Aufgabe:", "Thema:", "Frage:"] where text.hasPrefix(label) {
            text = String(text.dropFirst(label.count))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \"„“”«»'"))
        let lowered = text.lowercased()
        if lowered.contains("antwort:") || lowered.contains("struggle") || lowered.contains("fix:") { return nil }
        guard let last = text.last, "?.!".contains(last) else { return nil }
        let sentences = WritingSentences.split(text)
        guard (1...2).contains(sentences.count) else { return nil }
        let words = WritingSentences.words(in: lowered)
        guard (3...30).contains(words.count) else { return nil }
        guard !words.contains(where: { englishTells.contains($0) }) else { return nil }
        let german = words.contains { WritingSentences.germanMarkers.contains($0) || imperatives.contains($0) }
            || lowered.contains(where: { "äöüß".contains($0) })
        guard german else { return nil }
        return text
    }
}
