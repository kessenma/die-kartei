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

                if !validationResults.isEmpty {
                    validationSummary
                }

                FlashcardPreviewOptionsView(
                    flashcardStyle: $localStyle,
                    showGermanFirst: $showGermanFirst,
                    showExamplesOnGermanSide: $showExamplesOnGermanSide,
                    autoAdvance: $localAutoAdvance,
                    hasExamples: hasExamples,
                    validationIssues: localValidationResults,
                    cards: cards,
                    onFixIssues: { showCorrectionSheet = true }
                )

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
            AllIssuesCorrectionView(
                cards: $localCards,
                validationResults: $localValidationResults,
                savedCards: savedCards,
                onApplyCorrection: { index, article in applyCorrection(at: index, newArticle: article) }
            )
        }
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

    @ViewBuilder
    private var startButton: some View {
        Button {
            sessionStartTime = .now
            elapsedSeconds = 0
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
            }
            hasStarted = true
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
