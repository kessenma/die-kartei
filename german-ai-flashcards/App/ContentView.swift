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

    /// One-time first-launch intro for the hero model — shown only on devices that can run it, so we
    /// never lead with a download the hardware can't handle. Toggle the `.task` below off to disable
    /// the auto-show; the wizard stays reachable from Settings → Model.
    @AppStorage("hasSeenHeroModelIntro") private var hasSeenHeroModelIntro = false
    @State private var showHeroModelIntro = false

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
        .environment(router)
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
        .sheet(isPresented: $showHeroModelIntro) {
            HeroModelIntroSheet(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            )
        }
        .task {
            // First-launch soft intro for the hero model, capable devices only. Remove this block
            // to disable the auto-show; the wizard stays reachable from Settings → Model.
            guard !hasSeenHeroModelIntro, DeviceCapability.canRunHero else { return }
            hasSeenHeroModelIntro = true
            try? await Task.sleep(for: .seconds(0.6))
            showHeroModelIntro = true
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
                onComplete: { correct, total in
                    deckStore.saveGrammarQuizResult(correct: correct, total: total, category: category)
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

        case .cloze(let session):
            ClozePracticeView(
                session: session,
                onComplete: { mastered, missed in
                    // Correct fills retire the slip (self-heal); the round feeds the streak.
                    LearnerMemoryService.applyClozeResults(
                        mastered: mastered, missed: missed, in: modelContext
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
