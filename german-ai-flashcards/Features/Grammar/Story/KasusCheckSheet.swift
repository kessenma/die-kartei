//
//  KasusCheckSheet.swift
//  german-ai-flashcards
//
//  Der Kasus-Check · Which case? Six questions asked in order, the first one that fits decides.
//  It replaces the Wer/Wen/Wem question test, which breaks exactly where learners need it
//  (a preposition in front, gefallen, fragen), and every case explanation in the app follows the
//  same order, so the reason a round gives is always one of these six steps.
//
//  Reached from the Grammar hub's toolbar, the story player, each unit's Regel card and the
//  endings table, which lists the steps' short forms (`KasusCheckSheet.steps`) from here. Every
//  line is `KasusRich` markup: forms in their gender color, case words in their case color.
//

import SwiftUI

struct KasusCheckSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct Step: Identifiable {
        let id: Int
        let question: String
        /// The question in a few words, for the endings table's summary.
        let short: String
        /// What the step decides. Step one lists several, since the preposition picks.
        let answers: [(kasus: GrammarCase, example: String?)]
        let lines: [String]
        /// The trap for this step, set apart so it reads as a warning, not a rule.
        var note: String? = nil
    }

    static let steps: [Step] = [
        Step(
            id: 1,
            question: "Is there a **preposition** in front?",
            short: "A **preposition** in front? It decides.",
            answers: [
                (.akkusativ, "für {m:den} Hund"),
                (.dativ, "mit {m:dem} Hund"),
                (.genitiv, "wegen {m:des} Hundes"),
            ],
            lines: [
                "Then the preposition decides.",
                "**Two-way** prepositions (*in, an, auf…*) take the {dat:Dativ} for a place ({wechsel:Wo?}) and the {akk:Akkusativ} for a direction ({wechsel:Wohin?}).",
                "In time phrases *an, in, vor* and *zwischen* take the {dat:Dativ}: „*am Montag*“, „*vor* {m:dem} *Termin*“.",
                "A verb with its own preposition fixes the case: „*warten auf*“ + {akk:Akkusativ}.",
            ]
        ),
        Step(
            id: 2,
            question: "Does it hang on **another noun**?",
            short: "Hangs on **another noun**?",
            answers: [(.genitiv, nil)],
            lines: ["Whose or of what: „*der Name* {m:des} *Hundes*“, „*das Ende* {f:der} *Woche*“."]
        ),
        Step(
            id: 3,
            question: "Is it the **subject**?",
            short: "The **subject**?",
            answers: [(.nominativ, nil)],
            lines: ["The verb agrees with it, and each clause has one: „{m:Der} *Hund spielt.*“"],
            note: "With *gefallen, gehören* and *schmecken*, the thing is the subject and the person is {dat:Dativ}: „{m:Der} *Ball gefällt* {m:dem} *Hund.*“"
        ),
        Step(
            id: 4,
            question: "Does *sein, werden, bleiben* or *heißen* equate it with the subject?",
            short: "Equal to the subject after *sein*?",
            answers: [(.nominativ, nil)],
            lines: ["The noun on the other side of the verb is {nom:Nominativ} too: „*Das ist* {m:der} *Hund.*“ „*Er bleibt* {m:mein} *Freund.*“"]
        ),
        Step(
            id: 5,
            question: "Is it the **receiver**, or does a **Dativ verb** govern it?",
            short: "The **receiver**, or a **Dativ verb**?",
            answers: [(.dativ, nil)],
            lines: [
                "To whom something is given, shown or told: „*Er gibt* {m:dem} *Hund* {m:einen} *Keks.*“",
                "*helfen, danken, gefallen* and *gehören* take the {dat:Dativ}: „*Jonas hilft* {f:seiner} *Mutter.*“",
            ],
            note: "*fragen, anrufen* and *besuchen* can feel like they need a receiver, but they take the {akk:Akkusativ}: „*Ich frage* {m:den} *Lehrer.*“"
        ),
        Step(
            id: 6,
            question: "**None** of the above?",
            short: "**None** of these?",
            answers: [(.akkusativ, nil)],
            lines: ["Then it is the **direct object**: „*Er nimmt* {m:den} *Schlüssel.*“"]
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(kasusRich: "Ask these **in order**. The first question that fits decides the case, so a preposition always wins over everything below it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .themedListRow()

                Section {
                    ForEach(Self.steps) { step in
                        stepRow(step)
                    }
                } footer: {
                    Text("Every explanation in the app follows this order.")
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Der Kasus-Check")
                            .font(.headline)
                        Text("Which case?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepRow(_ step: Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(step.id)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                // Plain weight, so the bold key term stands out.
                Text(kasusRich: step.question)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(step.answers, id: \.kasus) { answer in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("→")
                            .foregroundStyle(.secondary)
                        // Not `CaseLabel`: inside a List a Label takes the row's wide icon slot.
                        HStack(spacing: 3) {
                            Image(systemName: answer.kasus.symbol)
                            Text(answer.kasus.name)
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(answer.kasus.color)
                        if let example = answer.example {
                            Text(kasusRich: "„\(example)“")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }

                ForEach(step.lines, id: \.self) { line in
                    Text(kasusRich: line)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note = step.note {
                    Label {
                        Text(kasusRich: note)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.bubble")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Kasus-Check · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            KasusCheckSheet()
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}
