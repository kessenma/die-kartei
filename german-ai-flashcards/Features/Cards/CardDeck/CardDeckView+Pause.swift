import SwiftUI
import SwiftData

extension CardDeckView {

    // MARK: - Pause / Resume

    func pauseSession() {
        isPaused = true
        sessionStartTime = nil
        savePauseProgress()
    }

    func resumeSession() {
        sessionStartTime = Date.now - TimeInterval(elapsedSeconds)
        isPaused = false
    }

    func startOver() {
        isPaused = false
        hasStarted = false
        currentIndex = 0
        isFlipped = false
        cardResults = [:]
        ankiRatings = [:]
        leitnerResults = [:]
        sessionStartTime = nil
        elapsedSeconds = 0
        savedProgress = nil
        clearPauseProgress()
    }

    // MARK: - Persistence

    func loadSavedProgress() {
        guard let deckID,
              let deck = fetchDeck(for: deckID),
              let data = deck.pausedProgressData,
              let progress = try? JSONDecoder().decode(DeckSessionProgress.self, from: data),
              progress.cardIndex < cards.count
        else { return }
        savedProgress = progress
    }

    func savePauseProgress() {
        guard let deckID, let deck = fetchDeck(for: deckID) else { return }
        let progress = DeckSessionProgress(
            cardIndex: currentIndex,
            elapsedSeconds: elapsedSeconds,
            studyModeRaw: localStyle.rawValue,
            cardResults: cardResults.isEmpty ? nil : cardResults,
            ankiRatingValues: ankiRatings.isEmpty ? nil : ankiRatings.mapValues { $0.rawValue },
            leitnerResults: leitnerResults.isEmpty ? nil : leitnerResults,
            ankiDueIndices: ankiDueIndices.isEmpty ? nil : ankiDueIndices,
            ankiDuePosition: isSRSMode ? ankiDuePosition : nil,
            cardGermanWords: cards.map { $0.germanWord }
        )
        deck.pausedProgressData = try? JSONEncoder().encode(progress)
        deck.pausedAt = .now
        try? modelContext.save()
    }

    func clearPauseProgress() {
        guard let deckID, let deck = fetchDeck(for: deckID) else { return }
        deck.pausedProgressData = nil
        deck.pausedAt = nil
        try? modelContext.save()
    }

    func resumeFromSavedProgress(_ progress: DeckSessionProgress) {
        currentIndex = progress.cardIndex
        elapsedSeconds = progress.elapsedSeconds
        if let style = FlashcardStyle(rawValue: progress.studyModeRaw) { localStyle = style }
        cardResults = progress.cardResults ?? [:]
        if let rawRatings = progress.ankiRatingValues {
            ankiRatings = rawRatings.compactMapValues { AnkiRating(rawValue: $0) }
        }
        leitnerResults = progress.leitnerResults ?? [:]
        ankiDueIndices = progress.ankiDueIndices ?? []
        ankiDuePosition = progress.ankiDuePosition ?? 0
        sessionStartTime = Date.now - TimeInterval(elapsedSeconds)
        savedProgress = nil
        clearPauseProgress()
        hasStarted = true
    }

    private func fetchDeck(for id: PersistentIdentifier) -> SavedDeck? {
        try? modelContext.fetch(FetchDescriptor<SavedDeck>()).first { $0.persistentModelID == id }
    }

    // MARK: - Pause Overlay

    @ViewBuilder
    var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Paused")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text("Card \(currentIndex + 1) of \(cards.count) · \(timerDisplay)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }

                VStack(spacing: 12) {
                    Button {
                        resumeSession()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        startOver()
                    } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                }
            }
            .padding(40)
        }
    }
}
