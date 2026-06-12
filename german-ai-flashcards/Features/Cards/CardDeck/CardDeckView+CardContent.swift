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

    @ViewBuilder
    var cardContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if isSRSMode {
                    Text("\(ankiDuePosition + 1) / \(ankiDueIndices.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(currentIndex + 1) / \(cards.count)")
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

            FlashCardView(
                isFlipped: $isFlipped,
                germanWord: cards[currentIndex].germanWord,
                englishWord: cards[currentIndex].englishTranslation,
                article: currentCard.article,
                showGermanFirst: showGermanFirst,
                badgeLogoName: cardBadgeLogoName,
                auxiliaryVerb: cards[currentIndex].auxiliaryVerb,
                pastParticiple: cards[currentIndex].pastParticiple,
                isSeparable: cards[currentIndex].isSeparable,
                verbPrefix: cards[currentIndex].verbPrefix,
                isRegular: cards[currentIndex].isRegular,
                exampleSentence: cards[currentIndex].exampleSentence
            )
            .id("\(currentIndex)-\(showGermanFirst)")

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
               isShowingGermanSide == showExamplesOnGermanSide {
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
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
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
                    .disabled(currentIndex == 0)

                    if isQuizMode {
                        if !localAutoAdvance {
                            Button(action: advanceOrFinish) {
                                Image(systemName: currentIndex >= cards.count - 1 ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                                    .font(.system(size: 44))
                            }
                            .disabled(cardResults[currentIndex] == nil)
                        }
                    } else {
                        Button(action: nextCard) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 44))
                        }
                        .disabled(currentIndex >= cards.count - 1)
                    }
                }
                .padding(.bottom, 90)
            }
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

    func wordTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "verb": return .blue
        case "adjective": return .purple
        default: return .green
        }
    }

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
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    func previousCard() {
        if currentIndex > 0 {
            isFlipped = false
            currentIndex -= 1
        }
    }

    func nextCard() {
        if currentIndex < cards.count - 1 {
            isFlipped = false
            currentIndex += 1
        }
    }
}
