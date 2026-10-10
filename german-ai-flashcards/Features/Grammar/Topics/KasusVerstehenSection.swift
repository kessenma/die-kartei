//
//  KasusVerstehenSection.swift
//  german-ai-flashcards
//
//  Verstehen · Understand: the unit screen's section between Die Regel and Geschichten, one row
//  per piece: Lektion (a sheet), then the exercises the unit offers (Rollen, Wer macht was?, Die
//  Probe), each with ✓ once played. Rows that start a round end in a play glyph, like the
//  Schnellrunde's.
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

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Section {
            row(symbol: "lightbulb.fill", title: "Lektion · The idea",
                caption: "What this case is, in English and German · about 2 min",
                done: progress.lessonRead(unit), isLesson: true, action: onLesson)
            NavigationLink {
                KasusExplainerLibraryView(unit: unit)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Warum dieser Fall? · Why this case?").font(.subheadline.weight(.medium))
                        Text("Worked contrasts, common traps, and the reason behind the form")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "text.magnifyingglass").foregroundStyle(unit.color)
                }
                .padding(.vertical, 4)
            }
            ForEach(offered) { exercise in
                row(symbol: exercise.symbol, title: "\(exercise.germanTitle) · \(exercise.englishTitle)",
                    caption: "\(exercise.blurb) · about \(exercise.minutes) min",
                    done: progress.conceptDone(unit, exercise), isLesson: false) {
                    onExercise(exercise)
                }
            }
            ForEach(extra) { kind in
                row(symbol: kind.meta.symbol, title: "\(kind.meta.germanTitle) · \(kind.meta.englishTitle)",
                    caption: "\(kind.meta.blurb) · about \(kind.meta.minutes) min",
                    done: progress.drillDone(kind.step, topicKey: unit.rawValue), isLesson: false) {
                    onDrill(kind)
                }
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

    private func row(symbol: String, title: String, caption: String, done: Bool, isLesson: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(unit.color)
                    .frame(width: 34, height: 34)
                    .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        Text(caption)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isLesson ? "book.pages" : "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(done ? "Done" : "Not yet")")
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
