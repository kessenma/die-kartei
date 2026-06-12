public struct Conjugation {
    public var tense: String
    public var ich: String
    public var du: String
    public var erSieEs: String
    public var wir: String
    public var ihr: String
    public var sieSie: String

    public init(tense: String, ich: String, du: String, erSieEs: String,
                wir: String, ihr: String, sieSie: String) {
        self.tense = tense
        self.ich = ich
        self.du = du
        self.erSieEs = erSieEs
        self.wir = wir
        self.ihr = ihr
        self.sieSie = sieSie
    }
}

public struct VocabCard {
    public var germanWord: String
    public var englishTranslation: String
    public var wordType: String?
    public var article: String?
    public var exampleSentence: String?
    public var conjugations: [Conjugation]?

    // Past-tense verb fields (nil for non-verb cards)
    public var auxiliaryVerb: String?
    public var pastParticiple: String?
    public var isSeparable: Bool?
    public var verbPrefix: String?
    public var isRegular: Bool?

    public init(germanWord: String,
                englishTranslation: String,
                wordType: String? = nil,
                article: String? = nil,
                exampleSentence: String? = nil,
                conjugations: [Conjugation]? = nil,
                auxiliaryVerb: String? = nil,
                pastParticiple: String? = nil,
                isSeparable: Bool? = nil,
                verbPrefix: String? = nil,
                isRegular: Bool? = nil) {
        self.germanWord = germanWord
        self.englishTranslation = englishTranslation
        self.wordType = wordType
        self.article = article
        self.exampleSentence = exampleSentence
        self.conjugations = conjugations
        self.auxiliaryVerb = auxiliaryVerb
        self.pastParticiple = pastParticiple
        self.isSeparable = isSeparable
        self.verbPrefix = verbPrefix
        self.isRegular = isRegular
    }
}

public struct VocabCardResponse {
    public var cards: [VocabCard]

    public init(cards: [VocabCard]) {
        self.cards = cards
    }
}
