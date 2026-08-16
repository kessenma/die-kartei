import Foundation
import NaturalLanguage

/// The words and phrases of a text that a glossary explains, in the form `SelectableGermanText`
/// needs them: surface forms as they actually appear, so marking them up is a word-by-word lookup.
struct GlossaryHighlight: Equatable {
    /// Lowercased single words occurring in the text, each mapped to the entry that explains it.
    var words: [String: GlossaryEntry] = [:]
    /// Multi-word terms, matched case-insensitively as literal spans.
    var phrases: [String] = []

    static let none = GlossaryHighlight()

    var isEmpty: Bool { words.isEmpty && phrases.isEmpty }

    /// The translations these words already have, keyed by the form they appear in. Feeding this to
    /// the word inspector answers a double-tap from the glossary instead of running the model.
    var wordTranslations: [String: KnownTranslation] {
        words.mapValues { KnownTranslation(german: $0.german, english: $0.english) }
    }
}

/// Works out which words in a story are the ones the glossary below explains, so the reader can see
/// at a glance what has a translation waiting.
///
/// The glossary lists dictionary forms ("die Katze", "gehen") while the story uses inflected ones
/// ("Katzen", "ging"), so matching goes through three passes, each narrower than a naive
/// substring search: the word itself, its lemma (`NLTagger` knows German), and finally a short
/// allow-list of inflection endings for the forms the lemmatizer misses. The endings are kept
/// deliberately tight — an unrelated compound ("Haus" vs. "Hausaufgabe") must never match.
enum StoryGlossaryHighlighter {

    static func highlight(for glossary: [GlossaryEntry], in text: String) -> GlossaryHighlight {
        guard !glossary.isEmpty, !text.isEmpty else { return .none }

        var targets: [Target] = []
        var phrases: [String] = []
        for entry in glossary {
            let term = headword(from: entry.german)
            guard term.count >= 2 else { continue }
            guard term.contains(" ") else {
                targets.append(Target(term, entry: entry))
                continue
            }
            // Multi-word entries ("zu Fuß", "sich freuen auf") mark the whole span when the story
            // uses them verbatim; otherwise fall back to their most distinctive word.
            if text.range(of: term, options: .caseInsensitive) != nil {
                phrases.append(term)
            } else if let longest = term.split(separator: " ").max(by: { $0.count < $1.count }),
                      longest.count >= 4 {
                targets.append(Target(String(longest), entry: entry))
            }
        }

        return GlossaryHighlight(words: surfaceForms(matching: targets, in: text), phrases: phrases)
    }

    // MARK: - Headwords

    /// Strip a glossary entry down to the word to look for: no article, no "(sich)", no plural hint
    /// after a comma ("der Hund, -e").
    private static func headword(from raw: String) -> String {
        var term = raw.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        if let comma = term.firstIndex(of: ",") { term = String(term[..<comma]) }
        term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["der ", "die ", "das ", "ein ", "eine ", "sich "]
        where term.lowercased().hasPrefix(article) {
            term = String(term.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
        }
        return term.trimmingCharacters(in: .whitespaces)
    }

    private struct Target {
        /// The headword, lowercased: matched outright and against each word's lemma.
        let key: String
        /// For an infinitive, the stem the conjugated forms are built on ("gehen" → "geh").
        /// Only lowercase headwords qualify, so the noun "das Leben" doesn't claim "lebt".
        let stem: String?
        /// The glossary entry this headword came from, carried through so a matched form keeps its
        /// translation.
        let entry: GlossaryEntry

        init(_ headword: String, entry: GlossaryEntry) {
            self.entry = entry
            key = headword.lowercased()
            if headword.first?.isUppercase == false, headword.count > 3 {
                let candidate = headword.hasSuffix("en")
                    ? String(headword.dropLast(2))
                    : (headword.hasSuffix("n") ? String(headword.dropLast()) : nil)
                stem = (candidate?.count ?? 0) >= 3 ? candidate?.lowercased() : nil
            } else {
                stem = nil
            }
        }

        func matches(word: String, lemma: String?) -> Bool {
            if word == key || lemma == key { return true }
            if let ending = word.suffix(after: key),
               StoryGlossaryHighlighter.inflectionEndings.contains(ending) { return true }
            if let stem, let ending = word.suffix(after: stem),
               StoryGlossaryHighlighter.verbEndings.contains(ending) { return true }
            return false
        }
    }

    // MARK: - Matching

    /// Case, plural and adjective endings a headword can pick up in a sentence.
    private static let inflectionEndings: Set<String> = ["e", "n", "en", "s", "es", "er", "ern", "em"]
    /// Endings on a verb stem, including the bare stem (the imperative).
    private static let verbEndings: Set<String> = ["", "e", "st", "t", "et", "en", "te", "test", "tet", "ten"]

    private static func surfaceForms(matching targets: [Target], in text: String) -> [String: GlossaryEntry] {
        guard !targets.isEmpty else { return [:] }
        var forms: [String: GlossaryEntry] = [:]
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(.german, range: text.startIndex..<text.endIndex)
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            let word = String(text[range]).lowercased()
            guard word.count >= 2, forms[word] == nil else { return true }
            let lemma = tag?.rawValue.lowercased()
            if let target = targets.first(where: { $0.matches(word: word, lemma: lemma) }) {
                forms[word] = target.entry
            }
            return true
        }
        return forms
    }
}

private extension String {
    /// What's left of this string after `prefix`, or nil when it doesn't start with it.
    func suffix(after prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
