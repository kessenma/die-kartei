//
//  BatchJob.swift
//  german-ai-flashcards
//
//  One item in the batch queue: a flashcard deck to generate, a short story to write, or a
//  picture pass over an existing deck's cards. Jobs are persisted so a queue built up during
//  the day survives app restarts until the learner runs it (before bed, for example).
//

import Foundation
import SwiftData

@Model
final class BatchJob {
    /// What kind of work this job does. Raw values are persisted — never rename.
    enum Kind: String {
        /// Generate a vocabulary deck (optionally followed by a `deckPictures` job).
        case flashcards
        /// Write a short story with questions and glossary (pictures drawn inline).
        case story
        /// Draw AI pictures for every card in an existing deck that doesn't have one yet.
        case deckPictures
    }

    enum Status: String {
        case queued, running, done, failed
    }

    var id: UUID
    var createdAt: Date
    /// Queue position; the runner takes queued jobs lowest-first.
    var sortOrder: Int
    var kindRaw: String
    var statusRaw: String
    /// Deck or story topic (for picture jobs, the target deck's topic) — the row title.
    var topic: String
    var errorMessage: String?
    var completedAt: Date?
    /// The model pinned at enqueue time for flashcard jobs (MLXModel raw value).
    var generatorRaw: String

    // Flashcard settings (mirrors the Create form).
    var wordCount: Int
    var includeExamples: Bool
    var includeGender: Bool
    var wordTypeFilterRaw: String
    var includeConjugations: Bool
    var selectedTenses: [String]
    /// Flashcards and stories: also draw AI pictures.
    var withImages: Bool

    // Story settings.
    var storyLevelRaw: String
    var storyGenreRaw: String
    var storyQuestionCount: Int
    /// Comma-joined `StoryQuestion.Kind` raw values.
    var storyQuestionKindsRaw: String
    var storyImageCount: Int
    /// Stories: learner-profile words to weave into the text (coach steering; empty = none).
    var weaveWords: [String]

    /// Picture jobs: the deck whose missing card pictures should be drawn.
    var targetDeckID: UUID?
    /// Set on completion so the finished row can open what it made.
    var resultDeckID: UUID?
    var resultStoryID: UUID?

    init(kind: Kind, topic: String, sortOrder: Int) {
        self.id = UUID()
        self.createdAt = .now
        self.sortOrder = sortOrder
        self.kindRaw = kind.rawValue
        self.statusRaw = Status.queued.rawValue
        self.topic = topic
        self.errorMessage = nil
        self.completedAt = nil
        self.generatorRaw = ""
        self.wordCount = 10
        self.includeExamples = true
        self.includeGender = true
        self.wordTypeFilterRaw = WordTypeFilter.all.rawValue
        self.includeConjugations = false
        self.selectedTenses = []
        self.withImages = false
        self.storyLevelRaw = CEFRLevel.a2.rawValue
        self.storyGenreRaw = StoryGenre.alltag.rawValue
        self.storyQuestionCount = 6
        self.storyQuestionKindsRaw = StoryQuestion.Kind.multipleChoice.rawValue
        self.storyImageCount = 2
        self.weaveWords = []
        self.targetDeckID = nil
        self.resultDeckID = nil
        self.resultStoryID = nil
    }

    // MARK: - Typed accessors

    var kind: Kind { Kind(rawValue: kindRaw) ?? .flashcards }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var wordTypeFilter: WordTypeFilter { WordTypeFilter(rawValue: wordTypeFilterRaw) ?? .all }
    var storyLevel: CEFRLevel { CEFRLevel(rawValue: storyLevelRaw) ?? .a2 }
    var storyGenre: StoryGenre { StoryGenre(rawValue: storyGenreRaw) ?? .alltag }

    var storyQuestionKinds: [StoryQuestion.Kind] {
        let kinds = storyQuestionKindsRaw.split(separator: ",").compactMap { StoryQuestion.Kind(rawValue: String($0)) }
        return kinds.isEmpty ? [.multipleChoice] : kinds
    }

    // MARK: - Factories

    static func flashcards(
        topic: String,
        wordCount: Int,
        includeExamples: Bool,
        includeGender: Bool,
        wordTypeFilter: WordTypeFilter,
        includeConjugations: Bool,
        selectedTenses: [String],
        withImages: Bool,
        generatorRaw: String,
        sortOrder: Int
    ) -> BatchJob {
        let job = BatchJob(kind: .flashcards, topic: topic, sortOrder: sortOrder)
        job.wordCount = wordCount
        job.includeExamples = includeExamples
        job.includeGender = includeGender
        job.wordTypeFilterRaw = wordTypeFilter.rawValue
        job.includeConjugations = includeConjugations
        job.selectedTenses = selectedTenses
        job.withImages = withImages
        job.generatorRaw = generatorRaw
        return job
    }

    static func story(
        topic: String,
        level: CEFRLevel,
        genre: StoryGenre,
        questionCount: Int,
        questionKinds: [StoryQuestion.Kind],
        withImages: Bool,
        imageCount: Int,
        weaveWords: [String] = [],
        sortOrder: Int
    ) -> BatchJob {
        let job = BatchJob(kind: .story, topic: topic, sortOrder: sortOrder)
        job.storyLevelRaw = level.rawValue
        job.storyGenreRaw = genre.rawValue
        job.storyQuestionCount = questionCount
        job.storyQuestionKindsRaw = questionKinds.map(\.rawValue).joined(separator: ",")
        job.withImages = withImages
        job.storyImageCount = imageCount
        job.weaveWords = weaveWords
        return job
    }

    static func deckPictures(deckID: UUID, topic: String, sortOrder: Int) -> BatchJob {
        let job = BatchJob(kind: .deckPictures, topic: topic, sortOrder: sortOrder)
        job.targetDeckID = deckID
        return job
    }

    // MARK: - Display

    var systemImage: String {
        switch kind {
        case .flashcards: "rectangle.stack"
        case .story: "book.pages"
        case .deckPictures: "photo.on.rectangle.angled"
        }
    }

    /// One-line recap of the job's settings for its queue row.
    var summary: String {
        switch kind {
        case .flashcards:
            var parts = ["\(wordCount) cards"]
            switch wordTypeFilter {
            case .all: break
            case .nouns: parts.append("nouns")
            case .verbs: parts.append("verbs")
            case .adjectives: parts.append("adjectives")
            case .verbsAndAdjectives: parts.append("verbs & adj.")
            }
            if includeConjugations { parts.append("conjugations") }
            if withImages { parts.append("pictures") }
            if let model = MLXModel(rawValue: generatorRaw) { parts.append(model.rawValue) }
            return parts.joined(separator: " · ")
        case .story:
            var parts = ["\(storyLevel.rawValue) story", storyGenre.label, "\(storyQuestionCount) questions"]
            if withImages { parts.append("\(storyImageCount) picture\(storyImageCount == 1 ? "" : "s")") }
            if !weaveWords.isEmpty { parts.append("your words") }
            return parts.joined(separator: " · ")
        case .deckPictures:
            return "Pictures for cards that don't have one yet"
        }
    }
}
