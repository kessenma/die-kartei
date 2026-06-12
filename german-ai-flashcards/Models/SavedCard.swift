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

        // SRS defaults
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.nextReviewDate = nil
        self.totalReviews = 0
        self.lapses = 0

        // Leitner default
        self.leitnerBox = 0

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
}
