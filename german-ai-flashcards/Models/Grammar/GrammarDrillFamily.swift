//
//  GrammarDrillFamily.swift
//  german-ai-flashcards
//
//  The two grammar drills that keep their own round model instead of filing as a `KasusRound`:
//  Der · Die · Das (`ArticleRound`) and Präpositionen (`PrepositionRound`). Neither stores which
//  exercise it was — only a free-text `topic` — so each is one family, named here once.
//
//  Before this type the names and symbols were written out at each call site, which meant the
//  same drill was named twice in two files. Verlauf's rows and the Fortschritt pane's
//  time-per-exercise rows both read it.
//

import Foundation

nonisolated enum GrammarDrillFamily: String, CaseIterable, Identifiable, Hashable {
    case article, preposition

    var id: String { rawValue }

    var germanTitle: String {
        switch self {
        case .article:     "Der · Die · Das"
        case .preposition: "Präpositionen"
        }
    }

    var symbol: String {
        switch self {
        case .article:     "textformat.abc"
        case .preposition: "arrow.triangle.branch"
        }
    }

    /// What a round of this family counts, for „10 nouns · 1m 01s“.
    var countNoun: String {
        switch self {
        case .article:     "nouns"
        case .preposition: "prepositions"
        }
    }
}
