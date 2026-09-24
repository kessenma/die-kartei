//
//  Preposition.swift
//  german-ai-flashcards
//
//  Value types for the preposition exercises — the German prepositions grouped by the case
//  they govern (Akkusativ, Dativ, Wechsel, Genitiv), with their meanings, contractions
//  ("in + das = ins") and worked examples.
//
//  `Preposition` and friends are the bundled *content* (decoded from prepositions.json by
//  `PrepositionService`); the session/round types below mirror `ArticleGame.swift` exactly, so
//  the Kasus drill rides the same rails: a session payload launched via `ActivityRouter`, a
//  round result handed up on completion, history-aware feedback handed back for the summary.
//

import Foundation
import SwiftUI

// MARK: - The four case groups

/// The case a preposition puts the following noun into. `wechsel` is the two-way group, whose
/// prepositions take Akkusativ for movement (Wohin?) and Dativ for location (Wo?).
nonisolated enum PrepositionCase: String, CaseIterable, Codable, Identifiable {
    case akkusativ
    case dativ
    case wechsel
    case genitiv

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .akkusativ: "Akkusativ"
        case .dativ:     "Dativ"
        case .wechsel:   "Wechsel"
        case .genitiv:   "Genitiv"
        }
    }

    /// Compact form for chips and the card's case tab.
    var shortLabel: String {
        switch self {
        case .akkusativ: "AKK"
        case .dativ:     "DAT"
        case .wechsel:   "WECHS"
        case .genitiv:   "GEN"
        }
    }

    /// One-line English gloss under the German name.
    var englishLabel: String {
        switch self {
        case .akkusativ: "always accusative"
        case .dativ:     "always dative"
        case .wechsel:   "accusative or dative"
        case .genitiv:   "genitive"
        }
    }

    /// The question that decides the case, for the two-way group.
    var questionWord: String? {
        self == .wechsel ? "Wohin? → Akkusativ · Wo? → Dativ" : nil
    }

    /// The article forms this case produces — the compact reminder on the rules sheet and in the
    /// game's reveal.
    var articleLine: String {
        switch self {
        case .akkusativ: "den (m) · die (f) · das (n) · die (Pl.)"
        case .dativ:     "dem (m) · der (f) · dem (n) · den …n (Pl.)"
        case .wechsel:   "movement → den/die/das · location → dem/der/dem"
        case .genitiv:   "des …s (m/n) · der (f/Pl.)"
        }
    }

    /// This group's fixed identity color, used on the drill buttons, the card's case tab and the
    /// rules sheet so the color itself becomes a memory hook. From `CasePalette`, so a
    /// preposition's case reads the same as that case everywhere else in the app.
    var color: Color {
        switch self {
        case .akkusativ: GrammarCase.akkusativ.color
        case .dativ:     GrammarCase.dativ.color
        case .wechsel:   CasePalette.wechsel
        case .genitiv:   GrammarCase.genitiv.color
        }
    }

    var symbol: String {
        switch self {
        case .akkusativ: GrammarCase.akkusativ.symbol
        case .dativ:     GrammarCase.dativ.symbol
        case .wechsel:   CasePalette.wechselSymbol
        case .genitiv:   GrammarCase.genitiv.symbol
        }
    }
}

// MARK: - Bundled content

/// How advanced a preposition is. Core rounds stay on what A1–B1 actually needs; `advanced`
/// covers the formal genitive prepositions (innerhalb, jenseits, …) that only show up in
/// writing, plus the couple of entries with awkward real-world usage.
nonisolated enum PrepositionTier: String, Codable {
    case core
    case advanced
}

/// A contraction of a preposition with a following article — "in + das = ins".
nonisolated struct PrepositionContraction: Codable, Hashable, Identifiable {
    /// The uncontracted pair ("in das").
    var long: String
    /// The contracted form ("ins").
    var short: String

    var id: String { short }
}

/// A worked sentence for one preposition. Two-way prepositions carry one of each case so the
/// Wohin/Wo contrast is visible side by side.
///
/// Array order in prepositions.json is the contract: the sentence the word's 3D scene depicts
/// comes first (for a two-way word, the first of each case), extra sentences follow. There is
/// no marker field to keep in sync — reordering the JSON *is* changing the primary.
nonisolated struct PrepositionExample: Codable, Hashable, Identifiable {
    var german: String
    var english: String
    /// The case this sentence actually uses. For a `wechsel` preposition this is `.akkusativ`
    /// or `.dativ` — never `.wechsel` — which is the whole point of the pair.
    var caseUsed: PrepositionCase

    var id: String { german }
}

/// One German preposition and everything the exercises need to teach it.
nonisolated struct Preposition: Codable, Identifiable, Hashable {
    var word: String
    /// The case it governs.
    var governs: PrepositionCase
    var meanings: [String]
    var contractions: [PrepositionContraction]
    var examples: [PrepositionExample]
    var tier: PrepositionTier
    /// The honest caveat, when there is one ("bis usually pairs with a second preposition…").
    var note: String?

    var id: String { word }

    /// "through, by means of" — the meanings as one line.
    var meaningLine: String { meanings.joined(separator: ", ") }

    /// "in + das = ins · in + dem = im", or nil when the preposition has none.
    var contractionLine: String? {
        guard !contractions.isEmpty else { return nil }
        return contractions.map { "\($0.long) = \($0.short)" }.joined(separator: " · ")
    }

    func example(for group: PrepositionCase) -> PrepositionExample? {
        examples.first { $0.caseUsed == group }
    }

    /// What a drill reveal shows: one worked sentence per case for a two-way preposition, one
    /// otherwise — the scene-depicting sentence (first in file order), so it matches the
    /// canvas above it, without the reveal ballooning as extra sentences are added.
    func revealExamples() -> [PrepositionExample] {
        guard governs == .wechsel else { return Array(examples.prefix(1)) }
        return [PrepositionCase.akkusativ, .dativ].compactMap { c in
            examples.first { $0.caseUsed == c }
        }
    }
}

nonisolated struct PrepositionsFile: Codable {
    let prepositions: [Preposition]
}

// MARK: - Session payload (Kasus drill)

/// One question in the Kasus drill: a preposition, the case it governs, and the example used to
/// make the point when the learner misses it.
nonisolated struct PrepositionQuestion: Identifiable, Equatable {
    let id = UUID()
    var word: String
    var governs: PrepositionCase
    var meaning: String
    var note: String?
    /// Shown on reveal. Two-way prepositions carry both sentences so the contrast lands.
    var examples: [PrepositionExample] = []

    init(_ preposition: Preposition) {
        self.word = preposition.word
        self.governs = preposition.governs
        self.meaning = preposition.meaningLine
        self.note = preposition.note
        // One sentence per relevant case, the on-screen scene's sentence first — not the
        // raw list, which also carries the extra examples.
        self.examples = preposition.revealExamples()
    }
}

/// The payload for launching a Kasus round via `Activity.prepositionCase`.
nonisolated struct PrepositionCaseSession: Identifiable {
    let id = UUID()
    var questions: [PrepositionQuestion]
    /// Source label shown in the top bar and stamped on round history ("All groups", "Wechsel", …).
    var topic: String
    /// The buttons the board offers, in `PrepositionCase.allCases` order. An "Akkusativ or Dativ?"
    /// round shows two, not four.
    ///
    /// Declared by the launcher from the *source pool*, never derived from the sampled questions:
    /// a ten-question round that happens to contain no Genitiv must not give that away by dropping
    /// the button.
    var answerCases: [PrepositionCase] = PrepositionCase.allCases

    var questionCount: Int { questions.count }
}

// MARK: - Round hand-off (game → persistence → summary)

/// What happened to one preposition during a round.
nonisolated struct PrepositionAnswerOutcome {
    var word: String
    var governs: PrepositionCase
    var meaning: String
    /// Answered correctly on the first tap.
    var firstTry: Bool
    /// The case wrongly tapped first, when missed.
    var wrongPick: PrepositionCase?
    /// The question already showed the answer — teaching mode, where the scene carries the case
    /// color. Such answers still count as practice but must not count as *mastery*.
    var scaffolded: Bool = false
}

/// A finished round, handed up through `onComplete`.
nonisolated struct PrepositionRoundResult {
    var outcomes: [PrepositionAnswerOutcome]
    var durationSeconds: Int

    var questionCount: Int { outcomes.count }
    var firstTryCount: Int { outcomes.filter(\.firstTry).count }

    /// The subset the learner answered without the answer on screen. This — not
    /// `firstTryCount` — is what may move the profile's Präpositionen skill.
    var unscaffolded: [PrepositionAnswerOutcome] { outcomes.filter { !$0.scaffolded } }
}

/// What persistence hands back so the summary can show history-aware callouts.
nonisolated struct PrepositionRoundFeedback {
    /// A preposition missed this round, enriched with its lifetime history.
    struct RepeatMiss: Identifiable {
        var word: String
        var governs: PrepositionCase
        var meaning: String
        /// Lifetime rounds missed, including this one. `>= 2` reads as "again".
        var timesMissed: Int
        /// The wrong case they keep reaching for, when that's a repeating pattern.
        var repeatedWrongCase: PrepositionCase?

        var id: String { word }
    }

    /// Fastest perfect round yet for this source at this round size.
    var isPersonalBest: Bool
    var misses: [RepeatMiss]

    static let empty = PrepositionRoundFeedback(isPersonalBest: false, misses: [])
}
