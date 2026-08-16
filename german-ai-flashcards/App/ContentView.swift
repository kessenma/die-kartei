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
    @Environment(\.modelContext) private var modelContext

    /// Legacy first-launch flag from when the hero intro was its own sheet. Still read (and set)
    /// so anyone who saw the old flow is never shown the wizard, and still respected by nothing
    /// else — the standalone sheet now only opens from Settings → Model.
    @AppStorage("hasSeenHeroModelIntro") private var hasSeenHeroModelIntro = false

    /// The combined first-launch wizard: hero pitch, then the placement check while the model
    /// downloads. Offered once, ever; devices that can't run the hero start at the check.
    @AppStorage("hasSeenOnboardingWizard") private var hasSeenOnboardingWizard = false
    @State private var showOnboardingWizard = false

    /// A retired model build still sitting in the hub cache, if this device has one. Item-driven so
    /// the sheet can never present before its payload is set, and nil for everyone who never had the
    /// old build — which, since a fresh install has no hub cache at all, is every new user.
    @State private var modelUpdate: ModelSupersession?

    /// The optional placement check. Offered once, after whichever model sheet (if any) has been
    /// dismissed — deliberately *not* gated on `DeviceCapability.canRunHero`, since knowing where a
    /// learner starts has nothing to do with whether their phone can run the hero model.
    @State private var showPlacement = false

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
                        resetToken: settingsResetToken
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
        .sheet(isPresented: $showOnboardingWizard) {
            OnboardingWizardView(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            )
        }
        .sheet(item: $modelUpdate, onDismiss: offerNextOnboardingStep) { supersession in
            ModelUpdateSheet(
                supersession: supersession,
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            )
        }
        .sheet(isPresented: $showPlacement) {
            PlacementQuizView(modelManager: coordinator.modelManager)
        }
        .memoryPressureBanner()
        .task {
            #if DEBUG
            // `-onboarding.resetWizard 1` clears every first-launch flag plus the stored estimate,
            // so a relaunch lands straight in the wizard — the sim can't be tapped through a reset
            // any other way.
            if UserDefaults.standard.bool(forKey: "onboarding.resetWizard") {
                UserDefaults.standard.removeObject(forKey: "hasSeenOnboardingWizard")
                UserDefaults.standard.removeObject(forKey: "hasSeenHeroModelIntro")
                UserDefaults.standard.removeObject(forKey: PlacementService.seenKey)
                PlacementService.clear()
                // The recorded answers are a separate store, and "fresh install" has to mean both
                // — otherwise a reset leaves the review screen full of history and the sim lies.
                PlacementAttemptStore.deleteAll()
                PlacementCoachExport.resetHighWaterMark()
                hasSeenOnboardingWizard = false
                hasSeenHeroModelIntro = false
            }
            PlacementService.applyDebugLaunchArgumentIfNeeded()
            PlacementService.applyDebugAttemptsLaunchArgumentIfNeeded()
            #endif

            // One-time roll-up of historical activity durations into the per-day log, so the
            // streak calendar's time totals cover the days that predate time tracking.
            StudyTimeBackfillService.runIfNeeded(in: modelContext)

            // Watch for system memory warnings for the whole session, not just while a model
            // happens to be loading.
            MemoryPressureMonitor.shared.startMonitoring()

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

    /// Routes first launch to the right offer, once, ever. New installs get the combined wizard;
    /// anyone the old two-sheet flow already reached keeps its semantics — the wizard must never
    /// appear for an existing user, but a legacy mid-state (hero intro seen, placement never
    /// offered) still gets its placement offer.
    private func offerNextOnboardingStep() {
        if hasSeenHeroModelIntro || PlacementService.hasBeenOffered {
            hasSeenOnboardingWizard = true
            offerPlacementIfNeeded()
            return
        }
        offerWizardIfNeeded()
    }

    /// Presents the wizard once, ever. Every flag is written *before* presenting, so a crash
    /// inside the sheet can't turn a one-time offer into a nag — the same discipline the model
    /// sheets above use. Marking the legacy flags too keeps the standalone sheets from ever
    /// auto-firing afterwards.
    private func offerWizardIfNeeded() {
        guard !hasSeenOnboardingWizard else { return }
        hasSeenOnboardingWizard = true
        hasSeenHeroModelIntro = true
        PlacementService.markOffered()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            showOnboardingWizard = true
        }
    }

    /// The legacy placement-only offer, kept for users the old flow half-finished. Marked offered
    /// *before* presenting, same crash-safety rule. Skipping still counts as offered; the check
    /// stays reachable from the pyramid.
    private func offerPlacementIfNeeded() {
        guard !PlacementService.hasBeenOffered else { return }
        PlacementService.markOffered()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            showPlacement = true
        }
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
                autoAdvance: coordinator.modelManager.autoAdvance
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
