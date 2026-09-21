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
    /// The built-in Apple model has no logo asset, so decks generated with it show no badge.
    var generatorLogoName: String? {
        if let model = MLXModel(rawValue: generatorRaw) {
            return model.usesSFSymbolLogo ? nil : model.logoName
        }
        if generatorRaw == "goethe" { return "logo-goethe" }
        return nil
    }

    var isPastTenseDeck: Bool {
        kind == .pastTense || kind == .pastTenseSRS
    }

    var hasPausedSession: Bool { pausedAt != nil }

    /// What sort of deck this is, derived from `generatorRaw`. Replaces scattered string
    /// comparisons so classification stays consistent across the app.
    enum Kind {
        /// User-generated (AI or bundled default) — the real "My Decks" content.
        case generated
        case goethe, goetheSRS
        case pastTense, pastTenseSRS
        case grammar
        /// Real saved-word content built from the phrase library / a conversation / a paper / a story
        /// / a job posting the learner studied / a class the learner is taking.
        case phrase, conversation, paper, story, job, classNotes
    }

    var kind: Kind {
        switch generatorRaw {
        case "goethe": .goethe
        case "goethe-srs": .goetheSRS
        case "past-tense": .pastTense
        case "past-tense-srs": .pastTenseSRS
        case "grammar": .grammar
        case "phrase": .phrase
        case "conversation": .conversation
        case "paper": .paper
        case "story": .story
        case "job": .job
        case "class": .classNotes
        default: .generated // "" or an MLXModel.rawValue
        }
    }

    /// An SF Symbol standing for the deck's source when it has no model logo to show — the
    /// document kinds, which no single model generated.
    var kindSymbol: String? {
        switch kind {
        case .job: "briefcase.fill"
        case .classNotes: "graduationcap.fill"
        case .story: "book.pages"
        case .paper: "doc.text"
        case .conversation: "bubble.left.and.bubble.right"
        case .phrase: "ear.badge.waveform"
        default: nil
        }
    }

    /// Decks that belong in the Library's browsable "Decks" list. Excludes the internal
    /// stats/SRS holders for Goethe / Past-tense / Grammar (which are activity plumbing,
    /// not standalone content) — fixing the empty-`grammar`-deck leak the old string filter missed.
    var isBrowsableContent: Bool {
        switch kind {
        case .generated, .phrase, .conversation, .paper, .story, .job, .classNotes: true
        case .goethe, .goetheSRS, .pastTense, .pastTenseSRS, .grammar: false
        }
    }


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
    // Added with the Again re-queue and the persisted direction; optional so older blobs decode.
    /// Distinct cards the SRS session set out to review (`ankiDueIndices` grows with re-queues).
    var sessionDueCount: Int?
    /// Card indices missed at least once this session.
    var sessionLapses: [Int]?
    /// Position in the plain/quiz play order, so a resume lands on the same card.
    var cardPosition: Int?
    var showGermanFirst: Bool?
}
