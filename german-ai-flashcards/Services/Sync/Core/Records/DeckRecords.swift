import Foundation

// SavedDeck, SavedCard and QuizResult as plain values. Field names and encodings follow
// `SavedDeckCodec`, `SavedCardCodec` and `QuizResultCodec` (Codecs/DeckCodecs.swift); defaults
// for a missing field follow the SwiftData models' initializers.

/// A deck's own fields (`SavedDeck`). Cards and quiz results are records of their own.
/// `pausedProgressData`/`pausedAt` never sync, so they aren't here either.
nonisolated struct DeckRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.savedDeck }

    var id: UUID
    var topic: String
    var wordCount = 0
    var includeExamples = false
    var includeGender = true
    var wordTypeFilterRaw = "All"
    var includeConjugations = false
    var selectedTenses: [String] = []
    var createdAt: Date
    var generatorRaw = ""
    var generationTimeSeconds: Double = 0
    var courseIDRaw: String? = nil
    var sourceText: String? = nil
    var sourceFile: String? = nil
    /// `MacPictureOrder.Request` / `.Result` JSON (docs/MAC_PICTURES.md), passed through as is.
    var macPictureRequest: SyncJSON? = nil
    var macPictureResult: SyncJSON? = nil
    var extra: SyncPayload = [:]

    init(id: UUID = UUID(), topic: String, generatorRaw: String = "", createdAt: Date = Date()) {
        self.id = id
        self.topic = topic
        self.generatorRaw = generatorRaw
        self.createdAt = createdAt
    }

    /// The one Wortschatz deck, with the id and settings iOS gives it
    /// (`DeckStore.fetchOrCreateWortschatzDeck`).
    static func wortschatz(wordCount: Int, createdAt: Date = Date()) -> DeckRecord {
        var deck = DeckRecord(id: SyncSingletonDecks.wortschatzDeckID, topic: SyncSingletonDecks.wortschatzTopic,
                              generatorRaw: SyncSingletonDecks.wortschatzGenerator, createdAt: createdAt)
        deck.wordCount = wordCount
        deck.includeExamples = true
        deck.includeGender = true
        return deck
    }

    init(payload p: SyncPayload) {
        id = p.uuid("id") ?? UUID()
        topic = p.string("topic") ?? ""
        createdAt = p.date("createdAt") ?? Date(timeIntervalSinceReferenceDate: 0)
        if let v = p.int("wordCount") { wordCount = v }
        if let v = p.bool("includeExamples") { includeExamples = v }
        if let v = p.bool("includeGender") { includeGender = v }
        if let v = p.string("wordTypeFilterRaw") { wordTypeFilterRaw = v }
        if let v = p.bool("includeConjugations") { includeConjugations = v }
        selectedTenses = p.strings("selectedTenses") ?? []
        if let v = p.string("generatorRaw") { generatorRaw = v }
        if let v = p.double("generationTimeSeconds") { generationTimeSeconds = v }
        courseIDRaw = p.string("courseIDRaw")
        sourceText = p.string("sourceText")
        sourceFile = p.string("sourceFile")
        macPictureRequest = p.json("macPictureRequest")
        macPictureResult = p.json("macPictureResult")
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, id: id) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("id", id)
        f.set("topic", topic)
        f.set("wordCount", wordCount)
        f.set("includeExamples", includeExamples)
        f.set("includeGender", includeGender)
        f.set("wordTypeFilterRaw", wordTypeFilterRaw)
        f.set("includeConjugations", includeConjugations)
        f.set("selectedTenses", selectedTenses)
        f.set("createdAt", createdAt)
        f.set("generatorRaw", generatorRaw)
        f.set("generationTimeSeconds", generationTimeSeconds)
        f.set("courseIDRaw", courseIDRaw)
        f.set("sourceText", sourceText)
        f.set("sourceFile", sourceFile)
        f.set("macPictureRequest", json: macPictureRequest)
        f.set("macPictureResult", json: macPictureResult)
        return f.payload
    }

    var index: RecordIndex {
        RecordIndex(naturalKey: generatorRaw.isEmpty ? nil : generatorRaw, sort: createdAt.timeIntervalSinceReferenceDate)
    }
}

/// One card and its spaced-repetition state (`SavedCard`).
///
/// Wortschatz cards (deck `SyncSingletonDecks.wortschatzDeckID`) exist as records only once
/// reviewed, as on iOS, whose sync sends only reviewed ones: the bundled word lists supply the
/// rest and own the word content.
nonisolated struct CardRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.savedCard }

    var id: UUID
    var deck: UUID?
    var germanWord: String
    var englishTranslation: String
    var wordType: String? = nil
    var article: String? = nil
    var exampleSentence: String? = nil
    var formsLine: String? = nil
    /// `[StoredConjugation]` JSON, passed through as is.
    var conjugations: SyncJSON? = nil
    var sortOrder = 0
    var imageFileName: String? = nil
    var easeFactor = 2.5
    var interval = 0
    var repetitions = 0
    var nextReviewDate: Date? = nil
    var totalReviews = 0
    var lapses = 0
    var leitnerBox = 0
    var lastReviewedAt: Date? = nil
    var lastReviewWasCorrect: Bool? = nil
    var firstReviewedAt: Date? = nil
    var extra: SyncPayload = [:]

    init(id: UUID = UUID(), deck: UUID?, germanWord: String, englishTranslation: String, sortOrder: Int = 0) {
        self.id = id
        self.deck = deck
        self.germanWord = germanWord
        self.englishTranslation = englishTranslation
        self.sortOrder = sortOrder
    }

    /// A Wortschatz card for a bundled Goethe word, with the id and content iOS gives it
    /// (`DeckStore.makeCard`): one card per exact word, `sortOrder` its index in
    /// `GoetheVocabService.orderedWords`.
    static func wortschatz(word: String, translation: String, wordType: String?, article: String?,
                           example: String?, sortOrder: Int) -> CardRecord {
        let deckID = SyncSingletonDecks.wortschatzDeckID
        var card = CardRecord(id: SyncSingletonDecks.cardID(deckID: deckID, germanWord: word), deck: deckID,
                              germanWord: word, englishTranslation: translation, sortOrder: sortOrder)
        card.wordType = wordType
        card.article = article
        card.exampleSentence = example?.isEmpty == false ? example : nil
        return card
    }

    init(payload p: SyncPayload) {
        id = p.uuid("id") ?? UUID()
        deck = p.uuid("deck")
        germanWord = p.string("germanWord") ?? ""
        englishTranslation = p.string("englishTranslation") ?? ""
        wordType = p.string("wordType")
        article = p.string("article")
        exampleSentence = p.string("exampleSentence")
        formsLine = p.string("formsLine")
        conjugations = p.json("conjugations")
        if let v = p.int("sortOrder") { sortOrder = v }
        imageFileName = p.string("imageFileName")
        if let v = p.double("easeFactor") { easeFactor = v }
        if let v = p.int("interval") { interval = v }
        if let v = p.int("repetitions") { repetitions = v }
        nextReviewDate = p.date("nextReviewDate")
        totalReviews = p.int("totalReviews") ?? 0
        lapses = p.int("lapses") ?? 0
        if let v = p.int("leitnerBox") { leitnerBox = v }
        lastReviewedAt = p.date("lastReviewedAt")
        lastReviewWasCorrect = p.bool("lastReviewWasCorrect")
        firstReviewedAt = p.date("firstReviewedAt")
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, id: id) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("id", id)
        f.set("deck", deck)
        f.set("germanWord", germanWord)
        f.set("englishTranslation", englishTranslation)
        f.set("wordType", wordType)
        f.set("article", article)
        f.set("exampleSentence", exampleSentence)
        f.set("formsLine", formsLine)
        f.set("conjugations", json: conjugations)
        f.set("sortOrder", sortOrder)
        f.set("imageFileName", imageFileName)
        f.set("easeFactor", easeFactor)
        f.set("interval", interval)
        f.set("repetitions", repetitions)
        f.set("nextReviewDate", nextReviewDate)
        f.set("totalReviews", totalReviews)
        f.set("lapses", lapses)
        f.set("leitnerBox", leitnerBox)
        f.set("lastReviewedAt", lastReviewedAt)
        f.set("lastReviewWasCorrect", lastReviewWasCorrect)
        f.set("firstReviewedAt", firstReviewedAt)
        return f.payload
    }

    var index: RecordIndex {
        RecordIndex(parent: deck, naturalKey: germanWord,
                    due: nextReviewDate?.timeIntervalSinceReferenceDate, sort: Double(sortOrder))
    }

    /// Stamp a rating, as `SavedCard.noteReview` does.
    mutating func noteReview(correct: Bool, at now: Date) {
        lastReviewedAt = now
        lastReviewWasCorrect = correct
        if firstReviewedAt == nil { firstReviewedAt = now }
    }
}

/// One finished session on a deck (`QuizResult`). Append-only.
nonisolated struct QuizResultRecord: KarteiRecord {
    static var spec: SyncKindSpec { SyncKinds.quizResult }

    var id: UUID
    var deck: UUID?
    var date: Date
    var totalCards = 0
    var correctCount = 0
    var incorrectCardIndices: [Int] = []
    var durationSeconds = 0
    var studyModeRaw = ""
    /// `[Int: Int]` JSON (Anki rating → count), passed through as is.
    var ankiRatings: SyncJSON? = nil
    var subDeckLabel: String? = nil
    var extra: SyncPayload = [:]

    init(id: UUID = UUID(), deck: UUID?, date: Date = Date()) {
        self.id = id
        self.deck = deck
        self.date = date
    }

    init(payload p: SyncPayload) {
        id = p.uuid("id") ?? UUID()
        deck = p.uuid("deck")
        date = p.date("date") ?? Date(timeIntervalSinceReferenceDate: 0)
        if let v = p.int("totalCards") { totalCards = v }
        if let v = p.int("correctCount") { correctCount = v }
        incorrectCardIndices = p.ints("incorrectCardIndices") ?? []
        if let v = p.int("durationSeconds") { durationSeconds = v }
        if let v = p.string("studyModeRaw") { studyModeRaw = v }
        ankiRatings = p.json("ankiRatings")
        subDeckLabel = p.string("subDeckLabel")
        keepExtra(from: p)
    }

    var name: SyncRecordName { SyncRecordName(kind: Self.spec.kind, id: id) }

    var fields: SyncPayload {
        var f = SyncFields()
        f.set("id", id)
        f.set("deck", deck)
        f.set("date", date)
        f.set("totalCards", totalCards)
        f.set("correctCount", correctCount)
        f.set("incorrectCardIndices", incorrectCardIndices)
        f.set("durationSeconds", durationSeconds)
        f.set("studyModeRaw", studyModeRaw)
        f.set("ankiRatings", json: ankiRatings)
        f.set("subDeckLabel", subDeckLabel)
        return f.payload
    }

    var index: RecordIndex {
        RecordIndex(parent: deck, sort: date.timeIntervalSinceReferenceDate)
    }
}
