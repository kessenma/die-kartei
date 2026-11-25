//
//  DiktatSentenceBank.swift
//  german-ai-flashcards
//
//  The sentences Diktat reads (docs/HOEREN.md ▸ Diktat). Bundled data only, never generated: a
//  dictation has to be right word for word, so every sentence comes from a list someone checked.
//
//  - The Goethe example sentences in a1/a2_vocabulary.json (b1 has none).
//  - The Tatoeba Perfekt examples in past_tense_verbs.json (`exampleSource == "tatoeba"`).
//  - The Kasus stories' sentences, which carry their targets' cases.
//  - A course: its recent handouts and its deck's example sentences (`DiktatCourseSource`).
//

import Foundation
import SwiftData

nonisolated enum DiktatSourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case vocab, perfekt, kasus, course
}

nonisolated struct DiktatSentence: Codable, Hashable, Sendable, Identifiable {
    var id: String { text }
    var text: String
    var english: String?
    var levelRaw: String
    var source: DiktatSourceKind
    /// The word the sentence was an example of, for "Save to deck".
    var headword: String?
    var headwordEnglish: String?
    /// Lowercased word → `GrammarFocus` raw value: what a word carries in this sentence (a Kasus
    /// target's case, a Perfekt participle or auxiliary). Feeds the ending-miss tag.
    var focusByWord: [String: String] = [:]

    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a1 }
    var focuses: [String: GrammarFocus] { focusByWord.compactMapValues(GrammarFocus.init(rawValue:)) }
}

/// The filters every source passes through. Pure, so a test can pin them.
nonisolated enum DiktatSentenceFilter {

    static func maxWords(for level: CEFRLevel) -> Int {
        switch level.hoerenRank {
        case 0: 8
        case 1: 12
        default: 16
        }
    }

    /// A sentence worth dictating: 3+ words, a capital first, a full stop or ! or ? last, no digits,
    /// brackets, slashes, dashes or abbreviations. Digits are out because a number is its own skill
    /// (Zahlen-Diktat) and "10 Uhr" would have to be typed in words.
    static func accepts(_ sentence: String, level: CEFRLevel) -> Bool {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = s.first, first.isUppercase, let last = s.last, ".!?".contains(last) else { return false }
        guard !s.contains(where: { $0.isNumber || "()/[]…–—_".contains($0) }) else { return false }
        guard !s.contains(" - "), !s.lowercased().contains("z. b"), !s.lowercased().contains("z.b") else { return false }
        let count = s.split(whereSeparator: { $0.isWhitespace }).count
        return count >= 3 && count <= maxWords(for: level)
    }

    /// One example field can hold several sentences ("Wie heißt du? Er schreibt wie ein Kind.").
    static func sentences(in text: String, level: CEFRLevel) -> [String] {
        WritingSentences.split(text).filter { accepts($0, level: level) }
    }
}

@MainActor
enum DiktatSentenceBank {

    private static var cache: [DiktatSentence]?

    /// Every bundled sentence, each at its own level, duplicates dropped.
    static var all: [DiktatSentence] {
        if let cache { return cache }
        var seen = Set<String>()
        var out: [DiktatSentence] = []
        func add(_ s: DiktatSentence) {
            guard seen.insert(s.text.lowercased()).inserted else { return }
            out.append(s)
        }

        for level in [GoetheLevel.a1, .a2] {
            let cefr = CEFRLevel(rawValue: level.rawValue) ?? .a1
            for entry in GoetheVocabService.entries(for: level) {
                guard let example = entry.example, !example.isEmpty else { continue }
                // Filtered at B1 length here; a level's own cap is applied when a round is built.
                for sentence in DiktatSentenceFilter.sentences(in: example, level: .b1) {
                    let head = entry.article.map { "\($0) \(entry.word)" } ?? entry.word
                    add(DiktatSentence(text: sentence, english: nil, levelRaw: cefr.rawValue, source: .vocab,
                                       headword: head, headwordEnglish: entry.translation))
                }
            }
        }

        for entry in PastTenseVerbService.allEntries where entry.exampleSource == "tatoeba" {
            guard let example = entry.example else { continue }
            for sentence in DiktatSentenceFilter.sentences(in: example, level: .b1) {
                var focus: [String: String] = [:]
                focus[entry.pastParticiple.lowercased()] = GrammarFocus.perfekt.rawValue
                for aux in entry.auxiliary == "sein" ? ["bin", "bist", "ist", "sind", "seid"]
                                                     : ["habe", "hast", "hat", "haben", "habt"] {
                    focus[aux] = GrammarFocus.perfekt.rawValue
                }
                add(DiktatSentence(text: sentence, english: nil, levelRaw: entry.level, source: .perfekt,
                                   headword: entry.infinitive, headwordEnglish: entry.translation,
                                   focusByWord: focus))
            }
        }

        for story in KasusStoryBank.bundled.stories {
            for paragraph in story.paragraphs {
                for sentence in DiktatSentenceFilter.sentences(in: paragraph.de, level: .b1) {
                    var focus: [String: String] = [:]
                    let lower = sentence.lowercased()
                    for target in story.targets where lower.contains(target.phrase.lowercased()) {
                        let tag = target.kasus.diktatFocus.rawValue
                        for word in DiktatScorer.words(target.phrase) { focus[word.core.lowercased()] = tag }
                    }
                    add(DiktatSentence(text: sentence, english: nil, levelRaw: story.level, source: .kasus,
                                       headword: nil, headwordEnglish: nil, focusByWord: focus))
                }
            }
        }

        cache = out
        return out
    }

    /// The sentences for a level: its own, plus some from the level below so a round is never
    /// all new. B1 has no vocabulary examples, so it also takes the long A2 sentences.
    static func pool(for level: CEFRLevel, sources: Set<DiktatSourceKind>) -> [DiktatSentence] {
        let cap = DiktatSentenceFilter.maxWords(for: level)
        let fits = all.filter { sources.contains($0.source) && wordCount($0.text) <= cap }
        switch level.hoerenRank {
        case 0:
            return fits.filter { $0.level == .a1 }
        case 1:
            return fits.filter { $0.level == .a2 || $0.level == .a1 }
        default:
            return fits.filter { $0.level.hoerenRank >= 2 || ($0.level == .a2 && wordCount($0.text) >= 9) }
        }
    }

    /// A round's sentences. At A2, about a third come from A1.
    static func round<R: RandomNumberGenerator>(level: CEFRLevel, sources: Set<DiktatSourceKind>,
                                                count: Int, rng: inout R) -> [DiktatSentence] {
        let pool = pool(for: level, sources: sources)
        if level == .a2 {
            let own = pool.filter { $0.level == .a2 }.shuffled(using: &rng)
            let below = pool.filter { $0.level == .a1 }.shuffled(using: &rng)
            let lower = min(below.count, count / 3)
            return Array((Array(own.prefix(count - lower)) + below.prefix(lower)).shuffled(using: &rng))
        }
        return Array(pool.shuffled(using: &rng).prefix(count))
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

/// A course as the source: the ear practises this week's class words.
@MainActor
enum DiktatCourseSource {

    /// Handouts from the last 14 days' entries (else the last three entries), then the example
    /// sentences on the course deck's cards. German sentences only.
    static func sentences(for course: ClassCourse, level: CEFRLevel, context: ModelContext) -> [DiktatSentence] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        let entries = course.entries.sorted { $0.date > $1.date }
        var recent = entries.filter { $0.date >= cutoff }
        if recent.isEmpty { recent = Array(entries.prefix(3)) }

        var seen = Set<String>()
        var out: [DiktatSentence] = []
        func add(_ text: String, headword: String? = nil, english: String? = nil) {
            guard WritingSentences.guessLanguage(text) == .german,
                  seen.insert(text.lowercased()).inserted else { return }
            out.append(DiktatSentence(text: text, english: nil, levelRaw: level.rawValue, source: .course,
                                      headword: headword, headwordEnglish: english))
        }

        for entry in recent {
            for material in entry.materials {
                for sentence in DiktatSentenceFilter.sentences(in: material.text, level: level) { add(sentence) }
            }
        }
        if let deck = ClassDeckStore.deck(for: course, context: context) {
            for card in deck.cards {
                guard let example = card.exampleSentence else { continue }
                for sentence in DiktatSentenceFilter.sentences(in: example, level: level) {
                    add(sentence, headword: card.germanWord, english: card.englishTranslation)
                }
            }
        }
        return out
    }

    /// Below this a course cannot fill a round, and the picker says why.
    static let minimum = 5
}

extension GrammarCase {
    /// The grammar point an ending miss on a Kasus target belongs to. A Nominativ ending is the
    /// article itself.
    nonisolated var diktatFocus: GrammarFocus {
        switch self {
        case .nominativ: .artikel
        case .akkusativ: .akkusativ
        case .dativ:     .dativ
        case .genitiv:   .genitiv
        }
    }
}
