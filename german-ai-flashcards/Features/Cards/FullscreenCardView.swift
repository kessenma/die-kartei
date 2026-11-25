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
    /// "der / die / das?" — withhold a noun's article on the German side until the flip.
    var hidesArticleUntilFlipped: Bool = false
    var model: MLXModel? = nil
    /// Index-aligned with `cards`; supplies each card's picture file name. Empty for loose decks.
    var savedCards: [SavedCard] = []
    /// The deck the pictures are filed under, or nil when there's no saved deck.
    var deckUUID: UUID? = nil
    var onApplyCorrection: ((Int, String?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var dragOffset: CGFloat = 0
    @State private var isRotated = false
    @State private var showCorrectionSheet = false
    /// The current card has been flipped at least once here; the example may show again.
    @State private var revealedCurrent = false
    /// The expanded picture lives here, not in the card: the card view is rebuilt per index, so a
    /// cover it owned would close itself the moment the learner pressed next inside it.
    @State private var expandedPicture: UIImage?
    @State private var showingPicture = false
    /// iPad: a card marked wrong asks to be written out with the Pencil (`WriteItSheet`).
    @AppStorage(CardStudyPrefs.writeAfterMissKey) private var writeAfterMiss = true
    @State private var writeItWord: WriteItWord?

    private var isShowingGermanSide: Bool {
        (showGermanFirst && !isFlipped) || (!showGermanFirst && isFlipped)
    }

    /// The example sentence usually contains the article, so it waits with it.
    private var exampleWouldLeakArticle: Bool {
        hidesArticleUntilFlipped && isShowingGermanSide && !isFlipped && !revealedCurrent && cards[currentIndex].article != nil
    }

    /// The current card's picture file name, when this deck has saved cards backing it.
    private var currentImageFileName: String? {
        savedCards.indices.contains(currentIndex) ? savedCards[currentIndex].imageFileName : nil
    }

    /// The folder this card's picture is filed under: its own deck's, since a deck mix or the
    /// Daily Review holds cards from many decks.
    private var currentImageDeckID: UUID? {
        savedCards.indices.contains(currentIndex) ? savedCards[currentIndex].deck?.id ?? deckUUID : deckUUID
    }

    /// What the picture viewer captions with. The picture is the German side, so the article quiz's
    /// rule holds there too: while the article is withheld, the caption may not carry it.
    private var viewerCaption: String {
        let card = cards[currentIndex]
        // Same four conditions as the card's own `articleHidden`, `showGermanFirst` included: the
        // quiz only withholds anything when the German side is the question.
        let withheld = hidesArticleUntilFlipped && showGermanFirst
            && !isFlipped && !revealedCurrent && card.article != nil
        return withheld
            ? ArticleGameService.bareNoun(card.germanWord)
            : card.germanWord.withArticle(card.article)
    }

    /// The answer, once the learner has turned the card over in the viewer.
    private var viewerSubcaption: String? {
        isFlipped ? cards[currentIndex].englishTranslation : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Klar keeps the plain system background; the identity themes paint their ground.
                if appTheme == .klar {
                    Color(.systemBackground).ignoresSafeArea()
                } else {
                    ThemedBackground().ignoresSafeArea()
                }

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
        .fullScreenCover(isPresented: $showingPicture) {
            Group {
                if let expandedPicture {
                    FullScreenImageView(
                        image: expandedPicture,
                        caption: viewerCaption,
                        subcaption: viewerSubcaption,
                        controls: { AnyView(pictureViewerControls) }
                    )
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            // Keyed on the index so stepping through the deck from inside the viewer swaps the
            // picture instead of leaving the first card's one up.
            .task(id: currentIndex) { await loadExpandedPicture() }
        }
        .writeItSheet($writeItWord, accent: model?.theme.accent ?? .accentColor)
        .statusBarHidden()
        .onChange(of: isFlipped) { _, flipped in
            if flipped { revealedCurrent = true }
        }
        .onChange(of: currentIndex) {
            revealedCurrent = false
        }
    }

    /// Decodes the current card's picture at full size for the viewer. The card underneath holds
    /// its own 512 pt copy; a second bitmap is about 1 MB and only lives while the viewer is up.
    /// A card without a picture closes the viewer rather than leaving a black screen.
    private func loadExpandedPicture() async {
        guard let fileName = currentImageFileName, let deckID = currentImageDeckID else {
            expandedPicture = nil
            showingPicture = false
            return
        }
        let decoded = await Task.detached(priority: .userInitiated) {
            CardImageStore.loadImage(fileName: fileName, deckID: deckID, maxPixelSize: 1024)
        }.value
        guard !Task.isCancelled else { return }
        expandedPicture = decoded
        if decoded == nil { showingPicture = false }
    }

    /// The session's controls, carried into the picture viewer: turn the card over, grade it, move
    /// on. Prev/next step `currentIndex`, which the cover survives because it belongs to this
    /// screen rather than to the card.
    @ViewBuilder
    private var pictureViewerControls: some View {
        VStack(spacing: 14) {
            if isQuizMode && isFlipped {
                quizButtons
            }

            HStack(spacing: 28) {
                Button(action: goPrevious) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 40))
                }
                .disabled(currentIndex == 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isFlipped.toggle() }
                } label: {
                    Text(isFlipped ? "Question" : "Answer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: goNext) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 40))
                }
                .disabled(currentIndex >= cards.count - 1)
            }
        }
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
                model: model,
                auxiliaryVerb: cards[currentIndex].auxiliaryVerb,
                pastParticiple: cards[currentIndex].pastParticiple,
                isSeparable: cards[currentIndex].isSeparable,
                verbPrefix: cards[currentIndex].verbPrefix,
                isRegular: cards[currentIndex].isRegular,
                exampleSentence: cards[currentIndex].exampleSentence,
                imageFileName: currentImageFileName,
                imageDeckID: currentImageDeckID,
                hidesArticleUntilFlipped: hidesArticleUntilFlipped,
                forms: cards[currentIndex].forms,
                onExpandPicture: { picture in
                    expandedPicture = picture
                    showingPicture = true
                }
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
                model: model,
                auxiliaryVerb: cards[currentIndex].auxiliaryVerb,
                pastParticiple: cards[currentIndex].pastParticiple,
                isSeparable: cards[currentIndex].isSeparable,
                verbPrefix: cards[currentIndex].verbPrefix,
                isRegular: cards[currentIndex].isRegular,
                exampleSentence: cards[currentIndex].exampleSentence,
                imageFileName: currentImageFileName,
                imageDeckID: currentImageDeckID,
                hidesArticleUntilFlipped: hidesArticleUntilFlipped,
                forms: cards[currentIndex].forms,
                onExpandPicture: { picture in
                    expandedPicture = picture
                    showingPicture = true
                }
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
               isShowingGermanSide == showExamplesOnGermanSide,
               !exampleWouldLeakArticle {
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
                if cardResults[currentIndex] != false, writeAfterMiss, CardStudyPrefs.writeAfterMissAvailable {
                    let card = cards[currentIndex]
                    writeItWord = WriteItWord(german: card.germanWord.withArticle(card.article),
                                              english: card.englishTranslation)
                }
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

    private func wordTypeColor(_ type: String) -> Color { WordClassPalette.color(for: type) }

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
