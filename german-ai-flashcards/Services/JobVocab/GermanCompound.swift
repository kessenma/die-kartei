//
//  GermanCompound.swift
//  german-ai-flashcards
//
//  Breaking a compound noun into the words it is built from: „Softwareentwicklung“ is Software +
//  Entwicklung, „Berufserfahrung“ Beruf + Erfahrung (with the linking „s“),
//  „Kundenservicemitarbeiter“ Kunde + Service + Mitarbeiter. Job ads are made of these, and a
//  learner who knows both halves knows the word.
//
//  Dictionary-based: a split is only offered when every part is a word the app knows — the
//  Goethe lists, the learner's cards, the job-ad formulas, and the words the ads themselves use on
//  their own. The last part (the head, which gives the gender and the meaning) must be a noun. A
//  word the dictionary already has is never split („Mitarbeiter“ is not mit + Arbeiter). When
//  nothing fits, there is no split: no guessing.
//

import Foundation

nonisolated struct GermanCompoundLexicon: Sendable {
    /// Lowercased word → the spelling to show.
    private(set) var words: [String: String] = [:]
    /// Stem → the spelling to show, nouns only, for an inflected last part („…entwicklungen“).
    private(set) var nounStems: [String: String] = [:]
    /// Lowercased nouns.
    private(set) var nouns: Set<String> = []
    /// Words known as words in their own right (the lists, cards, formulas): never split. The
    /// ads' own words are parts only, since an ad's compound is what is being split.
    private(set) var whole: Set<String> = []

    init() {}

    /// Add a word. `noun`: it is a noun (an article, a capital in the middle of a sentence).
    /// `asWhole`: a word in its own right, which is never split (false for the ads' own words).
    mutating func add(_ word: String, noun: Bool, asWhole: Bool = true) {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, !trimmed.contains(" "), trimmed.allSatisfy({ $0.isLetter || $0 == "-" }) else { return }
        let lower = trimmed.lowercased()
        if asWhole { whole.insert(lower) }
        if words[lower] == nil || noun { words[lower] = noun ? capitalised(trimmed) : trimmed }
        if noun {
            nouns.insert(lower)
            nounStems[GermanStem.stem(lower)] = nounStems[GermanStem.stem(lower)] ?? capitalised(trimmed)
        }
    }

    fileprivate func noun(_ lower: String) -> String? {
        if nouns.contains(lower) { return words[lower] }
        return nounStems[GermanStem.stem(lower)]
    }

    fileprivate func anyWord(_ lower: String) -> String? {
        guard !GermanBasicWords.contains(lower) else { return nil }
        return words[lower]
    }

    private func capitalised(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }
}

nonisolated enum GermanCompound {

    /// The parts of `word`, or nil when it is no compound the lexicon can account for.
    static func split(_ word: String, lexicon: GermanCompoundLexicon) -> [String]? {
        guard word.count >= 8, word.first?.isUppercase == true, !word.contains("-") else { return nil }
        if lexicon.whole.contains(word.lowercased()) { return nil }
        return parts(of: word.lowercased(), lexicon: lexicon, depth: 0)
    }

    /// The linking letters between two parts: Arbeit-s-zeit, Kunde-n-service, Hund-e-hütte.
    private static let linkers = ["", "s", "es", "n", "en", "e", "er"]

    private static func parts(of lower: String, lexicon: GermanCompoundLexicon, depth: Int) -> [String]? {
        guard depth < 4 else { return nil }
        let letters = Array(lower)
        // The longest last part first: the head is what the word is.
        for cut in 3 ..< max(3, letters.count - 3) {
            let tail = String(letters[cut...])
            guard tail.count >= 4, let headNoun = lexicon.noun(tail) else { continue }
            let front = String(letters[..<cut])
            for linker in linkers where front.hasSuffix(linker) {
                let stem = String(front.dropLast(linker.count))
                guard stem.count >= 3 else { continue }
                if let first = firstPart(stem, lexicon: lexicon) {
                    return [first, headNoun]
                }
                // The front may be a compound of its own.
                if let more = parts(of: stem, lexicon: lexicon, depth: depth + 1) {
                    return more + [headNoun]
                }
            }
        }
        return nil
    }

    /// A first part: a known word, or a verb stem whose infinitive is known (schreib- → schreiben,
    /// as in „Schreibtisch“), or a noun that drops its „-e“ (Schul- → Schule).
    private static func firstPart(_ stem: String, lexicon: GermanCompoundLexicon) -> String? {
        if let word = lexicon.anyWord(stem) { return word }
        if let verb = lexicon.anyWord(stem + "en") ?? lexicon.anyWord(stem + "n") { return verb }
        if let noun = lexicon.anyWord(stem + "e") { return noun }
        return nil
    }
}

extension GermanCompoundLexicon {
    /// The Goethe lists, the job-ad formulas, and the given extra words: the learner's cards
    /// (`asWhole`) and the ads' own words (parts only).
    @MainActor
    static func standard(extra: [(word: String, noun: Bool, asWhole: Bool)] = []) -> GermanCompoundLexicon {
        var lexicon = GermanCompoundLexicon()
        for word in GoetheVocabService.orderedWords {
            lexicon.add(word.word, noun: word.article != nil || word.wordType == .noun)
        }
        for formula in JobAdGlossary.all where !JobAdGlossary.searchKey(formula.german).contains(" ") {
            let split = CardKind.split(formula.german)
            lexicon.add(split.word, noun: split.article != nil)
        }
        for item in extra { lexicon.add(item.word, noun: item.noun, asWhole: item.asWhole) }
        return lexicon
    }
}
