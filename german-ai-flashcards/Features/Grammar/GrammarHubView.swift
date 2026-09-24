//
//  GrammarHubView.swift
//  german-ai-flashcards
//
//  Grammatik · Grammar: one path through the four cases, then the tools. Home's Grammar tile
//  and the Pyramid's Grammatik-Kern layer both push this screen.
//
//    Weiter · Up next              one row: where to pick up (`KasusPath.next`, never stored)
//    Die vier Fälle · The cases    Nominativ → Akkusativ → Dativ → Genitiv → Alle Fälle
//    Werkzeuge · Tools             Präpositionen (the 3D scenes), der/die/das, the endings table
//
//  The toolbar's question mark opens Der Kasus-Check, the decision order every case explanation
//  in the app follows. Flames come from the coach's profile (`LearnerMemoryService.shakyFocuses`),
//  so "needs work" means the same thing here as on Today.
//

import SwiftUI
import SwiftData

struct GrammarHubView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Query private var profiles: [LearnerProfile]
    /// Story and Schnellrunde history: the hero's pick and the unit rows' dots.
    @Query private var rounds: [KasusRound]
    /// The hero row launches its story or Schnellrunde through the router.
    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme

    @State private var showKasusCheck = false

    var body: some View {
        List {
            heroSection.themedListRow()
            unitsSection.themedListRow()
            toolsSection.themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Grammatik · Grammar")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showKasusCheck = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Der Kasus-Check")
            }
        }
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
    }

    // MARK: - Learner profile inputs

    /// Shaky structures, worst-first, by the coach's shared threshold.
    private var shaky: [GrammarFocus] { LearnerMemoryService.shakyFocuses(profiles.first) }

    private func isShaky(_ focus: GrammarFocus?) -> Bool {
        guard let focus else { return false }
        return shaky.contains(focus)
    }

    // MARK: - Weiter · Up next

    /// A story's steps take about this long end to end, for the hero's subtitle.
    private static let storyMinutes: [KasusStep: Int] = [.lesen: 8, .finden: 6, .einsetzen: 4]

    /// Where to pick up: a shaky case's story, an unplayed story, the first unfinished step from
    /// the learner's start unit, or the story played longest ago. Derived on every render.
    private var hero: KasusHero {
        KasusPath.next(profile: profiles.first, level: modelManager.germanLevel,
                       rounds: rounds, bank: KasusStoryBank.bundled)
    }

    private var heroSection: some View {
        let hero = hero
        return Section {
            Button {
                if let session = hero.storySession {
                    router.launch(.kasusStory(session))
                } else {
                    router.launch(.caseEndings(hero.quickRoundSession))
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: hero.unit.symbol)
                        .font(.title2)
                        .foregroundStyle(hero.unit.color)
                        .frame(width: 44, height: 44)
                        .background(hero.unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(heroTitle(hero))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(heroSubtitle(hero))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if case .shaky(let focus) = hero.reason {
                            Label("Coach: \(GrammarCase(focus: focus)?.name ?? hero.unit.germanTitle) braucht Übung",
                                  systemImage: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Weiter · Up next")
                .themedSectionHeader()
        }
    }

    /// Dativ · „Der verlorene Schlüssel“, or Akkusativ · Schnellrunde.
    private func heroTitle(_ hero: KasusHero) -> String {
        if let title = hero.storyTitle {
            return "\(hero.unit.germanTitle) · „\(title)“"
        }
        return "\(hero.unit.germanTitle) · Schnellrunde"
    }

    /// The steps still ahead in the story and roughly how long they take, or the Schnellrunde's
    /// cases.
    private func heroSubtitle(_ hero: KasusHero) -> String {
        guard let step = hero.step else {
            return "10 Sätze · \(hero.unit.casesInPlay.map(\.short).joined(separator: " + "))"
        }
        let steps = [KasusStep.lesen, .finden, .einsetzen].drop { $0 != step }
        let path = steps.map(\.germanLabel).joined(separator: " → ")
        let minutes = Self.storyMinutes[step] ?? 8
        let line = "\(path) · about \(minutes) min"
        return hero.reason == .review ? "Wiederholen · \(line)" : line
    }

    // MARK: - Die vier Fälle

    private var unitsSection: some View {
        Section {
            ForEach(KasusUnit.allCases) { unit in
                NavigationLink {
                    KasusUnitView(unit: unit)
                } label: {
                    unitRow(unit)
                }
            }
        } header: {
            Text("Die vier Fälle · The four cases")
                .themedSectionHeader()
        } footer: {
            Text("Go top to bottom or jump in anywhere. The levels are a guide, not a gate.")
        }
    }

    private func unitRow(_ unit: KasusUnit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: unit.symbol)
                .font(.title3)
                .foregroundStyle(unit.color)
                .frame(width: 34, height: 34)
                .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(unit.germanTitle) · \(unit.englishRole)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if let forms = unit.exampleForms {
                    Text(forms)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            progressDots(unit)
            if isShaky(unit.focus) { flame }
            Text(unit.levelLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Level \(unit.levelLabel)")
        }
        .padding(.vertical, 4)
    }

    /// One dot per story (filled once its Finden and Einsetzen are both played) and one for the
    /// Schnellrunde. Keyed on (storyID, unit, step), never on a title.
    private func progressDots(_ unit: KasusUnit) -> some View {
        let progress = KasusProgress(rounds: rounds)
        let done = KasusStoryBank.bundled.stories(for: unit).map { story in
            progress.isDone(storyID: story.id, unit: unit, step: .find)
                && progress.isDone(storyID: story.id, unit: unit, step: .fill)
        } + [progress.quickRoundDone(unit)]
        return HStack(spacing: 3) {
            ForEach(Array(done.enumerated()), id: \.offset) { _, filled in
                Circle()
                    .strokeBorder(unit.color, lineWidth: 1.2)
                    .background(Circle().fill(filled ? unit.color : .clear))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done.filter { $0 }.count) of \(done.count) done")
    }

    // MARK: - Werkzeuge

    private var toolsSection: some View {
        Section {
            NavigationLink {
                PrepositionHubView(modelManager: modelManager, mlxService: mlxService)
            } label: {
                toolRow(
                    "Präpositionen", "Which case each one takes",
                    shaky: isShaky(.praepositionen) || isShaky(.wechselpraepositionen)
                ) {
                    prepositionStill
                }
            }
            NavigationLink {
                ArticleGameSetupView(modelManager: modelManager, mlxService: mlxService)
            } label: {
                toolRow("Der · Die · Das", "Every noun's gender", shaky: isShaky(.artikel)) {
                    toolChip("textformat.abc")
                }
            }
            NavigationLink {
                CaseEndingsView()
            } label: {
                toolRow("Die Endungen · The table", "rese · nese · mrmn · srsr", shaky: false) {
                    toolChip("tablecells")
                }
            }
        } header: {
            Text("Werkzeuge · Tools")
                .themedSectionHeader()
        }
    }

    /// A still of one scene, never a live canvas: the hub is a list, and the app keeps one live
    /// RealityKit view per screen. Falls back to a plain chip if the render is missing.
    @ViewBuilder
    private var prepositionStill: some View {
        if let image = PrepositionScene.image(for: "auf", state: "dat") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            toolChip("arrow.triangle.branch")
        }
    }

    private func toolChip(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: 34, height: 34)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
    }

    /// The leading slot is 44 wide so the bare 3D still and the symbol chips line their titles up.
    private func toolRow<Icon: View>(
        _ title: String, _ subtitle: String, shaky: Bool, @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 12) {
            icon()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if shaky { flame }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Shared bits

    /// The coach's "needs work" mark, the same flame Today and the Pyramid use.
    private var flame: some View {
        Image(systemName: "flame.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("Needs work")
    }
}

// MARK: - Previews

#Preview("Grammar hub · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                GrammarHubView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(
        for: [SavedDeck.self, StudyDay.self, LearnerProfile.self, ChatConversation.self, KasusRound.self],
        inMemory: true
    )
}
