//
//  KasusUnit.swift
//  german-ai-flashcards
//
//  The Grammatik path, one unit per case: Nominativ → Akkusativ → Dativ → Genitiv → Alle Fälle.
//  Every unit runs the same loop (Regel → Geschichte → Schnellrunde), so a unit only has to say
//  which cases are in play, which ones Markieren asks and in what order, its soft level label and
//  the few rule lines its Regel card opens with.
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

    /// The cases Markieren asks, one round each, in this order: the unit's own case first, then
    /// the ones before it, newest first („Nächster Fall · Next case“). Akkusativ adds Nominativ,
    /// Dativ adds Akkusativ and Nominativ, Genitiv the other three; Alle Fälle runs the table
    /// order. A case the story has no words of is skipped (`KasusMarking.cases(for:in:)`).
    var markCases: [GrammarCase] {
        switch self {
        case .nominativ:  [.nominativ]
        case .akkusativ:  [.akkusativ, .nominativ]
        case .dativ:      [.dativ, .akkusativ, .nominativ]
        case .genitiv:    [.genitiv, .dativ, .akkusativ, .nominativ]
        case .alleFaelle: GrammarCase.allCases
        }
    }

    /// The brushes the old brush-sorting Finden hands out, which Markieren replaces. Akkusativ
    /// marks only its own case, so the hunt is for the one form that changed; from Dativ on,
    /// every case in play gets a brush.
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

    /// The Regel card's opening lines, in the `KasusRich` markup (bold key terms, italic German,
    /// forms in their gender color, case words in their case color). Short, and in Kasus-Check
    /// order: preposition first, then the noun it hangs on, the subject, sein, the receiver, and
    /// Akkusativ for the rest.
    var ruleLines: [String] {
        switch self {
        case .nominativ:
            [
                "The {nom:Nominativ} names the **subject**: whoever or whatever does the verb. „{m:Der} *Hund schläft.*“",
                "The verb agrees with the subject, and each clause has one: „{pl:Die} *Kinder spielen.*“",
                "It is the **dictionary form**, so {m:der}, {f:die}, {n:das} and {m:ein}, {f:eine}, {n:ein} stay as you learned them.",
                "After *sein, werden, bleiben* and *heißen*, the other noun is {nom:Nominativ} too: „*Das ist* {m:der} *Hund.*“",
            ]
        case .akkusativ:
            [
                "The {akk:Akkusativ} marks the **direct object**: what the verb acts on. „*Ich sehe* {m:den} *Hund.*“",
                "Only the **masculine** changes: {m:der} → {m:den}, {m:ein} → {m:einen}. {f:Die}, {n:das} and the plural {pl:die} stay as they are.",
                "*durch, für, gegen, ohne* and *um* always take the {akk:Akkusativ}: „*für* {m:den} *Hund*“.",
                "*fragen, anrufen* and *besuchen* can feel like they need a receiver, but they take the {akk:Akkusativ}: „*Ich frage* {m:den} *Lehrer.*“",
            ]
        case .dativ:
            [
                "The {dat:Dativ} marks the **receiver**: to whom something is given, shown or told. „*Er gibt* {m:dem} *Hund* {m:einen} *Keks.*“",
                "Some verbs always take it: *helfen, danken, gefallen, gehören, schmecken*. „*Ich helfe* {f:der} *Frau.*“",
                "*aus, bei, mit, nach, seit, von* and *zu* always take the {dat:Dativ}: „*mit* {m:dem} *Hund*“.",
                "**Two-way** prepositions (*in, an, auf…*) take the {dat:Dativ} for a place, {wechsel:Wo?}: „{m:Der} *Hund liegt unter* {m:dem} *Tisch.*“",
                "{m:der} → {m:dem}, {f:die} → {f:der}, {n:das} → {n:dem}, and the plural takes {pl:den} with **-n** on the noun: „*mit* {pl:den} *Kinder*{pl:n}“.",
            ]
        case .genitiv:
            [
                "The {gen:Genitiv} says **whose** or **of what**: „*das Auto* {m:des} *Mannes*“, „*das Ende* {f:der} *Woche*“.",
                "**Masculine** and **neuter** take **des**, and the noun adds **-s** or **-es**: {m:des} *Vater*{m:s}, {n:des} *Kind*{n:es}.",
                "**Feminine** and **plural** take **der**, and the noun stays as it is: {f:der} *Frau*, {pl:der} *Kinder*.",
                "*wegen, trotz* and *während* take the {gen:Genitiv} in writing: „*wegen* {n:des} *Wetters*“. In speech you will often hear the {dat:Dativ} instead.",
            ]
        case .alleFaelle:
            [
                "Run the **Kasus-Check** from the top; the first question that fits decides the case.",
                "A **preposition** in front decides first: *für* → {akk:Akkusativ}, *mit* → {dat:Dativ}, *wegen* → {gen:Genitiv}.",
                "Hanging on **another noun** („*der Name* ___“) → {gen:Genitiv}. The **subject**, or what *sein* equates it with → {nom:Nominativ}.",
                "The **receiver**, or the object of a **Dativ verb** like *helfen* → {dat:Dativ}. Anything else → {akk:Akkusativ}.",
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
