struct Conjugation {
    var tense: String
    var ich: String
    var du: String
    var erSieEs: String
    var wir: String
    var ihr: String
    var sieSie: String
}

struct VocabCard {
    var germanWord: String
    var englishTranslation: String
    var wordType: String?
    var article: String?
    var exampleSentence: String?
    var conjugations: [Conjugation]?

    // Past-tense verb fields (nil for non-verb cards)
    var auxiliaryVerb: String?
    var pastParticiple: String?
    var isSeparable: Bool?
    var verbPrefix: String?
    var isRegular: Bool?

    /// A one-line caption under the German word — a noun's plural ("Plural: -en") or a verb's
    /// present + Perfekt forms. Bundled Goethe words carry it; generated cards leave it nil.
    var forms: String? = nil
}

struct VocabCardResponse {
    var cards: [VocabCard]
}

extension String {
    /// Prefixes a noun with its article for display — `"Flug".withArticle("der")` → "der Flug".
    /// No-op when the article is missing or the word already starts with it (older saved cards
    /// can have the article baked into the word itself).
    func withArticle(_ article: String?) -> String {
        guard let article, !article.isEmpty else { return self }
        if lowercased().hasPrefix(article.lowercased() + " ") { return self }
        return "\(article) \(self)"
    }
}
