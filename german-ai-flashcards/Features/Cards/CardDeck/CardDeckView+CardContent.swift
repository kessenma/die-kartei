import SwiftUI

extension CardDeckView {

    var hasConjugations: Bool {
        if let conjugations = cards[currentIndex].conjugations, !conjugations.isEmpty, isShowingGermanSide {
            return true
        }
        return false
    }

    var isShowingGermanSide: Bool {
        (showGermanFirst && !isFlipped) || (!showGermanFirst && isFlipped)
    }

    var hasExamples: Bool {
        cards.contains { $0.exampleSentence != nil }
    }

    /// The example sentence usually contains the article, so it waits with it.
    var exampleWouldLeakArticle: Bool {
        articleQuiz && isShowingGermanSide && !isFlipped && !revealedCurrent && cards[currentIndex].article != nil
    }

    /// Cards finished this SRS session: the set-out count minus what is still ahead in the queue
    /// (a re-queued card counts once, however often it comes back).
    var srsDoneCount: Int {
        guard ankiDueIndices.indices.contains(ankiDuePosition) else { return sessionDueCount }
        let pending = Set(ankiDueIndices[ankiDuePosition...]).count
        return max(0, sessionDueCount - pending)
    }

    @ViewBuilder
    var cardContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if isSRSMode {
                    Text("\(min(srsDoneCount + 1, sessionDueCount)) / \(sessionDueCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(cardPosition + 1) / \(playOrder.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            if let gap = currentGapQuestion {
                PhraseGapCardView(
                    question: gap,
                    english: cards[currentIndex].englishTranslation,
                    accent: brandAccent
                ) { _, correct in
                    answerGap(correct)
                }
                // A card the session brings back (rated Again) asks afresh.
                .id("gap-\(currentIndex)-\(requeueCounts[currentIndex] ?? 0)")
            } else {
            FlashCardView(
                isFlipped: $isFlipped,
                germanWord: cards[currentIndex].germanWord,
                englishWord: cards[currentIndex].englishTranslation,
                article: currentCard.article,
                showGermanFirst: showGermanFirst,
                badgeLogoName: cardBadgeLogoName,
                model: generatorModel,
                auxiliaryVerb: cards[currentIndex].auxiliaryVerb,
                pastParticiple: cards[currentIndex].pastParticiple,
                isSeparable: cards[currentIndex].isSeparable,
                verbPrefix: cards[currentIndex].verbPrefix,
                isRegular: cards[currentIndex].isRegular,
                exampleSentence: cards[currentIndex].exampleSentence,
                imageFileName: imageFileName(at: currentIndex),
                imageDeckID: imageDeckID(at: currentIndex),
                hidesArticleUntilFlipped: articleQuiz,
                forms: cards[currentIndex].forms,
                onExpandPicture: { picture in
                    expandedPicture = picture
                    showingPicture = true
                }
            )
            .id("\(currentIndex)-\(showGermanFirst)")
            }

            HStack(spacing: 8) {
                if let wordType = cards[currentIndex].wordType, !wordType.isEmpty {
                    Text(wordType.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(wordTypeColor(wordType), in: Capsule())
                }

                if let validation = currentValidation {
                    ValidationBadgeView(result: validation, onTap: {
                        if validation.status.isCorrectable { showSingleCardCorrection = true }
                    })
                }
            }
            .padding(.top, 8)

            if let sentence = cards[currentIndex].exampleSentence,
               cards[currentIndex].auxiliaryVerb == nil,
               // A gap card shows it once answered: before, it would give the word away.
               currentGapQuestion != nil
                   ? isFlipped
                   : isShowingGermanSide == showExamplesOnGermanSide && !exampleWouldLeakArticle {
                HStack(spacing: 6) {
                    highlightedSentence(sentence, vocabWord: cards[currentIndex].germanWord)
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
                                .foregroundStyle(brandAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    if canMakeSentenceCards {
                        Button {
                            makeSentenceCard(sentence)
                        } label: {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.caption)
                                .foregroundStyle(brandAccent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Make this sentence a card")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            if hasConjugations {
                ScrollView {
                    conjugationSection(cards[currentIndex].conjugations!)
                        .padding(.top, 12)
                }
                .frame(maxHeight: 200)
            }

            Spacer()

            if isLeitnerMode && isFlipped {
                leitnerRatingButtons
                    .padding(.bottom, 16)
            } else if isAnkiMode && isFlipped {
                ankiRatingButtons
                    .padding(.bottom, 16)
            } else if isQuizMode && isFlipped {
                quizButtons
                    .padding(.bottom, 16)
            }

            if isLeitnerMode, currentIndex < savedCards.count {
                leitnerBoxBadge(savedCards[currentIndex].leitnerBox)
                    .padding(.bottom, 4)
            }

            if isSRSMode {
                HStack(spacing: 60) {
                    Button(action: previousCard) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                    }
                    .disabled(ankiDuePosition == 0)

                    if !localAutoAdvance {
                        Button(action: isAnkiMode ? ankiAdvance : leitnerAdvance) {
                            Image(systemName: ankiDuePosition >= ankiDueIndices.count - 1 ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                                .font(.system(size: 44))
                        }
                        .disabled(isAnkiMode ? ankiRatings[currentIndex] == nil : leitnerResults[currentIndex] == nil)
                    }
                }
                .padding(.bottom, 90)
            } else {
                HStack(spacing: 60) {
                    Button(action: previousCard) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                    }
                    .disabled(cardPosition == 0)

                    if isQuizMode {
                        if !localAutoAdvance {
                            Button(action: advanceOrFinish) {
                                Image(systemName: cardPosition >= playOrder.count - 1 ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                                    .font(.system(size: 44))
                            }
                            .disabled(cardResults[currentIndex] == nil)
                        }
                    } else {
                        Button(action: nextCard) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 44))
                        }
                        .disabled(cardPosition >= cards.count - 1)
                    }
                }
                .padding(.bottom, 90)
            }
        }
    }

    // MARK: - Sentence cards

    /// A saved deck to add to and a tutor to translate with (not in a deck mix: which deck?).
    var canMakeSentenceCards: Bool {
        savedDeck != nil && !DocumentTutorChoice.downloaded.isEmpty
    }

    /// Opens the inspector on an example sentence; saving it adds a phrase card to this deck.
    func makeSentenceCard(_ sentence: String) {
        guard let deck = savedDeck else { return }
        let model = modelManager.map(DocumentTutorChoice.current) ?? DocumentTutorChoice.downloaded.first
        guard let model else { return }
        let context = modelContext
        sentenceInspector?.tearDown()
        let inspector = WordInspectorModel(
            mlxService: mlxService,
            model: model,
            isWordSaved: { text in
                let key = CardKind.matchKey(text)
                return deck.cards.contains { CardKind.matchKey($0.germanWord) == key }
            },
            onSave: { german, english in
                guard let english, !english.isEmpty else { return }
                DeckCardAdder.add(german: german, english: english, to: deck, context: context)
            }
        )
        sentenceInspector = inspector
        inspector.inspect(sentence)
    }

    // MARK: - Phrase gaps

    /// The gap the current card shows, when it is a phrase card with one and gaps are on.
    var currentGapQuestion: PhraseGapQuestion? {
        guard phraseGaps, cards.indices.contains(currentIndex) else { return nil }
        return gapQuestions[currentIndex]
    }

    /// Deals every phrase card's gap for this session (`PhraseGapPlanner`). Seeded by the deck's
    /// topic, so a card asks the same question each time it comes round in a session.
    func prepareGapQuestions() {
        guard phraseGaps else { gapQuestions = [:]; return }
        let words = cards.map { PhraseGapPlanner.DeckWord(german: $0.germanWord, wordType: $0.wordType) }
        guard words.contains(where: { $0.wordType == CardKind.phrase || CardKind.isPhrase($0.german) }) else {
            gapQuestions = [:]
            return
        }
        let validator = WiktionaryValidator.shared
        let pairs = Set(VerbPrepositionService.all().map { pair in
            "\(pair.verb.split(separator: " ").last.map(String.init) ?? pair.verb) \(pair.preposition)".lowercased()
        })
        var seed: UInt64 = 1_469_598_103_934_665_603
        for byte in topic.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        gapQuestions = PhraseGapPlanner.questions(
            for: words,
            isVerb: { validator.partsOfSpeech(of: $0)?.contains("verb") == true },
            verbPrepositions: pairs,
            seed: seed
        )
    }

    /// A gap answered: the card counts as flipped (so the rating row shows) and the answer becomes
    /// the mode's own result. Quiz and Leitner take it as right or wrong; Anki takes a wrong answer
    /// as Didn't know and leaves Hard / Good / Easy to the learner after a right one. Auto-advance
    /// moves on only after a right answer, once the marked phrase has been seen.
    func answerGap(_ correct: Bool) {
        let index = currentIndex
        isFlipped = true
        // After a beat, so the right answer shows on the card before the sheet covers it.
        if !correct { askToWrite(index, delay: .milliseconds(900)) }
        if isLeitnerMode {
            leitnerResults[index] = correct
        } else if isAnkiMode {
            if !correct { ankiRatings[index] = .again }
        } else if isQuizMode {
            cardResults[index] = correct
        }
        guard correct, localAutoAdvance, !isAnkiMode else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard currentIndex == index, isFlipped else { return }
            if isLeitnerMode { leitnerAdvance() } else if isQuizMode { advanceOrFinish() }
        }
    }

    func highlightedSentence(_ sentence: String, vocabWord: String) -> Text {
        guard let range = sentence.range(of: vocabWord, options: .caseInsensitive) else {
            return Text(sentence)
        }

        let before = String(sentence[sentence.startIndex..<range.lowerBound])
        let match = String(sentence[range])
        let after = String(sentence[range.upperBound..<sentence.endIndex])

        return Text("\(Text(before))\(Text(match).bold().italic(false).underline().foregroundColor(.primary))\(Text(after))")
    }

    func wordTypeColor(_ type: String) -> Color { WordClassPalette.color(for: type) }

    @ViewBuilder
    func conjugationSection(_ conjugations: [Conjugation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(conjugations, id: \.tense) { conjugation in
                VStack(alignment: .leading, spacing: 6) {
                    Text(conjugation.tense)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    HStack(alignment: .top, spacing: 16) {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                            conjugationRow("ich", conjugation.ich)
                            conjugationRow("du", conjugation.du)
                            conjugationRow("er/sie/es", conjugation.erSieEs)
                        }
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                            conjugationRow("wir", conjugation.wir)
                            conjugationRow("ihr", conjugation.ihr)
                            conjugationRow("Sie/sie", conjugation.sieSie)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    func conjugationRow(_ person: String, _ form: String) -> some View {
        GridRow {
            Text(person)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            Text(form)
                .font(.subheadline)
                .fixedSize(horizontal: true, vertical: false)
            Button {
                SpeechService.shared.speak(form)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption2)
                    .foregroundStyle(brandAccent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Picture viewer

    /// The expanded picture, with the session carried over it: this deck's rating buttons for the
    /// active mode and its prev/next, under the same rules as on the card (no advancing before a
    /// rating, nothing forward while auto-advance is on). Attached to this screen rather than to
    /// the card so stepping through the deck doesn't dismiss it.
    @ViewBuilder
    var pictureViewer: some View {
        Group {
            if let expandedPicture {
                FullScreenImageView(
                    image: expandedPicture,
                    caption: pictureViewerCaption,
                    subcaption: isFlipped ? cards[currentIndex].englishTranslation : nil,
                    controls: { AnyView(pictureViewerControls) }
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        // Keyed on the index so stepping through the deck from inside the viewer swaps the picture
        // instead of leaving the first card's one up.
        .task(id: currentIndex) { await loadExpandedPicture() }
    }

    /// What the viewer captions the picture with. The picture is the German side, so the article
    /// quiz's rule holds there too: while the article is withheld, the caption may not carry it.
    var pictureViewerCaption: String {
        // Word from `cards`, article from `currentCard`, the same split `cardContent` uses so an
        // applied correction shows. `showGermanFirst` is in the condition because the quiz only
        // withholds anything when the German side is the question.
        let word = cards[currentIndex].germanWord
        let article = currentCard.article
        let withheld = articleQuiz && showGermanFirst && !isFlipped && !revealedCurrent && article != nil
        return withheld ? ArticleGameService.bareNoun(word) : word.withArticle(article)
    }

    /// Decodes the current card's picture at full size for the viewer. The card underneath holds
    /// its own 512 pt copy; a second bitmap is about 1 MB and only lives while the viewer is up.
    /// A card without a picture closes the viewer rather than leaving a black screen.
    func loadExpandedPicture() async {
        guard let fileName = imageFileName(at: currentIndex),
              let deckID = imageDeckID(at: currentIndex) else {
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

    @ViewBuilder
    var pictureViewerControls: some View {
        VStack(spacing: 14) {
            if isLeitnerMode && isFlipped {
                leitnerRatingButtons
            } else if isAnkiMode && isFlipped {
                ankiRatingButtons
            } else if isQuizMode && isFlipped {
                quizButtons
            }

            HStack(spacing: 28) {
                Button(action: previousCard) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 40))
                }
                .disabled(isSRSMode ? ankiDuePosition == 0 : cardPosition == 0)

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

                if !localAutoAdvance {
                    if isSRSMode {
                        Button(action: isAnkiMode ? ankiAdvance : leitnerAdvance) {
                            Image(systemName: ankiDuePosition >= ankiDueIndices.count - 1 ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                                .font(.system(size: 40))
                        }
                        .disabled(isAnkiMode ? ankiRatings[currentIndex] == nil : leitnerResults[currentIndex] == nil)
                    } else if isQuizMode {
                        Button(action: advanceOrFinish) {
                            Image(systemName: cardPosition >= playOrder.count - 1 ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                                .font(.system(size: 40))
                        }
                        .disabled(cardResults[currentIndex] == nil)
                    } else {
                        Button(action: nextCard) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 40))
                        }
                        .disabled(cardPosition >= cards.count - 1)
                    }
                }
            }
        }
        // The SRS rating buttons are built to fill a card's width; over a picture they would
        // otherwise stretch to an iPad's full screen.
        .frame(maxWidth: 460)
    }

    /// Steps back through the order the session is actually being played in — the due list in SRS
    /// modes, the (possibly shuffled) play order everywhere else.
    func previousCard() {
        if isSRSMode {
            guard ankiDuePosition > 0, ankiDueIndices.indices.contains(ankiDuePosition - 1) else { return }
            isFlipped = false
            ankiDuePosition -= 1
            currentIndex = ankiDueIndices[ankiDuePosition]
        } else {
            let order = playOrder
            guard cardPosition > 0, order.indices.contains(cardPosition - 1) else { return }
            isFlipped = false
            cardPosition -= 1
            currentIndex = order[cardPosition]
        }
    }

    func nextCard() {
        let order = playOrder
        guard order.indices.contains(cardPosition + 1) else { return }
        isFlipped = false
        cardPosition += 1
        currentIndex = order[cardPosition]
    }
}
