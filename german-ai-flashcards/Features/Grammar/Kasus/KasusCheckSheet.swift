//
//  KasusCheckSheet.swift
//  german-ai-flashcards
//
//  Der Kasus-Check · Which case? Six questions asked in order, the first one that fits decides.
//  It replaces the Wer/Wen/Wem question test, which breaks exactly where learners need it
//  (a preposition in front, gefallen, fragen), and every case explanation in the app follows the
//  same order, so the reason a round gives is always one of these six steps.
//
//  Reached from the Grammar hub's toolbar and each unit's Regel card.
//

import SwiftUI

struct KasusCheckSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id: Int
        let question: String
        /// What the step decides. Step one lists several, since the preposition picks.
        let answers: [(kasus: GrammarCase, example: String?)]
        let lines: [String]
        /// The trap for this step, set apart so it reads as a warning, not a rule.
        var note: String? = nil
    }

    private let steps: [Step] = [
        Step(
            id: 1,
            question: "Is there a preposition in front?",
            answers: [
                (.akkusativ, "für den Hund"),
                (.dativ, "mit dem Hund"),
                (.genitiv, "wegen des Hundes"),
            ],
            lines: [
                "Then the preposition decides.",
                "Two-way prepositions (in, an, auf…) take the Dativ for a place (Wo?) and the Akkusativ for a direction (Wohin?).",
                "In time phrases an, in, vor and zwischen take the Dativ: „am Montag“, „vor dem Termin“.",
                "A verb with its own preposition fixes the case: „warten auf“ + Akkusativ.",
            ]
        ),
        Step(
            id: 2,
            question: "Does it hang on another noun?",
            answers: [(.genitiv, nil)],
            lines: ["Whose or of what: „der Name des Hundes“, „das Ende der Woche“."]
        ),
        Step(
            id: 3,
            question: "Is it the subject?",
            answers: [(.nominativ, nil)],
            lines: ["The verb agrees with it, and each clause has one: „Der Hund spielt.“"],
            note: "With gefallen, gehören and schmecken, the thing is the subject and the person is Dativ: „Der Ball gefällt dem Hund.“"
        ),
        Step(
            id: 4,
            question: "Does sein, werden, bleiben or heißen equate it with the subject?",
            answers: [(.nominativ, nil)],
            lines: ["The noun on the other side of the verb is Nominativ too: „Das ist der Hund.“ „Er bleibt mein Freund.“"]
        ),
        Step(
            id: 5,
            question: "Is it the receiver, or does a Dativ verb govern it?",
            answers: [(.dativ, nil)],
            lines: [
                "To whom something is given, shown or told: „Er gibt dem Hund einen Keks.“",
                "helfen, danken, gefallen and gehören take the Dativ: „Jonas hilft seiner Mutter.“",
            ],
            note: "fragen, anrufen and besuchen can feel like they need a receiver, but they take the Akkusativ: „Ich frage den Lehrer.“"
        ),
        Step(
            id: 6,
            question: "None of the above?",
            answers: [(.akkusativ, nil)],
            lines: ["Then it is the direct object: „Er nimmt den Schlüssel.“"]
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ask these in order. The first question that fits decides the case, so a preposition always wins over everything below it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .themedListRow()

                Section {
                    ForEach(steps) { step in
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
                Text(step.question)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(step.answers, id: \.kasus) { answer in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("→")
                            .foregroundStyle(.secondary)
                        CaseLabel(kasus: answer.kasus, style: .name)
                            .fontWeight(.semibold)
                        if let example = answer.example {
                            Text("„\(example)“")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }

                ForEach(step.lines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note = step.note {
                    Label(note, systemImage: "exclamationmark.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
