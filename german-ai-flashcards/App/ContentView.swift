//
//  ContentView.swift
//  german-ai-flashcards
//
//  Created by Kyle Essenmacher on 5/14/26.
//

import SwiftUI
import SwiftData

/// Payload for the post-generation "keep which cards?" sheet. Item-driven presentation
/// guarantees the sheet always builds with the cards in hand — a Bool flag could present
/// before SwiftUI saw the freshly set arrays, briefly showing an empty picker.
private struct CardSelectionPayload: Identifiable {
    let id = UUID()
    let cards: [VocabCard]
    let validationResults: [ValidationResult]
    /// Set when the pictures were drawn before the review (`CardImageTiming.everyCard`), so the
    /// sheet can show them next to each card.
    let draftImageID: UUID?
    let draftImages: [String: String]
}

/// A deck that's saved but is still having its pictures drawn, held here so the overlay can stand
/// between the review and the deck screen. `CardImageTiming.keptCards` produces one of these; the
/// deck opens when the run ends, or sooner if the learner doesn't want to wait.
private struct PendingIllustration: Identifiable {
    let id = UUID()
    let deckUUID: UUID
    let session: StudySession
    let topic: String
}

struct ContentView: View {
    @State private var selectedTab: MenuTab = .home
    @State private var visitedTabs: Set<MenuTab> = [.home]
    @Bindable var coordinator: GenerationCoordinator

    /// Drives the immersive activity cover (flashcard player, grammar quiz, …). Launchers set
    /// `router.active`; this view presents it through the single `.fullScreenCover` below.
    @State private var router = ActivityRouter()

    @State private var settingsResetToken: Int = 0
    @State private var homeResetToken: Int = 0
    @State private var pendingSelection: CardSelectionPayload?
    @State private var pendingIllustration: PendingIllustration?
    @State private var saveError: String?
    #if DEBUG
    @State private var showPlacementReview = false
    @State private var showLevelSettings = false
    @State private var showConversationSetup = false
    /// `-wortschatz.debugOpen 1`: the hub sits two taps into Home, and this simulator can't tap.
    @State private var showWortschatzHub = false
    /// `-stories.debugOpen 1`: the reader sits several taps deep and needs a story that has
    /// pictures, which normally means running diffusion. See `StoryDebugSeeder`.
    @State private var debugStory: StudyStory?
    #endif
    @Environment(\.modelContext) private var modelContext

    /// Legacy first-launch flag from when the hero intro was its own sheet. Still read (and set)
    /// so anyone who saw the old flow is never shown the wizard, and still respected by nothing
    /// else — the standalone sheet now only opens from Settings → Model.
    @AppStorage("hasSeenHeroModelIntro") private var hasSeenHeroModelIntro = false

    /// Superseded by `hasSeenOnboardingV2`. Still written so a downgrade doesn't re-onboard, and
    /// still cleared by the debug reset.
    @AppStorage("hasSeenOnboardingWizard") private var hasSeenOnboardingWizard = false

    /// The first-launch flow: why-a-download, the tutor offer, then the placement check while the
    /// model downloads. Offered once, ever.
    ///
    /// A *new* key rather than a reuse of `hasSeenOnboardingWizard`, and that is deliberate: the
    /// flow now leads with an explanation nobody who saw the old wizard has ever been shown, so
    /// everyone gets it once. The steps self-skip for people who are already set up (see
    /// `OnboardingWizardView`), which is what keeps that from being a nuisance.
    @AppStorage("hasSeenOnboardingV2") private var hasSeenOnboardingV2 = false
    @State private var showOnboardingWizard = false

    /// Deep links into the Settings tab, so the Home tutor card and the upgrade nudges can point
    /// somewhere real instead of naming a screen and leaving the reader to find it.
    @State private var settingsRouter = SettingsRouter()

    /// A retired model build still sitting in the hub cache, if this device has one. Item-driven so
    /// the sheet can never present before its payload is set, and nil for everyone who never had the
    /// old build — which, since a fresh install has no hub cache at all, is every new user.
    @State private var modelUpdate: ModelSupersession?

    /// The version whose release notes to show at launch, if this launch is the first on a new
    /// version of an existing install. Item-driven for the same reason as `modelUpdate`.
    @State private var whatsNewRelease: WhatsNewRelease?

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                HomeHubView(
                    coordinator: coordinator,
                    onGenerationComplete: {
                        guard !coordinator.generatedCards.isEmpty else { return }
                        pendingSelection = CardSelectionPayload(
                            cards: coordinator.generatedCards,
                            validationResults: coordinator.validationResults,
                            draftImageID: coordinator.draftImageID,
                            draftImages: coordinator.draftImages
                        )
                    },
                    resetToken: homeResetToken
                )
                .opacity(selectedTab == .home ? 1 : 0)
                .allowsHitTesting(selectedTab == .home)

                if visitedTabs.contains(.library) {
                    UnifiedLibraryView(
                        modelManager: coordinator.modelManager,
                        mlxService: coordinator.mlxService
                    )
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                }

                if visitedTabs.contains(.settings) {
                    SettingsView(
                        modelManager: coordinator.modelManager,
                        mlxService: coordinator.mlxService,
                        resetToken: settingsResetToken,
                        route: $settingsRouter.route
                    )
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                visitedTabs.insert(newTab)
                // Pressing Home always lands on the hub root, even when arriving from
                // another tab with screens still pushed on Home's stack.
                if newTab == .home { homeResetToken += 1 }
            }
            // The app-wide ground sits behind all three tabs at once, so switching tabs never
            // crossfades the background. Each tab's own List still has to opt into showing it
            // through (`.themedListScreen()`); on Klar this is the system grouped color either way.
            .themedScreen()

            VStack {
                Spacer()

                if let saveError {
                    Text("Save failed: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                NavBar(
                    selectedTab: $selectedTab,
                    isGenerating: coordinator.isGenerating || BatchQueueService.shared.isRunning,
                    isDownloading: coordinator.mlxService.isLoading,
                    downloadProgress: coordinator.mlxService.downloadProgress,
                    modelTheme: coordinator.mlxService.loadedModel?.theme,
                    onReselect: { tab in
                        // Re-tapping the active tab pops any pushed sub-screen back to
                        // that tab's root view.
                        switch tab {
                        case .home: homeResetToken += 1
                        case .settings: settingsResetToken += 1
                        case .library: break
                        }
                    }
                )
            }
            // The bar's column runs through the bottom safe area so the bar can sit on the screen
            // edge rather than floating above the home indicator; the Spacer takes up the slack and
            // NavBar keeps its own clearance from the indicator.
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay {
            if let pendingIllustration {
                IllustratingDeckView(
                    topic: pendingIllustration.topic,
                    model: coordinator.modelManager.selectedMLXModel,
                    onStudyNow: { openDeck(pendingIllustration) }
                )
                .transition(.opacity)
            }
        }
        // Gamification moments (level up, daily goal, streak milestones, badges, pyramid layers)
        // rise above whichever tab is active. The center decides; this only displays.
        .overlay { CelebrationOverlayHost() }
        .environment(router)
        .environment(settingsRouter)
        // Anyone can ask for a Settings destination by setting the route; the shell is what brings
        // the tab forward to show it.
        .onChange(of: settingsRouter.route) { showSettingsRoute() }
        // The loaded model's brand theme, published once for the whole app. Themes that defer
        // their accent to the model (Klar) resolve their tint from this; the identity-forward
        // themes ignore it and assert their own.
        .environment(\.modelTheme, coordinator.mlxService.loadedModel?.theme)
        .sheet(item: $pendingSelection) { selection in
            CardSelectionView(
                cards: selection.cards,
                topic: coordinator.lastTopic,
                validationResults: selection.validationResults,
                draftImageID: selection.draftImageID,
                draftImages: selection.draftImages,
                onSave: { selected in
                    pendingSelection = nil
                    finalizeSession(with: selected)
                },
                onCancel: {
                    pendingSelection = nil
                    // Nothing will ever adopt these pictures now.
                    coordinator.discardDraftImages()
                }
            )
        }
        .fullScreenCover(item: $router.active) { activity in
            activityCover(activity)
        }
        // Full screen, not a sheet. Setup is the app's first screen, not an interruption laid over
        // it — and a cover has no swipe-to-dismiss, which replaces the old
        // `interactiveDismissDisabled` guard that kept a half-finished check from vanishing.
        .fullScreenCover(isPresented: $showOnboardingWizard) {
            OnboardingWizardView(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService,
                onOpenModelSettings: openModelSettings
            )
        }
        .sheet(item: $modelUpdate, onDismiss: offerNextOnboardingStep) { supersession in
            ModelUpdateSheet(
                supersession: supersession,
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            )
        }
        .sheet(item: $whatsNewRelease) { release in
            WhatsNewSheet(current: release)
        }
        #if DEBUG
        // `-placement.debugOpenReview 1` opens the answer review straight from launch. The screen
        // otherwise sits three taps deep behind the Lernpyramide, and a simulator can be driven by
        // launch arguments but not by taps — so without this the only way to see it is by hand.
        .sheet(isPresented: $showPlacementReview) {
            NavigationStack {
                PlacementReviewView(modelManager: coordinator.modelManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showPlacementReview = false }
                        }
                    }
            }
        }
        // `-level.debugOpenLevel 1` opens Settings ▸ Learning ▸ Your Level, which is otherwise two
        // taps deep. Same reason as the review sheet above.
        .sheet(isPresented: $showLevelSettings) {
            NavigationStack {
                LevelSettingsView(modelManager: coordinator.modelManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showLevelSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showConversationSetup) {
            ConversationSetupView(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            ) { _ in showConversationSetup = false }
        }
        .sheet(item: $debugStory) { story in
            NavigationStack {
                StoryDetailView(
                    story: story,
                    modelManager: coordinator.modelManager,
                    mlxService: coordinator.mlxService
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { debugStory = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showWortschatzHub) {
            NavigationStack {
                WortschatzHubView(coordinator: coordinator)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showWortschatzHub = false }
                        }
                    }
            }
            .environment(router)
            .environment(settingsRouter)
        }
        #endif
        .memoryPressureBanner()
        .memoryReadoutOverlay()
        // The banner above is outside the `.environment(settingsRouter)` applied further in, so
        // it gets its own — its "See what's using memory" link routes through this.
        .environment(settingsRouter)
        .task {
            #if DEBUG
            // `-onboarding.resetWizard 1` clears every first-launch flag plus the stored estimate,
            // so a relaunch lands straight in the wizard — the sim can't be tapped through a reset
            // any other way.
            if UserDefaults.standard.bool(forKey: "onboarding.resetWizard") {
                UserDefaults.standard.removeObject(forKey: "hasSeenOnboardingV2")
                UserDefaults.standard.removeObject(forKey: "hasSeenOnboardingWizard")
                UserDefaults.standard.removeObject(forKey: "hasSeenHeroModelIntro")
                UserDefaults.standard.removeObject(forKey: PlacementService.seenKey)
                PlacementService.clear()
                // The recorded answers are a separate store, and "fresh install" has to mean both
                // — otherwise a reset leaves the review screen full of history and the sim lies.
                PlacementAttemptStore.deleteAll()
                PlacementCoachExport.resetHighWaterMark()
                // The level anchor is part of "fresh install" too — a declared level would
                // otherwise survive the reset and the wizard would open pre-answered.
                UserDefaults.standard.removeObject(forKey: "german.level")
                UserDefaults.standard.removeObject(forKey: "german.level.declared")
                coordinator.modelManager.germanLevel = .a2
                coordinator.modelManager.germanLevelIsDeclared = false
                hasSeenOnboardingV2 = false
                hasSeenOnboardingWizard = false
                hasSeenHeroModelIntro = false
            }
            // `-onboarding.debugV2Only 1` clears *only* the V2 flag, leaving the placement result
            // and the level anchor alone. That's the returning-user path: someone already set up,
            // meeting the new explanation for the first time, whose check steps should self-skip.
            // `resetWizard` can't test it — it wipes the very result the skip depends on.
            if UserDefaults.standard.bool(forKey: "onboarding.debugV2Only") {
                UserDefaults.standard.removeObject(forKey: "hasSeenOnboardingV2")
                hasSeenOnboardingV2 = false
            }
            // `-settings.debugOpenModel 1` fires the deep link at launch. Proves it *pushes* — the
            // only handle on this stack before `SettingsRouter` was one that popped to root.
            if UserDefaults.standard.bool(forKey: "settings.debugOpenModel") {
                openModelSettings()
            }
            PlacementService.applyDebugLaunchArgumentIfNeeded()
            PlacementService.applyDebugAttemptsLaunchArgumentIfNeeded()
            // `-review.debugForce 1` raises the App Store ask without the seven-day streak the real
            // trigger needs — the only way to see that sheet on a simulator.
            ReviewPromptService.shared.applyDebugLaunchArgumentIfNeeded()
            // `-whatsNew.debugForce 1` raises the release-notes sheet on a simulator, which never
            // has an "update" to detect — the only way to see that sheet without shipping.
            WhatsNew.applyDebugLaunchArgumentIfNeeded()
            // `-level.debugDeclare B2` hard-selects a level the way the intro door does, so the
            // "declaring credits nothing" invariant can be checked on a simulator that can't tap.
            // Deliberately writes no `PlacementResult` — that's the whole thing being verified.
            if let raw = UserDefaults.standard.string(forKey: "level.debugDeclare"),
               let level = CEFRLevel(rawValue: raw.uppercased()) {
                coordinator.modelManager.germanLevel = level
                coordinator.modelManager.germanLevelIsDeclared = true
                PlacementService.markOffered()
            }
            if UserDefaults.standard.bool(forKey: "placement.debugOpenReview") {
                showPlacementReview = true
            }
            if UserDefaults.standard.bool(forKey: "level.debugOpenLevel") {
                showLevelSettings = true
            }
            // `-conversation.debugOpenSetup 1` opens New Conversation, which otherwise sits behind
            // Speaking ▸ Conversation ▸ +. Same reason as the two above: the upgrade nudge under
            // the model picker is only reachable by tapping, and this simulator can't.
            if UserDefaults.standard.bool(forKey: "conversation.debugOpenSetup") {
                showConversationSetup = true
            }
            if UserDefaults.standard.bool(forKey: "placement.debugVerify") {
                print(PlacementCoachExport.runDebugVerification(in: modelContext))
            }
            // `-screenshots.debugFill 1` / `-screenshots.debugRestore 1` run Settings ▸ Developer ▸
            // Screenshot Data from launch. The button is three taps deep and this simulator can't
            // tap; on real hardware you'd always use the button.
            if UserDefaults.standard.bool(forKey: "screenshots.debugFill") {
                print("[screenshots] " + ScreenshotDataSeeder.fill(in: modelContext))
            }
            if UserDefaults.standard.bool(forKey: "screenshots.debugRestore") {
                print("[screenshots] restored: \(ScreenshotDataSeeder.restore(in: modelContext))")
            }
            // The Wortschatz box on a simulator that can't tap. `-wortschatz.debugLegacyDecks 1`
            // recreates the three old per-level SRS decks and clears the merge flag, so the merge
            // below has input; `-wortschatz.debugMerge 1` re-runs the merge now;
            // `-wortschatz.debugSeed 1` spreads the merged deck over new / due / known / lapsed
            // (reversible with `-wortschatz.debugRestore 1`).
            if UserDefaults.standard.bool(forKey: "wortschatz.debugOpen") {
                showWortschatzHub = true
            }
            // `-wortschatz.debugOpenSession 1` starts a box session at launch (the player is
            // three taps deep), so the "der · die · das?" front can be checked on a simulator.
            if UserDefaults.standard.bool(forKey: "wortschatz.debugOpenSession"),
               let session = deckStore.wortschatzSession(
                    scope: WortschatzScope.load(), style: WortschatzPrefs.style(),
                    newBudget: WortschatzPrefs.newPerDay(), sessionCap: WortschatzPrefs.sessionCap()
               ) {
                router.launch(.cardDeck(session))
            }
            // `-stories.debugSeed 1` / `-stories.debugOpen 1` / `-stories.debugRemove 1`: an
            // illustrated story without running diffusion, so the reader's three picture layouts
            // can be checked on a simulator that can neither tap nor generate.
            if UserDefaults.standard.bool(forKey: "stories.debugRemove") {
                print("[stories] removed: \(StoryDebugSeeder.remove(in: modelContext))")
            }
            if UserDefaults.standard.bool(forKey: "stories.debugSeed") {
                print("[stories] seeded: \(StoryDebugSeeder.seed(in: modelContext)?.title ?? "failed")")
            }
            if UserDefaults.standard.bool(forKey: "stories.debugOpen") {
                debugStory = StoryDebugSeeder.seed(in: modelContext)
            }
            if UserDefaults.standard.bool(forKey: "wortschatz.debugLegacyDecks") {
                print("[wortschatz] " + WortschatzDebugSeeder.createLegacyDecks(in: modelContext))
            }
            if UserDefaults.standard.bool(forKey: "wortschatz.debugMerge") {
                print("[wortschatz] " + WortschatzDebugSeeder.rerunMerge(in: modelContext))
            }
            if UserDefaults.standard.bool(forKey: "wortschatz.debugSeed") {
                print("[wortschatz] " + WortschatzDebugSeeder.seed(in: modelContext))
            }
            if UserDefaults.standard.bool(forKey: "wortschatz.debugRestore") {
                print("[wortschatz] restored: \(WortschatzDebugSeeder.restore(in: modelContext))")
            }
            #endif

            // One-time roll-up of historical activity durations into the per-day log, so the
            // streak calendar's time totals cover the days that predate time tracking.
            StudyTimeBackfillService.runIfNeeded(in: modelContext)
            // One-time merge of the per-level Goethe SRS decks into the single Wortschatz deck, so
            // a word studied at A1 and again at A2 has one schedule from now on.
            WortschatzMergeService.runIfNeeded(in: modelContext)

            // Watch for system memory warnings for the whole session, not just while a model
            // happens to be loading.
            MemoryPressureMonitor.shared.startMonitoring()

            // Was the last session closed by iOS, a crash, or the app switcher? The marker it
            // left behind says, and lands in the memory log (Settings ▸ Speicher) with the last
            // reading and the screen that was open.
            MemoryDiagnostics.beginSession()

            // A load still marked in-flight means the app went away mid-load last time — on a
            // device that's tight for the model, that's iOS reclaiming it. Say so once.
            if let interrupted = MLXGenerationService.takeInterruptedLoad() {
                MemoryPressureMonitor.shared.noteInterruptedLoad(of: interrupted)
            }

            // A retired model build still in the cache outranks the first-launch intro: those are
            // the learner's gigabytes, and after a retrain ordinary use quietly starts a fresh
            // multi-GB download (GenerationCoordinator auto-loads the selected model), so this has
            // to land ahead of it. Marked seen *before* presenting, so a crash inside the sheet
            // can't turn a one-time offer into a nag. The `return` is what keeps the two sheets
            // mutually exclusive by construction rather than by assumption.
            if let supersession = ModelSupersession.launchPrompt {
                supersession.markUpdateSheetSeen()
                try? await Task.sleep(for: .seconds(0.6))
                modelUpdate = supersession
                return
            }

            offerNextOnboardingStep()
        }
    }

    /// Routes first launch to the onboarding flow, once, ever.
    ///
    /// This used to fork on the legacy flags to keep a half-finished old flow — hero intro seen,
    /// placement never offered — from losing its placement offer. That fork is gone because the
    /// flow itself now handles the case: its check step self-skips only when a stored result
    /// exists, so a legacy mid-state gets the check inside the flow rather than as a separate
    /// sheet afterwards.
    private func offerNextOnboardingStep() {
        // Release notes are asked first, and the two can never both present: the prompt returns
        // nil for exactly the launches where the wizard should run (a fresh install), stamping the
        // version as seen so a new user is never told what changed since a version they never had.
        if let release = WhatsNew.launchPrompt(isFreshInstall: !hasSeenOnboardingV2) {
            offerWhatsNew(release)
            return
        }
        offerWizardIfNeeded()
    }

    /// Marked seen *before* presenting, like every launch sheet here. Delayed for the same reason
    /// as the wizard: this also runs from the supersession sheet's `onDismiss`, and a sheet
    /// presented synchronously while another is still dismissing is dropped.
    private func offerWhatsNew(_ release: WhatsNewRelease) {
        WhatsNew.markSeen()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            whatsNewRelease = release
        }
    }

    /// Presents the flow once, ever. Every flag is written *before* presenting, so a crash inside
    /// it can't turn a one-time offer into a nag — the same discipline the model sheets above use.
    ///
    /// The legacy flags are marked too, so the standalone sheets never auto-fire afterwards and a
    /// downgrade wouldn't re-onboard. `markOffered()` is no longer called here: presentation is
    /// gated on `hasSeenOnboardingV2` alone now, and the flow's own steps write the placement keys
    /// when they run. Marking it here would only claim the check had been offered on runs that
    /// skip it.
    private func offerWizardIfNeeded() {
        guard !hasSeenOnboardingV2 else { return }
        hasSeenOnboardingV2 = true
        hasSeenOnboardingWizard = true
        hasSeenHeroModelIntro = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            showOnboardingWizard = true
        }
    }

    /// Takes the learner to Settings ▸ Model & Downloads.
    ///
    /// Only sets the intent. Switching to the tab is `showSettingsRoute`'s job, so that *every*
    /// caller gets it — a nudge buried three screens down only has the router, not this view's
    /// tab state, and setting a route without switching tabs would push the destination onto a
    /// stack nobody is looking at.
    private func openModelSettings() {
        settingsRouter.route = .model
    }

    /// Brings the Settings tab forward for a route someone asked for.
    ///
    /// Both steps matter. The Settings tab is built lazily (`visitedTabs`), so it has to exist
    /// before a route can be honoured, and `.onChange(of: selectedTab)` inserts it only after the
    /// body pass — too late. Nothing here touches `settingsResetToken`: bumping it would give the
    /// stack a fresh identity and throw the push away.
    private func showSettingsRoute() {
        guard settingsRouter.route != nil else { return }
        visitedTabs.insert(.settings)
        selectedTab = .settings
    }

    // MARK: - Activity presentation

    @ViewBuilder
    private func activityCover(_ activity: Activity) -> some View {
        switch activity {
        case .cardDeck(let session):
            CardDeckView(
                cards: session.cards,
                topic: session.topic,
                deckID: session.deckID,
                validationResults: session.validationResults,
                onQuizComplete: { correct, total, missedIndices, duration, mode, ankiRatings in
                    deckStore.saveQuizResult(
                        deckID: session.deckID,
                        correct: correct, total: total, missedIndices: missedIndices,
                        durationSeconds: duration, mode: mode, ankiRatings: ankiRatings,
                        subDeckLabel: session.subDeckLabel
                    )
                },
                savedCards: session.savedCards,
                flashcardStyle: session.flashcardStyle,
                generatorModel: session.generatorModel,
                autoAdvance: coordinator.modelManager.autoAdvance,
                autoResume: session.autoResume,
                autoStart: session.autoStart,
                badgeLogoName: session.badgeLogoName,
                modelManager: coordinator.modelManager
            )
            .environment(coordinator.mlxService)

        case .grammarMultipleChoice(let category, let showHints):
            GrammarMultipleChoiceView(
                category: category,
                showHints: showHints,
                hapticMode: coordinator.modelManager.hapticFeedbackMode,
                onComplete: { correct, total, durationSeconds in
                    deckStore.saveGrammarQuizResult(
                        correct: correct, total: total, category: category,
                        durationSeconds: durationSeconds
                    )
                    // Drill scores feed the coach's memory: `grammaticalCase` carries the
                    // GrammarFocus raw value for bundled (akkusativ/dativ) and AI categories.
                    if let focus = GrammarFocus(rawValue: category.grammaticalCase) {
                        LearnerMemoryService.applyDrillResult(
                            focus: focus, correct: correct, total: total, in: modelContext
                        )
                    }
                },
                onDismiss: {
                    router.dismiss()
                }
            )

        case .matching(let session):
            MatchingGameView(
                session: session,
                hapticMode: coordinator.modelManager.hapticFeedbackMode,
                onComplete: { result in
                    // Reuse the quiz-result rail: matching slots into per-deck stats and the
                    // streak (via StudyLogService inside saveQuizResult) with no schema change.
                    deckStore.saveQuizResult(
                        deckID: session.deckID,
                        correct: result.firstTryCount, total: result.pairCount, missedIndices: [],
                        durationSeconds: result.durationSeconds, mode: .default, ankiRatings: nil,
                        subDeckLabel: session.subDeckLabel
                    )
                    // Pair-level history: repeat-mistake detection, tricky-pair sampling, and the
                    // learner-profile hand-off. Returns the summary's "missed again" / PB callouts.
                    return MatchingStatsService.recordRound(
                        result,
                        topic: session.topic,
                        feedCoach: coordinator.modelManager.matchingFeedsCoach,
                        in: modelContext
                    )
                },
                onDismiss: {
                    router.dismiss()
                }
            )

        case .articleGame(let session):
            ArticleGameView(
                session: session,
                hapticMode: coordinator.modelManager.hapticFeedbackMode,
                onComplete: { result in
                    // Streak (as grammar practice), the profile's Artikel skill, per-noun
                    // history, and the coach hand-off all live inside recordRound.
                    ArticleGameService.recordRound(
                        result,
                        topic: session.topic,
                        feedCoach: coordinator.modelManager.articleFeedsCoach,
                        in: modelContext
                    )
                },
                onDismiss: {
                    router.dismiss()
                }
            )

        case .prepositionCase(let session):
            PrepositionCaseGameView(
                session: session,
                hapticMode: coordinator.modelManager.hapticFeedbackMode,
                pictureMode: coordinator.modelManager.prepositionPictureMode,
                onComplete: { result in
                    // Streak (as grammar practice), the profile's Präpositionen skill, per-word
                    // history, and the coach hand-off all live inside recordRound.
                    PrepositionService.recordRound(
                        result,
                        topic: session.topic,
                        feedCoach: coordinator.modelManager.prepositionsFeedCoach,
                        in: modelContext
                    )
                },
                onDismiss: {
                    router.dismiss()
                }
            )

        case .cloze(let session):
            ClozePracticeView(
                session: session,
                onComplete: { mastered, missed, durationSeconds in
                    // Correct fills retire the slip (self-heal); the round feeds the streak.
                    LearnerMemoryService.applyClozeResults(
                        mastered: mastered, missed: missed, seconds: durationSeconds,
                        in: modelContext
                    )
                },
                onDismiss: {
                    router.dismiss()
                }
            )
        }
    }

    // MARK: - Generation → study

    /// Persist only the cards the user chose to keep, then launch the deck.
    private func finalizeSession(with selectedCards: [VocabCard]) {
        guard !selectedCards.isEmpty else { return }
        let deck = saveCurrentSession(cards: selectedCards)

        // The cards were already validated (and their articles corrected) right after
        // generation. Carry those results across instead of re-running the check, so the deck
        // screen can still report what was corrected — a second pass would just see clean
        // cards and report nothing.
        let resultsByWord = Dictionary(
            coordinator.validationResults.map { ($0.germanWord.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let results = selectedCards.map { card in
            resultsByWord[card.germanWord.lowercased()]
                ?? ValidationResult(germanWord: card.germanWord, status: .unchecked, dictionaryTranslation: nil)
        }

        let session = StudySession(
            cards: selectedCards,
            topic: coordinator.lastTopic,
            deckID: deck?.persistentModelID,
            validationResults: results,
            savedCards: deck?.cards.sorted { $0.sortOrder < $1.sortOrder } ?? [],
            flashcardStyle: coordinator.modelManager.flashcardStyle,
            generatorRaw: coordinator.lastGeneratorRaw,
            subDeckLabel: nil
        )

        // Any card still without a picture gets one before the deck opens — either because the
        // learner chose `.keptCards` and this is the whole picture run, or because a `.everyCard`
        // run came up short. A run they stopped themselves is left alone.
        if let deck,
           coordinator.modelManager.flashcardIllustrationsEnabled,
           ImageGenModel.current.isDownloaded,
           !coordinator.draftImagesStopped,
           deck.cards.contains(where: { $0.imageFileName == nil }) {
            let job = PendingIllustration(deckUUID: deck.id, session: session, topic: deck.topic)
            pendingIllustration = job
            DeckIllustrationService.launch(
                deckUUID: deck.id,
                topic: deck.topic,
                modelContext: modelContext,
                mlxService: coordinator.mlxService,
                onFinish: { openDeck(job) }
            )
            return
        }

        router.launch(.cardDeck(session))
    }

    /// Drop the picture overlay and start studying. Called both when the run finishes and when the
    /// learner taps "Start studying now" — whichever comes first wins, and the second is a no-op,
    /// so a run the learner walked away from doesn't yank them into the deck later. Pictures that
    /// are still being drawn keep landing on the deck screen as they finish.
    private func openDeck(_ job: PendingIllustration) {
        guard pendingIllustration?.id == job.id else { return }
        pendingIllustration = nil
        router.launch(.cardDeck(job.session))
    }

    @discardableResult
    private func saveCurrentSession(cards: [VocabCard]) -> SavedDeck? {
        let deck = SavedDeck(
            topic: coordinator.lastTopic,
            wordCount: coordinator.lastWordCount,
            includeExamples: coordinator.lastIncludeExamples,
            includeGender: coordinator.lastIncludeGender,
            wordTypeFilter: coordinator.lastWordTypeFilter,
            includeConjugations: coordinator.lastIncludeConjugations,
            selectedTenses: coordinator.lastSelectedTenses,
            vocabCards: cards
        )
        deck.generatorRaw = coordinator.lastGeneratorRaw
        deck.generationTimeSeconds = coordinator.lastGenerationTimeSeconds
        modelContext.insert(deck)
        do {
            try modelContext.save()
            adoptDraftImages(into: deck)
            return deck
        } catch {
            saveError = error.localizedDescription
            print("SwiftData save failed: \(error)")
            return nil
        }
    }

    /// Move the pictures drawn before the review onto the cards that survived it, and throw the
    /// rest away. A card whose file didn't make the move is simply left without one — the deck's
    /// own "Illustrate this deck" button will offer to draw it again.
    private func adoptDraftImages(into deck: SavedDeck) {
        guard let draftID = coordinator.draftImageID, !coordinator.draftImages.isEmpty else { return }
        for card in deck.cards {
            guard let draftFileName = coordinator.draftImages[card.germanWord.lowercased()] else { continue }
            card.imageFileName = CardImageStore.adopt(
                draftFileName: draftFileName, from: draftID, toCard: card.id, in: deck.id
            )
        }
        try? modelContext.save()
        coordinator.discardDraftImages()   // deletes whatever wasn't adopted
    }
}

#Preview {
    ContentView(coordinator: GenerationCoordinator(modelManager: MLXModelManager()))
        .modelContainer(for: SavedDeck.self, inMemory: true)
}
