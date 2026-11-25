//
//  MatchingStats.swift
//  german-ai-flashcards
//
//  Persistence for the card-matching game. Two stores:
//  - `MatchingPairStat` — one row per word pair, accumulating how often it's seen vs. missed and
//    *what it keeps getting confused with*, so the game can spot "same mistake again" and bias
//    future rounds toward tricky pairs.
//  - `MatchingRound` — one row per completed round, backing the progress strip and personal bests.
//
//  Plus the value types the game hands up on completion (`MatchingRoundResult`) and gets back
//  for its summary (`MatchingRoundFeedback`).
//

import Foundation
import SwiftData

// MARK: - Per-pair cumulative stats

/// Lifetime matching stats for one German ↔ English pair, keyed by `MatchingStatsService.pairKey`.
@Model
final class MatchingPairStat {
    var key: String
    /// Display forms (German without its article — the article is stored separately).
    var german: String
    var article: String?
    var english: String

    /// Rounds this pair appeared in.
    var timesSeen: Int
    /// Rounds where the pair was involved in at least one wrong attempt.
    var timesMissed: Int
    /// Consecutive rounds matched on the first try — resets to 0 on a miss. A pair with miss
    /// history "graduates" out of the tricky list once this reaches `MatchingStatsService.graduationStreak`.
    var firstTryStreak: Int
    var lastSeenAt: Date
    var lastMissedAt: Date?

    /// Encoded `[String: Int]` — wrong English meanings the learner has paired this German word
    /// with, and how often. The max-count entry is "the same mistake" worth calling out.
    var confusionsData: Data?

    init(key: String, german: String, article: String?, english: String) {
        self.key = key
        self.german = german
        self.article = article
        self.english = english
        self.timesSeen = 0
        self.timesMissed = 0
        self.firstTryStreak = 0
        self.lastSeenAt = Date()
        self.lastMissedAt = nil
    }

    var confusions: [String: Int] {
        get {
            guard let confusionsData else { return [:] }
            return (try? JSONDecoder().decode([String: Int].self, from: confusionsData)) ?? [:]
        }
        set { confusionsData = try? JSONEncoder().encode(newValue) }
    }

    /// The wrong meaning this word gets paired with most often (nil when it's only ever been
    /// missed "anonymously", i.e. its English tile was taken by another word).
    var topConfusion: String? {
        confusions.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    /// Missed repeatedly and not yet re-proven — worth re-drilling and surfacing to the learner.
    var isTricky: Bool {
        timesMissed >= MatchingStatsService.troubleMinMisses
            && firstTryStreak < MatchingStatsService.graduationStreak
    }

    /// "der See" for display, or just the word when there's no article.
    var displayGerman: String {
        german.withArticle(article)
    }
}

// MARK: - Per-round history

/// One completed matching round — the unit of the progress strip and personal-best lookups.
@Model
final class MatchingRound {
    var date: Date
    var topic: String
    var pairCount: Int
    var firstTryCount: Int
    var durationSeconds: Int

    init(topic: String, pairCount: Int, firstTryCount: Int, durationSeconds: Int) {
        self.date = Date()
        self.topic = topic
        self.pairCount = pairCount
        self.firstTryCount = firstTryCount
        self.durationSeconds = durationSeconds
    }

    var isPerfect: Bool { firstTryCount == pairCount && pairCount > 0 }
}

// MARK: - Round hand-off (game → persistence → summary)

/// What happened to one pair during a round, reported by `MatchingGameView` on completion.
struct MatchingPairOutcome {
    var german: String
    var article: String?
    var english: String
    /// Matched without ever being part of a wrong attempt.
    var firstTry: Bool
    /// English meanings the learner wrongly paired this German word with, this round.
    var wrongEnglishPicks: [String]
}

/// A finished round, handed up through `onComplete`.
struct MatchingRoundResult {
    var outcomes: [MatchingPairOutcome]
    var durationSeconds: Int

    var pairCount: Int { outcomes.count }
    var firstTryCount: Int { outcomes.filter(\.firstTry).count }
}

/// What persistence hands back so the round summary can show history-aware callouts.
struct MatchingRoundFeedback {
    /// A pair missed this round, enriched with its lifetime history.
    struct RepeatMiss: Identifiable {
        var displayGerman: String
        var english: String
        /// Lifetime rounds missed, including this one. `>= 2` reads as "again".
        var timesMissed: Int
        /// The wrong meaning it's most often paired with, when that's a repeating pattern.
        var repeatedConfusion: String?
        var id: String { displayGerman + "|" + english }
    }

    /// Fastest perfect round yet for this deck at this board size.
    var isPersonalBest: Bool
    var misses: [RepeatMiss]

    static let empty = MatchingRoundFeedback(isPersonalBest: false, misses: [])
}
