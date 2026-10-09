//
//  PrepositionStats.swift
//  german-ai-flashcards
//
//  Persistence for the preposition Kasus drill, mirroring `ArticleStats`:
//  - `PrepositionStat` — one row per preposition, accumulating seen/missed counts and *which
//    wrong case keeps being picked*, so rounds can bias toward tricky ones and the summary can
//    say "you keep putting mit in the accusative".
//  - `PrepositionRound` — one row per completed round, backing the progress strip + personal bests.
//

import Foundation
import SwiftData

// MARK: - Per-preposition cumulative stats

/// Lifetime Kasus-drill stats for one preposition, keyed by the lowercased word.
@Model
final class PrepositionStat {
    var key: String
    /// Display form ("außer").
    var word: String
    /// The correct case's raw value ("dativ").
    var caseRaw: String
    /// The English meanings as one line, so the summary can name the word without reloading JSON.
    var meaning: String

    /// Rounds this preposition appeared in.
    var timesSeen: Int
    /// Rounds where it was answered wrong.
    var timesMissed: Int
    /// Consecutive rounds answered first-try — resets on a miss. A preposition with miss history
    /// "graduates" out of the tricky list at `PrepositionService.graduationStreak`.
    var firstTryStreak: Int
    var lastSeenAt: Date
    var lastMissedAt: Date?

    /// Encoded `[String: Int]` — wrong cases picked for this preposition, and how often.
    var wrongPicksData: Data?

    init(key: String, word: String, caseRaw: String, meaning: String) {
        self.key = key
        self.word = word
        self.caseRaw = caseRaw
        self.meaning = meaning
        self.timesSeen = 0
        self.timesMissed = 0
        self.firstTryStreak = 0
        self.lastSeenAt = Date()
        self.lastMissedAt = nil
    }

    var governs: PrepositionCase? { PrepositionCase(rawValue: caseRaw) }

    var wrongPicks: [String: Int] {
        get {
            guard let wrongPicksData else { return [:] }
            return (try? JSONDecoder().decode([String: Int].self, from: wrongPicksData)) ?? [:]
        }
        set { wrongPicksData = try? JSONEncoder().encode(newValue) }
    }

    /// The wrong case this preposition keeps attracting (deterministic tie-break).
    var topWrongPick: PrepositionCase? {
        let top = wrongPicks.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
        return top.flatMap(PrepositionCase.init(rawValue:))
    }

    /// Missed repeatedly and not yet re-proven — worth re-drilling.
    var isTricky: Bool {
        timesMissed >= PrepositionService.troubleMinMisses
            && firstTryStreak < PrepositionService.graduationStreak
    }
}

// MARK: - Per-round history

/// One completed Kasus round.
@Model
final class PrepositionRound {
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
