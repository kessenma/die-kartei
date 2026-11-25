//
//  KasusVerstehenSection.swift
//  german-ai-flashcards
//
//  Verstehen · Understand: the unit screen's section between Die Regel and Geschichten, one row
//  per piece: Lektion (a sheet), then the exercises the unit offers (Rollen, Wer macht was?, Die
//  Probe), each with ✓ once played. Rows that start a round end in a play glyph, like the
//  Schnellrunde's.
//
//  Every row here is a task, so each wears its task drawing (`GrammarTaskArt`, through
//  `GrammarTaskRow`) rather than a symbol chip — including the Lektion, whose title, blurb and
//  minutes all come from the registry instead of being spelled out here. „Warum dieser Fall?“ is
//  reading, not a task, so it keeps a chip (`GrammarShelfRow`).
//

import SwiftUI

struct KasusVerstehenSection: View {
    let unit: KasusUnit
    let progress: KasusProgress
    let offered: [KasusConceptExercise]
    /// Drills the registry files under Verstehen beyond the concept bank's (the Pronomen-Brücke).
    var extra: [KasusDrillKind] = []
    let onLesson: () -> Void
    let onExercise: (KasusConceptExercise) -> Void
    var onDrill: (KasusDrillKind) -> Void = { _ in }

    /// The Lektion's row, read off the registry like every other row in the section.
    private var lesson: KasusDrillMeta { KasusRoundStep.lesson.meta }

    var body: some View {
        Section {
            Button(action: onLesson) {
                GrammarTaskRow(icon: .art(lesson.art),
                               title: "\(lesson.germanTitle) · \(lesson.englishTitle)",
                               subtitle: "\(lesson.blurb) · about \(lesson.minutes) min",
                               done: progress.lessonRead(unit), tail: .read, tint: unit.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(lesson.germanTitle). \(progress.lessonRead(unit) ? "Done" : "Not yet")")
            NavigationLink {
                KasusExplainerLibraryView(unit: unit)
            } label: {
                GrammarShelfRow(title: "Warum dieser Fall? · Why this case?",
                                subtitle: "Worked contrasts, common traps, and the reason behind the form") {
                    GrammarRowChip(symbol: "text.magnifyingglass", tint: unit.color)
                }
            }
            ForEach(offered) { exercise in
                Button { onExercise(exercise) } label: {
                    GrammarTaskRow(icon: .art(exercise.art),
                                   title: "\(exercise.germanTitle) · \(exercise.englishTitle)",
                                   subtitle: "\(exercise.blurb) · about \(exercise.minutes) min",
                                   done: progress.conceptDone(unit, exercise), tint: unit.color)
                }
                .buttonStyle(.plain)
            }
            ForEach(extra) { kind in
                Button { onDrill(kind) } label: {
                    GrammarTaskRow(icon: .art(kind.meta.art),
                                   title: "\(kind.meta.germanTitle) · \(kind.meta.englishTitle)",
                                   subtitle: "\(kind.meta.blurb) · about \(kind.meta.minutes) min",
                                   done: progress.drillDone(kind.step, topicKey: unit.rawValue),
                                   tint: unit.color)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Verstehen · Understand")
                .themedSectionHeader()
        } footer: {
            Text(unit == .nominativ
                 ? "The idea first, then name each phrase's job. The other drills start with the Akkusativ."
                 : "The idea first, then the roles, then reading who does what by the ending alone. Nothing here moves the coach except Die Probe.")
        }
    }
}

#Preview("Verstehen · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                List {
                    KasusVerstehenSection(unit: .dativ, progress: KasusProgress(rounds: []),
                                          offered: KasusConceptExercise.allCases,
                                          onLesson: {}, onExercise: { _ in })
                        .themedListRow()
                }
                .themedListScreen()
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}
