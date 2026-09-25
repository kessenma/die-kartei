import Foundation
import SwiftData

/// Decks whose id both devices derive from (generatorRaw, topic) rather than make up at random:
/// the Wortschatz deck and the per-topic stats and SRS decks, which each device fetch-or-creates.
enum SyncSingletonDecks {
    static let generators: Set<String> = ["goethe", "goethe-srs", "past-tense", "past-tense-srs", "grammar"]

    static func isSingleton(_ deck: SavedDeck?) -> Bool {
        deck.map { generators.contains($0.generatorRaw) } ?? false
    }

    /// Canonical deck id: the same on every device for the same generator and topic.
    static func deckID(generatorRaw: String, topic: String) -> UUID {
        SyncNameUUID.make("deck", generatorRaw, topic)
    }

    /// The id for a story's, job posting's or course's own deck when it has to be created here.
    /// If the parent already links a deck that simply hasn't arrived from the other device yet,
    /// reuse that id so the two become one record when it lands. Otherwise derive it from the
    /// parent, so two devices creating it offline create the same deck.
    static func linkedDeckID(existing: UUID?, kind: String, parentID: UUID) -> UUID {
        existing ?? SyncNameUUID.make("linked-deck", kind, parentID.uuidString)
    }

    /// Canonical card id inside a singleton deck: one card per German word.
    /// The exact word, never lowercased: the Goethe lists hold 34 pairs that differ only by
    /// case (sie/Sie, essen/Essen), and each is its own card.
    static func cardID(deckID: UUID, germanWord: String) -> UUID {
        SyncNameUUID.make("card", deckID.uuidString, germanWord)
    }
}

// MARK: - SavedDeck

/// A deck's own fields. Cards and quiz results sync as their own records. `pausedProgressData`
/// never travels: it indexes one session's card order on this device.
enum SavedDeckCodec: SyncCodec {
    typealias Model = SavedDeck

    static let spec = SyncKindSpec(kind: "SavedDeck")

    static func recordName(for model: SavedDeck) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ d: SavedDeck) -> SyncPayload {
        var f = SyncFields()
        f.set("id", d.id)
        f.set("topic", d.topic)
        f.set("wordCount", d.wordCount)
        f.set("includeExamples", d.includeExamples)
        f.set("includeGender", d.includeGender)
        f.set("wordTypeFilterRaw", d.wordTypeFilterRaw)
        f.set("includeConjugations", d.includeConjugations)
        f.set("selectedTenses", d.selectedTenses)
        f.set("createdAt", d.createdAt)
        f.set("generatorRaw", d.generatorRaw)
        f.set("generationTimeSeconds", d.generationTimeSeconds)
        f.set("courseIDRaw", d.courseIDRaw)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> SavedDeck? {
        fetchDeck(id: name.id, in: context)
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> SavedDeck? {
        let deck = SavedDeck(topic: flat.string("topic") ?? "", wordCount: 0, includeExamples: false)
        deck.id = name.id
        context.insert(deck)
        update(deck, from: flat, in: context)
        return deck
    }

    static func update(_ d: SavedDeck, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("topic") { d.topic = v }
        if let v = flat.int("wordCount") { d.wordCount = v }
        if let v = flat.bool("includeExamples") { d.includeExamples = v }
        if let v = flat.bool("includeGender") { d.includeGender = v }
        if let v = flat.string("wordTypeFilterRaw") { d.wordTypeFilterRaw = v }
        if let v = flat.bool("includeConjugations") { d.includeConjugations = v }
        d.selectedTenses = flat.strings("selectedTenses") ?? []
        if let v = flat.date("createdAt") { d.createdAt = v }
        if let v = flat.string("generatorRaw") { d.generatorRaw = v }
        if let v = flat.double("generationTimeSeconds") { d.generationTimeSeconds = v }
        d.courseIDRaw = flat.string("courseIDRaw")
    }

    static func cascadeChildren(of model: SavedDeck) -> [any PersistentModel] {
        model.cards + model.quizResults
    }

    static func fetchDeck(id: UUID, in context: ModelContext) -> SavedDeck? {
        var d = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
}

// MARK: - SavedCard

/// One card and its spaced-repetition state.
/// - The schedule fields travel as one group, taken whole from the later review, so a schedule is
///   never half of one review and half of another.
/// - `totalReviews` and `lapses` are per-device counters: a card reviewed on both devices counts
///   both reviews.
/// - Wortschatz cards sync only once reviewed (the bundle rebuilds the rest), and their word
///   content is never overwritten from a payload: the bundled lists own it.
enum SavedCardCodec: SyncCodec {
    typealias Model = SavedCard

    static let scheduleFields = [
        "easeFactor", "interval", "repetitions", "nextReviewDate", "leitnerBox",
        "lastReviewedAt", "lastReviewWasCorrect",
    ]

    static let spec = SyncKindSpec(
        kind: "SavedCard",
        rules: [
            "totalReviews": .counter,
            "lapses": .counter,
            "firstReviewedAt": .min,
        ],
        groups: [
            SyncFieldGroup(fields: scheduleFields,
                           orderBy: ["lastReviewedAt", "repetitions", "interval", "easeFactor"])
        ]
    )

    static func recordName(for model: SavedCard) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func includes(_ card: SavedCard) -> Bool {
        guard let deck = card.deck else { return false }
        // Reviewed means reviewed: words studied before `firstReviewedAt` existed (1.6 and earlier)
        // have review counts but no date.
        if deck.generatorRaw == "goethe-srs" { return card.firstReviewedAt != nil || card.totalReviews > 0 }
        return true
    }

    static func bootstrap(for card: SavedCard) -> SyncBootstrap {
        SyncSingletonDecks.isSingleton(card.deck) ? .perStore : .shared
    }

    static func known(_ c: SavedCard) -> SyncPayload {
        var f = SyncFields()
        f.set("id", c.id)
        f.set("deck", c.deck?.id)
        f.set("germanWord", c.germanWord)
        f.set("englishTranslation", c.englishTranslation)
        f.set("wordType", c.wordType)
        f.set("article", c.article)
        f.set("exampleSentence", c.exampleSentence)
        f.set("conjugations", jsonData: c.conjugationsData)
        f.set("sortOrder", c.sortOrder)
        f.set("imageFileName", c.imageFileName)
        f.set("easeFactor", c.easeFactor)
        f.set("interval", c.interval)
        f.set("repetitions", c.repetitions)
        f.set("nextReviewDate", c.nextReviewDate)
        f.set("totalReviews", c.totalReviews)
        f.set("lapses", c.lapses)
        f.set("leitnerBox", c.leitnerBox)
        f.set("lastReviewedAt", c.lastReviewedAt)
        f.set("lastReviewWasCorrect", c.lastReviewWasCorrect)
        f.set("firstReviewedAt", c.firstReviewedAt)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> SavedCard? {
        let id = name.id
        var d = FetchDescriptor<SavedCard>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func parent(of flat: SyncPayload) -> SyncRecordName? {
        flat.uuid("deck").map { SyncRecordName(kind: SavedDeckCodec.spec.kind, id: $0) }
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> SavedCard? {
        guard let deckID = flat.uuid("deck"), let deck = SavedDeckCodec.fetchDeck(id: deckID, in: context) else {
            return nil
        }
        let card = SavedCard(germanWord: flat.string("germanWord") ?? "",
                             englishTranslation: flat.string("englishTranslation") ?? "")
        card.id = name.id
        context.insert(card)
        card.deck = deck
        writeContent(card, from: flat)
        update(card, from: flat, in: context)
        return card
    }

    static func update(_ c: SavedCard, from flat: SyncPayload, in context: ModelContext) {
        if c.deck?.generatorRaw != "goethe-srs" { writeContent(c, from: flat) }
        if let v = flat.double("easeFactor") { c.easeFactor = v }
        if let v = flat.int("interval") { c.interval = v }
        if let v = flat.int("repetitions") { c.repetitions = v }
        c.nextReviewDate = flat.date("nextReviewDate")
        c.totalReviews = flat.int("totalReviews") ?? 0
        c.lapses = flat.int("lapses") ?? 0
        if let v = flat.int("leitnerBox") { c.leitnerBox = v }
        c.lastReviewedAt = flat.date("lastReviewedAt")
        c.lastReviewWasCorrect = flat.bool("lastReviewWasCorrect")
        c.firstReviewedAt = flat.date("firstReviewedAt")
    }

    private static func writeContent(_ c: SavedCard, from flat: SyncPayload) {
        if let v = flat.string("germanWord") { c.germanWord = v }
        if let v = flat.string("englishTranslation") { c.englishTranslation = v }
        c.wordType = flat.string("wordType")
        c.article = flat.string("article")
        c.exampleSentence = flat.string("exampleSentence")
        c.conjugationsData = flat.jsonData("conjugations")
        if let v = flat.int("sortOrder") { c.sortOrder = v }
        c.imageFileName = flat.string("imageFileName")
    }
}

// MARK: - QuizResult

/// One finished session on a deck. Append-only, so rows from both devices simply add up.
enum QuizResultCodec: SyncCodec {
    typealias Model = QuizResult

    static let spec = SyncKindSpec(kind: "QuizResult")

    static func recordName(for model: QuizResult) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func includes(_ result: QuizResult) -> Bool { result.deck != nil }

    static func known(_ q: QuizResult) -> SyncPayload {
        var f = SyncFields()
        f.set("id", q.id)
        f.set("deck", q.deck?.id)
        f.set("date", q.date)
        f.set("totalCards", q.totalCards)
        f.set("correctCount", q.correctCount)
        f.set("incorrectCardIndices", q.incorrectCardIndices)
        f.set("durationSeconds", q.durationSeconds)
        f.set("studyModeRaw", q.studyModeRaw)
        f.set("ankiRatings", jsonData: q.ankiRatingsData)
        f.set("subDeckLabel", q.subDeckLabel)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> QuizResult? {
        let id = name.id
        var d = FetchDescriptor<QuizResult>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func parent(of flat: SyncPayload) -> SyncRecordName? {
        flat.uuid("deck").map { SyncRecordName(kind: SavedDeckCodec.spec.kind, id: $0) }
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> QuizResult? {
        guard let deckID = flat.uuid("deck"), let deck = SavedDeckCodec.fetchDeck(id: deckID, in: context) else {
            return nil
        }
        let result = QuizResult(totalCards: flat.int("totalCards") ?? 0, correctCount: flat.int("correctCount") ?? 0)
        result.id = name.id
        context.insert(result)
        result.deck = deck
        update(result, from: flat, in: context)
        return result
    }

    static func update(_ q: QuizResult, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { q.date = v }
        if let v = flat.int("totalCards") { q.totalCards = v }
        if let v = flat.int("correctCount") { q.correctCount = v }
        q.incorrectCardIndices = flat.ints("incorrectCardIndices") ?? []
        if let v = flat.int("durationSeconds") { q.durationSeconds = v }
        if let v = flat.string("studyModeRaw") { q.studyModeRaw = v }
        q.ankiRatingsData = flat.jsonData("ankiRatings")
        q.subDeckLabel = flat.string("subDeckLabel")
    }
}
