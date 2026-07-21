import Foundation
import SwiftData

/// One calendar day on which the learner did *something* — a flashcard review, a grammar
/// exercise, or a conversation. The lightweight per-day log the "Today" streak is built on
/// (the prerequisite called out in `FUTURE_FEATURES.md` #6). One row per day, fetch-or-created
/// and incremented as activities finish; a real streak is just the run of consecutive rows.
@Model
final class StudyDay {
    /// Midnight (`Calendar.startOfDay`) for this day — the row's identity. Never two rows per day.
    var dayStart: Date
    /// Flashcards reviewed today (Anki/Leitner/flip), across all decks.
    var cardsReviewed: Int
    /// Grammar multiple-choice exercises answered today.
    var grammarExercises: Int
    /// Conversations finished today.
    var conversations: Int
    /// Seconds spent reading or listening to stories today. Defaulted so days logged before
    /// story tracking existed migrate cleanly.
    var storySeconds: Int = 0
    /// Story comprehension questions answered today.
    var storyQuestions: Int = 0
    /// When the most recent activity landed — lets "Today" show a fresh-vs-stale sense of the day.
    var lastActivityAt: Date

    init(dayStart: Date) {
        self.dayStart = dayStart
        self.cardsReviewed = 0
        self.grammarExercises = 0
        self.conversations = 0
        self.storySeconds = 0
        self.storyQuestions = 0
        self.lastActivityAt = dayStart
    }

    /// Reading time only counts as a study day once it passes a minute — a ten-second glance at a
    /// story shouldn't keep a streak alive, but a real read with no questions answered should.
    static let storyStreakSeconds = 60

    /// Whole minutes of story reading, the unit the calendar and progress screens show.
    var storyMinutes: Int { storySeconds / 60 }

    /// Did the learner do anything at all on this day? (Guards against empty rows.)
    var hasActivity: Bool {
        cardsReviewed > 0 || grammarExercises > 0 || conversations > 0
            || storyQuestions > 0 || storySeconds >= Self.storyStreakSeconds
    }
}
