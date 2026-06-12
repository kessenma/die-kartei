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
}

struct VocabCardResponse {
    var cards: [VocabCard]
}
