//
//  KasusHelp.swift
//  german-ai-flashcards
//
//  How much help an „Englisch & Fälle“ round shows. One dial, three presets, and **the same five
//  options at every setting**: what changes is how many crutches are on screen, never how many
//  answers are plausible, so a first-try share still means the same thing from one round to the
//  next — and the coach reads exactly that number.
//
//    Leicht   German line, every asked phrase ringed, case names and glosses on the buttons,
//             only the unit's cases, every phrase in the sentence asked
//    Normal   German line and rings, case names; no glosses, all five buttons
//    Frei     German only, one ring, bare questions, one phrase per sentence
//
//  The preset is also the **stage ramp**: rather than asking the same span in English and again in
//  German, Leicht pins every item to Beide, Normal walks Englisch → Beide → Deutsch across the
//  round, and Frei pins Deutsch. One ask per item.
//
//  Seeded from the declared `germanLevel` and never written back, the contract `MLXModelManager`
//  already states for every level picker in the app: nothing is stored until the learner touches
//  the dial, and then it stops following their level.
//
//  Foundation only: the drill reads it through `DrillVariant`, the setup screen through
//  `@AppStorage`.
//

import Foundation

nonisolated enum KasusHelp: String, CaseIterable, Identifiable, Hashable {
    case leicht, normal, frei

    var id: String { rawValue }

    /// `UserDefaults` key. Absent means „automatisch“: derived from the declared level.
    static let storageKey = "kasus.hilfe"
    /// The level the preset is derived from, which `MLXModelManager.germanLevelRaw` mirrors.
    static let levelKey = "german.level"

    var germanLabel: String {
        switch self {
        case .leicht: "Leicht"
        case .normal: "Normal"
        case .frei:   "Frei"
        }
    }

    var englishLabel: String {
        switch self {
        case .leicht: "Most help"
        case .normal: "Some help"
        case .frei:   "No help"
        }
    }

    /// The line under the segmented control: what this setting actually does, in one sentence.
    var blurb: String {
        switch self {
        case .leicht:
            "German under the English, every asked phrase ringed, the case over each question, and only this unit's cases."
        case .normal:
            "German under the English, phrases ringed, case names on the buttons. No English glosses, all five questions."
        case .frei:
            "German only, one phrase per sentence, bare questions. Nothing on screen but the sentence."
        }
    }

    // MARK: The switches

    /// The German twin under the English line.
    var showsGerman: Bool { self != .frei }
    /// Ring every phrase the round will ask in this sentence, not just the one in hand.
    var ringsEveryPhrase: Bool { self != .frei }
    /// The case name above each question on its button.
    var showsCaseName: Bool { self != .frei }
    /// „who or what“ under the German question.
    var showsEnglishGloss: Bool { self == .leicht }
    /// Four buttons cut to the unit's cases in play. Never cut per sentence: two thirds of the
    /// items hold exactly two cases, so that would be a coin flip.
    var limitsToUnitCases: Bool { self == .leicht }
    /// Ask every asked phrase of a sentence, not one. At Leicht the answers already in make the
    /// last phrase inferable, which is the scaffold; at Frei nothing is answerable by elimination.
    var asksWholeSentence: Bool { self != .frei }
    /// Leicht and Frei pin one stage; Normal walks the round.
    var pinnedStage: EnglishStage? {
        switch self {
        case .leicht: .beide
        case .normal: nil
        case .frei:   .deutsch
        }
    }
    /// An eased round says so in Verlauf and stays out of the coach's maths, the way a round that
    /// showed its answers already does.
    var marksTheRound: Bool { self == .leicht }

    // MARK: Seeding

    /// What a declared level suggests. A first guess, not a finding: CEFR says what a learner can
    /// say, not whether anyone ever taught them what a direct object is.
    static func seeded(level: CEFRLevel) -> KasusHelp {
        switch level {
        case .a1, .a2: .leicht
        case .b1:      .normal
        case .b2, .c1: .frei
        }
    }

    /// The preset in force: the learner's own choice, else their level's. `stored` empty means
    /// „automatisch“.
    static func resolve(stored raw: String?, level: CEFRLevel) -> KasusHelp {
        guard let raw, let pinned = KasusHelp(rawValue: raw) else { return seeded(level: level) }
        return pinned
    }

    /// True while nothing is stored, so the setup screen can say „Dein Level hat das gewählt“.
    static func isAutomatic(stored raw: String?) -> Bool {
        guard let raw, KasusHelp(rawValue: raw) != nil else { return true }
        return false
    }
}

// MARK: - Stage

/// Which language the sentence is in when the question is asked. The reveal always shows both.
nonisolated enum EnglishStage: String, CaseIterable, Identifiable, Hashable {
    /// The English line alone: build the handle.
    case englisch
    /// English over German, spans aligned: the two lines are the lesson.
    case beide
    /// German alone: the handle is gone.
    case deutsch

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .englisch: "Englisch"
        case .beide:    "Beide"
        case .deutsch:  "Deutsch"
        }
    }

    /// Whether the German line is on screen while the question is being asked.
    var showsGerman: Bool { self != .englisch }
    /// Whether the English line is on screen while the question is being asked.
    var showsEnglish: Bool { self != .deutsch }
}
