import DieKarteiCore
import Foundation
import SwiftData

@Model
final class SavedDeck {
    var id: UUID
    var topic: String
    var wordCount: Int
    var includeExamples: Bool
    var includeGender: Bool
    var wordTypeFilterRaw: String
    var includeConjugations: Bool
    var selectedTenses: [String]
    var createdAt: Date

    /// Raw value identifying the generator: MLXModel.rawValue or "goethe".
    var generatorRaw: String

    @Relationship(deleteRule: .cascade, inverse: \SavedCard.deck)
    var cards: [SavedCard]

    @Relationship(deleteRule: .cascade, inverse: \QuizResult.deck)
    var quizResults: [QuizResult]

    var pausedProgressData: Data?
    var pausedAt: Date?

    /// Seconds the model took to generate this deck's cards (0 = unknown / pre-existing deck).
    var generationTimeSeconds: Double

    var wordTypeFilter: WordTypeFilter {
        WordTypeFilter(rawValue: wordTypeFilterRaw) ?? .all
    }

    init(
        topic: String,
        wordCount: Int,
        includeExamples: Bool,
        includeGender: Bool = true,
        wordTypeFilter: WordTypeFilter = .all,
        includeConjugations: Bool = false,
        selectedTenses: [String] = [],
        createdAt: Date = .now,
        cards: [SavedCard] = []
    ) {
        self.id = UUID()
        self.topic = topic
        self.wordCount = wordCount
        self.includeExamples = includeExamples
        self.includeGender = includeGender
        self.wordTypeFilterRaw = wordTypeFilter.rawValue
        self.includeConjugations = includeConjugations
        self.selectedTenses = selectedTenses
        self.createdAt = createdAt
        self.generatorRaw = ""
        self.cards = cards
        self.quizResults = []
        self.pausedProgressData = nil
        self.pausedAt = nil
        self.generationTimeSeconds = 0
    }

    /// Asset name for the generator logo, or nil if no custom image is available.
    var generatorLogoName: String? {
        if let model = MLXModel(rawValue: generatorRaw) { return model.logoName }
        if generatorRaw == "goethe" { return "logo-goethe" }
        return nil
    }

    var isPastTenseDeck: Bool {
        generatorRaw == "past-tense" || generatorRaw == "past-tense-srs"
    }

    var hasPausedSession: Bool { pausedAt != nil }


    /// Create a SavedDeck from generation parameters and resulting VocabCards.
    convenience init(
        topic: String,
        wordCount: Int,
        includeExamples: Bool,
        includeGender: Bool = true,
        wordTypeFilter: WordTypeFilter = .all,
        includeConjugations: Bool = false,
        selectedTenses: [String] = [],
        vocabCards: [VocabCard]
    ) {
        self.init(
            topic: topic,
            wordCount: wordCount,
            includeExamples: includeExamples,
            includeGender: includeGender,
            wordTypeFilter: wordTypeFilter,
            includeConjugations: includeConjugations,
            selectedTenses: selectedTenses
        )
        self.cards = vocabCards.enumerated().map { index, card in
            SavedCard(
                germanWord: card.germanWord,
                englishTranslation: card.englishTranslation,
                wordType: card.wordType,
                article: card.article,
                exampleSentence: card.exampleSentence,
                conjugations: card.conjugations,
                sortOrder: index
            )
        }
    }

    /// Convert stored cards back to VocabCard array for use with CardDeckView.
    var vocabCards: [VocabCard] {
        cards
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { savedCard in
                VocabCard(
                    germanWord: savedCard.germanWord,
                    englishTranslation: savedCard.englishTranslation,
                    wordType: savedCard.wordType,
                    article: savedCard.article,
                    exampleSentence: savedCard.exampleSentence,
                    conjugations: savedCard.conjugations
                )
            }
    }
}

struct DeckSessionProgress: Codable {
    var cardIndex: Int
    var elapsedSeconds: Int
    var studyModeRaw: String
    var cardResults: [Int: Bool]?
    var ankiRatingValues: [Int: Int]?
    var leitnerResults: [Int: Bool]?
    var ankiDueIndices: [Int]?
    var ankiDuePosition: Int?
    var cardGermanWords: [String]?
}
