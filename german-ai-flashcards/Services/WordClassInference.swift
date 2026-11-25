//
//  WordClassInference.swift
//  german-ai-flashcards
//
//  What part of speech a vocabulary row is. The bundled dictionary answers first
//  (`WiktionaryValidator.partsOfSpeech`); where it has never heard of the word — a compound a
//  teacher built, a phrase, a proper noun — the row's own shape is read instead.
//
//  The dictionary's answer comes in as data rather than being looked up here, so the rules can be
//  tested without a database and so the lookup stays where it has to be (the validator is not
//  thread-safe; see `WordClassTagger`).
//

import Foundation

nonisolated enum WordClassInference {

    /// The three definite articles, as a sheet writes them in front of a noun. Spelled out here
    /// rather than borrowed from `DocumentDeckService`, which is main-actor isolated.
    static let articles: Set<String> = ["der", "die", "das"]

    /// The row's class, or nil when nothing here is sure enough to put a tag on it. Pass the
    /// dictionary's parts of speech, an empty set when it does not know the word, or nil when there
    /// is no dictionary at all.
    static func classify(german: String, english: String, partsOfSpeech: Set<String>?) -> WordClass? {
        let word = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        if let pos = partsOfSpeech, !pos.isEmpty,
           let fromDict = fromDictionary(pos, isCapitalized: isCapitalized(headword(word) ?? word)) {
            return fromDict
        }
        return fromShape(german: word, english: english)
    }

    /// The dictionary's `pos` strings mapped across, with the capital as the tie-break.
    ///
    /// German nominalizes freely, so the dictionary offers a noun reading for a great many words
    /// that are not nouns here: "essen" is also "das Essen", "gestern" is also "das Gestern", "gut"
    /// is also "das Gut". Taking the noun reading every time made adverbs and adjectives come back
    /// as Nomen. German nouns are capitalized, so that is the signal: a **lowercase** word with any
    /// non-noun reading is not the noun. A lowercase word the dictionary knows *only* as a noun
    /// still reads as one — a sheet that wrote a noun in lower case is likelier than a dictionary
    /// with nothing else to say.
    static func fromDictionary(_ pos: Set<String>, isCapitalized: Bool) -> WordClass? {
        let noun = pos.contains("noun")
        let verb = pos.contains("verb")
        let adjective = pos.contains("adj") || pos.contains("adjective")
        let adverb = pos.contains("adv") || pos.contains("adverb")
        if noun, isCapitalized || !(verb || adjective || adverb) { return .noun }
        // An adjective before an adverb: German uses the bare adjective adverbially ("gut",
        // "schnell"), so the dictionary lists both and the adjective is the one being taught.
        if verb { return .verb }
        if adjective { return .adjective }
        if adverb { return .adverb }
        return noun ? .noun : nil
    }

    /// What the row itself gives away. Deliberately short: a phrase like "in aller Frühe" comes
    /// back nil and wears no tag, which is more honest than calling it a noun because it starts
    /// with a lowercase word.
    static func fromShape(german: String, english: String) -> WordClass? {
        let word = german.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = word.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = tokens.first else { return nil }

        // An article is the sheet saying "noun" out loud.
        if articles.contains(first.lowercased()), tokens.count > 1 { return .noun }

        let englishSide = english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if englishSide.hasPrefix("to ") { return .verb }

        guard tokens.count == 1 else { return nil }
        if isCapitalized(word) { return .noun }
        // An infinitive: lowercase and ending -en / -eln / -ern. "segeln", "wandern", "lächeln".
        let lower = word.lowercased()
        if lower.count >= 4, ["en", "ln", "rn"].contains(String(lower.suffix(2))) { return .verb }
        return nil
    }

    /// The form to look up in the dictionary: the article off, the first word only, a sheet's
    /// plural or gender note off the end.
    ///
    /// Deliberately *not* `DocumentDeckService.key`. That one answers "are these two rows the same
    /// card?" and must stay the single notion of a duplicate; this one answers "what word is this?"
    /// and is never used to compare two rows.
    static func headword(_ german: String) -> String? {
        var word = german.trimmingCharacters(in: .whitespacesAndNewlines)
        word = word.replacingOccurrences(of: VocabListParser.pluralEndingPattern, with: "",
                                         options: .regularExpression)
        word = word.replacingOccurrences(of: VocabListParser.genderMarkerPattern, with: "",
                                         options: .regularExpression)
        word = word.replacingOccurrences(of: #"\((pl|sg)\.?\)"#, with: "", options: .regularExpression)
        let tokens = word.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init)
        guard let first = tokens.first else { return nil }
        if articles.contains(first.lowercased()), tokens.count > 1 {
            return tokens[1]
        }
        return first
    }

    private static func isCapitalized(_ word: String) -> Bool {
        word.first?.isUppercase == true
    }
}
