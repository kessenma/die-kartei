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

    /// The coach's skill the topic reads and moves. The reflexive topic gets its own focus with
    /// its first drills.
    var focus: GrammarFocus? {
        switch self {
        case .kasus(let unit): unit.focus
        case .reflexiv:        nil
        }
    }

    /// The Regel card's lines, in the `KasusRich` markup.
    var ruleLines: [String] {
        switch self {
        case .kasus(let unit): unit.ruleLines
        case .reflexiv:        []
        }
    }

    /// The lesson's paged cards (`KasusLessonView`).
    @MainActor
    var lessonCards: [KasusLessonCard] {
        switch self {
        case .kasus(let unit): KasusLesson.cards(for: unit)
        case .reflexiv:        []
        }
    }

    /// The memory aids the lesson's last card and the Merkhilfen list draw on.
    @MainActor
    var mnemonics: [KasusMnemonic] {
        switch self {
        case .kasus(let unit): KasusMnemonics.forUnit(unit)
        case .reflexiv:        []
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
    /// fill, then the practice rounds. Reads the bundled banks.
    @MainActor
    func exercises(concepts: KasusConceptBank) -> [KasusDrillKind] {
        switch self {
        case .kasus(let unit):
            concepts.offered(for: unit).map(\.kind) + [.quick, .build]
        case .reflexiv:
            []
        }
    }

    /// The exercises on the bundled banks.
    @MainActor
    func exercises() -> [KasusDrillKind] { exercises(concepts: .bundled) }

    /// Something to show: a lesson or an exercise. A topic whose content isn't bundled yet stays
    /// off the hub.
    @MainActor
    var isAvailable: Bool { !lessonCards.isEmpty || !exercises().isEmpty }
}
