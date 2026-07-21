//
//  StoryStats.swift
//  german-ai-flashcards
//
//  Persistence for story study, mirroring `MatchingStats` / `ArticleStats`:
//  - `StoryReadingSession` — one row per stretch of reading or listening, so time spent with a
//    story counts as study even when no question is ever answered.
//  - `StoryQuizAttempt` — one row per finished comprehension quiz (the story's answer to
//    `QuizResult`, which is deck-shaped and can't hold a story).
//
//  Both carry the story's title and level inline: the rows outlive the story (a deleted story
//  shouldn't erase the history it produced) and the progress screen groups by level.
//

import Foundation
import SwiftData

// MARK: - Reading / listening

/// One continuous stretch of time with a story — from opening it to leaving the screen (or
/// backgrounding the app). Short glances are dropped by `StoryProgressService.minRecordedSeconds`,
/// so a row always represents real reading.
@Model
final class StoryReadingSession {
    var id: UUID
    /// When the stretch ended (what the day-detail timeline sorts on).
    var date: Date
    var storyID: UUID
    var storyTitle: String
    /// `CEFRLevel` raw value of the story, for the per-level breakdown.
    var levelRaw: String
    var seconds: Int
    /// True when the learner was in Hören mode (exam-style listening) rather than reading.
    var wasListening: Bool
    /// Words double-tapped for a translation during the stretch — the "I needed help here" signal.
    var lookups: Int
    /// Words saved into the story's deck during the stretch.
    var wordsSaved: Int

    init(
        storyID: UUID,
        storyTitle: String,
        levelRaw: String,
        seconds: Int,
        wasListening: Bool,
        lookups: Int,
        wordsSaved: Int,
        date: Date = Date()
    ) {
        self.id = UUID()
        self.date = date
        self.storyID = storyID
        self.storyTitle = storyTitle
        self.levelRaw = levelRaw
        self.seconds = seconds
        self.wasListening = wasListening
        self.lookups = lookups
        self.wordsSaved = wordsSaved
    }

    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a2 }

    /// "12 min" / "45 s" — the compact form used in lists.
    var formattedDuration: String { StoryProgressService.formatShort(seconds) }
}

// MARK: - Comprehension quiz

/// One finished run through a story's questions.
@Model
final class StoryQuizAttempt {
    var id: UUID
    var date: Date
    var storyID: UUID
    var storyTitle: String
    var levelRaw: String
    var questionCount: Int
    var correctCount: Int
    var durationSeconds: Int
    /// True when the questions were answered from listening (the story stayed hidden).
    var wasListening: Bool
    /// Free-response answers the model had to grade — the hardest question kind, worth
    /// separating out on the progress screen.
    var writtenCount: Int

    init(
        storyID: UUID,
        storyTitle: String,
        levelRaw: String,
        questionCount: Int,
        correctCount: Int,
        durationSeconds: Int,
        wasListening: Bool,
        writtenCount: Int
    ) {
        self.id = UUID()
        self.date = Date()
        self.storyID = storyID
        self.storyTitle = storyTitle
        self.levelRaw = levelRaw
        self.questionCount = questionCount
        self.correctCount = correctCount
        self.durationSeconds = durationSeconds
        self.wasListening = wasListening
        self.writtenCount = writtenCount
    }

    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a2 }

    var scorePercentage: Int {
        questionCount > 0 ? Int((Double(correctCount) / Double(questionCount) * 100).rounded()) : 0
    }

    var isPerfect: Bool { questionCount > 0 && correctCount == questionCount }
}
