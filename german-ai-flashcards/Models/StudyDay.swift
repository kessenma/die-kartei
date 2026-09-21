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

    // MARK: Time on task
    //
    // One bucket per activity family, so a day can be read as "how long" and not just "how many".
    // Every bucket is defaulted, so days written before time tracking existed migrate cleanly and
    // read as zero until `StudyTimeBackfillService` fills them in from the per-record history.

    /// Seconds spent on flashcards, card matching, and cloze rounds.
    var cardSeconds: Int = 0
    /// Seconds spent on grammar drills and der/die/das rounds.
    var grammarSeconds: Int = 0
    /// Seconds spent in conversation practice. Accrued live as the chat runs, not only at the end,
    /// so a chat that never gets summarized still counts its time.
    var conversationSeconds: Int = 0
    /// Seconds spent on story comprehension quizzes (reading time lives in `storySeconds`).
    var storyQuizSeconds: Int = 0

    // MARK: New words
    //
    // The Wortschatz daily budget. Defaulted like the time buckets, so older days read as zero.
    // Neither field counts toward `hasActivity`: asking for ten more words is not studying.

    /// Goethe words rated for the first time today.
    var newWordsIntroduced: Int = 0
    /// Extra new words the learner asked for today beyond the daily setting ("Learn 10 more").
    var newWordsBonus: Int = 0

    init(dayStart: Date) {
        self.dayStart = dayStart
        self.cardsReviewed = 0
        self.grammarExercises = 0
        self.conversations = 0
        self.storySeconds = 0
        self.storyQuestions = 0
        self.lastActivityAt = dayStart
        self.cardSeconds = 0
        self.grammarSeconds = 0
        self.conversationSeconds = 0
        self.storyQuizSeconds = 0
        self.newWordsIntroduced = 0
        self.newWordsBonus = 0
    }

    /// Time only counts as a study day once it passes a minute — a ten-second glance at a story
    /// shouldn't keep a streak alive, but a real read with no questions answered should. Applies
    /// to any untallied stretch (reading, an unsummarized conversation).
    static let storyStreakSeconds = 60

    /// Whole minutes of story reading, the unit the calendar and progress screens show.
    var storyMinutes: Int { storySeconds / 60 }

    /// Every second logged today, across all activities — the number the calendar totals.
    var totalSeconds: Int {
        cardSeconds + grammarSeconds + conversationSeconds + storySeconds + storyQuizSeconds
    }

    /// Whole minutes studied today, the unit the calendar's time shading buckets on.
    var totalMinutes: Int { totalSeconds / 60 }

    /// Did the learner do anything at all on this day? (Guards against empty rows.)
    var hasActivity: Bool {
        cardsReviewed > 0 || grammarExercises > 0 || conversations > 0
            || storyQuestions > 0 || totalSeconds >= Self.storyStreakSeconds
    }
}

// MARK: - Duration formatting

/// The one place study durations turn into text, so the calendar, the day sheet, and the range
/// summary always phrase the same number the same way. Rolls up to hours once there are any.
enum StudyTimeFormat {
    /// `"—"` / `"< 1 min"` / `"37 min"` / `"2 h 05 min"` / `"3 h"`.
    static func long(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        guard seconds >= 60 else { return "< 1 min" }
        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest)) min"
    }

    /// The compact form for tight spots (a cell's accessibility value, a summary chip): `"45m"`,
    /// `"2h 05m"`.
    static func short(_ seconds: Int) -> String {
        guard seconds >= 60 else { return seconds > 0 ? "<1m" : "0m" }
        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(String(format: "%02d", rest))m"
    }
}
