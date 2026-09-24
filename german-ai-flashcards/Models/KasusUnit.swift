//
//  KasusUnit.swift
//  german-ai-flashcards
//
//  The Grammatik path, one unit per case: Nominativ → Akkusativ → Dativ → Genitiv → Alle Fälle.
//  Every unit runs the same loop (Regel → Geschichte → Schnellrunde), so a unit only has to say
//  which cases are in play, which ones the Finden exercise hands out brushes for, its soft level
//  label and the few rule lines its Regel card opens with.
//
//  Earlier cases stay in play as the path goes on, so no round past Nominativ is single-case: a
//  round of nothing but Dativ has the same answer every time. The level labels are a guide,
//  never a gate; nothing here locks a unit.
//

import SwiftUI

enum KasusUnit: String, CaseIterable, Identifiable {
    case nominativ, akkusativ, dativ, genitiv, alleFaelle

    var id: String { rawValue }

    /// The unit's own case. Alle Fälle has none: it is the whole decision order at once.
    var focusCase: GrammarCase? {
        switch self {
        case .nominativ:  .nominativ
        case .akkusativ:  .akkusativ
        case .dativ:      .dativ
        case .genitiv:    .genitiv
        case .alleFaelle: nil
        }
    }

    var germanTitle: String {
        switch self {
        case .nominativ:  "Nominativ"
        case .akkusativ:  "Akkusativ"
        case .dativ:      "Dativ"
        case .genitiv:    "Genitiv"
        case .alleFaelle: "Alle Fälle"
        }
    }

    var englishRole: String {
        switch self {
        case .nominativ:  "The subject"
        case .akkusativ:  "The direct object"
        case .dativ:      "The receiver (to whom)"
        case .genitiv:    "Whose / of what"
        case .alleFaelle: "All four together"
        }
    }

    /// One noun through the unit's case, for the hub row. Alle Fälle has no single form to show.
    var exampleForms: String? {
        switch self {
        case .nominativ:  "der Hund · ein Hund"
        case .akkusativ:  "den Hund · einen Hund"
        case .dativ:      "dem Hund · einem Hund"
        case .genitiv:    "des Hundes · eines Hundes"
        case .alleFaelle: nil
        }
    }

    /// Where textbooks (Menschen, Netzwerk) teach it. A label, never a gate.
    var levelLabel: String {
        switch self {
        case .nominativ:  "A1"
        case .akkusativ:  "A1"
        case .dativ:      "A1–A2"
        case .genitiv:    "B1"
        case .alleFaelle: "B1"
        }
    }

    /// Every case the unit's exercises can ask about, in table order. Earlier cases stay in, so
    /// the new one is always told apart from what came before.
    var casesInPlay: [GrammarCase] {
        switch self {
        case .nominativ:              [.nominativ]
        case .akkusativ:              [.nominativ, .akkusativ]
        case .dativ:                  [.nominativ, .akkusativ, .dativ]
        case .genitiv, .alleFaelle:   GrammarCase.allCases
        }
    }

    /// The brushes Finden hands out. Akkusativ marks only its own case, so the hunt is for the
    /// one form that changed; from Dativ on, every case in play gets a brush.
    var findenBrushes: [GrammarCase] {
        switch self {
        case .nominativ:              [.nominativ]
        case .akkusativ:              [.akkusativ]
        case .dativ:                  [.nominativ, .akkusativ, .dativ]
        case .genitiv, .alleFaelle:   GrammarCase.allCases
        }
    }

    /// The coach's skill this unit reads and moves. Nominativ and Alle Fälle have none, and no
    /// new `GrammarFocus` is added for them.
    var focus: GrammarFocus? {
        switch self {
        case .akkusativ: .akkusativ
        case .dativ:     .dativ
        case .genitiv:   .genitiv
        case .nominativ, .alleFaelle: nil
        }
    }

    var symbol: String { focusCase?.symbol ?? "square.grid.2x2" }

    /// The case color, or neutral for Alle Fälle: graphite already means Nominativ.
    var color: Color { focusCase?.color ?? .secondary }

    /// The Regel card's opening lines. Short, and in Kasus-Check order: preposition first, then
    /// the noun it hangs on, the subject, sein, the receiver, and Akkusativ for the rest.
    var ruleLines: [String] {
        switch self {
        case .nominativ:
            [
                "The Nominativ names the subject: whoever or whatever does the verb. „Der Hund schläft.“",
                "The verb agrees with the subject, and each clause has one: „Die Kinder spielen.“",
                "It is the dictionary form, so der, die, das and ein, eine stay as you learned them.",
                "After sein, werden, bleiben and heißen, the other noun is Nominativ too: „Das ist der Hund.“",
            ]
        case .akkusativ:
            [
                "The Akkusativ marks the direct object: what the verb acts on. „Ich sehe den Hund.“",
                "Only the masculine changes: der → den, ein → einen. Die, das and the plural stay as they are.",
                "durch, für, gegen, ohne and um always take the Akkusativ: „für den Hund“.",
                "fragen, anrufen and besuchen can feel like they need a receiver, but they take the Akkusativ: „Ich frage den Lehrer.“",
            ]
        case .dativ:
            [
                "The Dativ marks the receiver: to whom something is given, shown or told. „Er gibt dem Hund einen Keks.“",
                "Some verbs always take it: helfen, danken, gefallen, gehören, schmecken. „Ich helfe der Frau.“",
                "aus, bei, mit, nach, seit, von and zu always take the Dativ: „mit dem Hund“.",
                "Two-way prepositions (in, an, auf…) take the Dativ for a place, Wo?: „Der Hund liegt unter dem Tisch.“",
                "der → dem, die → der, das → dem, and the plural takes den with -n on the noun: „mit den Kindern“.",
            ]
        case .genitiv:
            [
                "The Genitiv says whose or of what: „das Auto des Mannes“, „das Ende der Woche“.",
                "Masculine and neuter take des, and the noun adds -s or -es: des Hundes, des Kindes.",
                "Feminine and plural take der, and the noun stays as it is: der Frau, der Kinder.",
                "wegen, trotz and während take the Genitiv in writing: „wegen des Wetters“. In speech you will often hear the Dativ instead.",
            ]
        case .alleFaelle:
            [
                "Run the Kasus-Check from the top; the first question that fits decides the case.",
                "A preposition in front decides first: für → Akkusativ, mit → Dativ, wegen → Genitiv.",
                "Hanging on another noun („der Name ___“) → Genitiv. The subject, or what sein equates it with → Nominativ.",
                "The receiver, or the object of a Dativ verb like helfen → Dativ. Anything else → Akkusativ.",
            ]
        }
    }

    /// Where a learner's declared or placed level starts them. Read only; the path never writes
    /// the level back.
    static func start(for level: CEFRLevel) -> KasusUnit {
        switch level {
        case .a1:             .nominativ
        case .a2:             .akkusativ
        case .b1, .b2, .c1:   .dativ
        }
    }
}
