//
//  TabelleSetupView.swift
//  german-ai-flashcards
//
//  „Übung einstellen“ for Die Tabelle, built like `EnglischSetupView`: a `List` of sections, only
//  the settings nobody else can answer, and one Start button. The round length is the registry's
//  (sixteen cells, whatever the shape), so what is left is which chart and how much of it is
//  blank — and both are remembered, because a learner who wants the whole table wants it twice.
//

import SwiftUI
import SwiftData

struct TabelleSetupView: View {
    let kind: KasusDrillKind

    @AppStorage(TableConfig.chartKey) private var chartRaw = ArticleChart.definite.rawValue
    @AppStorage(TableConfig.shapeKey) private var shapeRaw = ArticleTableShape.whole.rawValue

    @Environment(ActivityRouter.self) private var router

    private var chart: ArticleChart { ArticleChart(rawValue: chartRaw) ?? .definite }
    private var shape: ArticleTableShape { ArticleTableShape(rawValue: shapeRaw) ?? .whole }

    var body: some View {
        List {
            headerSection.themedListRow()
            chartSection.themedListRow()
            shapeSection.themedListRow()
            startSection.themedListRow()
        }
        .themedListScreen()
        .navigationTitle(kind.meta.germanTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Diese Runde

    private var headerSection: some View {
        Section {
            VStack(spacing: 10) {
                GrammarTaskArtView(art: kind.meta.art, size: 54)
                Text("\(ArticleTableRound.cellCount) Felder · about \(kind.meta.minutes) min")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(kind.meta.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } header: {
            Text("Diese Runde · This round").themedSectionHeader()
        } footer: {
            Text("Every round asks all sixteen cells, so a score means the same whichever shape you pick.")
        }
    }

    // MARK: - Welche Tabelle?

    private var chartSection: some View {
        Section {
            Picker("Welche Tabelle?", selection: $chartRaw) {
                ForEach(ArticleChart.allCases) { chart in
                    Text(chart.germanTitle).tag(chart.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(chart == .definite
                 ? "der, die, das — the chart whose last letters spell rese · nese · mrmn · srsr."
                 : "ein, eine, einen … with kein in the plural column, where ein has no form.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Welche Tabelle? · Which chart").themedSectionHeader()
        }
    }

    // MARK: - Wie viel steht da?

    private var shapeSection: some View {
        Section {
            Picker("Wie viel steht da?", selection: $shapeRaw) {
                ForEach(ArticleTableShape.allCases) { shape in
                    Text(shape.germanLabel).tag(shape.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("\(shape.englishLabel) · \(shape.blurb)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Wie viel steht da? · How much is given").themedSectionHeader()
        }
    }

    // MARK: - Starten

    private var startSection: some View {
        Section {
            Button {
                let config = TableConfig(chart: chart, shape: shape)
                router.launch(.grammarDrill(GrammarDrillSession(kind: kind, topic: .kasus(.alleFaelle),
                                                                variant: .table(config))))
            } label: {
                Label("Starten", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Die Tabelle · setup · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                TabelleSetupView(kind: .tabelle)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(for: [KasusRound.self], inMemory: true)
}
