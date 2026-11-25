//
//  ArticleStats.swift
//  german-ai-flashcards
//
//  Persistence for the der/die/das game, mirroring `MatchingStats`:
//  - `ArticleWordStat` — one row per noun, accumulating seen/missed counts and *which wrong
//    article keeps being picked*, so rounds can bias toward tricky nouns and the summary can
//    say "you keep reaching for der".
//  - `ArticleRound` — one row per completed round, backing the progress strip + personal bests.
//

import Foundation
import SwiftData

// MARK: - Per-noun cumulative stats

/// Lifetime article-game stats for one noun, keyed by the lowercased noun.
@Model
final class ArticleWordStat {
    var key: String
    /// Display form, no article ("Gabel").
    var noun: String
    /// The correct article's raw value ("die").
    var articleRaw: String
    var english: String

    /// Rounds this noun appeared in.
    var timesSeen: Int
    /// Rounds where it was answered wrong.
    var timesMissed: Int
    /// Consecutive rounds answered first-try — resets on a miss. A noun with miss history
    /// "graduates" out of the tricky list at `ArticleGameService.graduationStreak`.
    var firstTryStreak: Int
    var lastSeenAt: Date
    var lastMissedAt: Date?

    /// Encoded `[String: Int]` — wrong articles picked for this noun, and how often.
    var wrongPicksData: Data?

    init(key: String, noun: String, articleRaw: String, english: String) {
        self.key = key
        self.noun = noun
        self.articleRaw = articleRaw
        self.english = english
        self.timesSeen = 0
        self.timesMissed = 0
        self.firstTryStreak = 0
        self.lastSeenAt = Date()
        self.lastMissedAt = nil
    }

    var article: GermanArticle? { GermanArticle(rawValue: articleRaw) }

    var wrongPicks: [String: Int] {
        get {
            guard let wrongPicksData else { return [:] }
            return (try? JSONDecoder().decode([String: Int].self, from: wrongPicksData)) ?? [:]
        }
        set { wrongPicksData = try? JSONEncoder().encode(newValue) }
    }

    /// The wrong article this noun keeps attracting (deterministic tie-break).
    var topWrongPick: GermanArticle? {
        let top = wrongPicks.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
        return top.flatMap(GermanArticle.init(rawValue:))
    }

    /// Missed repeatedly and not yet re-proven — worth re-drilling.
    var isTricky: Bool {
        timesMissed >= ArticleGameService.troubleMinMisses
            && firstTryStreak < ArticleGameService.graduationStreak
    }

    /// "die Gabel" for display.
    var displayGerman: String { noun.withArticle(articleRaw) }
}

// MARK: - Per-round history

/// One completed article-game round.
@Model
final class ArticleRound {
    var date: Date
    var topic: String
    var questionCount: Int
    var firstTryCount: Int
    var durationSeconds: Int

    init(topic: String, questionCount: Int, firstTryCount: Int, durationSeconds: Int) {
        self.date = Date()
        self.topic = topic
        self.questionCount = questionCount
        self.firstTryCount = firstTryCount
        self.durationSeconds = durationSeconds
    }

    var isPerfect: Bool { firstTryCount == questionCount && questionCount > 0 }
}
