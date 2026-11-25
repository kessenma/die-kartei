//
//  ConversationQualityService.swift
//  german-ai-flashcards
//
//  Reads finished conversations and says how *well* they went, not how many there were.
//
//  This exists because the Spitze — the peak of the Lernpyramide, production, the hardest thing the
//  app teaches — was measured by counting finished chats. A count rewards showing up, which is the
//  right rule for XP and the wrong one for the summit: twenty abandoned two-turn chats would crown
//  the pyramid. Conversation *quality* is the one signal no placement quiz can shortcut, which is
//  what makes it the honest top of the structure.
//
//  Nothing is stored — this derives from `ChatConversation.summary`, which is already saved.
//

import Foundation

enum ConversationQualityService {

    // MARK: - Tuning

    /// A conversation shorter than this isn't a conversation. Unlike the density bar below, this
    /// number needs no calibration: it's the difference between talking and opening a screen.
    static let minimumTurns = 4

    /// Corrections per learner turn at or below which a conversation counts as well held.
    ///
    /// **Provisional.** Unlike the placement cutoffs, this one could not be set by simulation —
    /// correction density depends on the coach's own correcting behaviour, which is a real model's
    /// output on real speech and cannot be faked convincingly. `distribution(...)` exists to settle
    /// it against actual history; see Fortschritt ▸ Conversation quality for what the data says.
    static let qualityDensityBar = 0.35

    /// Well-held conversations that crown the Spitze.
    static let qualityGoal = 12

    // MARK: - Per conversation

    /// Corrections per learner turn, or nil when the conversation is too short to judge.
    static func density(_ conversation: ChatConversation) -> Double? {
        guard let summary = conversation.summary, summary.turnCount >= minimumTurns else { return nil }
        return Double(summary.correctionCount) / Double(summary.turnCount)
    }

    /// Long enough to count, and held without being corrected on most turns.
    static func isWellHeld(_ conversation: ChatConversation) -> Bool {
        guard let density = density(conversation) else { return false }
        return density <= qualityDensityBar
    }

    static func wellHeldCount(_ conversations: [ChatConversation]) -> Int {
        // Closure literals rather than bare function references: `ChatConversation` is a
        // MainActor-isolated `@Model`, so passing `isWellHeld` directly hands an isolated function
        // to a nonisolated higher-order call. A literal inherits the caller's isolation instead.
        conversations.filter { isWellHeld($0) }.count
    }

    // MARK: - Distribution

    /// What the learner's own history actually looks like — the measurement that settles the bar.
    struct Distribution {
        var total: Int
        var judged: Int
        var tooShort: Int
        var median: Double?
        var lowerQuartile: Double?
        var upperQuartile: Double?
        /// How many conversations would count at each candidate bar.
        var clearing: [(bar: Double, count: Int)]

        var isEmpty: Bool { judged == 0 }
    }

    static let candidateBars: [Double] = [0.15, 0.25, 0.35, 0.50, 0.75]

    static func distribution(_ conversations: [ChatConversation]) -> Distribution {
        let densities = conversations.compactMap { density($0) }.sorted()
        let tooShort = conversations.filter { $0.summary != nil && density($0) == nil }.count

        return Distribution(
            total: conversations.count,
            judged: densities.count,
            tooShort: tooShort,
            median: quantile(densities, 0.5),
            lowerQuartile: quantile(densities, 0.25),
            upperQuartile: quantile(densities, 0.75),
            clearing: candidateBars.map { bar in
                (bar, densities.filter { $0 <= bar }.count)
            }
        )
    }

    private static func quantile(_ sorted: [Double], _ q: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        guard upper < sorted.count else { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
