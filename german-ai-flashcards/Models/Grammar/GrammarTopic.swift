//
//  GrammarTopic.swift
//  german-ai-flashcards
//
//  A teachable area of Grammatik with a lesson, exercises, a coach focus and a hub row: the five
//  units of the case path, and the topics that aren't a case (Reflexivverben). A topic's `key` is
//  what `KasusRound.unitRaw` stores, so the five units keep their raw values and nothing recorded
//  changes; a topic that isn't a unit files under its own key and stays out of every unit screen.
//
//  Imports SwiftUI for `Color`, so this file stays out of training/kasus_cli; the CLI and the
//  recording rail key on the String topic key instead.
//

import SwiftUI

nonisolated enum GrammarTopic: Hashable, Identifiable {
    /// One of the five units of the case path.
    case kasus(KasusUnit)
    /// Reflexivverben: mich or mir, sich or dich. Not a case: its drills span Akkusativ and Dativ.
    case reflexiv

    static let allCases: [GrammarTopic] = KasusUnit.allCases.map(GrammarTopic.kasus) + [.reflexiv]

    static let reflexivKey = "reflexiv"

    /// What `KasusRound.unitRaw` stores: the unit's raw value, or the topic's own key.
    var key: String {
        switch self {
        case .kasus(let unit): unit.rawValue
        case .reflexiv:        Self.reflexivKey
        }
    }

    /// Case-insensitive, like the debug arguments' `unitNamed`.
    init?(key: String) {
        let lowered = key.lowercased()
        if let unit = KasusUnit.allCases.first(where: { $0.rawValue.lowercased() == lowered }) {
            self = .kasus(unit)
        } else if lowered == Self.reflexivKey {
            self = .reflexiv
        } else {
            return nil
        }
    }

    var id: String { key }

    /// The unit, for the case path's own screens; nil for a topic that isn't a case.
    var unit: KasusUnit? {
        switch self {
        case .kasus(let unit): unit
        case .reflexiv:        nil
        }
    }

    var germanTitle: String {
        switch self {
        case .kasus(let unit): unit.germanTitle
        case .reflexiv:        "Reflexive Verben"
        }
    }

    var englishRole: String {
        switch self {
        case .kasus(let unit): unit.englishRole
        case .reflexiv:        "sich: myself, yourself, each other"
        }
    }

    var symbol: String {
        switch self {
        case .kasus(let unit): unit.symbol
        case .reflexiv:        "arrow.uturn.backward.circle.fill"
        }
    }

    /// A topic that spans several cases never wears one case's colour.
    var color: Color {
        switch self {
        case .kasus(let unit): unit.color
        case .reflexiv:        .secondary
        }
    }

    /// Where textbooks teach it. A label, never a gate.
    var levelLabel: String {
        switch self {
        case .kasus(let unit): unit.levelLabel
        case .reflexiv:        "A2"
        }
    }

    /// The hub-row caption under the title. Display only, so a new topic brings its own line
    /// instead of a screen hard-coding one.
    var rowSubtitle: String? {
        switch self {
        case .kasus(let unit): unit.exampleForms
        case .reflexiv:        "mich / mir · dich / dir · sich"
        }
    }

    /// Every case the topic's exercises can ask about, in table order.
    var casesInPlay: [GrammarCase] {
        switch self {
        case .kasus(let unit): unit.casesInPlay
        case .reflexiv:        [.akkusativ, .dativ]
        }
    }

    /// The case a round leans on; nil spreads a round evenly.
    var emphasis: GrammarCase? {
        switch self {
        case .kasus(let unit): unit.focusCase
        case .reflexiv:        nil
        }
    }

    /// The coach's skill the topic reads and moves. A topic that isn't a case pools every
    /// counting answer into its one focus (`KasusService.skillMoves`).
    var focus: GrammarFocus? {
        switch self {
        case .kasus(let unit): unit.focus
        case .reflexiv:        .reflexivverben
        }
    }

    /// The Regel card's lines, in the `KasusRich` markup.
    var ruleLines: [String] {
        switch self {
        case .kasus(let unit): unit.ruleLines
        case .reflexiv:        ReflexivLesson.ruleLines
        }
    }

    /// The lesson's paged cards (`KasusLessonView`).
    @MainActor
    var lessonCards: [KasusLessonCard] {
        switch self {
        case .kasus(let unit): KasusLesson.cards(for: unit)
        case .reflexiv:        ReflexivLesson.cards
        }
    }

    /// The memory aids the lesson's last card and the Merkhilfen list draw on.
    @MainActor
    var mnemonics: [KasusMnemonic] {
        switch self {
        case .kasus(let unit): KasusMnemonics.forUnit(unit)
        case .reflexiv:        [ReflexivLesson.mnemonic]
        }
    }

    /// The drill the lesson's „Üben“ launches.
    var lessonPractice: KasusDrillKind? {
        switch self {
        case .kasus:    .roles
        case .reflexiv: .reflexCase
        }
    }

    /// The label of the lesson's last button: „Üben · Practice: Rollen“.
    var practiceLabel: String {
        "Üben · Practice: \(lessonPractice?.meta.germanTitle ?? "")"
    }

    /// The exercise kinds the topic offers, in screen order: the Verstehen drills its items can
    /// fill, then the practice rounds. Reads the banks it is handed.
    @MainActor
    func exercises(concepts: KasusConceptBank, gaps: GapChoiceBank) -> [KasusDrillKind] {
        switch self {
        case .kasus(let unit):
            var kinds = concepts.offered(for: unit).map(\.kind)
            // Verstehen: the Pronomen-Brücke once the Akkusativ is in play (English shows no case
            // on a subject alone).
            if unit.casesInPlay.contains(.akkusativ) { kinds.append(.bridge) }
            // Üben: the Schnellrunde and Bau das Wort always; the Dativ verbs once the Dativ is
            // in play; Finde den Fehler where two cases can be confused and the Rollen items are
            // there to plant in; the Blitzrunde for every unit.
            kinds += [.quick, .build]
            if unit.casesInPlay.contains(.dativ) { kinds.append(.dativVerbs) }
            if unit.casesInPlay.count >= 2, concepts.items(for: unit, exercise: .roles).count >= 10 { kinds.append(.fehler) }
            kinds.append(.blitz)
            return kinds
        case .reflexiv:
            return gaps.offered(topic: key).compactMap(\.kind)
        }
    }

    /// The exercises on the bundled banks.
    @MainActor
    func exercises() -> [KasusDrillKind] { exercises(concepts: .bundled, gaps: .bundled) }

    /// What the question-mark menu may pin over a drill of this topic: the article table for a
    /// case, the pronoun table for the reflexive topic.
    var reference: KasusReferenceContent {
        switch self {
        case .kasus:    .articles(GrammarCase.allCases)
        case .reflexiv: .reflexivePronouns
        }
    }

    /// Something to show: a lesson or an exercise. Since the rooms reorg nothing gates a hub row
    /// on this (a topic's `.struktur` row upgrades the moment its enum case exists), so shipping
    /// the case IS the ship act: land the lesson and the bundled items in the same change.
    @MainActor
    var isAvailable: Bool { !lessonCards.isEmpty || !exercises().isEmpty }
}
