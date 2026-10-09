//
//  GrammarTopic.swift
//  german-ai-flashcards
//
//  A teachable area of Grammatik with a lesson, exercises, a coach focus and a hub row: the five
//  units of the case path today, and the topics that aren't a case (Reflexivverben next). A
//  topic's `key` is what `KasusRound.unitRaw` stores, so the five units keep their raw values and
//  nothing recorded changes; a topic that isn't a unit files under its own key and stays out of
//  every unit screen.
//
//  Imports SwiftUI for `Color`, so this file stays out of training/kasus_cli; the CLI and the
//  recording rail key on the String topic key instead.
//

import SwiftUI

nonisolated enum GrammarTopic: Hashable, Identifiable {
    /// One of the five units of the case path.
    case kasus(KasusUnit)

    static let allCases: [GrammarTopic] = KasusUnit.allCases.map(GrammarTopic.kasus)

    /// What `KasusRound.unitRaw` stores: the unit's raw value.
    var key: String {
        switch self {
        case .kasus(let unit): unit.rawValue
        }
    }

    /// Case-insensitive, like the debug arguments' `unitNamed`.
    init?(key: String) {
        let lowered = key.lowercased()
        if let unit = KasusUnit.allCases.first(where: { $0.rawValue.lowercased() == lowered }) {
            self = .kasus(unit)
            return
        }
        return nil
    }

    var id: String { key }

    /// The unit, for the case path's own screens; nil for a topic that isn't a case.
    var unit: KasusUnit? {
        switch self {
        case .kasus(let unit): unit
        }
    }

    var germanTitle: String {
        switch self {
        case .kasus(let unit): unit.germanTitle
        }
    }

    var englishRole: String {
        switch self {
        case .kasus(let unit): unit.englishRole
        }
    }

    var symbol: String {
        switch self {
        case .kasus(let unit): unit.symbol
        }
    }

    /// A topic that spans several cases never wears one case's colour.
    var color: Color {
        switch self {
        case .kasus(let unit): unit.color
        }
    }

    var levelLabel: String {
        switch self {
        case .kasus(let unit): unit.levelLabel
        }
    }

    /// Every case the topic's exercises can ask about, in table order.
    var casesInPlay: [GrammarCase] {
        switch self {
        case .kasus(let unit): unit.casesInPlay
        }
    }

    /// The case a round leans on; nil spreads a round evenly.
    var emphasis: GrammarCase? {
        switch self {
        case .kasus(let unit): unit.focusCase
        }
    }

    /// The coach's skill the topic reads and moves.
    var focus: GrammarFocus? {
        switch self {
        case .kasus(let unit): unit.focus
        }
    }

    /// The Regel card's lines, in the `KasusRich` markup.
    var ruleLines: [String] {
        switch self {
        case .kasus(let unit): unit.ruleLines
        }
    }

    /// The drill the lesson's „Üben“ launches.
    var lessonPractice: KasusDrillKind? {
        switch self {
        case .kasus: .roles
        }
    }

    /// The exercise kinds the topic offers, in screen order: the Verstehen drills its items can
    /// fill, then the practice rounds. Reads the bundled banks.
    @MainActor
    func exercises(concepts: KasusConceptBank) -> [KasusDrillKind] {
        switch self {
        case .kasus(let unit):
            concepts.offered(for: unit).map(\.kind) + [.quick, .build]
        }
    }

    /// The exercises on the bundled banks.
    @MainActor
    func exercises() -> [KasusDrillKind] { exercises(concepts: .bundled) }
}
