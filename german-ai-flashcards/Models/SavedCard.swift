import Foundation
import SwiftData

/// Codable representation of a conjugation for persistence.
struct StoredConjugation: Codable {
    var tense: String
    var ich: String
    var du: String
    var erSieEs: String
    var wir: String
    var ihr: String
    var sieSie: String

    init(from conjugation: Conjugation) {
        self.tense = conjugation.tense
        self.ich = conjugation.ich
        self.du = conjugation.du
        self.erSieEs = conjugation.erSieEs
        self.wir = conjugation.wir
        self.ihr = conjugation.ihr
        self.sieSie = conjugation.sieSie
    }

    func toConjugation() -> Conjugation {
        Conjugation(
            tense: tense,
            ich: ich,
            du: du,
            erSieEs: erSieEs,
            wir: wir,
            ihr: ihr,
            sieSie: sieSie
        )
    }
}

@Model
final class SavedCard {
    var id: UUID
    var germanWord: String
    var englishTranslation: String
    var wordType: String?
    var article: String?
    var exampleSentence: String?
    var conjugationsData: Data?
    var sortOrder: Int

    /// File name of this card's AI-generated picture inside `CardImageStore.directory(for:)`,
    /// or nil if the card has none. Optional so existing stores migrate lightweightly, and so
    /// "has no picture yet" is the natural query for the illustrate-the-rest pass.
    var imageFileName: String?

    // MARK: - Spaced Repetition (Anki-style) Fields

    /// SM-2 ease factor — starts at 2.5, minimum 1.3.
    var easeFactor: Double
    /// Current review interval in days.
    var interval: Int
    /// Number of consecutive correct reviews (resets on lapse).
    var repetitions: Int
    /// Next scheduled review date.
    var nextReviewDate: Date?
    /// Total number of times this card was reviewed.
    var totalReviews: Int
    /// Number of times the card was forgotten (rated "Again").
    var lapses: Int

    // MARK: - Leitner Fields

    /// Current Leitner box (0 = new/unseen, 1–5 = active boxes).
    var leitnerBox: Int

    // MARK: - Review history (optional so existing stores migrate lightweightly)

    /// When this card was last rated, in any mode. Lets "today" screens list what was reviewed.
    var lastReviewedAt: Date?
    /// How the last rating went: false for Didn't know / wrong, true otherwise.
    var lastReviewWasCorrect: Bool?
    /// When this card got its first rating ever — the day the learner met it.
    var firstReviewedAt: Date?

    var deck: SavedDeck?

    init(
        germanWord: String,
        englishTranslation: String,
        wordType: String? = nil,
        article: String? = nil,
        exampleSentence: String? = nil,
        conjugations: [Conjugation]? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.germanWord = germanWord
        self.englishTranslation = englishTranslation
        self.wordType = wordType
        self.article = article
        self.exampleSentence = exampleSentence
        self.sortOrder = sortOrder
        self.imageFileName = nil

        // SRS defaults
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.nextReviewDate = nil
        self.totalReviews = 0
        self.lapses = 0

        // Leitner default
        self.leitnerBox = 0

        self.lastReviewedAt = nil
        self.lastReviewWasCorrect = nil
        self.firstReviewedAt = nil

        if let conjugations, !conjugations.isEmpty {
            let stored = conjugations.map { StoredConjugation(from: $0) }
            self.conjugationsData = try? JSONEncoder().encode(stored)
        }
    }

    var conjugations: [Conjugation]? {
        guard let data = conjugationsData else { return nil }
        let stored = try? JSONDecoder().decode([StoredConjugation].self, from: data)
        return stored?.map { $0.toConjugation() }
    }

    /// Stamp a rating: last review time and result, and the first-ever review if this is it.
    func noteReview(correct: Bool, at now: Date = .now) {
        lastReviewedAt = now
        lastReviewWasCorrect = correct
        if firstReviewedAt == nil { firstReviewedAt = now }
    }

    /// The value-type card the player studies, built from this row. Cards of the Wortschatz deck
    /// also carry their plural / Perfekt forms line, looked up in the bundled index rather than
    /// stored — the lists own that data, the store only owns progress.
    var vocabCard: VocabCard {
        VocabCard(
            germanWord: germanWord,
            englishTranslation: englishTranslation,
            wordType: wordType,
            article: article,
            exampleSentence: exampleSentence,
            conjugations: conjugations,
            forms: deck?.kind == .goetheSRS ? GoetheVocabService.index[germanWord]?.formsLine : nil
        )
    }
}
