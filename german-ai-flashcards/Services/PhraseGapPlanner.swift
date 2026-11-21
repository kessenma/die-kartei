//
//  PhraseGapPlanner.swift
//  german-ai-flashcards
//
//  Which word of a phrase card to hide, and what to offer in its place. A phrase is hard not for
//  its words but for which ones go together: "eine Störung ___" (beheben), "Erfahrung ___ Git"
//  (mit). So the gap goes where the phrase is learned:
//
//   1. a known verb + preposition pair ("sich freuen auf") → the preposition,
//   2. a verb in its infinitive ("eine Störung beheben") → the verb,
//   3. a preposition ("fundierte Kenntnisse in Python") → the preposition,
//   4. otherwise the longest content word; in a whole sentence, its key noun.
//
//  The three other choices are of the same kind, so the shape never gives the answer away:
//  prepositions from a common list, verbs from the deck and then a short list, words from the
//  deck. Too few → no gap, and the card stays a normal flip card. Pure and seeded: the same deck
//  deals the same questions every time it is drawn. See docs/PHRASES.md.
//

import Foundation

nonisolated struct PhraseGapQuestion: Hashable, Sendable {
    enum Kind: String, Sendable { case preposition, verb, word }

    /// The phrase as printed, split on spaces.
    let tokens: [String]
    let hiddenIndex: Int
    /// The hidden word without the punctuation around it.
    let answer: String
    /// The answer and three others, shuffled.
    let options: [String]
    let kind: Kind

    /// The token with its word replaced by a blank, punctuation kept ("beheben." → "_____.").
    func blanked(_ blank: String = "_____") -> [String] {
        tokens.enumerated().map { index, token in
            index == hiddenIndex ? token.replacingOccurrences(of: answer, with: blank) : token
        }
    }
}

nonisolated enum PhraseGapPlanner {

    /// What the planner knows about the rest of the deck, for distractors.
    struct DeckWord: Sendable {
        var german: String
        var wordType: String?
    }

    /// A gap for every phrase card that can have one, by card index.
    static func questions(
        for cards: [DeckWord],
        isVerb: (String) -> Bool,
        verbPrepositions: Set<String> = [],
        seed: UInt64 = 0
    ) -> [Int: PhraseGapQuestion] {
        // First find every gap, so the verbs other phrases hide can stand in for each other.
        var gaps: [Int: Gap] = [:]
        for (index, card) in cards.enumerated() where card.wordType == CardKind.phrase || CardKind.isPhrase(card.german) {
            if let gap = gap(in: card.german, isVerb: isVerb, verbPrepositions: verbPrepositions) { gaps[index] = gap }
        }
        let phraseVerbs = gaps.values.filter { $0.kind == .verb }.map(\.answer)
        let deckVerbs = cards.filter { $0.wordType?.lowercased() == "verb" && !$0.german.contains(" ") }.map(\.german)
        let deckNouns = cards.filter { $0.wordType?.lowercased() == "noun" && !$0.german.contains(" ") }.map(\.german)
        let deckOthers = cards.filter {
            !$0.german.contains(" ") && !["noun", "verb", CardKind.phrase].contains($0.wordType?.lowercased() ?? "")
        }.map(\.german)

        var out: [Int: PhraseGapQuestion] = [:]
        for (index, gap) in gaps.sorted(by: { $0.key < $1.key }) {
            var rng = SeededGenerator(seed: seed &+ UInt64(index) &* 2_654_435_761 &+ 1)
            let pool: [String]
            switch gap.kind {
            case .preposition:
                pool = commonPrepositions.shuffled(using: &rng)
            case .verb:
                // The deck's own verbs first: they are the ones that could really be confused.
                pool = (deckVerbs + phraseVerbs).filter(looksInfinitive).shuffled(using: &rng)
                    + commonVerbs.shuffled(using: &rng)
            case .word:
                let isNoun = gap.answer.first?.isUppercase == true
                pool = (isNoun ? deckNouns + capitalizedWords(in: gaps.values.map(\.tokens)) : deckOthers)
                    .shuffled(using: &rng)
            }
            var seen: Set<String> = [gap.answer.lowercased()]
            var distractors: [String] = []
            for word in pool where distractors.count < 3 {
                let clean = core(word)
                guard clean.count >= 2, seen.insert(clean.lowercased()).inserted else { continue }
                distractors.append(clean)
            }
            guard distractors.count == 3 else { continue }
            out[index] = PhraseGapQuestion(tokens: gap.tokens, hiddenIndex: gap.index, answer: gap.answer,
                                           options: ([gap.answer] + distractors).shuffled(using: &rng), kind: gap.kind)
        }
        return out
    }

    // MARK: - The gap

    struct Gap: Equatable {
        var tokens: [String]
        var index: Int
        var answer: String
        var kind: PhraseGapQuestion.Kind
    }

    /// Where the gap goes in one phrase, or nil when it has no word worth hiding.
    static func gap(in phrase: String, isVerb: (String) -> Bool, verbPrepositions: Set<String> = []) -> Gap? {
        let tokens = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        let cores = tokens.map(core)
        guard tokens.count >= 2 else { return nil }
        let lowered = cores.map { $0.lowercased() }
        func make(_ index: Int, _ kind: PhraseGapQuestion.Kind) -> Gap {
            Gap(tokens: tokens, index: index, answer: cores[index], kind: kind)
        }

        let prepositionIndexes = lowered.indices.filter { commonPrepositionSet.contains(lowered[$0]) }
        let verbIndexes = cores.indices.filter { index in
            let word = cores[index]
            guard looksInfinitive(word), word.first?.isLowercase == true,
                  !commonPrepositionSet.contains(lowered[index]), !fillers.contains(lowered[index]) else { return false }
            return isVerb(word) || index == cores.count - 1
        }
        let isSentence = tokens.count >= 4 && (tokens.last?.last).map { ".!?".contains($0) } == true

        // 1. A verb + preposition pair the app teaches: the preposition is the point.
        for v in verbIndexes {
            for p in prepositionIndexes where verbPrepositions.contains("\(lowered[v]) \(lowered[p])") {
                return make(p, .preposition)
            }
        }
        if !isSentence {
            // 2. The verb (the last one: German phrases end on the infinitive).
            if let v = verbIndexes.last { return make(v, .verb) }
            // 3. The preposition.
            if let p = prepositionIndexes.first { return make(p, .preposition) }
        }
        // 4. The longest content word; in a sentence, a noun that isn't its first word.
        let content = cores.indices.filter { cores[$0].count >= 3 && !fillers.contains(lowered[$0]) }
        let nouns = content.filter { $0 > 0 && cores[$0].first?.isUppercase == true }
        let candidates = isSentence && !nouns.isEmpty ? nouns : content
        guard let best = candidates.max(by: { a, b in
            cores[a].count != cores[b].count ? cores[a].count < cores[b].count : a < b
        }) else { return nil }
        return make(best, .word)
    }

    // MARK: - Words

    static let commonPrepositions = ["in", "an", "auf", "mit", "für", "von", "zu", "bei", "über", "nach",
                                     "aus", "um", "unter", "vor", "gegen", "ohne", "durch", "seit"]
    private static let commonPrepositionSet = Set(commonPrepositions)

    static let commonVerbs = ["machen", "haben", "geben", "nehmen", "bringen", "stellen", "führen", "halten",
                              "finden", "lassen", "setzen", "legen", "holen", "zeigen", "suchen", "schreiben"]

    /// Articles, pronouns and placeholders: never the gap.
    private static let fillers: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines",
        "sich", "ich", "du", "er", "sie", "es", "wir", "ihr", "mich", "dich", "mir", "dir", "uns", "euch",
        "und", "oder", "aber", "nicht", "etw", "etwas", "jdn", "jdm", "jds", "jemand", "jemanden", "jemandem",
    ]

    /// "beheben", "ändern", "sammeln", "sein", "tun".
    static func looksInfinitive(_ word: String) -> Bool {
        let w = word.lowercased()
        if w == "sein" || w == "tun" { return true }
        return w.count >= 4 && (w.hasSuffix("en") || w.hasSuffix("ern") || w.hasSuffix("eln"))
    }

    /// The word without punctuation around it ("Python." → "Python", "„gut“" → "gut").
    static func core(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces))
    }

    private static func capitalizedWords(in phrases: [[String]]) -> [String] {
        phrases.flatMap { $0.dropFirst() }.map(core).filter { $0.count >= 3 && $0.first?.isUppercase == true }
    }
}
