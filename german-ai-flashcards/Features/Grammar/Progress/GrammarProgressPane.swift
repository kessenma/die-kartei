//
//  GrammarProgressPane.swift
//  german-ai-flashcards
//
//  Grammatik ▸ Fortschritt: what the grammar rounds add up to. Four sections, all derived —
//  nothing here is stored.
//
//    Grammatik-Tage        13 weeks of grammar days, shaded by time (`GrammarDayStrip`)
//    Zeit pro Übung        one row per exercise: time, rounds, right first try
//    Pro Fall              rounds · answers · first-try share, one bar per case
//    Verlauf               the drill-down into the rounds themselves
//
//  A `Group` of `Section`s rather than its own `List`, so it drops into the hub's list the way
//  `StreakCalendarSection` drops into Home's. It owns its three `@Query`s on purpose: SwiftUI
//  doesn't build a child's queries until the child enters the tree, so the hub's Üben mode pays
//  nothing for them.
//
//  The numbers come from the rounds, not from `StudyDay` — see `GrammarProgress` for why, and
//  for the consequence the footer states out loud.
//

import SwiftUI
import SwiftData

struct GrammarProgressPane: View {
    /// Unsorted: the aggregation reads every round and doesn't care about order.
    @Query private var kasusRounds: [KasusRound]
    @Query private var articleRounds: [ArticleRound]
    @Query private var prepositionRounds: [PrepositionRound]

    /// How far back the day strip looks. Thirteen weeks is a quarter, and the width the strip
    /// fits without scrolling on a phone.
    private static let weeks = 13

    var body: some View {
        let progress = GrammarProgress(kasus: kasusRounds, articles: articleRounds,
                                       prepositions: prepositionRounds)
        Group {
            if progress.rounds == 0 {
                emptySection
            } else {
                daysSection(progress)
                exercisesSection(progress)
                caseSection(progress)
            }
            historySection
        }
    }

    // MARK: - Nothing yet

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Noch keine Runden · No rounds yet")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Play a story, a Schnellrunde or any exercise and your time, your days and your accuracy per case show up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .themedListRow()
    }

    // MARK: - Grammatik-Tage

    private func daysSection(_ progress: GrammarProgress) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(dayLine(progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GrammarDayStrip(weeks: Self.weeks, metrics: progress.dayMetrics())
                    // 91 cells would be 91 VoiceOver stops; the rounds themselves are in Verlauf.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenDays(progress))
            }
            .padding(.vertical, 6)
        } header: {
            Text("Grammatik-Tage · Grammar days")
                .themedSectionHeader()
        } footer: {
            Text("Darker is longer. Grammar only — Home's calendar counts every kind of study.")
        }
        .themedListRow()
    }

    /// „4 h 20 min · 23 Tage · 61 Runden“
    private func dayLine(_ progress: GrammarProgress) -> String {
        [StudyTimeFormat.long(progress.totalSeconds),
         "\(progress.activeDays) \(progress.activeDays == 1 ? "Tag" : "Tage")",
         "\(progress.rounds) \(progress.rounds == 1 ? "Runde" : "Runden")"]
            .joined(separator: " · ")
    }

    private func spokenDays(_ progress: GrammarProgress) -> String {
        "\(Self.weeks) weeks of grammar: \(StudyTimeFormat.long(progress.totalSeconds)) over \(progress.activeDays) days"
    }

    // MARK: - Zeit pro Übung

    private func exercisesSection(_ progress: GrammarProgress) -> some View {
        Section {
            ForEach(progress.exercises) { row in
                GrammarShelfRow(title: title(for: row.id), subtitle: subtitle(row)) {
                    HistoryIcon(symbol: symbol(for: row.id), color: color(for: row.id))
                } trailing: {
                    // A read lesson asks nothing, so a score would read „0/0 · 0 %“.
                    if row.firstTryPercent == nil {
                        Text(StudyTimeFormat.short(row.seconds))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        HistoryScore(firstTry: row.firstTry, asked: row.answers,
                                     caption: StudyTimeFormat.short(row.seconds))
                    }
                }
            }
        } header: {
            Text("Zeit pro Übung · Time per exercise")
                .themedSectionHeader()
        } footer: {
            Text("Longest first. Counted from the rounds themselves, so these minutes can differ a little from the grammar time on Home.")
        }
        .themedListRow()
    }

    /// „Dativ · Endungen“, „Der · Die · Das“.
    private func title(for id: GrammarExerciseID) -> String {
        switch id {
        case .kasus(let stepRaw, let topicKey):
            let step = KasusRoundStep(rawValue: stepRaw)?.meta.germanTitle ?? stepRaw
            guard let topic = GrammarTopic(key: topicKey) else { return step }
            return "\(topic.germanTitle) · \(step)"
        case .family(let family):
            return family.germanTitle
        }
    }

    /// „14 Runden · zuletzt heute“.
    private func subtitle(_ row: GrammarProgress.ExerciseTotals) -> String {
        let rounds = "\(row.rounds) \(row.rounds == 1 ? "Runde" : "Runden")"
        return "\(rounds) · zuletzt \(KasusHistoryFormat.relativeDay(row.lastPlayed))"
    }

    /// The step's retrospective symbol — `meta.art` is the launcher's drawing, not a history row's.
    private func symbol(for id: GrammarExerciseID) -> String {
        switch id {
        case .kasus(let stepRaw, _):
            KasusRoundStep(rawValue: stepRaw)?.meta.symbol ?? "checklist"
        case .family(let family):
            family.symbol
        }
    }

    private func color(for id: GrammarExerciseID) -> Color? {
        switch id {
        case .kasus(_, let topicKey): GrammarTopic(key: topicKey)?.color
        case .family:                 nil
        }
    }

    // MARK: - Pro Fall

    private func caseSection(_ progress: GrammarProgress) -> some View {
        Section {
            GrammarCaseSummary(rounds: progress.rounds, answers: progress.answers,
                               firstTry: progress.firstTry, perCase: progress.perCase)
        } header: {
            Text("Pro Fall · Per case")
                .themedSectionHeader()
        } footer: {
            if progress.perCase.isEmpty {
                Text("The bars fill once you have played a round on the case path.")
            } else {
                Text("First tries per case, over every round you have played. A reflexive pronoun can't show a case, so those rounds count above but not in the bars.")
            }
        }
        .themedListRow()
    }

    // MARK: - Verlauf

    private var historySection: some View {
        let latest = GrammarHistoryEntry.all(kasus: kasusRounds, articles: articleRounds,
                                             prepositions: prepositionRounds).first
        return Section {
            NavigationLink {
                KasusHistoryView()
            } label: {
                GrammarShelfRow(title: "Verlauf · Your rounds",
                                subtitle: latest.map(lastRoundLine) ?? "Every scored round, day by day") {
                    GrammarRowChip(symbol: "clock.arrow.circlepath")
                } trailing: {
                    if let latest {
                        HistoryScore(firstTry: latest.firstTry, asked: latest.asked)
                    }
                }
            }
        }
        .themedListRow()
    }

    /// Last: Dativ · Endungen · today
    private func lastRoundLine(_ entry: GrammarHistoryEntry) -> String {
        "Last: \(entry.shortLabel) · \(KasusHistoryFormat.relativeDay(entry.date))"
    }
}

// MARK: - Preview

#Preview("Fortschritt · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                List {
                    GrammarProgressPane()
                }
                .themedListScreen()
                .navigationTitle("Grammatik · Grammar")
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .modelContainer(KasusHistoryPreview.container())
}
