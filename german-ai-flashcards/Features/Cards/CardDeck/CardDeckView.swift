import SwiftUI
import SwiftData

struct CardDeckView: View {
    var cards: [VocabCard]
    var topic: String = ""
    var deckID: PersistentIdentifier?
    var validationResults: [ValidationResult] = []
    var onQuizComplete: ((_ correct: Int, _ total: Int, _ missedIndices: [Int], _ durationSeconds: Int, _ mode: FlashcardStyle, _ ankiRatings: [Int: AnkiRating]?) -> Void)?
    /// Saved cards for Anki-style SRS updates; passed when launching from library.
    var savedCards: [SavedCard] = []
    var flashcardStyle: FlashcardStyle = .default
    /// The model that generated this deck, when known. Drives the deck's brand theming.
    var generatorModel: MLXModel? = nil
    var autoAdvance: Bool = false
    /// When true, restore the paused session immediately on appear (Home ▸ Continue), skipping
    /// the setup screen's resume prompt.
    var autoResume: Bool = false
    /// When true, skip the setup screen and begin at once — for launchers that are themselves the
    /// setup screen (the Wortschatz hub). A paused session still wins.
    var autoStart: Bool = false
    /// Badge the card wears when no model logo applies. Falls back to the Goethe mark for
    /// Wortschatz decks (`cardBadgeLogoName`).
    var badgeLogoName: String? = nil
    /// Backs the in-session card settings sheet; nil hides its shortcuts.
    var modelManager: MLXModelManager? = nil

    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var appTheme
    /// Injected at the app root. Needed so an illustrate-this-deck run can free the language
    /// model before loading the diffusion pipeline.
    @Environment(MLXGenerationService.self) var mlxService

    @State var localStyle: FlashcardStyle = .default
    @State var currentIndex = 0
    /// Which side shows first. Shared with Settings ▸ Cards and the setup picker through one key.
    @AppStorage(CardStudyPrefs.germanFirstKey) var showGermanFirst = true
    /// Nouns hide their article on the German side until the flip (der / die / das?).
    @AppStorage(CardStudyPrefs.articleQuizKey) var articleQuiz = true
    /// A card rated Again comes back a few cards later in the same session.
    @AppStorage(CardStudyPrefs.repeatMissedKey) var repeatMissed = true
    @AppStorage(CardStudyPrefs.shuffleKey) var shuffleCards = false
    @State var hasStarted = false
    @State var isFlipped = false
    @State var showExamplesOnGermanSide = true
    /// How AI pictures present on the German side (immersive gradient vs high-contrast bar).
    /// Persisted so the choice sticks across sessions; `FlashCardView` reads the same key.
    @AppStorage(FlashcardImageStyle.defaultsKey) var flashcardImageStyle: FlashcardImageStyle = .immersive
    @State var isFullscreen = false
    @State var cardResults: [Int: Bool] = [:]
    @State var showQuizSummary = false
    @State var sessionStartTime: Date?
    @State var elapsedSeconds: Int = 0
    /// Tracks which cards have been rated in Anki mode (index → rating).
    @State var ankiRatings: [Int: AnkiRating] = [:]
    /// In Anki/Leitner mode, the subset of card indices that are due for review.
    @State var ankiDueIndices: [Int] = []
    /// Position within the ankiDueIndices array.
    @State var ankiDuePosition: Int = 0
    /// How many distinct cards this SRS session set out to review. `ankiDueIndices` grows as
    /// missed cards are re-queued, so it can't serve as the denominator any more.
    @State var sessionDueCount = 0
    /// Card indices missed at least once this session — the summary's "missed" list.
    @State var sessionLapses: Set<Int> = []
    /// How often each card has been put back into the queue (capped so a card can't loop forever).
    @State var requeueCounts: [Int: Int] = [:]
    /// How many cards later a missed card comes back.
    let requeueGap = 3
    @State var showCardSettings = false
    /// The current card has been flipped at least once, so its article is no longer withheld and
    /// the example sentence may show again. Mirrors `FlashCardView.revealed`; resets per card.
    @State var revealedCurrent = false
    /// Play order for plain/quiz mode: position → index into `cards`. Deck order on the first
    /// pass, reshuffled by "Try Again" so a repeat run isn't the same sequence. SRS modes use
    /// `ankiDueIndices`/`ankiDuePosition` for the same job.
    @State var cardOrder: [Int] = []
    /// Position within `playOrder`.
    @State var cardPosition: Int = 0
    /// Leitner right/wrong results (index → correct).
    @State var leitnerResults: [Int: Bool] = [:]
    @State var isPaused: Bool = false
    @State var savedProgress: DeckSessionProgress? = nil
    @State var showValidationInfo = false
    @State var showCorrectionSheet = false
    @State var showSingleCardCorrection = false
    /// Guards the redraw-every-picture button on the setup screen.
    @State var confirmingRedraw = false
    @State var localAutoAdvance: Bool = false
    @State var localCards: [VocabCard] = []
    @State var localValidationResults: [ValidationResult] = []

    var isQuizMode: Bool { deckID != nil }
    var isAnkiMode: Bool { localStyle == .anki && !savedCards.isEmpty }
    var isLeitnerMode: Bool { localStyle == .leitner && !savedCards.isEmpty }
    var isSRSMode: Bool { isAnkiMode || isLeitnerMode }

    /// The generating model's brand theme, when known.
    var deckTheme: ModelTheme? { generatorModel?.theme }
    /// The model's accent, or the app accent for bundled decks with no model.
    var brandAccent: Color { deckTheme?.accent ?? .accentColor }

    /// The session's badge when it brought one, else the Goethe mark for the Wortschatz box.
    var cardBadgeLogoName: String? {
        badgeLogoName ?? (savedDeck?.kind == .goetheSRS ? DeckStore.wortschatzBadge : nil)
    }

    /// Studying the Goethe word box: first ratings count against today's new-word budget.
    var isWortschatzSession: Bool { savedDeck?.kind == .goetheSRS }

    /// Puts a missed card back into the queue a few cards ahead, at most twice per card, and
    /// records the lapse either way. Returns whether the card was actually re-queued.
    @discardableResult
    func requeue(_ idx: Int) -> Bool {
        sessionLapses.insert(idx)
        guard repeatMissed, requeueCounts[idx, default: 0] < 2 else { return false }
        requeueCounts[idx, default: 0] += 1
        let at = min(ankiDuePosition + 1 + requeueGap, ankiDueIndices.count)
        ankiDueIndices.insert(idx, at: at)
        return true
    }

    /// Resets the re-queue bookkeeping for a fresh pass over `ankiDueIndices`.
    func resetSessionTally() {
        sessionDueCount = ankiDueIndices.count
        sessionLapses = []
        requeueCounts = [:]
    }

    var currentValidation: ValidationResult? {
        guard currentIndex < localValidationResults.count else { return nil }
        return localValidationResults[currentIndex]
    }

    var currentCard: VocabCard {
        localCards.indices.contains(currentIndex) ? localCards[currentIndex] : cards[currentIndex]
    }

    // MARK: - Card pictures

    /// The saved deck being studied, when this is a library/saved deck rather than a loose set
    /// of cards. `savedCards` is index-aligned with `cards` (both ordered by `sortOrder`).
    var savedDeck: SavedDeck? { savedCards.first?.deck }

    /// The deck UUID that card pictures are filed under, or nil when there's no saved deck.
    var deckUUID: UUID? { savedDeck?.id }

    /// This card's picture file name, read straight from SwiftData in `body` so pictures that
    /// finish generating in the background pop in without a manual refresh.
    func imageFileName(at index: Int) -> String? {
        savedCards.indices.contains(index) ? savedCards[index].imageFileName : nil
    }

    func applyCorrection(at index: Int, newArticle: String?) {
        guard index < localCards.count else { return }
        if let article = newArticle {
            localCards[index].article = article
        }
        if index < localValidationResults.count {
            localValidationResults[index] = ValidationResult(
                germanWord: localValidationResults[index].germanWord,
                status: .verified,
                dictionaryTranslation: localValidationResults[index].dictionaryTranslation
            )
        }
        if index < savedCards.count {
            if let article = newArticle {
                savedCards[index].article = article
            }
            try? modelContext.save()
        }
    }

    var timerDisplay: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Dismisses the activity cover, persisting an in-progress session first so the deck's
    /// setup screen (and Home ▸ Continue) can offer to resume it.
    private func closeActivity() {
        if hasStarted, !showQuizSummary, !isPaused {
            savePauseProgress()
        }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            VStack {
                if cards.isEmpty {
                    emptyLibraryState
                } else if !hasStarted {
                    setupScreen
                } else if showQuizSummary {
                    quizSummaryScreen
                } else {
                    ZStack {
                        cardContent
                        if isPaused { pauseOverlay }
                    }
                }
            }
            .navigationTitle(hasStarted ? "" : "Flashcards")
            .navigationBarTitleDisplayMode(.inline)
            // The identity themes paint their ground behind the whole player; Klar keeps the exact
            // system background it has always had, so this is a no-op there.
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .tint(brandAccent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            closeActivity()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        if hasStarted && !cards.isEmpty {
                            Button {
                                isFullscreen = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                            Button {
                                isPaused ? resumeSession() : pauseSession()
                            } label: {
                                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            }
                        }
                    }
                }

                if hasStarted && !cards.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Front side", selection: $showGermanFirst) {
                                Label("German first", systemImage: "textformat")
                                    .tag(true)
                                Label("English first", systemImage: "textformat.abc")
                                    .tag(false)
                            }

                            Toggle("Ask der / die / das first", systemImage: "questionmark.circle", isOn: $articleQuiz)

                            Divider()

                            Picker("Show examples on", selection: $showExamplesOnGermanSide) {
                                Label("Examples on German side", systemImage: "d.circle")
                                    .tag(true)
                                Label("Examples on English side", systemImage: "e.circle")
                                    .tag(false)
                            }

                            Divider()

                            Picker("Picture style", selection: $flashcardImageStyle) {
                                ForEach(FlashcardImageStyle.allCases) { style in
                                    Label(style.label, systemImage: style.systemImage).tag(style)
                                }
                            }

                            if modelManager != nil {
                                Divider()

                                Button("All card settings…", systemImage: "slider.horizontal.3") {
                                    showCardSettings = true
                                }
                            }
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $isFullscreen, onDismiss: {
                // Fullscreen steps `currentIndex` in deck order; realign our position with
                // whatever card it left us on so the deck doesn't jump back.
                if isSRSMode {
                    // Re-queued cards appear more than once, so look from the current position
                    // forward first and only then anywhere in the queue.
                    if ankiDueIndices.indices.contains(ankiDuePosition),
                       let pos = ankiDueIndices[ankiDuePosition...].firstIndex(of: currentIndex) {
                        ankiDuePosition = pos
                    } else if let pos = ankiDueIndices.firstIndex(of: currentIndex) {
                        ankiDuePosition = pos
                    }
                } else {
                    cardPosition = playOrder.firstIndex(of: currentIndex) ?? cardPosition
                }
            }) {
                FullscreenCardView(
                    cards: $localCards,
                    currentIndex: $currentIndex,
                    isFlipped: $isFlipped,
                    cardResults: $cardResults,
                    validationResults: $localValidationResults,
                    showGermanFirst: showGermanFirst,
                    showExamplesOnGermanSide: showExamplesOnGermanSide,
                    isQuizMode: isQuizMode,
                    badgeLogoName: cardBadgeLogoName,
                    hidesArticleUntilFlipped: articleQuiz,
                    model: generatorModel,
                    savedCards: savedCards,
                    deckUUID: deckUUID,
                    onApplyCorrection: { index, article in applyCorrection(at: index, newArticle: article) }
                )
            }
            .sheet(isPresented: $showSingleCardCorrection) {
                if localValidationResults.indices.contains(currentIndex) {
                    CorrectionSheetView(
                        germanWord: currentCard.germanWord,
                        englishWord: currentCard.englishTranslation,
                        validationResult: localValidationResults[currentIndex],
                        wordType: currentCard.wordType,
                        onApply: { article in applyCorrection(at: currentIndex, newArticle: article) }
                    )
                }
            }
            .sheet(isPresented: $showCardSettings, onDismiss: {
                // The setup screen mirrors the global style / auto-advance in local state; pick up
                // whatever the sheet changed before the session starts. Mid-session they stay put.
                if !hasStarted, let modelManager {
                    localStyle = modelManager.flashcardStyle
                    localAutoAdvance = modelManager.autoAdvance
                }
            }) {
                if let modelManager {
                    CardSettingsSheet(modelManager: modelManager)
                }
            }
        }
        .onAppear {
            localStyle = flashcardStyle
            localAutoAdvance = autoAdvance
            if localCards.isEmpty { localCards = cards }
            if localValidationResults.isEmpty { localValidationResults = validationResults }
            loadSavedProgress()
            if autoResume, let progress = savedProgress {
                resumeFromSavedProgress(progress)
            }
            // Launchers that are their own setup screen skip ours, unless there is nothing due
            // (the Start button would be disabled for the same reason).
            if autoStart, savedProgress == nil, !hasStarted, !(isSRSMode && srsDueCount == 0) {
                beginSession()
            }
        }
        .onChange(of: flashcardStyle) { _, newValue in
            if !hasStarted { localStyle = newValue }
        }
        .onChange(of: cards.count) {
            localStyle = flashcardStyle
            localCards = cards
            localValidationResults = validationResults
            currentIndex = 0
            cardOrder = []
            cardPosition = 0
            ankiDueIndices = []
            ankiDuePosition = 0
            sessionDueCount = 0
            sessionLapses = []
            requeueCounts = [:]
            hasStarted = false
            isPaused = false
            cardResults = [:]
            showQuizSummary = false
            sessionStartTime = nil
            elapsedSeconds = 0
            savedProgress = nil
            loadSavedProgress()
        }
        .onChange(of: deckID) {
            savedProgress = nil
            loadSavedProgress()
        }
        .onChange(of: isFlipped) { _, flipped in
            if flipped { revealedCurrent = true }
        }
        .onChange(of: currentIndex) {
            revealedCurrent = false
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app mid-session persists position so it survives a hard kill.
            if phase != .active, hasStarted, !showQuizSummary, !isPaused {
                savePauseProgress()
            }
        }
        .onDisappear {
            // Safety net: the cover was dismissed some other way — persist position.
            if hasStarted, !showQuizSummary, !isPaused {
                savePauseProgress()
            }
        }
        .memoryContext("Deck study")
        // Keyed on the summary flag too: the loop exits when the session ends, and "Try Again"
        // only clears that flag — without it in the id the timer would never restart.
        .task(id: "\(hasStarted)-\(showQuizSummary)") {
            guard hasStarted, !showQuizSummary else { return }
            while !Task.isCancelled && hasStarted && !showQuizSummary {
                if !isPaused, let start = sessionStartTime {
                    elapsedSeconds = Int(Date.now.timeIntervalSince(start))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
