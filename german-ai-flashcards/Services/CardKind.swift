//
//  CardKind.swift
//  german-ai-flashcards
//
//  One word or a phrase? Decided from the German text alone, in one place, for every path that
//  saves a card. A phrase ("eine Störung beheben", "der Meinung sein") is stored whole, with no
//  article split off and `wordType == CardKind.phrase`, so it never reaches the article quiz, the
//  dictionary's gender guess, or the der/die/das game. See docs/PHRASES.md.
//

import Foundation

nonisolated enum CardKind {
    /// The `SavedCard.wordType` / `VocabCard.wordType` value for a phrase. Deliberately not a
    /// `WordClass` case: that enum is the parser's four word classes.
    static let phrase = "phrase"

    private static let articles: Set<String> = ["der", "die", "das"]

    /// A card's German, split for saving.
    struct Split: Equatable {
        /// The text to store as `germanWord`: the word without its article, or the whole phrase.
        let word: String
        /// der / die / das (lowercased) when the text is an article plus one word.
        let article: String?
        let isPhrase: Bool
        /// The forms the sheet listed after the word, for the card's caption (`listedForms`):
        /// "neckte / hat geneckt", "Plural: die Kieselsteine". Nil when it listed none.
        var forms: String? = nil
        /// The listed forms were a verb's principal parts.
        var formsAreVerbs: Bool = false

        /// What to store as `wordType` when nothing better is known.
        var wordType: String? {
            if isPhrase { return CardKind.phrase }
            if article != nil { return "noun" }
            return formsAreVerbs ? "verb" : nil
        }
    }

    /// Splits a leading der/die/das off only when exactly one word follows it ("das Ticket",
    /// "der First-Level-Support"); anything longer is a phrase and stays whole ("der Meinung sein").
    /// A word followed by the forms a sheet lists for it ("necken / neckte / hat geneckt") is that
    /// word, with the forms set apart in `forms`: one word, not a six-word phrase.
    static func split(_ german: String) -> Split {
        let trimmed = german.trimmingCharacters(in: .whitespacesAndNewlines)
        if let listed = listedForms(trimmed) {
            let head = split(listed.headword)
            return Split(word: head.word, article: head.article, isPhrase: head.isPhrase,
                         forms: listed.forms, formsAreVerbs: listed.isVerb)
        }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first else { return Split(word: trimmed, article: nil, isPhrase: false) }
        if tokens.count >= 2, articles.contains(first.lowercased()) {
            let rest = Array(tokens.dropFirst())
            guard isOneWord(rest) else { return Split(word: trimmed, article: nil, isPhrase: true) }
            return Split(word: rest.joined(separator: " "), article: first.lowercased(), isPhrase: false)
        }
        return Split(word: trimmed, article: nil, isPhrase: !isOneWord(tokens))
    }

    /// Whether this German, as typed or printed, is a phrase.
    static func isPhrase(_ german: String) -> Bool { split(german).isPhrase }

    /// Whether a stored card holds a phrase: tagged as one, or several words once its article
    /// (stored apart on older cards) is put back in front.
    static func isPhrase(germanWord: String, article: String?, wordType: String?) -> Bool {
        if wordType == phrase { return true }
        return isPhrase(joined(germanWord, article: article))
    }

    /// "Meinung sein" + der → "der Meinung sein"; a word that already starts with its article
    /// is left alone. `String.withArticle`, kept here so this file compiles on its own (the probes).
    static func joined(_ germanWord: String, article: String?) -> String {
        guard let article, !article.isEmpty else { return germanWord }
        if germanWord.lowercased().hasPrefix(article.lowercased() + " ") { return germanWord }
        return "\(article) \(germanWord)"
    }

    /// How two cards are matched for "already saved": a leading article stripped whatever follows
    /// it, lowercased. Looser than `split` on purpose, so a phrase saved before the phrase rule
    /// (stored as "Meinung sein" + der) still matches "der Meinung sein".
    static func matchKey(_ german: String) -> String {
        var word = german.trimmingCharacters(in: .whitespacesAndNewlines)
        // "necken / neckte / hat geneckt", saved whole before `listedForms`, is the card "necken".
        if let listed = listedForms(word) { word = listed.headword }
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            word = String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
        }
        return word.lowercased()
    }

    // MARK: - Forms listed after a word

    /// A sheet's entry split into its word and the forms listed after it.
    struct ListedForms: Equatable {
        /// What the card is for: "necken", "sich besinnen", "der Kieselstein".
        let headword: String
        /// The caption: "neckte / hat geneckt", or for a noun "Plural: die Kieselsteine".
        let forms: String
        let isVerb: Bool
    }

    /// The word and its listed forms, when the entry is one of the two shapes teachers print:
    ///
    /// - a verb's principal parts, ending in the perfect: "binden / band / hat gebunden",
    ///   "anzünden/ zündete…an/ hat angezündet", "sich besinnen / besann sich / hat sich besonnen".
    ///   An arrow ends the infinitive early: "sich hüten –> hüte dich! hütete sich / hat sich
    ///   gehütet" is "sich hüten" with the rest as its forms.
    /// - a noun and its plural: "der Kieselstein/ die Kieselsteine (pl)". Without the "(pl)" the
    ///   second noun must read as the first's plural, so "der Lehrer/ die Lehrerin" is left alone.
    ///
    /// Anything else with a slash ("herrje / herrjemine") is nil.
    static func listedForms(_ german: String) -> ListedForms? {
        let text = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("/") else { return nil }
        var parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, !parts.contains(where: \.isEmpty), let last = parts.last else { return nil }

        // A verb: the last part is the perfect, "hat geneckt", "ist gekrochen", "hat sich besonnen".
        let perfect = words(last)
        if perfect.count >= 2, ["hat", "ist"].contains(perfect[0].lowercased()) {
            var head = parts.removeFirst()
            if let arrow = head.range(of: #"\s*(?:[-–—]+>|→)\s*"#, options: .regularExpression) {
                let tail = head[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                head = head[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty { parts.insert(tail, at: 0) }
            }
            let headWords = words(head)
            guard (1...3).contains(headWords.count),
                  headWords.allSatisfy({ $0.allSatisfy { $0.isLetter || $0 == "-" } }) else { return nil }
            return ListedForms(headword: head, forms: parts.joined(separator: " / "), isVerb: true)
        }

        // A noun and its plural.
        guard parts.count == 2 else { return nil }
        let singular = words(parts[0])
        let pluralText = parts[1].replacingOccurrences(of: #"\s*\((?:pl|Pl)\.?\)"#, with: "",
                                                       options: .regularExpression)
        let plural = words(pluralText)
        guard singular.count == 2, articles.contains(singular[0].lowercased()),
              plural.count == 2, plural[0].lowercased() == "die" else { return nil }
        let marked = pluralText != parts[1]
        guard marked || readsAsPlural(plural[1], of: singular[1]) else { return nil }
        return ListedForms(headword: parts[0], forms: "Plural: \(plural.joined(separator: " "))", isVerb: false)
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The plural is built on the singular ("Sorge" → "Sorgen", "Vorwurf" → "Vorwürfe" once the
    /// umlauts are set aside) and is not a feminine form ("Lehrer" → "Lehrerin").
    private static func readsAsPlural(_ plural: String, of singular: String) -> Bool {
        let umlauts: [Character: Character] = ["ä": "a", "ö": "o", "ü": "u"]
        func plain(_ word: String) -> String { String(word.lowercased().map { umlauts[$0] ?? $0 }) }
        guard singular.count >= 2, !plural.lowercased().hasSuffix("in") else { return false }
        return plain(plural).hasPrefix(plain(singular))
    }

    // MARK: - The one-word test

    /// One word, after setting aside what a vocabulary sheet prints beside a word rather than as
    /// part of it: a dash meaning "no plural" ("die Berufserfahrung —"), a trailing note in
    /// brackets ("die Kenntnisse (Pluralform)"), and plural notation after a comma
    /// ("der Tisch, -e", "der Tisch, die Tische"). "sich" plus one word is a reflexive verb.
    private static func isOneWord(_ tokens: [String]) -> Bool {
        var words = tokens

        // Plural notation after a comma.
        if let comma = words.firstIndex(where: { $0.hasSuffix(",") }), comma + 1 < words.count {
            let next = words[comma + 1]
            if next.hasPrefix("-") || next.hasPrefix("–") || next.hasPrefix("¨")
                || articles.contains(next.lowercased()) {
                words = Array(words[...comma])
            }
        }
        // A trailing bracketed note.
        if let open = words.firstIndex(where: { $0.hasPrefix("(") }), open > 0,
           words.last?.hasSuffix(")") == true {
            words = Array(words[..<open])
        }
        // Dash-only tokens.
        words.removeAll { token in token.allSatisfy { "—–-".contains($0) } }

        if words.count == 2, words[0].lowercased() == "sich" { return true }
        return words.count <= 1
    }
}
