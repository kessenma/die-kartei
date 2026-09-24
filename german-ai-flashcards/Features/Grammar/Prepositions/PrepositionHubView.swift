//
//  PrepositionHubView.swift
//  german-ai-flashcards
//
//  The preposition launcher: every exercise built on `prepositions.json` in one place — the
//  Kasus drill (which case does this preposition take?), the bundled fill-in-the-blank sets,
//  the flip-card reference deck, and a meaning-matching round through the existing matching
//  game. The progress strip on top reads the persisted `PrepositionRound` / `PrepositionStat`
//  history, and the toolbar's question mark opens the cheat sheet.
//
//  Deliberately no single-case rounds: a round of nothing but Dativ prepositions has the same
//  answer every time. Every Kasus launcher mixes at least two groups.
//

import SwiftUI
import SwiftData

struct PrepositionHubView: View {
    /// Owns the picture-mode setting; the drill needs the same value, so it lives on the
    /// manager rather than in a view-local @AppStorage that would drift from it.
    var modelManager: MLXModelManager
    /// Only the tutor-scene mock needs this, and only to push the real Model screen behind its
    /// Download button. Optional so the two previews below keep constructing this view with one
    /// argument.
    var mlxService: MLXGenerationService?

    @Query(sort: \PrepositionRound.date, order: .reverse) private var rounds: [PrepositionRound]
    @Query private var stats: [PrepositionStat]
    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @AppStorage("prepositions.questionCount") private var questionCount = 10
    @AppStorage("prepositions.trickyFirst") private var trickyFirst = true
    @AppStorage("prepositions.includeAdvanced") private var includeAdvanced = false
    @AppStorage("prepositions.showHints") private var showHints = false
    /// Tints the matching board's German column by case (and shows the legend). Off makes the
    /// round a pure meaning recall with no color to lean on.
    @AppStorage("prepositions.matchColorCoded") private var matchColorCoded = true

    @State private var showRules = false
    @State private var showsTutorLab = false
    @State private var isOptionsExpanded = false
    @State private var errorMessage: String?

    private let questionCountOptions = [5, 10, 15, 20]

    private var trickyCount: Int { stats.filter(\.isTricky).count }

    /// First-try accuracy across the most recent rounds, as a whole percent.
    private var recentAccuracy: Int? {
        let recent = rounds.prefix(10)
        let questions = recent.reduce(0) { $0 + $1.questionCount }
        guard questions > 0 else { return nil }
        let hits = recent.reduce(0) { $0 + $1.firstTryCount }
        return Int((Double(hits) / Double(questions) * 100).rounded())
    }

    /// The bundled fill-in-the-blank sets that belong to prepositions.
    private var blankCategories: [GrammarCategory] {
        GrammarExerciseService.loadCategories().filter {
            $0.grammaticalCase == GrammarFocus.praepositionen.rawValue
                || $0.grammaticalCase == GrammarFocus.wechselpraepositionen.rawValue
        }
    }

    var body: some View {
        List {
            if !rounds.isEmpty {
                progressSection.themedListRow()
            }
            optionsSection.themedListRow()
            drillSection.themedListRow()
            blankSection.themedListRow()
            studySection.themedListRow()

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                .themedListRow()
            }

            #if DEBUG
            renderTestSection.themedListRow()
            #endif
        }
        .themedListScreen()
        .navigationTitle("Präpositionen")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRules = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showRules) {
            PrepositionRulesSheet()
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section {
            HStack(spacing: 0) {
                progressStat("\(rounds.count)", rounds.count == 1 ? "round" : "rounds")
                if let accuracy = recentAccuracy {
                    Divider().padding(.vertical, 6)
                    progressStat("\(accuracy)%", "first-try, last 10")
                }
                Divider().padding(.vertical, 6)
                progressStat("\(trickyCount)", trickyCount == 1 ? "tricky one" : "tricky ones")
            }

            if trickyCount >= PrepositionService.minQuestions {
                Button {
                    // All four buttons: a tricky pool can hold anything, and narrowing them
                    // would hand over half the answer.
                    launchDrill(
                        topic: "Tricky Prepositions",
                        groups: Set(PrepositionCase.allCases),
                        pool: PrepositionService.trickyPrepositions(in: modelContext),
                        trickyBias: false
                    )
                } label: {
                    Label(
                        "Drill the ones you keep missing",
                        systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
                    )
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Your Progress")
        }
    }

    private func progressStat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Round options

    /// One-line recap of the current setup, shown while the options group is collapsed.
    private var optionsSummary: String {
        var parts = ["\(questionCount) per round"]
        if trickyFirst { parts.append("tricky ones first") }
        if includeAdvanced { parts.append("formal Genitiv") }
        parts.append(modelManager.prepositionPictureMode.label.lowercased())
        return parts.joined(separator: " · ")
    }

    /// Collapsed by default: expanded, this card fills the screen and pushes every launcher below
    /// the fold, which leaves the hub looking like a setup form with no way to start.
    private var optionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isOptionsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prepositions per round")
                    Picker("Prepositions per round", selection: $questionCount) {
                        ForEach(questionCountOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                Toggle("Bring back tricky ones", isOn: $trickyFirst)
                Toggle("Include formal Genitiv prepositions", isOn: $includeAdvanced)
                Toggle("Show hints in fill-in-the-blank", isOn: $showHints)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pictures")
                    Picker("Pictures", selection: Binding(
                        get: { modelManager.prepositionPictureMode },
                        set: { modelManager.prepositionPictureMode = $0 }
                    )) {
                        ForEach(PrepositionPictureMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(modelManager.prepositionPictureMode.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Options")
                    Text(optionsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if isOptionsExpanded {
                Text("Formal adds innerhalb, jenseits, oberhalb and friends: Genitiv-only prepositions you'll meet in writing rather than in conversation.")
            }
        }
    }

    // MARK: - Kasus drill

    private var drillSection: some View {
        Section {
            Button {
                launchDrill(
                    topic: "All Prepositions",
                    groups: Set(PrepositionCase.allCases),
                    pool: PrepositionService.prepositions(includeAdvanced: includeAdvanced)
                )
            } label: {
                sourceRow(
                    "All Prepositions",
                    "\(poolCount(Set(PrepositionCase.allCases))) prepositions across all four groups",
                    "square.stack.3d.up"
                )
            }
            .buttonStyle(.plain)

            Button {
                launchDrill(
                    topic: "Akkusativ or Dativ",
                    groups: [.akkusativ, .dativ],
                    pool: PrepositionService.prepositions(
                        groups: [.akkusativ, .dativ], includeAdvanced: includeAdvanced
                    )
                )
            } label: {
                sourceRow(
                    "Akkusativ or Dativ?",
                    "Just the fixed-case ones — the everyday confusion",
                    "arrow.left.arrow.right"
                )
            }
            .buttonStyle(.plain)

            Button {
                launchDrill(
                    topic: "Fixed or Two-Way",
                    groups: [.akkusativ, .dativ, .wechsel],
                    pool: PrepositionService.prepositions(
                        groups: [.akkusativ, .dativ, .wechsel], includeAdvanced: includeAdvanced
                    )
                )
            } label: {
                sourceRow(
                    "Fixed or Two-Way?",
                    "Spot the ten that switch between Akkusativ and Dativ",
                    "arrow.triangle.branch"
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("Kasus Drill")
        } footer: {
            Text("A preposition, four cases, one tap. Miss one and it shows you the case with a worked example.")
        }
    }

    private func poolCount(_ groups: Set<PrepositionCase>) -> Int {
        PrepositionService.prepositions(groups: groups, includeAdvanced: includeAdvanced).count
    }

    // MARK: - Fill in the blank

    private var blankSection: some View {
        Section {
            ForEach(blankCategories) { category in
                Button {
                    router.launch(.grammarMultipleChoice(category: category, showHints: showHints))
                } label: {
                    sourceRow(
                        category.title,
                        "\(category.subtitle) · \(category.exercises.count) exercises",
                        "text.insert"
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Fill in the Blank")
        } footer: {
            Text("The sentence decides: Wohin or Wo, which preposition fits, and when to use the short forms.")
        }
    }

    // MARK: - Study & match

    private var studySection: some View {
        Section {
            NavigationLink {
                PrepositionCardsView()
            } label: {
                sourceRow(
                    "Preposition Cards",
                    "Flip through meanings, cases, contractions and examples",
                    "rectangle.stack",
                    isLauncher: false
                )
            }

            Button {
                launchMatching(topic: "Prepositions", groups: Set(PrepositionCase.allCases))
            } label: {
                sourceRow(
                    "Match the Meanings",
                    matchColorCoded ? "All groups mixed, colored by case" : "All groups mixed",
                    "square.grid.2x2.fill"
                )
            }
            .buttonStyle(.plain)

            ForEach(PrepositionCase.allCases) { group in
                let available = poolCount([group])
                if available >= 4 {
                    Button {
                        launchMatching(topic: "\(group.germanLabel) Prepositions", groups: [group])
                    } label: {
                        matchGroupRow(group, count: available)
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle("Color matching tiles by case", isOn: $matchColorCoded)
        } header: {
            Text("Learn & Warm Up")
        } footer: {
            Text("Start on the cards if the words themselves are new; the drills assume you know roughly what each one means. One group at a time is the gentler warm-up. Colored tiles carry the Kasus drill's colors onto the matching board; turn them off to go on meaning alone.")
        }
    }

    /// A single-group matching row, in that group's color.
    private func matchGroupRow(_ group: PrepositionCase, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(group.color)
                .frame(width: 34, height: 34)
                .background(group.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Match: \(group.germanLabel) only")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(count) prepositions · \(group.englishLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(group.color)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Animation gallery (tuning surface)

    #if DEBUG
    /// Every preposition scene playing its live choreography, one per page — the place to
    /// judge motion timings on a real device without driving to each drill. Debug builds only:
    /// a tuning surface, not something a learner should land on.
    private var renderTestSection: some View {
        Section {
            NavigationLink {
                PrepositionSceneGalleryView()
            } label: {
                sourceRow(
                    "Animation Gallery",
                    "Every 3D scene live: word, meaning, motion",
                    "cube.transparent",
                    isLauncher: false
                )
            }

            // Not a preposition scene — it rides here because this is the tuning surface where
            // motion gets judged on a real device, and the figure has nowhere else to live yet.
            NavigationLink {
                FigurGalleryView()
            } label: {
                sourceRow(
                    "Figur",
                    "The Bauhaus figure assembling itself",
                    "figure.stand",
                    isLauncher: false
                )
            }

            // Also not a preposition scene. The onboarding download pitch, judged against the
            // wizard's own copy — throwaway until it is settled.
            //
            // A cover rather than a push, and that is not a style choice: the app's NavBar is an
            // overlay in ContentView's ZStack that runs through the bottom safe area, so a
            // pushed screen's own action bar ends up underneath it. The real wizard is presented
            // as a cover for the same reason, so mocking it as one is also the only way the
            // geometry being judged is the geometry that will ship.
            Button {
                showsTutorLab = true
            } label: {
                sourceRow(
                    "Tutor-Szene",
                    "The onboarding download pitch",
                    "shippingbox",
                    isLauncher: false
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("Work in Progress")
        }
        .fullScreenCover(isPresented: $showsTutorLab) {
            TutorSceneLabView(modelManager: modelManager, mlxService: mlxService)
        }
    }
    #endif

    // MARK: - Launch

    private func launchDrill(
        topic: String,
        groups: Set<PrepositionCase>,
        pool: [Preposition],
        trickyBias: Bool? = nil
    ) {
        guard let session = PrepositionService.session(
            topic: topic,
            pool: pool,
            count: questionCount,
            trickyFirst: trickyBias ?? trickyFirst,
            answerCases: groups,
            in: modelContext
        ) else {
            errorMessage = "Not enough prepositions in this group for a round."
            return
        }
        errorMessage = nil
        router.launch(.prepositionCase(session))
    }

    private func launchMatching(topic: String, groups: Set<PrepositionCase>) {
        guard let session = PrepositionService.matchingSession(
            topic: topic,
            groups: groups,
            includeAdvanced: includeAdvanced,
            limit: 8,
            colorCoded: matchColorCoded
        ) else {
            errorMessage = "Not enough prepositions in this group for a matching round."
            return
        }
        errorMessage = nil
        router.launch(.matching(session))
    }

    // MARK: - Shared row

    /// `isLauncher` rows start a round on tap, so they end in a play glyph rather than a chevron —
    /// the hub mixes them with plain navigation rows, and the two shouldn't look alike.
    @ViewBuilder
    private func sourceRow(
        _ title: String, _ subtitle: String, _ icon: String, isLauncher: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLauncher {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview("Preposition hub · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                PrepositionHubView(modelManager: MLXModelManager())
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(for: [PrepositionRound.self, PrepositionStat.self], inMemory: true)
}
