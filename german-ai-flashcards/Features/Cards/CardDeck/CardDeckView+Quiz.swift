import SwiftUI
import SwiftData

extension CardDeckView {

    @ViewBuilder
    var quizButtons: some View {
        HStack(spacing: 40) {
            Button {
                if cardResults[currentIndex] != false { askToWrite(currentIndex) }
                cardResults[currentIndex] = false
                if localAutoAdvance { advanceOrFinish() }
            } label: {
                Image(systemName: cardResults[currentIndex] == false ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
            }

            Button {
                cardResults[currentIndex] = true
                if localAutoAdvance { advanceOrFinish() }
            } label: {
                Image(systemName: cardResults[currentIndex] == true ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
            }
        }
    }

    /// The end-of-session tally, read from whichever results store the active mode actually fills:
    /// Anki → `ankiRatings`, Leitner → `leitnerResults`, quiz/default → `cardResults`. Mirrors the
    /// three `finish*` functions. The shared summary screen used to always read `cardResults`, so
    /// SRS runs (whose results live elsewhere) showed 0% with the wrong total.
    var quizSummaryTally: (correct: Int, total: Int, missed: [Int]) {
        if isSRSMode {
            // Both SRS modes tally lapses per distinct card, since a re-queued card is rated
            // more than once and only counts once against the session.
            let total = sessionDueCount
            let missed = sessionLapses.sorted()
            return (max(0, total - missed.count), total, missed)
        } else {
            let correct = cardResults.values.filter { $0 }.count
            let missed = cardResults.filter { !$0.value }.map { $0.key }.sorted()
            return (correct, playOrder.count, missed)
        }
    }

    @ViewBuilder
    var quizSummaryScreen: some View {
        let tally = quizSummaryTally
        let correct = tally.correct
        let total = tally.total
        let missed = tally.missed
        let percentage = total > 0 ? Int(Double(correct) / Double(total) * 100) : 0

        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: percentage >= 80 ? "star.fill" : percentage >= 50 ? "hand.thumbsup.fill" : "book.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(percentage >= 80 ? .yellow : percentage >= 50 ? .blue : .orange)

                Text(isReviewingMissed ? "Review Complete!" : isAnkiMode ? "Session Complete!" : "Quiz Complete!")
                    .font(.title)
                    .fontWeight(.bold)

                if isAnkiMode {
                    // Four ratings, not right/wrong: lead with how many cards were reviewed and
                    // how they split, and keep "knew it" (anything but Didn't know) as the score.
                    VStack(spacing: 0) {
                        Text("\(total)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text(total == 1 ? "card reviewed" : "cards reviewed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ankiRatingBreakdown

                    Text("Knew \(correct) of \(total) · \(percentage)%")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(correct) / \(total)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))

                    Text("\(percentage)%")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                Label(timerDisplay, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !missed.isEmpty {
                    VStack(spacing: 8) {
                        Text(isAnkiMode ? "Didn't Know" : "Missed Words")
                            .font(.headline)
                            .padding(.bottom, 4)

                        // Two columns meeting at a center line: German set against it from the
                        // left, English from the right, so each pair reads across the line.
                        VStack(spacing: 8) {
                            ForEach(missed, id: \.self) { index in
                                if index < cards.count {
                                    HStack(spacing: 28) {
                                        Text(cards[index].germanWord)
                                            .fontWeight(.medium)
                                            .multilineTextAlignment(.trailing)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                        Text(cards[index].englishTranslation)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .background {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    // The launcher's way on leads; Done (back to the start screen) steps down.
                    onwardButton

                    Button {
                        reviewMissed()
                    } label: {
                        Label("Review Missed Cards", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.bordered)
                    .disabled(missed.isEmpty)

                    Button {
                        resetQuiz()
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        finishedARound = true
                        hasStarted = false
                        isReviewingMissed = false
                        showQuizSummary = false
                        cardResults = [:]
                        currentIndex = 0
                        cardOrder = []
                        cardPosition = 0
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(DoneButtonStyle(prominent: onward == nil))
                }

                Spacer().frame(height: 120)
            }
        }
    }

    /// The order the plain (non-SRS) deck is played in, falling back to deck order whenever the
    /// stored order is stale (deck swapped out from under us). A review of the missed cards plays
    /// only those, so its order is shorter than the deck on purpose.
    var playOrder: [Int] {
        if isReviewingMissed { return cardOrder.filter(cards.indices.contains) }
        return cardOrder.count == cards.count ? cardOrder : Array(cards.indices)
    }

    func advanceOrFinish() {
        let order = playOrder
        if cardPosition < order.count - 1 {
            isFlipped = false
            cardPosition += 1
            currentIndex = order[cardPosition]
        } else {
            finishQuiz()
        }
    }

    func finishQuiz() {
        let correct = cardResults.values.filter { $0 }.count
        let total = playOrder.count
        let missed = cardResults.filter { !$0.value }.map { $0.key }.sorted()
        stampDefaultModeAnswers()
        if isReviewingMissed {
            recordMissedReview(cards: total)
        } else {
            onQuizComplete?(correct, total, missed, elapsedSeconds, localStyle, nil)
            creditDeckMix(mode: localStyle)
        }
        clearPauseProgress()
        showQuizSummary = true
    }

    /// Default mode has no scheduler, but its ✓ and ✗ are still answers: stamp each on its saved
    /// card (`SavedCard.noteReview`, "in any mode"), so the Wortliste and the Schreibblatt and
    /// Zeichnen pickers can say "missed last time" for a learner who never uses Anki or Leitner.
    /// Only the last-answer stamps move; SM-2 and Leitner fields (reviews, lapses, boxes) stay
    /// theirs. Anki and Leitner stamp through their own services, so they are skipped here.
    func stampDefaultModeAnswers() {
        guard localStyle == .default, !cardResults.isEmpty else { return }
        var stamped = false
        for (index, correct) in cardResults where savedCards.indices.contains(index) {
            savedCards[index].noteReview(correct: correct)
            stamped = true
        }
        if stamped { try? modelContext.save() }
    }

    /// "Review Missed Cards": a short round over just the cards the summary lists as missed, in
    /// the same mode, shuffled. SRS ratings still apply, as they do when a missed card is
    /// re-queued mid-session; the round's score is not saved (see `isReviewingMissed`). Its own
    /// summary lists what is still missed, so the learner can go again until nothing is.
    func reviewMissed() {
        let missed = quizSummaryTally.missed.filter(cards.indices.contains)
        guard !missed.isEmpty else { return }
        if isSRSMode, !isReviewingMissed {
            var seen: Set<Int> = []
            fullSessionDueIndices = ankiDueIndices.filter { seen.insert($0).inserted }
        }
        isReviewingMissed = true
        cardResults = [:]
        ankiRatings = [:]
        leitnerResults = [:]
        isFlipped = false
        sessionStartTime = .now
        elapsedSeconds = 0

        let order = missed.shuffled()
        if isSRSMode {
            ankiDueIndices = order
            ankiDuePosition = 0
            resetSessionTally()
        } else {
            cardOrder = order
            cardPosition = 0
        }
        currentIndex = order[0]
        showQuizSummary = false
    }

    /// A review round counts toward today's streak and study time, the part of a finished session
    /// it shares; the scored result stays the session's own.
    func recordMissedReview(cards count: Int) {
        StudyLogService.record(.cards(count), seconds: elapsedSeconds, in: modelContext)
    }

    /// "Try Again": replay the whole session from the top in a fresh random order. Every mode's
    /// results *and* its position have to be cleared — leaving `ankiDuePosition` parked at the end
    /// used to drop you on the last card and finish the session on the first answer.
    func resetQuiz() {
        // From a review's summary, Try Again means the whole session again, not the review.
        if isReviewingMissed {
            isReviewingMissed = false
            if isSRSMode { ankiDueIndices = fullSessionDueIndices }
        }
        cardResults = [:]
        ankiRatings = [:]
        leitnerResults = [:]
        isFlipped = false
        showQuizSummary = false
        sessionStartTime = .now
        elapsedSeconds = 0

        if isSRSMode {
            // Replay the same due set rather than recomputing it: the first pass already
            // rescheduled these cards, so a fresh "what's due" query would come back empty.
            // Drop the re-queued repeats first (keeping first occurrences) so each card is
            // played once, then reshuffle.
            var seen: Set<Int> = []
            ankiDueIndices = ankiDueIndices.filter { seen.insert($0).inserted }.shuffled()
            ankiDuePosition = 0
            currentIndex = ankiDueIndices.first ?? 0
            resetSessionTally()
        } else {
            cardOrder = Array(cards.indices).shuffled()
            cardPosition = 0
            currentIndex = cardOrder.first ?? 0
        }
    }
}

/// The summary's Done: the prominent way out, unless a launcher's way on (`StudyOnward`) leads.
struct DoneButtonStyle: PrimitiveButtonStyle {
    let prominent: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}
