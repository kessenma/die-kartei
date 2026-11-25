//
//  GrammarBereichView.swift
//  german-ai-flashcards
//
//  One room of the Grammatik hub (`GrammarArea`): the area's shelf rendered from `area.rows`, so
//  adding an exercise, a rule sheet or a future structure is one entry in GrammarArea.swift and
//  this view never changes. Präpositionen keeps its own grown screen (`PrepositionHubView`); the
//  hub pushes this view for every other area.
//
//    Die Reihen · rows        a `.struktur` renders as a full topic row (dots, flame, push) once
//                             `GrammarRoute(focus).hasExercise`, and as a quiet Lektion row (the
//                             30-second sheet) until then — the in-place upgrade, one predicate
//    Mehr dazu · cross-links  pushes into a neighbour that drills the same ground
//
//  Dots mean finishable, so Lektion rows carry none. Flames come from the coach's profile, the
//  same `LearnerMemoryService.shakyFocuses` the hub and Today read.
//
//  Art marks a task, a chip marks a place: Der · Die · Das and the Lektion rows wear a task
//  drawing (`GrammarTaskArt`), while a topic row, the rule sheet and the cross-links keep a chip
//  (`GrammarShelfRow`). A Lektion row is both, so it is the one row that carries a drawing *and* a
//  flame and a level.
//

import SwiftUI
import SwiftData

struct GrammarBereichView: View {
    let area: GrammarArea
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Query private var profiles: [LearnerProfile]
    /// Topic rows' progress dots; the same unfiltered query the hub and topic screens use.
    @Query private var rounds: [KasusRound]
    @Environment(\.appTheme) private var appTheme

    /// The Lektion row's sheet (`GrammarLessonSheet`), one structure at a time.
    @State private var lessonFocus: GrammarFocus?
    @State private var rulesSheet: BereichSheet?

    private var shaky: [GrammarFocus] { LearnerMemoryService.shakyFocuses(profiles.first) }

    var body: some View {
        List {
            headerSection.themedListRow()
            rowsSection.themedListRow()
            crossLinksSection.themedListRow()
        }
        .themedListScreen()
        .navigationTitle(area.germanTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $lessonFocus) { focus in
            GrammarLessonSheet(focus: focus)
        }
        .sheet(item: $rulesSheet) { sheet in
            switch sheet {
            case .articleRules: ArticleRulesSheet()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: area.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.germanTitle)
                        .font(.headline)
                    Text(area.englishRole)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(area.levelLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Level \(area.levelLabel)")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Rows

    private var rowsSection: some View {
        Section {
            ForEach(area.rows) { row in
                switch row {
                case .struktur(let focus): strukturRow(focus)
                case .screen(let screen):  screenRow(screen)
                case .sheet(let sheet):    sheetRow(sheet)
                case .drill(let kind):     drillRow(kind)
                }
            }
        } footer: {
            Text("The levels are a guide, not a gate.")
        }
    }

    /// The in-place upgrade: the same shelf position is a topic row once the structure has an
    /// exercise of its own, and a quiet Lektion row until then.
    @ViewBuilder
    private func strukturRow(_ focus: GrammarFocus) -> some View {
        if case .topic(let topic) = GrammarRoute(focus) {
            NavigationLink {
                ReflexivTopicView(topic: topic)
            } label: {
                topicRow(topic, focus: focus)
            }
        } else {
            lektionRow(focus)
        }
    }

    private func topicRow(_ topic: GrammarTopic, focus: GrammarFocus) -> some View {
        GrammarShelfRow(title: "\(topic.germanTitle) · \(topic.englishRole)",
                        subtitle: topic.rowSubtitle,
                        shaky: shaky.contains(focus), level: topic.levelLabel) {
            GrammarRowChip(symbol: topic.symbol, tint: topic.color)
        } trailing: {
            topicDots(topic)
        }
    }

    /// A structure with only the 30-second lesson so far: lighter, no dots (dots mean finishable).
    private func lektionRow(_ focus: GrammarFocus) -> some View {
        Button {
            lessonFocus = focus
        } label: {
            // Quiet: the drawing and the text take `.secondary`, because there is no round to
            // play here yet — only the 30-second read.
            GrammarTaskRow(icon: .art(KasusRoundStep.lesson.meta.art),
                           title: "\(focus.germanLabel) · Lektion",
                           subtitle: focus.englishLabel, tail: .read, tint: .secondary,
                           shaky: shaky.contains(focus), level: focus.introducedAt.rawValue)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func screenRow(_ screen: BereichScreen) -> some View {
        switch screen {
        case .articleGame:
            NavigationLink {
                ArticleGameSetupView(modelManager: modelManager, mlxService: mlxService)
            } label: {
                GrammarTaskRow(icon: .art(.labelOneWord), title: "Der · Die · Das",
                               subtitle: "Every noun's gender", tail: .none,
                               shaky: shaky.contains(.artikel), level: "A1")
            }
        }
    }

    /// One exercise from the registry: the row builds itself from `KasusDrillMeta` and pushes the
    /// exercise's own setup screen, which is where the unit, the chart or the help level are
    /// chosen. The setup screen is the only thing a kind brings of its own here.
    private func drillRow(_ kind: KasusDrillKind) -> some View {
        NavigationLink {
            switch kind {
            case .tabelle: TabelleSetupView(kind: kind)
            default:       EnglischSetupView(kind: kind)
            }
        } label: {
            GrammarTaskRow(icon: .art(kind.meta.art),
                           title: "\(kind.meta.germanTitle) · \(kind.meta.englishTitle)",
                           subtitle: "\(kind.meta.blurb) · about \(kind.meta.minutes) min",
                           done: played(kind), tail: .play)
        }
    }

    /// The done mark: any topic this kind can be played on has a scored round.
    private func played(_ kind: KasusDrillKind) -> Bool {
        let progress = KasusProgress(rounds: rounds)
        let topics: [String] = switch kind {
        case .tabelle: [KasusUnit.alleFaelle.rawValue]
        default:       EnglishAnchors.units.map(\.rawValue)
        }
        return topics.contains { progress.drillDone(kind.step, topicKey: $0) }
    }

    private func sheetRow(_ sheet: BereichSheet) -> some View {
        Button {
            rulesSheet = sheet
        } label: {
            switch sheet {
            case .articleRules:
                GrammarShelfRow(title: "Die 18 Regeln · The gender patterns",
                                subtitle: "How far each ending can be trusted") {
                    GrammarRowChip(symbol: "list.bullet.rectangle")
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mehr dazu

    @ViewBuilder
    private var crossLinksSection: some View {
        if !area.crossLinks.isEmpty {
            Section {
                ForEach(area.crossLinks) { link in
                    crossLinkRow(link)
                }
            } header: {
                Text("Mehr dazu · More on this").themedSectionHeader()
            }
        }
    }

    @ViewBuilder
    private func crossLinkRow(_ link: BereichLink) -> some View {
        switch link {
        case .dativUnit:
            NavigationLink {
                KasusUnitView(unit: .dativ, modelManager: modelManager, mlxService: mlxService)
            } label: {
                GrammarShelfRow(title: "Dativ-Verben · The verb decides",
                                subtitle: "A drill in the Dativ unit") {
                    GrammarRowChip(symbol: "hand.raised.fill")
                }
            }
        case .prepositionVerbTrack:
            NavigationLink {
                PrepositionHubView(modelManager: modelManager, mlxService: mlxService,
                                   initialTrack: .verb)
            } label: {
                GrammarShelfRow(title: "Verben mit Präpositionen",
                                subtitle: "warten auf, denken an — the pair fixes the case",
                                shaky: shaky.contains(.verbenPraepositionen)) {
                    GrammarRowChip(symbol: "arrow.triangle.branch")
                }
            }
        }
    }

    // MARK: - Shared bits

    /// One dot for the lesson, one per drill the topic offers, like the hub's old Themen rows.
    private func topicDots(_ topic: GrammarTopic) -> some View {
        let progress = KasusProgress(rounds: rounds)
        let done = [progress.lessonRead(topicKey: topic.key)]
            + topic.exercises().map { progress.drillDone($0.step, topicKey: topic.key) }
        return HStack(spacing: 3) {
            ForEach(Array(done.enumerated()), id: \.offset) { _, filled in
                Circle()
                    .strokeBorder(topic.color, lineWidth: 1.2)
                    .background(Circle().fill(filled ? topic.color : .clear))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done.filter { $0 }.count) of \(done.count) done")
    }
}

// MARK: - Previews

#Preview("Verben room · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                GrammarBereichView(area: .verben, modelManager: MLXModelManager(), mlxService: MLXGenerationService())
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(for: [LearnerProfile.self, KasusRound.self, ArticleRound.self, PrepositionRound.self], inMemory: true)
}

#Preview("Artikel room") {
    NavigationStack {
        GrammarBereichView(area: .artikel, modelManager: MLXModelManager(), mlxService: MLXGenerationService())
    }
    .environment(ActivityRouter())
    .modelContainer(for: [LearnerProfile.self, KasusRound.self, ArticleRound.self, PrepositionRound.self], inMemory: true)
}
