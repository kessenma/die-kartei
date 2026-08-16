//
//  LearnerLevel.swift
//  german-ai-flashcards
//
//  The learner's XP level and German rank — the single score every activity feeds. Pure value
//  math over a total XP figure; `ExperienceService` computes that figure from the `StudyDay`
//  log, so leveling up needs no storage of its own.
//
//  The curve is deliberately gentle at the bottom (level 2 at 100 XP, a review session or two)
//  and stretches out as ranks climb, so early wins come fast and later ranks mean something.
//

import SwiftUI

// MARK: - Rank

/// The German rank names a level maps to. Bands widen as levels climb — the same shape as the
/// XP curve — and the label pairs a German name (the identity) with a short English gloss.
enum LearnerRank: String, CaseIterable, Identifiable {
    case neuling, anfaenger, lernender, entdecker, kenner, sprachfreund, wortschmied, meister, grossmeister

    var id: String { rawValue }

    var germanName: String {
        switch self {
        case .neuling:      "Neuling"
        case .anfaenger:    "Anfänger"
        case .lernender:    "Lernender"
        case .entdecker:    "Entdecker"
        case .kenner:       "Kenner"
        case .sprachfreund: "Sprachfreund"
        case .wortschmied:  "Wortschmied"
        case .meister:      "Meister"
        case .grossmeister: "Großmeister"
        }
    }

    var englishName: String {
        switch self {
        case .neuling:      "Newcomer"
        case .anfaenger:    "Beginner"
        case .lernender:    "Learner"
        case .entdecker:    "Explorer"
        case .kenner:       "Connoisseur"
        case .sprachfreund: "Language friend"
        case .wortschmied:  "Word smith"
        case .meister:      "Master"
        case .grossmeister: "Grand master"
        }
    }

    /// The level at which this rank starts (rank 1 begins at level 1).
    var firstLevel: Int {
        switch self {
        case .neuling:      1
        case .anfaenger:    3
        case .lernender:    5
        case .entdecker:    7
        case .kenner:       10
        case .sprachfreund: 13
        case .wortschmied:  17
        case .meister:      21
        case .grossmeister: 26
        }
    }

    /// Accent per rank, so climbing visibly changes the level card. Follows the app's existing
    /// activity color language (blue/purple/green family), ending in a gold for the top ranks.
    var tint: Color {
        switch self {
        case .neuling:      .blue
        case .anfaenger:    .teal
        case .lernender:    .green
        case .entdecker:    .purple
        case .kenner:       .indigo
        case .sprachfreund: .pink
        case .wortschmied:  .orange
        case .meister:      Color(light: 0xB8860B, dark: 0xE6C15A)   // gold
        case .grossmeister: Color(light: 0x8B6508, dark: 0xF0D77B)   // deep gold
        }
    }

    static func rank(for level: Int) -> LearnerRank {
        var result = LearnerRank.neuling
        for rank in allCases where level >= rank.firstLevel { result = rank }
        return result
    }
}

// MARK: - Level

/// Where a total XP figure lands on the curve: which level, which rank that level carries, and
/// how far through the level the learner is.
struct LearnerLevel: Equatable {
    let totalXP: Int
    let level: Int
    let rank: LearnerRank
    /// XP earned since this level started.
    let xpIntoLevel: Int
    /// XP needed to leave this level (`xpIntoLevel / xpForNextLevel` is the progress bar).
    let xpForNextLevel: Int

    var progress: Double {
        guard xpForNextLevel > 0 else { return 0 }
        return min(1, Double(xpIntoLevel) / Double(xpForNextLevel))
    }

    /// Cumulative XP required to *reach* `level` (level 1 starts at 0). The quadratic keeps
    /// early levels quick (2 → 100, 3 → 300, 4 → 600, 5 → 1 000, 10 → 4 500, 20 → 19 000).
    static func threshold(forLevel level: Int) -> Int {
        50 * max(0, level - 1) * max(1, level)
    }

    static func level(forTotalXP xp: Int) -> LearnerLevel {
        var level = 1
        while threshold(forLevel: level + 1) <= xp { level += 1 }
        let floor = threshold(forLevel: level)
        return LearnerLevel(
            totalXP: xp,
            level: level,
            rank: LearnerRank.rank(for: level),
            xpIntoLevel: xp - floor,
            xpForNextLevel: threshold(forLevel: level + 1) - floor
        )
    }
}
