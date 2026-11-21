//
//  GrammarArea.swift
//  german-ai-flashcards
//
//  The Grammatik hub's rooms: everything that isn't the case path, shelved by domain. Display-only
//  grouping — no stored keys, no registry contact. `KasusRoundStep` raw values, round ids, topic
//  keys and `KasusDrillMeta.placement` are all untouched by where a room shelves a row.
//
//  Growth contract (docs/GRAMMAR_EXERCISES.md § The hub's rooms):
//    - a new standalone exercise or rule sheet = one `BereichRow` in its area's `rows`
//      (`.drill(kind)` for one from the registry: the row builds itself from `KasusDrillMeta`);
//    - a new structure = one `.struktur(focus)` row — it renders as a quiet Lektion row while
//      `GrammarRoute(focus).hasExercise` is false and upgrades IN PLACE to a full topic row the
//      day its `GrammarTopic` ships (one predicate, never two maintained lists);
//    - a new area (say Zeiten & Formen split out of Verben) = one case here — the hub and
//      `GrammarBereichView` iterate `allCases` / `rows` and are never edited for it.
//
//  The three case foci (akkusativ, dativ, genitiv) belong to the path, not to a room; every other
//  `GrammarFocus` files under exactly one area, which is what feeds a room row's flame
//  (`GrammarAreaTests` holds the partition).
//

import Foundation

nonisolated enum GrammarArea: String, CaseIterable, Identifiable {
    /// The preposition hub, both tracks. Keeps its own screen (`PrepositionHubView`).
    case praepositionen
    /// Der · Die · Das, the 18 gender rules, and the adjective endings that hang off them.
    case artikel
    /// The verb structures: Reflexive Verben today, the tense and mood lessons beside it.
    case verben
    /// The four anchor questions, asked on the English sentence first. Exercises only, no
    /// structures: the cases they are about live on the path.
    case englisch

    var id: String { rawValue }

    var germanTitle: String {
        switch self {
        case .praepositionen: "Präpositionen"
        case .artikel:        "Artikel & Endungen"
        case .verben:         "Verben"
        case .englisch:       "Englisch & Fälle"
        }
    }

    /// The hub row's English, and the room header's caption — names the contents in plain
    /// English, so nobody has to decode the taxonomy before the tap.
    var englishRole: String {
        switch self {
        case .praepositionen: "Which case each one takes"
        case .artikel:        "Every noun's gender, and its endings"
        case .verben:         "Reflexives, tenses and moods"
        case .englisch:       "Wer, wen, wem, wessen — starting in English"
        }
    }

    var symbol: String {
        switch self {
        case .praepositionen: "arrow.triangle.branch"
        case .artikel:        "textformat.abc"
        case .verben:         "figure.run"
        case .englisch:       "character.bubble"
        }
    }

    /// An area spans cases, so it never wears a case colour; rows use the tint chip.

    /// The coach skills the area's rows read. A room row wears the flame when any is shaky.
    var foci: [GrammarFocus] {
        switch self {
        case .praepositionen: [.praepositionen, .wechselpraepositionen, .verbenPraepositionen]
        case .artikel:        [.artikel, .adjektivendungen]
        case .verben:         [.reflexivverben, .perfekt, .modalverben, .praeteritum, .futur, .konjunktiv2]
        // Recognition exercises on the path's own cases: there is no skill of its own here, and
        // nothing in the room can move the coach, so a flame would be one nobody could put out.
        case .englisch:       []
        }
    }

    func isShaky(_ shaky: [GrammarFocus]) -> Bool {
        foci.contains { shaky.contains($0) }
    }

    /// „A1–B1“: the span of the area's structures. A label, never a gate. A room with no
    /// structures of its own names the span of the path it reads.
    var levelLabel: String {
        if case .englisch = self { return "A1–B1" }
        let levels = foci.map(\.introducedAt.rawValue).sorted()
        guard let first = levels.first, let last = levels.last else { return "" }
        return first == last ? first : "\(first)–\(last)"
    }

    /// True for an area that keeps its own grown screen instead of the generic room.
    var hasOwnHub: Bool { self == .praepositionen }

    /// The room's shelf, in screen order (level order for the structures). An area with
    /// `hasOwnHub` leaves this empty.
    var rows: [BereichRow] {
        switch self {
        case .praepositionen:
            []
        case .artikel:
            [.screen(.articleGame), .drill(.tabelle), .sheet(.articleRules), .struktur(.adjektivendungen)]
        case .verben:
            [.struktur(.perfekt), .struktur(.modalverben), .struktur(.reflexivverben),
             .struktur(.praeteritum), .struktur(.futur), .struktur(.konjunktiv2)]
        // Finde den Fall is registered but not built yet, so it isn't shelved: a row whose module
        // composes nothing is a dead end, and `UnbuiltModule` exists for exactly that gap.
        case .englisch:
            [.drill(.frage), .drill(.englischeFalle)]
        }
    }

    /// Mehr dazu: pushes into a neighbour that drills the same ground — links, never absorbed rows.
    var crossLinks: [BereichLink] {
        switch self {
        case .praepositionen: []
        case .artikel:        []
        case .verben:         [.dativUnit, .prepositionVerbTrack]
        case .englisch:       [.dativUnit, .prepositionVerbTrack]
        }
    }
}

/// One shelf row of a room. Destinations are existing screens; adding a row never adds a screen.
nonisolated enum BereichRow: Hashable, Identifiable {
    /// A grammar structure. Renders as a full topic row (dots, push) once
    /// `GrammarRoute(focus).hasExercise`, and as a quiet Lektion row (the 30-second sheet) until
    /// then — the in-place upgrade.
    case struktur(GrammarFocus)
    /// Pushes an existing screen.
    case screen(BereichScreen)
    /// Presents an existing rule sheet.
    case sheet(BereichSheet)
    /// One exercise from the registry, shelved straight into a room: the row is built from
    /// `KasusDrillMeta` and pushes the exercise's setup screen.
    case drill(KasusDrillKind)

    var id: String {
        switch self {
        case .struktur(let focus): "struktur:\(focus.rawValue)"
        case .screen(let screen):  "screen:\(screen.rawValue)"
        case .sheet(let sheet):    "sheet:\(sheet.rawValue)"
        case .drill(let kind):     "drill:\(kind.rawValue)"
        }
    }
}

nonisolated enum BereichScreen: String, Hashable {
    /// `ArticleGameSetupView`: sources, options and the der/die/das round.
    case articleGame
}

nonisolated enum BereichSheet: String, Hashable, Identifiable {
    /// `ArticleRulesSheet`: the 18 gender patterns.
    case articleRules

    var id: String { rawValue }
}

nonisolated enum BereichLink: String, Hashable, Identifiable {
    /// The Dativ unit, where the Dativ-Verben drill lives (a drill, deliberately not a topic).
    case dativUnit
    /// The preposition hub opened on the Verb + Präposition track.
    case prepositionVerbTrack

    var id: String { rawValue }
}
