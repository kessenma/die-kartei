//
//  JobVocabAnalyzer.swift
//  german-ai-flashcards
//
//  Counts the words of one or more job ads: which words come up, how often, and in how many of the
//  ads. Read several postings for the same kind of job and the words they share are the job's
//  vocabulary — „Kenntnisse“, „Erfahrung“, „eigenverantwortlich“, „abgeschlossenes Studium“ —
//  which is what is worth a flashcard first.
//
//  Pure Foundation + NaturalLanguage, no model, so it runs on the simulator, the Mac and in tests.
//  Word forms are grouped by a stem (`GermanStem`, CISTEM): „Kenntnisse“, „Kenntnissen“ and
//  „Kenntnis“ are one word, shown as its shortest spelling. Apple's tagger has no German lemmas
//  (`NLTagger.availableTagSchemes(for: .word, language: .german)` is language, script and token
//  type only), so a stemmer is what there is. A capitalised word (a noun) is kept apart from a
//  lowercase one with the same stem („Arbeit“ / „arbeiten“), unless it is only capitalised for
//  starting its line.
//  Phrases are the two-to-six-word runs that more than one ad uses, starting and ending on a
//  content word, so „Erfahrung in der Softwareentwicklung“ counts and „in der“ never does.
//

import Foundation
import NaturalLanguage

/// One posting's text, as the analyzer sees it.
nonisolated struct JobVocabSource: Hashable, Sendable {
    let id: UUID
    let title: String
    let text: String
}

/// A word (all its forms) or a phrase, with how often it came up.
nonisolated struct JobVocabTerm: Identifiable, Hashable, Sendable {
    /// The stem for a word (`N:` in front for a capitalised one), the lowercased words for a phrase.
    let key: String
    /// What the list shows and the card starts from: the shortest spelling for a word, the most
    /// common one for a phrase.
    var display: String
    /// Every spelling seen, with its count.
    var forms: [String: Int]
    /// Occurrences across all the ads.
    var total: Int
    /// The ads it appears in.
    var sources: Set<UUID>
    /// The first sentence it appears in, for the card's example and the context sheet.
    var example: String?
    var isPhrase: Bool
    /// An article, pronoun, preposition… (`GermanBasicWords`).
    var isBasic: Bool

    var id: String { (isPhrase ? "p:" : "w:") + key }
    var adCount: Int { sources.count }

    /// Spellings other than the one shown, most common first.
    var otherForms: [String] {
        forms.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
            .filter { $0.caseInsensitiveCompare(display) != .orderedSame }
    }

    /// Every spelling as `CardKind.matchKey` reads it: what "is this already in a deck" is
    /// checked against.
    var matchKeys: Set<String> {
        var keys = Set(forms.keys.map { CardKind.matchKey($0) })
        keys.insert(CardKind.matchKey(display))
        return keys
    }
}

nonisolated enum JobVocabAnalyzer {

    // MARK: - Words

    /// Every word of every source, its forms grouped (when `groupForms`), most widespread first:
    /// by the number of ads, then by total count, then alphabetically.
    static func words(in sources: [JobVocabSource], groupForms: Bool = true) -> [JobVocabTerm] {
        struct Group {
            var term: JobVocabTerm
            /// Every use was the first word of its line or sentence, so its capital proves nothing.
            var onlyInitial = true
        }
        var groups: [String: Group] = [:]
        for source in sources {
            for sentence in sentences(of: source.text) {
                for (index, token) in tokens(in: sentence).enumerated() {
                    guard isWordLike(token.text) else { continue }
                    let lower = token.text.lowercased()
                    let noun = token.text.first?.isUppercase == true
                    let stem = groupForms ? GermanStem.stem(lower) : lower
                    let key = (noun ? "N:" : "w:") + stem
                    var group = groups[key] ?? Group(term: JobVocabTerm(
                        key: stem, display: token.text, forms: [:], total: 0, sources: [],
                        example: nil, isPhrase: false, isBasic: false
                    ))
                    group.term.forms[token.text, default: 0] += 1
                    group.term.total += 1
                    group.term.sources.insert(source.id)
                    if group.term.example == nil { group.term.example = sentence }
                    if index > 0 { group.onlyInitial = false }
                    groups[key] = group
                }
            }
        }
        // „Fundierte Kenntnisse“ at the head of a bullet is the adjective „fundierte“: a
        // capitalised group seen only at the start of lines joins the lowercase one, when there is one.
        for (key, group) in groups where key.hasPrefix("N:") && group.onlyInitial {
            let lowerKey = "w:" + key.dropFirst(2)
            guard var lowercase = groups[lowerKey] else { continue }
            // Its capital was the line's, not the word's.
            for (form, count) in group.term.forms { lowercase.term.forms[form.lowercased(), default: 0] += count }
            lowercase.term.total += group.term.total
            lowercase.term.sources.formUnion(group.term.sources)
            lowercase.term.example = lowercase.term.example ?? group.term.example
            groups[lowerKey] = lowercase
            groups[key] = nil
        }
        return groups.map { key, group in finished(group.term, noun: key.hasPrefix("N:")) }.sorted(by: ranking)
    }

    /// The display form — the shortest spelling, which for most groups is the base form („Kunde“
    /// over „Kunden“, „Erfahrung“ over „Erfahrungen“), the more common one on a tie — and whether
    /// it is a basic word. A noun's key carries a mark so „Arbeit“ and „arbeiten“ stay two terms.
    private static func finished(_ term: JobVocabTerm, noun: Bool) -> JobVocabTerm {
        let display = term.forms.min { a, b in
            if a.key.count != b.key.count { return a.key.count < b.key.count }
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }?.key ?? term.display
        return JobVocabTerm(
            key: (noun ? "N:" : "") + term.key, display: display, forms: term.forms, total: term.total,
            sources: term.sources, example: term.example, isPhrase: false,
            isBasic: term.forms.keys.allSatisfy { GermanBasicWords.contains($0) }
        )
    }

    static func ranking(_ a: JobVocabTerm, _ b: JobVocabTerm) -> Bool {
        if a.adCount != b.adCount { return a.adCount > b.adCount }
        if a.total != b.total { return a.total > b.total }
        return a.display.localizedCaseInsensitiveCompare(b.display) == .orderedAscending
    }

    // MARK: - Phrases

    /// Runs of two to six words, starting and ending on a content word, that come up in at least
    /// `minimumAds` ads (with one ad, at least twice). A run inside a longer one that is just as
    /// widespread is left out, so „abgeschlossenes Studium“ isn't listed again inside
    /// „ein abgeschlossenes Studium der Informatik“.
    static func phrases(in sources: [JobVocabSource], minimumAds: Int? = nil) -> [JobVocabTerm] {
        let needed = minimumAds ?? (sources.count > 1 ? 2 : 1)
        var terms: [String: JobVocabTerm] = [:]
        for source in sources {
            for sentence in sentences(of: source.text) {
                let words = tokens(in: sentence).map(\.text)
                guard words.count >= 2 else { continue }
                for length in 2...6 where words.count >= length {
                    for start in 0...(words.count - length) {
                        let run = Array(words[start ..< start + length])
                        guard run.allSatisfy(isWordLike),
                              let first = run.first, let last = run.last,
                              !GermanBasicWords.contains(first), !GermanBasicWords.contains(last),
                              first.count > 2, last.count > 2 else { continue }
                        let text = run.joined(separator: " ")
                        let key = text.lowercased()
                        var term = terms[key] ?? JobVocabTerm(
                            key: key, display: text, forms: [:], total: 0, sources: [],
                            example: sentence, isPhrase: true, isBasic: false
                        )
                        term.forms[text, default: 0] += 1
                        term.total += 1
                        term.sources.insert(source.id)
                        terms[key] = term
                    }
                }
            }
        }
        let kept = terms.values.filter { term in
            sources.count > 1 ? term.adCount >= needed : term.total >= max(2, needed)
        }
        // Drop a run that a longer kept run contains and that is no more widespread than it.
        let pruned = kept.filter { term in
            !kept.contains { other in
                other.key.count > term.key.count
                    && (" " + other.key + " ").contains(" " + term.key + " ")
                    && other.adCount >= term.adCount && other.total >= term.total
            }
        }
        return pruned.map { term in
            var out = term
            out.display = term.forms.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? term.display
            return out
        }.sorted(by: ranking)
    }

    // MARK: - Context

    /// The text's sentences, with every line a sentence of its own: a posting's bullet lists carry
    /// no full stops, and a heading must not run into the line under it.
    static func sentences(of text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•·-–*▪︎◦"))
                .trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = trimmed
            tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
                let sentence = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { out.append(sentence) }
                return true
            }
        }
        return out
    }

    /// The first sentence of `text` holding `word` as a whole word (case-insensitive), or nil.
    static func sentence(containing word: String, in text: String) -> String? {
        let target = word.lowercased()
        let wanted = tokens(in: target).map(\.text)
        guard !wanted.isEmpty else { return nil }
        for sentence in sentences(of: text) {
            let words = tokens(in: sentence).map { $0.text.lowercased() }
            guard words.count >= wanted.count else { continue }
            for start in 0...(words.count - wanted.count) where Array(words[start ..< start + wanted.count]) == wanted {
                return sentence
            }
        }
        return nil
    }

    /// The words of a phrase worth a card of their own: no article, pronoun or preposition, no
    /// letterless bits, each once, in order.
    static func contentWords(of phrase: String) -> [String] {
        var seen = Set<String>()
        return tokens(in: phrase).map(\.text).filter { word in
            guard isWordLike(word), !GermanBasicWords.contains(word) else { return false }
            return seen.insert(word.lowercased()).inserted
        }
    }

    // MARK: - Tokens

    struct Token: Hashable {
        let text: String
        let range: NSRange
    }

    /// Letter runs, keeping inner hyphens and apostrophes („Full-Stack-Entwickler“, „geht's“).
    /// Digits end a word; a run that is only one letter („m/w/d“) is dropped by `isWordLike`.
    static func tokens(in text: String) -> [Token] {
        let ns = text as NSString
        var out: [Token] = []
        var start: Int? = nil
        func isLetter(_ c: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(c) else { return false }
            return CharacterSet.letters.contains(scalar)
        }
        func isJoiner(_ c: unichar) -> Bool { c == 0x2D || c == 0x27 || c == 0x2019 || c == 0x2011 }
        var i = 0
        while i <= ns.length {
            let c: unichar? = i < ns.length ? ns.character(at: i) : nil
            if let c, isLetter(c) {
                if start == nil { start = i }
            } else if let c, isJoiner(c), start != nil, i + 1 < ns.length, isLetter(ns.character(at: i + 1)) {
                // An inner hyphen or apostrophe: the word goes on.
            } else if let s = start {
                let range = NSRange(location: s, length: i - s)
                out.append(Token(text: ns.substring(with: range), range: range))
                start = nil
            }
            i += 1
        }
        return out
    }

    /// Two letters or more: single letters („m/w/d“) and stray marks go, „IT“ stays.
    static func isWordLike(_ word: String) -> Bool {
        word.count >= 2 && word.contains(where: \.isLetter)
    }
}
