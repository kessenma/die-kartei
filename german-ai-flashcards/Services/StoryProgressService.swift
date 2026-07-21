//
//  StoryProgressService.swift
//  german-ai-flashcards
//
//  Turns story study into tracked progress, the way `MatchingStatsService` / `ArticleGameService`
//  do for the games. Three jobs:
//    1. **Write** — record reading stretches and finished quizzes (`StoryReadingSession` /
//       `StoryQuizAttempt`) and fold both into the per-day `StudyDay` log, so a story counts
//       toward the streak even when no question is ever answered.
//    2. **Hand off to the coach** — words looked up while reading and single-word fixes from
//       graded written answers flow into `LearnerProfile`, like the matching game's trouble words.
//    3. **Read** — pure aggregation over already-fetched rows, so the progress screen can compute
//       everything straight from its `@Query` and stay reactive.
//

import Foundation
import SwiftData

@MainActor
enum StoryProgressService {

    /// Stretches shorter than this are dropped: closing a story you just generated, or bouncing
    /// off the screen, isn't reading and shouldn't litter the history.
    static let minRecordedSeconds = 15

    // MARK: - Write

    /// Record one finished stretch of reading or listening. `countsTowardStreak` is the learner's
    /// setting — when it's off, the session is still kept for the progress screen, it just doesn't
    /// tint the calendar or keep the streak alive.
    @discardableResult
    static func recordReading(
        story: StudyStory,
        seconds: Int,
        wasListening: Bool,
        lookups: Int,
        wordsSaved: Int,
        countsTowardStreak: Bool,
        in context: ModelContext
    ) -> StoryReadingSession? {
        guard seconds >= minRecordedSeconds else { return nil }
        let session = StoryReadingSession(
            storyID: story.id,
            storyTitle: story.title,
            levelRaw: story.levelRaw,
            seconds: seconds,
            wasListening: wasListening,
            lookups: lookups,
            wordsSaved: wordsSaved
        )
        context.insert(session)
        if countsTowardStreak {
            StudyLogService.record(.storyReading(seconds), in: context)
        }
        try? context.save()
        return session
    }

    /// Record one finished comprehension quiz and count its questions toward the day.
    @discardableResult
    static func recordQuiz(
        story: StudyStory,
        questionCount: Int,
        correctCount: Int,
        durationSeconds: Int,
        wasListening: Bool,
        writtenCount: Int,
        in context: ModelContext
    ) -> StoryQuizAttempt? {
        guard questionCount > 0 else { return nil }
        let attempt = StoryQuizAttempt(
            storyID: story.id,
            storyTitle: story.title,
            levelRaw: story.levelRaw,
            questionCount: questionCount,
            correctCount: correctCount,
            durationSeconds: durationSeconds,
            wasListening: wasListening,
            writtenCount: writtenCount
        )
        context.insert(attempt)
        StudyLogService.record(.storyQuestions(questionCount), in: context)
        try? context.save()
        return attempt
    }

    /// Total seconds already logged against one story — the running total its screen shows.
    static func secondsRead(storyID: UUID, in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<StoryReadingSession>(
            predicate: #Predicate { $0.storyID == storyID }
        )
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.seconds }
    }

    // MARK: - Read (pure, over already-fetched rows)

    /// Everything the progress screen shows, derived in one pass.
    struct Summary {
        var totalSeconds = 0
        var sessionCount = 0
        /// Distinct stories that have at least one reading session.
        var storiesRead = 0
        var listeningSeconds = 0
        var lookups = 0
        var wordsSaved = 0
        var longestSessionSeconds = 0
        var lastReadAt: Date?

        var quizCount = 0
        var questionsAnswered = 0
        var questionsCorrect = 0
        var listeningQuizCount = 0
        var perfectQuizzes = 0

        /// Consecutive days ending today (or yesterday, so today can still be saved) with any
        /// story activity — the story-only sibling of the app-wide flame.
        var dayStreak = 0
        /// Distinct days with any story activity.
        var activeDays = 0

        var accuracy: Int {
            questionsAnswered > 0
                ? Int((Double(questionsCorrect) / Double(questionsAnswered) * 100).rounded())
                : 0
        }
        var hasAnything: Bool { sessionCount > 0 || quizCount > 0 }
        var averageSessionSeconds: Int { sessionCount > 0 ? totalSeconds / sessionCount : 0 }
        /// Share of time spent in Hören mode, 0…1 — reading vs listening balance.
        var listeningShare: Double {
            totalSeconds > 0 ? Double(listeningSeconds) / Double(totalSeconds) : 0
        }
    }

    /// Per-CEFR-level slice, so the screen can show where the learner actually spends their time.
    struct LevelSlice: Identifiable {
        var level: CEFRLevel
        var seconds: Int
        var questionsAnswered: Int
        var questionsCorrect: Int
        var id: String { level.rawValue }

        var accuracy: Int {
            questionsAnswered > 0
                ? Int((Double(questionsCorrect) / Double(questionsAnswered) * 100).rounded())
                : 0
        }
    }

    static func summary(
        sessions: [StoryReadingSession],
        attempts: [StoryQuizAttempt],
        asOf now: Date = Date()
    ) -> Summary {
        var s = Summary()
        var stories = Set<UUID>()

        for session in sessions {
            s.sessionCount += 1
            s.totalSeconds += session.seconds
            s.lookups += session.lookups
            s.wordsSaved += session.wordsSaved
            s.longestSessionSeconds = max(s.longestSessionSeconds, session.seconds)
            if session.wasListening { s.listeningSeconds += session.seconds }
            stories.insert(session.storyID)
            if let last = s.lastReadAt {
                s.lastReadAt = max(last, session.date)
            } else {
                s.lastReadAt = session.date
            }
        }
        s.storiesRead = stories.count

        for attempt in attempts {
            s.quizCount += 1
            s.questionsAnswered += attempt.questionCount
            s.questionsCorrect += attempt.correctCount
            if attempt.wasListening { s.listeningQuizCount += 1 }
            if attempt.isPerfect { s.perfectQuizzes += 1 }
        }

        let days = activeDays(sessions: sessions, attempts: attempts)
        s.activeDays = days.count
        s.dayStreak = streak(over: days, asOf: now)
        return s
    }

    static func levelSlices(
        sessions: [StoryReadingSession],
        attempts: [StoryQuizAttempt]
    ) -> [LevelSlice] {
        var byLevel: [String: LevelSlice] = [:]
        for session in sessions {
            var slice = byLevel[session.levelRaw] ?? LevelSlice(level: session.level, seconds: 0, questionsAnswered: 0, questionsCorrect: 0)
            slice.seconds += session.seconds
            byLevel[session.levelRaw] = slice
        }
        for attempt in attempts {
            var slice = byLevel[attempt.levelRaw] ?? LevelSlice(level: attempt.level, seconds: 0, questionsAnswered: 0, questionsCorrect: 0)
            slice.questionsAnswered += attempt.questionCount
            slice.questionsCorrect += attempt.correctCount
            byLevel[attempt.levelRaw] = slice
        }
        return CEFRLevel.allCases.compactMap { byLevel[$0.rawValue] }
    }

    /// Days (midnight-keyed) with any story activity at all — reading *or* questions.
    private static func activeDays(sessions: [StoryReadingSession], attempts: [StoryQuizAttempt]) -> Set<Date> {
        let cal = Calendar.current
        var days = Set(sessions.map { cal.startOfDay(for: $0.date) })
        days.formUnion(attempts.map { cal.startOfDay(for: $0.date) })
        return days
    }

    /// Same "alive from yesterday" rule as `StudyLogService.currentStreak`, so the two never
    /// disagree about what a streak day is.
    private static func streak(over days: Set<Date>, asOf now: Date) -> Int {
        let cal = Calendar.current
        guard !days.isEmpty else { return 0 }
        let today = cal.startOfDay(for: now)
        var cursor = today
        if !days.contains(today) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    // MARK: - Formatting

    /// "45 s" / "12 min" / "1 h 05 min" — one compact duration format for every story surface.
    nonisolated static func formatShort(_ seconds: Int) -> String {
        if seconds < 60 { return "\(max(0, seconds)) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }

    /// "12:05" — the live session clock shown while reading.
    nonisolated static func formatClock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
