//
//  EnglischSetupView.swift
//  german-ai-flashcards
//
//  „Übung einstellen“: the one screen in front of an „Englisch & Fälle“ round. The deck launcher's
//  shape (a `List` of sections, one settings row, one Start button) with everything the app already
//  knows left out of it — the round length is the registry's (`KasusDrillMeta.roundSize`), and the
//  task is the row the learner tapped. What is left is the unit and how much help, which are the
//  only two things nobody else can answer.
//
//  The preset is seeded from the declared `germanLevel` and never written back: nothing is stored
//  until the dial is touched, and then it stops following the level
//  (`KasusHelp.resolve(stored:level:)`, `MLXModelManager.germanLevel`'s own contract).
//

import SwiftUI
import SwiftData

struct EnglischSetupView: View {
    let kind: KasusDrillKind

    @AppStorage(KasusHelp.storageKey) private var storedHelp = ""
    @AppStorage(KasusHelp.levelKey) private var levelRaw = CEFRLevel.a2.rawValue
    @AppStorage("kasus.englisch.unit") private var unitRaw = KasusUnit.alleFaelle.rawValue

    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme

    /// The units this exercise can be played on at all, read from the bundled items.
    @State private var units: [KasusUnit] = []

    private var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a2 }
    private var help: KasusHelp { KasusHelp.resolve(stored: storedHelp.isEmpty ? nil : storedHelp, level: level) }
    private var isAutomatic: Bool { storedHelp.isEmpty }
    private var unit: KasusUnit {
        let stored = KasusUnit(rawValue: unitRaw) ?? .alleFaelle
        return units.contains(stored) ? stored : (units.last ?? .alleFaelle)
    }

    var body: some View {
        List {
            headerSection.themedListRow()
            helpSection.themedListRow()
            startSection.themedListRow()
        }
        .themedListScreen()
        .navigationTitle(kind.meta.germanTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if units.isEmpty { units = EnglishAnchors.playableUnits(kind) }
        }
    }

    // MARK: - Diese Runde

    private var headerSection: some View {
        Section {
            VStack(spacing: 10) {
                GrammarTaskArtView(art: kind.meta.art, tint: unit.color, size: 54)
                Text("\(unit.germanTitle) · \(kind.meta.roundSize) Sätze · about \(kind.meta.minutes) min")
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

            if units.count > 1 {
                Picker("Einheit", selection: Binding(get: { unit }, set: { unitRaw = $0.rawValue })) {
                    ForEach(units) { unit in
                        Text("\(unit.germanTitle) · \(unit.casesInPlay.map(\.short).joined(separator: " + "))")
                            .tag(unit)
                    }
                }
            }
        } header: {
            Text("Diese Runde · This round").themedSectionHeader()
        } footer: {
            if units.isEmpty {
                Text("Nothing to practise here yet.")
            } else {
                Text("The cases in play come from the unit; everything else about the round is already set.")
            }
        }
    }

    // MARK: - Wie viel Hilfe?

    private var helpSection: some View {
        Section {
            Picker("Wie viel Hilfe?", selection: Binding(get: { help }, set: { storedHelp = $0.rawValue })) {
                ForEach(KasusHelp.allCases) { preset in
                    Text(preset.germanLabel).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Text(help.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !isAutomatic {
                Button("Wieder automatisch · Follow my level") { storedHelp = "" }
                    .font(.subheadline)
            }
        } header: {
            Text("Wie viel Hilfe? · How much help").themedSectionHeader()
        } footer: {
            if isAutomatic {
                Text("Dein Level \(level.rawValue) picked this. Changing it here doesn't change your level.")
            } else {
                Text("You picked this yourself, so it no longer follows your level.")
            }
        }
    }

    // MARK: - Starten

    private var startSection: some View {
        Section {
            Button {
                router.launch(.grammarDrill(GrammarDrillSession(kind: kind, topic: .kasus(unit),
                                                                variant: .english(EnglishConfig(help: help)))))
            } label: {
                Label("Starten", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(units.isEmpty)
        }
    }
}

#Preview("Übung einstellen · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                EnglischSetupView(kind: .frage)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(for: [KasusRound.self], inMemory: true)
}
