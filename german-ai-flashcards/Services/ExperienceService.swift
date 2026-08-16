//
//  ExperienceService.swift
//  german-ai-flashcards
//
//  Turns the existing `StudyDay` log into XP. Every activity already writes its counts and its
//  seconds into the per-day row (flashcards via `DeckStore.saveQuizResult`, drills via
//  `saveGrammarQuizResult`, chats via `LearnerMemoryService.applySession`, stories via the
//  reading timer and quiz) — so XP is a pure read over data that already exists, and leveling
//  up needs no storage of its own.
//
//  The weights lean on *finishing things* (a review, a quiz, a chat) with a small drip for
//  time-on-task, so points track learning behavior rather than app-opens.
//

import Foundation

enum ExperienceService {

    // MARK: Weights (tuning lives here and nowhere else)

    static let xpPerCard = 1            // flashcard reviewed (any style, matching, cloze)
    static let xpPerGrammar = 2         // grammar exercise / der-die-das / Kasus item
    static let xpPerStoryQuestion = 5   // comprehension question answered
    static let xpPerConversation = 10   // chat finished
    static let xpPerMinute = 1          // any study minute (reading, listening, reviewing…)

    // MARK: Read

    /// XP one day earned.
    static func xp(for day: StudyDay) -> Int {
        day.cardsReviewed * xpPerCard
            + day.grammarExercises * xpPerGrammar
            + day.storyQuestions * xpPerStoryQuestion
            + day.conversations * xpPerConversation
            + (day.totalSeconds / 60) * xpPerMinute
    }

    /// Lifetime XP across the whole log.
    static func totalXP(_ days: [StudyDay]) -> Int {
        days.reduce(0) { $0 + xp(for: $1) }
    }

    /// XP earned today — the "+N heute" line on the level card.
    static func todayXP(_ days: [StudyDay], asOf now: Date = Date()) -> Int {
        let today = Calendar.current.startOfDay(for: now)
        guard let day = days.first(where: { Calendar.current.startOfDay(for: $0.dayStart) == today }) else { return 0 }
        return xp(for: day)
    }

    /// The level a lifetime XP figure lands on.
    static func level(for days: [StudyDay]) -> LearnerLevel {
        LearnerLevel.level(forTotalXP: totalXP(days))
    }

    // MARK: - Daily goal

    /// The goal choices offered in Settings, in minutes.
    static let dailyGoalOptions = [5, 10, 15, 20, 30]
    static let defaultDailyGoalMinutes = 10

    /// Seconds studied today toward the ring.
    static func todaySeconds(_ days: [StudyDay], asOf now: Date = Date()) -> Int {
        let today = Calendar.current.startOfDay(for: now)
        return days.first(where: { Calendar.current.startOfDay(for: $0.dayStart) == today })?.totalSeconds ?? 0
    }

    /// Ring fill, 0…1 (capped — overtime reads as a closed ring, not an overflowing one).
    static func dailyGoalProgress(_ days: [StudyDay], goalMinutes: Int, asOf now: Date = Date()) -> Double {
        guard goalMinutes > 0 else { return 0 }
        return min(1, Double(todaySeconds(days, asOf: now)) / Double(goalMinutes * 60))
    }

    static func dailyGoalMet(_ days: [StudyDay], goalMinutes: Int, asOf now: Date = Date()) -> Bool {
        dailyGoalProgress(days, goalMinutes: goalMinutes, asOf: now) >= 1
    }
}
