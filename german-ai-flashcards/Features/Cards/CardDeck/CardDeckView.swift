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
    var onStartGoetheStudy: (([VocabCard], String, FlashcardStyle, String) -> Void)? = nil
    var resetTrigger: Int = 0
    var autoAdvance: Bool = false
    var isActiveTab: Bool = true

    @Environment(\.modelContext) var modelContext

    @State var localStyle: FlashcardStyle = .default
    @State var currentIndex = 0
    @State var showGermanFirst = true
    @State var hasStarted = false
    @State var isFlipped = false
    @State var showExamplesOnGermanSide = true
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
    /// Leitner right/wrong results (index → correct).
    @State var leitnerResults: [Int: Bool] = [:]
    @State var isPaused: Bool = false
    @State var savedProgress: DeckSessionProgress? = nil
    @State var showValidationInfo = false
    @State var showCorrectionSheet = false
    @State var showSingleCardCorrection = false
    @State var localAutoAdvance: Bool = false
    @State var localCards: [VocabCard] = []
    @State var localValidationResults: [ValidationResult] = []
    @State private var wasAutoPaused: Bool = false

    var isQuizMode: Bool { deckID != nil }
    var isAnkiMode: Bool { localStyle == .anki && !savedCards.isEmpty }
    var isLeitnerMode: Bool { localStyle == .leitner && !savedCards.isEmpty }
    var isSRSMode: Bool { isAnkiMode || isLeitnerMode }

    var cardBadgeLogoName: String? {
        let goetheLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
        guard goetheLevels.contains(where: { topic == "\($0) Vocabulary" }) else { return nil }
        return "logo-goethe-square-icon"
    }

    var currentValidation: ValidationResult? {
        guard currentIndex < localValidationResults.count else { return nil }
        return localValidationResults[currentIndex]
    }

    var currentCard: VocabCard {
        localCards.indices.contains(currentIndex) ? localCards[currentIndex] : cards[currentIndex]
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
            .toolbar {
                if hasStarted && !cards.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 16) {
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

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Front side", selection: $showGermanFirst) {
                                Label("German first", systemImage: "textformat")
                                    .tag(true)
                                Label("English first", systemImage: "textformat.abc")
                                    .tag(false)
                            }

                            Divider()

                            Picker("Show examples on", selection: $showExamplesOnGermanSide) {
                                Label("Examples on German side", systemImage: "d.circle")
                                    .tag(true)
                                Label("Examples on English side", systemImage: "e.circle")
                                    .tag(false)
                            }
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $isFullscreen) {
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
        }
        .onAppear {
            localStyle = flashcardStyle
            localAutoAdvance = autoAdvance
            if localCards.isEmpty { localCards = cards }
            if localValidationResults.isEmpty { localValidationResults = validationResults }
            loadSavedProgress()
        }
        .onChange(of: flashcardStyle) { _, newValue in
            if !hasStarted { localStyle = newValue }
        }
        .onChange(of: cards.count) {
            localStyle = flashcardStyle
            localCards = cards
            localValidationResults = validationResults
            currentIndex = 0
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
        .onChange(of: resetTrigger) {
            localStyle = flashcardStyle
            hasStarted = false
            showQuizSummary = false
            isPaused = false
            wasAutoPaused = false
            currentIndex = 0
            isFlipped = false
            cardResults = [:]
            ankiRatings = [:]
            leitnerResults = [:]
            sessionStartTime = nil
            elapsedSeconds = 0
            savedProgress = nil
            loadSavedProgress()
        }
        .onChange(of: isActiveTab) { _, active in
            guard hasStarted, !showQuizSummary else { return }
            if !active && !isPaused {
                wasAutoPaused = true
                pauseSession()
            } else if active && wasAutoPaused {
                wasAutoPaused = false
                resumeSession()
            }
        }
        .task(id: hasStarted) {
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
