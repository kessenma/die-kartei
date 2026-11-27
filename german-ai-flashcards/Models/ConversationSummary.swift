import Foundation

// Moved out of ChatConversation.swift (SwiftData) unchanged, so the shared conversation session
// can build summaries and saved-word lists on Android too.

// MARK: - Persisted coaching summary

/// The end-of-session analysis, encoded into `ChatConversation.summaryData`.
nonisolated struct ConversationSummary: Codable {
    var strengths: [String]
    var improvements: [String]
    var patternNote: String
    var wordsPracticed: [String]
    var correctionCount: Int
    /// Optional — corrections the learner repaired themselves after a nudge (elicitation feedback).
    var selfCorrections: Int?
    /// Optional for backward-compatibility with summaries saved before hint tracking.
    var hintsUsed: Int?
    /// Optional for backward-compatibility — AI replies the learner translated to English.
    var translationsUsed: Int?
    /// Optional — turns produced via the "Say it in German" helper.
    var phraseHelperUsed: Int?
    /// Optional — SRS-due words the learner re-used correctly, advancing their review schedule.
    var spacedReviews: [String]?
    /// Optional — longest run of consecutive unaided user turns this session (no hints,
    /// no phrase helper, no translation of the reply just before).
    var bestUnaidedStreak: Int?
    /// Optional — true when that run beat the stored all-time best at summary time.
    var unaidedStreakIsRecord: Bool?
    var turnCount: Int
    var generatedAt: Date
    /// Raw model text kept as a fallback when structured parsing was incomplete.
    var rawText: String?

    var isEmpty: Bool {
        strengths.isEmpty && improvements.isEmpty && patternNote.isEmpty
    }
}

/// A vocabulary word the learner tapped and saved during a conversation.
nonisolated struct SavedVocabItem: Codable, Identifiable, Hashable {
    var german: String
    var english: String
    var id: String { german.lowercased() }
}
