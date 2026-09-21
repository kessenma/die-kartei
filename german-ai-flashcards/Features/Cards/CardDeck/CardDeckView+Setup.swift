import SwiftUI

extension CardDeckView {

    @ViewBuilder
    var setupScreen: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 150))
                        .foregroundStyle(.tint.opacity(0.15))

                    VStack(spacing: 6) {
                        if !topic.isEmpty {
                            Text(topic)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Text("\(cards.count) cards ready")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }

                if !localValidationResults.isEmpty {
                    validationSummary
                }

                FlashcardPreviewOptionsView(
                    flashcardStyle: $localStyle,
                    showGermanFirst: $showGermanFirst,
                    showExamplesOnGermanSide: $showExamplesOnGermanSide,
                    autoAdvance: $localAutoAdvance,
                    hasExamples: hasExamples,
                    cards: cards
                )

                if modelManager != nil {
                    Button {
                        showCardSettings = true
                    } label: {
                        Label("Card settings…", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                    }
                }

                illustrateDeckRow

                if isAnkiMode {
                    let dueCount = savedCards.filter { card in
                        guard let next = card.nextReviewDate else { return true }
                        return next <= .now
                    }.count

                    VStack(spacing: 4) {
                        Text("\(dueCount) cards due for review")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if dueCount == 0 {
                            Text("All caught up! Come back later.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if isLeitnerMode {
                    leitnerSetupInfo
                }

                if let progress = savedProgress {
                    pausedSessionPrompt(progress)
                } else {
                    startButton
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 120)
            .padding(.horizontal)
        }
        .sheet(isPresented: $showValidationInfo) {
            ValidationInfoSheet()
        }
        .sheet(isPresented: $showCorrectionSheet) {
            ValidationReviewView(
                cards: $localCards,
                validationResults: $localValidationResults,
                onApplyCorrection: { index, article in applyCorrection(at: index, newArticle: article) }
            )
        }
    }

    // MARK: - Illustrate this deck

    /// The picture controls for this deck: the style the next pictures are drawn in, an offer to
    /// draw the cards that don't have one yet, and a redraw for decks that are already illustrated
    /// but in a style the learner has since changed their mind about.
    ///
    /// Unlike before, this stays on screen once every card has a picture — a style you can't apply
    /// to a finished deck isn't much of a setting.
    @ViewBuilder
    var illustrateDeckRow: some View {
        let service = DeckIllustrationService.shared
        if ImageGenModel.current.isDownloaded,
           let deckUUID,
           savedDeck?.isBrowsableContent == true,
           !savedCards.isEmpty {

            let missingCount = savedCards.filter { $0.imageFileName == nil }.count
            let drawnCount = savedCards.count - missingCount

            VStack(spacing: 12) {
                CardImageStyleRow(mlxService: mlxService)
                    .frame(maxWidth: 320)

                if service.illustratingDeckUUID == deckUUID {
                    ProgressView(value: service.progress)
                    HStack {
                        Text("Picture \(min(service.completedCount + 1, service.totalCount)) of \(service.totalCount)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { service.stop() }
                            .font(.caption)
                    }
                } else {
                    if missingCount > 0 {
                        Button {
                            launchIllustration(deckUUID: deckUUID, redrawAll: false)
                        } label: {
                            Label("Illustrate this deck", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(service.isRunning)

                        Text("Draws a picture for each of the \(missingCount) cards without one, on-device. You can start studying right away.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if drawnCount > 0 {
                        Button {
                            confirmingRedraw = true
                        } label: {
                            Label("Redraw in this style", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(service.isRunning)

                        Text("Replaces all \(savedCards.count) pictures using the style above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal)
            .alert("Redraw every picture?", isPresented: $confirmingRedraw) {
                Button("Cancel", role: .cancel) {}
                Button("Redraw", role: .destructive) {
                    launchIllustration(deckUUID: deckUUID, redrawAll: true)
                }
            } message: {
                Text("The \(drawnCount) pictures this deck already has are replaced with new ones in your current style. You can stop partway; whatever has been redrawn stays.")
            }
        }
    }

    private func launchIllustration(deckUUID: UUID, redrawAll: Bool) {
        DeckIllustrationService.launch(
            deckUUID: deckUUID,
            topic: topic,
            modelContext: modelContext,
            mlxService: mlxService,
            redrawAll: redrawAll
        )
    }

    @ViewBuilder
    private func pausedSessionPrompt(_ progress: DeckSessionProgress) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("You have a paused session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Card \(progress.cardIndex + 1) of \(cards.count) · \(formattedElapsed(progress.elapsedSeconds))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                resumeFromSavedProgress(progress)
            } label: {
                Label("Continue", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(role: .destructive) {
                savedProgress = nil
                clearPauseProgress()
            } label: {
                Text("Start Fresh")
                    .font(.subheadline)
            }
        }
    }

    /// Starts a fresh session from the top: deck order for plain/quiz play, the due set for SRS.
    /// Shared by the Start button and `autoStart` launches.
    func beginSession() {
        sessionStartTime = .now
        elapsedSeconds = 0
        cardOrder = Array(cards.indices)
        cardPosition = 0
        currentIndex = 0
        if isAnkiMode {
            ankiDueIndices = savedCards.enumerated().compactMap { index, card in
                guard let next = card.nextReviewDate else { return index }
                return next <= .now ? index : nil
            }
            ankiDuePosition = 0
            if !ankiDueIndices.isEmpty {
                currentIndex = ankiDueIndices[0]
            }
        } else if isLeitnerMode {
            let sessionNumber = leitnerSessionNumber
            ankiDueIndices = savedCards.enumerated().compactMap { index, card in
                LeitnerService.isDue(box: card.leitnerBox, sessionNumber: sessionNumber) ? index : nil
            }
            ankiDuePosition = 0
            if !ankiDueIndices.isEmpty {
                currentIndex = ankiDueIndices[0]
            }
        } else {
            ankiDueIndices = []
            ankiDuePosition = 0
        }
        resetSessionTally()
        hasStarted = true
    }

    @ViewBuilder
    private var startButton: some View {
        Button {
            beginSession()
        } label: {
            Label(isSRSMode ? "Start Review" : "Start", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSRSMode && srsDueCount == 0)
    }

    private func formattedElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    var emptyLibraryState: some View {
        Spacer()
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Cards Selected")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Go to the Library tab to pick a deck to study.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        Spacer()
    }
}
