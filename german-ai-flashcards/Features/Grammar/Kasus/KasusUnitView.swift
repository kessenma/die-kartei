//
//  KasusUnitView.swift
//  german-ai-flashcards
//
//  One case on the Grammatik path. Every unit runs the same loop, top to bottom:
//
//    Die Regel · The rule        a few lines, the endings table with this case lit, the Kasus-Check
//    Geschichten · Stories       the bundled stories for this unit (Lesen → Markieren → Endungen)
//    Deine KI-Geschichten        „Neue Geschichte · New story (KI)“ and the tutor-written stories
//                                (Phase 3, behind the developer toggle; `KasusAIStorySection`)
//    Schnellrunde · Quick round  the endings drill, limited to the unit's cases
//    Deine Runden · Your rounds  the unit's last three rounds, and all of them in Verlauf
//    Mehr dazu · Also for this   the preposition cards on this case's group (3D stills), or
//                                der · die · das for the Nominativ
//
//  Rows that start a round end in a play glyph; rows that navigate get the list's chevron (the
//  same rule as `PrepositionHubView.sourceRow`).
//

import SwiftUI
import SwiftData

struct KasusUnitView: View {
    let unit: KasusUnit
    /// For the Nominativ's der · die · das row, which can make its own AI topics, and for the
    /// tutor-written stories. Without them those rows are left out.
    let modelManager: MLXModelManager?
    let mlxService: MLXGenerationService?

    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme
    /// Optional so previews and hosts without one still render; the download state then points
    /// at Settings ▸ Model in words.
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?

    @Query private var rounds: [KasusRound]

    /// Settings ▸ Developer: „KI-Geschichten im Kasus-Pfad“.
    @AppStorage(KasusStoryGenerator.enabledKey) private var aiStoriesEnabled = KasusStoryGenerator.defaultEnabled
    /// The generation sheet, while it's up.
    @State private var generation: KasusGenerationJob?
    /// What the sheet asked to play; launched once the sheet has gone (a full-screen cover can't
    /// come up over a sheet).
    @State private var pendingSession: KasusSession?
    /// `ModelReadiness` reads the disk and publishes nothing; bumping this re-reads it.
    @State private var readinessToken = UUID()

    /// Nil until the learner opens or closes "Die Regel" by hand. Until then it is open until the
    /// unit's first round, so a returning learner lands on the exercises instead of the rule.
    @State private var ruleExpandedChoice: Bool?
    @State private var showKasusCheck = false

    /// Questions in one Schnellrunde.
    private let quickRoundCount = 10

    init(unit: KasusUnit, modelManager: MLXModelManager? = nil, mlxService: MLXGenerationService? = nil) {
        self.unit = unit
        self.modelManager = modelManager
        self.mlxService = mlxService
    }

    var body: some View {
        List {
            headerSection.themedListRow()
            ruleSection.themedListRow()
            storiesSection
            aiStoriesSection
            quickRoundSection.themedListRow()
            roundsSection.themedListRow()
            moreSection.themedListRow()
        }
        .themedListScreen()
        .navigationTitle(unit.germanTitle)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
        .sheet(item: $generation, onDismiss: launchPendingSession) { job in
            KasusGenerationSheet(job: job, onPlay: { pendingSession = $0 })
        }
        .onAppear { readinessToken = UUID() }
        .onChange(of: mlxService?.isLoading) { readinessToken = UUID() }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: unit.symbol)
                    .font(.title2)
                    .foregroundStyle(unit.color)
                    .frame(width: 44, height: 44)
                    .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.englishRole)
                        .font(.headline)
                    if let forms = unit.exampleForms {
                        Text(forms)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(unit.levelLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Level \(unit.levelLabel)")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Die Regel

    private var hasPlayedUnit: Bool {
        rounds.contains { $0.unitRaw == unit.rawValue }
    }

    private var isRuleExpanded: Binding<Bool> {
        Binding(
            get: { ruleExpandedChoice ?? !hasPlayedUnit },
            set: { ruleExpandedChoice = $0 }
        )
    }

    private var ruleSection: some View {
        Section {
            DisclosureGroup(isExpanded: isRuleExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unit.ruleLines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(unit.color)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(kasusRich: line)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)

                CaseEndingsTable(cases: unit.casesInPlay, highlight: unit.focusCase)
                    .padding(.vertical, 6)

                Button {
                    showKasusCheck = true
                } label: {
                    Label("Der Kasus-Check · Which case?", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            } label: {
                Text("Die Regel · The rule")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Geschichten

    private var stories: [KasusStory] { KasusStoryBank.bundled.stories(for: unit) }

    /// One row per bundled story for this unit, launched through the router as `.kasusStory`.
    /// Units without a story show nothing here.
    @ViewBuilder
    private var storiesSection: some View {
        let stories = self.stories
        if !stories.isEmpty {
            let progress = KasusProgress(rounds: rounds)
            Section {
                ForEach(stories) { story in
                    storyRow(story, progress: progress)
                }
            } header: {
                Text("Geschichten · Stories")
                    .themedSectionHeader()
            } footer: {
                Text("Read the story, mark the cases, then fill in the endings. About 8 minutes.")
            }
            .themedListRow()
        }
    }

    private func storyRow(_ story: KasusStory, progress: KasusProgress) -> some View {
        let found = progress.isDone(storyID: story.id, unit: unit, step: .find)
        let filled = progress.isDone(storyID: story.id, unit: unit, step: .fill)
        return Button {
            // Pick up where it was left: Endungen once Markieren is done, otherwise from the top.
            let start: KasusStep = found && !filled ? .einsetzen : .lesen
            router.launch(.kasusStory(KasusSession(storyID: story.id, unit: unit, startStep: start)))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.title3)
                    .foregroundStyle(unit.color)
                    .frame(width: 34, height: 34)
                    .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("„\(story.title)“")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("\(story.level) · Markieren \(stepMark(found)) · Endungen \(stepMark(filled))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(story.title), \(story.level). Markieren \(found ? "done" : "not yet"), Endungen \(filled ? "done" : "not yet").")
    }

    /// ✓ once the step has been played, ○ before.
    private func stepMark(_ done: Bool) -> Image {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
    }

    // MARK: - Deine KI-Geschichten

    #if DEBUG
    /// `-kasus.debugGenerate <unit>` names this unit: the row shows as ready with the canned
    /// writer, since nothing is ever ready in a simulator that can't run MLX.
    private var debugLaunch: KasusGenerateDebug.Launch? {
        KasusGenerateDebug.fromLaunchArguments().flatMap { $0.unit == unit ? $0 : nil }
    }
    #endif

    private var aiAvailability: KasusGenerationAvailability {
        _ = readinessToken
        guard aiStoriesEnabled else { return .hidden }
        #if DEBUG
        if debugLaunch != nil { return .ready(.gemma4_E4B_german) }
        #endif
        guard let modelManager, mlxService != nil else { return .hidden }
        return KasusStoryGenerator.availability(selectedStoryModel: modelManager.selectedStoryModel, enabled: true)
    }

    private var aiTutorLabel: String? {
        #if DEBUG
        if let debugLaunch { return "Canned · \(debugLaunch.fixture.rawValue)" }
        #endif
        return nil
    }

    /// A German tutor is downloading or loading: the service doesn't say which model it's
    /// loading, so this reads the pick it loads, as Settings ▸ Model does.
    private var isTutorLoading: Bool {
        guard mlxService?.isLoading == true, let modelManager else { return false }
        return MLXModel.germanTutors.contains(modelManager.selectedMLXModel)
    }

    private var aiStoriesSection: some View {
        KasusAIStorySection(
            unit: unit,
            availability: aiAvailability,
            tutorLabel: aiTutorLabel,
            progress: KasusProgress(rounds: rounds),
            isDownloading: isTutorLoading,
            onNewStory: startGeneration,
            onGetTutor: settingsRouter.map { settings in { settings.route = .model } }
        )
    }

    /// Opens the generation sheet with the unit's own level. A story that fails the check falls
    /// back on the unit's first bundled story not played through yet.
    private func startGeneration() {
        #if DEBUG
        if let debugLaunch {
            let (generator, request) = KasusGenerateDebug.generator(for: debugLaunch)
            generation = KasusGenerationJob(generator: generator, request: request,
                                            tutorName: KasusGenerationCopy.tutorName(generator.writer.modelID))
            return
        }
        #endif
        guard case .ready(let model) = aiAvailability, let mlxService else { return }
        var request = KasusGenerationRequest(unit: unit, level: KasusStoryPlanner.defaultLevel(for: unit))
        let progress = KasusProgress(rounds: rounds)
        request.fallbackStoryID = stories.first {
            !progress.isDone(storyID: $0.id, unit: unit, step: .find) || !progress.isDone(storyID: $0.id, unit: unit, step: .fill)
        }?.id
        generation = KasusGenerationJob(generator: .live(model: model, service: mlxService), request: request,
                                        tutorName: KasusGenerationCopy.shortName(model))
    }

    private func launchPendingSession() {
        guard let session = pendingSession else { return }
        pendingSession = nil
        router.launch(.kasusStory(session))
    }

    // MARK: - Schnellrunde

    private var quickRoundSection: some View {
        Section {
            Button {
                router.launch(.caseEndings(CaseEndingsSession(unit: unit)))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Schnellrunde · Quick round")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text("\(quickRoundCount) Sätze · \(unit.casesInPlay.map(\.short).joined(separator: " + "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Pick the article that fits the sentence. Every miss shows which case it is and why.")
        }
    }

    // MARK: - Deine Runden

    /// This unit's rounds, newest first, without the record check's synthetic ones.
    private var unitRounds: [KasusRound] {
        rounds.filter { $0.unitRaw == unit.rawValue && $0.isListed }.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var roundsSection: some View {
        let played = unitRounds
        if !played.isEmpty {
            Section {
                ForEach(played.prefix(3)) { round in
                    NavigationLink {
                        KasusRoundDetailView(round: round)
                    } label: {
                        KasusRoundRow(round: round, showsUnit: false)
                    }
                }
                NavigationLink {
                    KasusHistoryView(unit: unit)
                } label: {
                    Text(played.count > 3 ? "Alle anzeigen · All \(played.count)" : "Alle anzeigen · Show all")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                }
            } header: {
                Text("Deine Runden · Your rounds")
                    .themedSectionHeader()
            }
        }
    }

    // MARK: - Mehr dazu

    /// Where else this case gets practised: the preposition cards opened on its group (and the
    /// two-way ones for Dativ), or der · die · das for the Nominativ, whose form is the one the
    /// dictionary gives.
    private enum MoreLink: Hashable {
        case cards(PrepositionCase?)
        case articles
    }

    private var moreLinks: [MoreLink] {
        let articles: [MoreLink] = modelManager != nil && mlxService != nil ? [.articles] : []
        switch unit {
        case .nominativ:  return articles
        case .akkusativ:  return [.cards(.akkusativ)]
        case .dativ:      return [.cards(.dativ), .cards(.wechsel)]
        case .genitiv:    return [.cards(.genitiv)]
        case .alleFaelle: return [.cards(nil)] + articles
        }
    }

    @ViewBuilder
    private var moreSection: some View {
        let links = moreLinks
        if !links.isEmpty {
            Section {
                ForEach(links, id: \.self) { link in
                    NavigationLink {
                        moreDestination(link)
                    } label: {
                        moreRow(link)
                    }
                }
            } header: {
                Text("Mehr dazu · Also for this case")
                    .themedSectionHeader()
            } footer: {
                Text(links == [.articles]
                     ? "The Nominativ is the dictionary form, so knowing a noun's gender is knowing its article."
                     : "Cards with a 3D scene for each preposition: what it means, its case, and examples.")
            }
        }
    }

    @ViewBuilder
    private func moreDestination(_ link: MoreLink) -> some View {
        switch link {
        case .cards(let group):
            PrepositionCardsView(initialGroup: group)
        case .articles:
            if let modelManager, let mlxService {
                ArticleGameSetupView(modelManager: modelManager, mlxService: mlxService)
            }
        }
    }

    /// A tile for the still, the title, one line under it.
    private func moreRow(_ link: MoreLink) -> some View {
        HStack(spacing: 12) {
            moreIcon(link)
            VStack(alignment: .leading, spacing: 2) {
                Text(moreTitle(link))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(kasusRich: moreSubtitle(link))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func moreTitle(_ link: MoreLink) -> String {
        switch link {
        case .cards(.akkusativ?): "Präpositionen mit Akkusativ"
        case .cards(.dativ?):     "Präpositionen mit Dativ"
        case .cards(.wechsel?):   "Wo oder Wohin? · Two-way"
        case .cards(.genitiv?):   "Präpositionen mit Genitiv"
        case .cards(nil):         "Alle Präpositionen · Every group"
        case .articles:           "Der · Die · Das"
        }
    }

    /// In the `KasusRich` markup, so case words and forms carry their colors.
    private func moreSubtitle(_ link: MoreLink) -> String {
        switch link {
        case .cards(.wechsel?):
            return "{wechsel:Wo?} → {dat:Dativ} · {wechsel:Wohin?} → {akk:Akkusativ}"
        case .cards(.akkusativ?):
            return "für · ohne · durch · gegen · um"
        case .cards(.dativ?):
            return "mit · nach · bei · seit · von · zu · aus"
        case .cards(.genitiv?):
            return "wegen · trotz · während · statt"
        case .cards(nil):
            return "{akk:Akk} · {dat:Dat} · {wechsel:Wechsel} · {gen:Gen}, in 3D"
        case .articles:
            return "Every noun's gender: {m:der}, {f:die} or {n:das}"
        }
    }

    /// Which render a row shows, and where its subject sits: the renders leave a wide empty
    /// margin, and each one's subject sits somewhere else in it.
    private struct Still {
        let word: String
        let state: String
        let zoom: CGFloat
        /// The subject's center, as a fraction of the render.
        let focus: CGPoint
    }

    private func sceneStill(for link: MoreLink) -> Still? {
        switch link {
        case .cards(.akkusativ?): Still(word: "für", state: "dat", zoom: 1.3, focus: CGPoint(x: 0.46, y: 0.56))
        case .cards(.dativ?):     Still(word: "mit", state: "dat", zoom: 1.5, focus: CGPoint(x: 0.62, y: 0.56))
        case .cards(.wechsel?):   Still(word: "wohinwo", state: "akk", zoom: 1.3, focus: CGPoint(x: 0.4, y: 0.5))
        case .cards(.genitiv?):   Still(word: "wegen", state: "dat", zoom: 1.05, focus: CGPoint(x: 0.5, y: 0.55))
        case .cards(nil):         Still(word: "auf", state: "dat", zoom: 1.25, focus: CGPoint(x: 0.42, y: 0.6))
        case .articles:           nil
        }
    }

    /// A still of the group's scene on a tile, never a live canvas (one RealityKit view per
    /// screen). A plain chip when there is no still.
    @ViewBuilder
    private func moreIcon(_ link: MoreLink) -> some View {
        let tile = RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous)
        let side: CGFloat = 60
        let still = sceneStill(for: link)
        if let still, let image = PrepositionScene.image(for: still.word, state: still.state) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .scaleEffect(still.zoom)
                .offset(x: (0.5 - still.focus.x) * side * still.zoom,
                        y: (0.5 - still.focus.y) * side * still.zoom)
                .frame(width: side, height: 46)
                .background(Color.secondary.opacity(0.06))
                .clipShape(tile)
                .accessibilityHidden(true)
        } else {
            Image(systemName: link == .articles ? "textformat.abc" : "arrow.triangle.branch")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 60, height: 46)
                .background(.tint.opacity(0.12), in: tile)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Previews

#Preview("Kasus unit · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                KasusUnitView(unit: .dativ)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(for: [LearnerProfile.self, StudyDay.self, KasusRound.self, GeneratedKasusStory.self], inMemory: true)
}

#Preview("Kasus unit · Markieren played") {
    let container = try! ModelContainer(
        for: LearnerProfile.self, StudyDay.self, KasusRound.self, GeneratedKasusStory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(KasusRound(
        storyID: "ks-dat-a2-schluessel", unitRaw: KasusUnit.dativ.rawValue, stepRaw: KasusRoundStep.find.rawValue,
        askedCount: 26, firstTryCount: 21, durationSeconds: 190
    ))
    return NavigationStack {
        KasusUnitView(unit: .dativ)
    }
    .environment(ActivityRouter())
    .modelContainer(container)
}

#Preview("Kasus unit · rounds + Mehr dazu · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                KasusUnitView(unit: .dativ)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(KasusHistoryPreview.container())
}
