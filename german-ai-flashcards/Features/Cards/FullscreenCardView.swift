import DieKarteiCore
import SwiftUI

struct FullscreenCardView: View {
    @Binding var cards: [VocabCard]
    @Binding var currentIndex: Int
    @Binding var isFlipped: Bool
    @Binding var cardResults: [Int: Bool]
    @Binding var validationResults: [ValidationResult]
    let showGermanFirst: Bool
    let showExamplesOnGermanSide: Bool
    let isQuizMode: Bool
    let badgeLogoName: String?
    var onApplyCorrection: ((Int, String?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isRotated = false
    @State private var showCorrectionSheet = false

    private var isShowingGermanSide: Bool {
        (showGermanFirst && !isFlipped) || (!showGermanFirst && isFlipped)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar — always stays upright, never rotated
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(currentIndex + 1) / \(cards.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isRotated.toggle()
                            }
                        } label: {
                            Image(systemName: isRotated ? "rotate.left" : "rotate.right")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Card area — this part rotates
                    ZStack {
                        if isRotated {
                            rotatedCardLayout(containerSize: geo.size)
                        } else {
                            normalCardLayout
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    let threshold: CGFloat = 80

                    if vertical < -threshold && abs(vertical) > abs(horizontal) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            isFlipped.toggle()
                        }
                    } else if horizontal < -threshold {
                        goNext()
                    } else if horizontal > threshold {
                        goPrevious()
                    }

                    withAnimation(.spring(response: 0.3)) {
                        dragOffset = 0
                    }
                }
        )
        .sheet(isPresented: $showCorrectionSheet) {
            if validationResults.indices.contains(currentIndex) {
                CorrectionSheetView(
                    germanWord: cards[currentIndex].germanWord,
                    englishWord: cards[currentIndex].englishTranslation,
                    validationResult: validationResults[currentIndex],
                    wordType: cards[currentIndex].wordType,
                    onApply: { article in
                        if let article {
                            cards[currentIndex].article = article
                        }
                        validationResults[currentIndex].status = .verified
                        onApplyCorrection?(currentIndex, article)
                    }
                )
            }
        }
        .statusBarHidden()
    }

    // MARK: - Rotated layout (card + quiz buttons rotated 90°, no nav buttons)

    @ViewBuilder
    private func rotatedCardLayout(containerSize: CGSize) -> some View {
        // After 90° rotation, the visible width is containerSize.height (minus toolbar)
        // and the visible height is containerSize.width
        let visibleWidth = containerSize.height - 60  // leave room for toolbar
        let visibleHeight = containerSize.width

        VStack(spacing: 12) {
            Spacer()

            FlashCardView(
                isFlipped: $isFlipped,
                germanWord: cards[currentIndex].germanWord,
                englishWord: cards[currentIndex].englishTranslation,
                article: cards[currentIndex].article,
                showGermanFirst: showGermanFirst,
                badgeLogoName: badgeLogoName,
                auxiliaryVerb: cards[currentIndex].auxiliaryVerb,
                pastParticiple: cards[currentIndex].pastParticiple,
                isSeparable: cards[currentIndex].isSeparable,
                verbPrefix: cards[currentIndex].verbPrefix,
                isRegular: cards[currentIndex].isRegular,
                exampleSentence: cards[currentIndex].exampleSentence
            )
            .id("fs-\(currentIndex)-\(showGermanFirst)")
            .frame(maxWidth: visibleHeight - 32) // constrain card width to fit rotated bounds

            if let wordType = cards[currentIndex].wordType, !wordType.isEmpty {
                wordTypeBadge(wordType)
            }

            if isQuizMode && isFlipped {
                quizButtons
            }

            Spacer()
        }
        .frame(width: visibleWidth, height: visibleHeight)
        .rotationEffect(.degrees(90))
        .frame(width: visibleHeight, height: visibleWidth) // override layout frame to match post-rotation size
    }

    // MARK: - Normal (non-rotated) layout

    @ViewBuilder
    private var normalCardLayout: some View {
        VStack {
            Spacer()

            FlashCardView(
                isFlipped: $isFlipped,
                germanWord: cards[currentIndex].germanWord,
                englishWord: cards[currentIndex].englishTranslation,
                article: cards[currentIndex].article,
                showGermanFirst: showGermanFirst,
                badgeLogoName: badgeLogoName,
                auxiliaryVerb: cards[currentIndex].auxiliaryVerb,
                pastParticiple: cards[currentIndex].pastParticiple,
                isSeparable: cards[currentIndex].isSeparable,
                verbPrefix: cards[currentIndex].verbPrefix,
                isRegular: cards[currentIndex].isRegular,
                exampleSentence: cards[currentIndex].exampleSentence
            )
            .id("fs-\(currentIndex)-\(showGermanFirst)")
            .offset(x: dragOffset * 0.3)

            HStack(spacing: 8) {
                if let wordType = cards[currentIndex].wordType, !wordType.isEmpty {
                    wordTypeBadge(wordType)
                }
                if validationResults.indices.contains(currentIndex) {
                    ValidationBadgeView(result: validationResults[currentIndex], onTap: {
                        if validationResults[currentIndex].status.isCorrectable {
                            showCorrectionSheet = true
                        }
                    })
                }
            }
            .padding(.top, 8)

            if let sentence = cards[currentIndex].exampleSentence,
               cards[currentIndex].auxiliaryVerb == nil,
               isShowingGermanSide == showExamplesOnGermanSide {
                HStack(spacing: 6) {
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                        .multilineTextAlignment(.center)

                    if isShowingGermanSide {
                        Button {
                            SpeechService.shared.speak(sentence)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if isShowingGermanSide, let conjugations = cards[currentIndex].conjugations, !conjugations.isEmpty {
                ScrollView {
                    conjugationGrid(conjugations)
                }
                .frame(maxHeight: 180)
            }

            if isQuizMode && isFlipped {
                quizButtons
                    .padding(.top, 12)
            }

            Spacer()

            navButtons
                .padding(.bottom, 40)
        }
    }

    // MARK: - Shared components

    @ViewBuilder
    private var quizButtons: some View {
        HStack(spacing: 40) {
            Button {
                cardResults[currentIndex] = false
            } label: {
                Image(systemName: cardResults[currentIndex] == false ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
            }

            Button {
                cardResults[currentIndex] = true
            } label: {
                Image(systemName: cardResults[currentIndex] == true ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func wordTypeBadge(_ type: String) -> some View {
        Text(type.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(wordTypeColor(type), in: Capsule())
    }

    private func wordTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "verb": return .blue
        case "adjective": return .purple
        default: return .green
        }
    }

    @ViewBuilder
    private func conjugationGrid(_ conjugations: [Conjugation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(conjugations, id: \.tense) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.tense)
                        .font(.caption)
                        .fontWeight(.semibold)
                    HStack(alignment: .top, spacing: 12) {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                            fsConjugationRow("ich", c.ich)
                            fsConjugationRow("du", c.du)
                            fsConjugationRow("er/sie/es", c.erSieEs)
                        }
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                            fsConjugationRow("wir", c.wir)
                            fsConjugationRow("ihr", c.ihr)
                            fsConjugationRow("Sie/sie", c.sieSie)
                        }
                    }
                    .font(.caption2)
                }
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func fsConjugationRow(_ person: String, _ form: String) -> some View {
        GridRow {
            Text(person).foregroundStyle(.secondary)
            Text(form)
            Button {
                SpeechService.shared.speak(form)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var navButtons: some View {
        HStack(spacing: 80) {
            Button(action: goPrevious) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 50))
            }
            .disabled(currentIndex == 0)

            Button(action: goNext) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 50))
            }
            .disabled(currentIndex >= cards.count - 1)
        }
    }

    private func goPrevious() {
        if currentIndex > 0 {
            isFlipped = false
            currentIndex -= 1
        }
    }

    private func goNext() {
        if currentIndex < cards.count - 1 {
            isFlipped = false
            currentIndex += 1
        }
    }
}
