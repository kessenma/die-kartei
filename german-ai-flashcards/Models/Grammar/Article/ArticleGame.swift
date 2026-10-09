//
//  ArticleGame.swift
//  german-ai-flashcards
//
//  Value types for the der/die/das article game — the gender-recognition drill where the
//  learner sees a bare noun and taps its definite article. Mirrors the matching game's
//  shape: a session payload launched via `ActivityRouter`, a round result handed up on
//  completion, and history-aware feedback handed back for the summary.
//

import Foundation
import SwiftUI

// MARK: - The three articles

/// A German definite article (Nominativ). Each carries a fixed identity color used across the
/// game — buttons, breakdowns, and the rules sheet — so learners build a color ↔ gender link.
/// (Red never signals "wrong" in this game; mistakes use shake/dim so `die` can own red.)
enum GermanArticle: String, CaseIterable, Codable, Identifiable {
    case der
    case die
    case das

    var id: String { rawValue }

    /// This article as a `Gender`, so the game shares one palette with the flashcards, the card
    /// corner tab, and the theme picker rather than keeping a second set of near-miss colors.
    var gender: Gender {
        switch self {
        case .der: .der
        case .die: .die
        case .das: .das
        }
    }

    /// The fixed identity color. Delegates to `GenderPalette` — previously this was plain
    /// `.blue`/`.red`/`.green`, which read *close* to the flashcard colors without matching them,
    /// so the same noun could be two different blues in two screens.
    var color: Color { gender.color }

    /// "maskulin" — the German gender name, for compact labels.
    var genderGerman: String {
        switch self {
        case .der: "maskulin"
        case .die: "feminin"
        case .das: "neutrum"
        }
    }

    var genderEnglish: String {
        switch self {
        case .der: "masculine"
        case .die: "feminine"
        case .das: "neuter"
        }
    }

    /// Lenient init from stored/model text ("Die ", "das", …). Nil for anything else.
    init?(text: String?) {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let article = GermanArticle(rawValue: raw) else { return nil }
        self = article
    }
}

// MARK: - Session payload

/// One question on the board: a bare noun and its correct article.
struct ArticleQuestion: Identifiable, Equatable {
    let id = UUID()
    /// The noun without its article, capitalized ("Gabel").
    var noun: String
    var article: GermanArticle
    var english: String
}

/// The payload for launching an article-game round via `Activity.articleGame`.
struct ArticleGameSession: Identifiable {
    let id = UUID()
    var questions: [ArticleQuestion]
    /// Source label shown in the top bar and stamped on round history ("Goethe A1", a topic, …).
    var topic: String

    var questionCount: Int { questions.count }
}

// MARK: - Round hand-off (game → persistence → summary)

/// What happened to one noun during a round.
struct ArticleAnswerOutcome {
    var noun: String
    var article: GermanArticle
    var english: String
    /// Answered correctly on the first tap.
    var firstTry: Bool
    /// The article wrongly tapped first, when missed.
    var wrongPick: GermanArticle?
}

/// A finished round, handed up through `onComplete`.
struct ArticleRoundResult {
    var outcomes: [ArticleAnswerOutcome]
    var durationSeconds: Int

    var questionCount: Int { outcomes.count }
    var firstTryCount: Int { outcomes.filter(\.firstTry).count }
}

/// What persistence hands back so the summary can show history-aware callouts.
struct ArticleRoundFeedback {
    /// A noun missed this round, enriched with its lifetime history.
    struct RepeatMiss: Identifiable {
        var noun: String
        var article: GermanArticle
        var english: String
        /// Lifetime rounds missed, including this one. `>= 2` reads as "again".
        var timesMissed: Int
        /// The wrong article they keep reaching for, when that's a repeating pattern.
        var repeatedWrongArticle: GermanArticle?
        var id: String { noun }

        var displayGerman: String { noun.withArticle(article.rawValue) }
    }

    /// Fastest perfect round yet for this source at this round size.
    var isPersonalBest: Bool
    var misses: [RepeatMiss]

    static let empty = ArticleRoundFeedback(isPersonalBest: false, misses: [])
}
