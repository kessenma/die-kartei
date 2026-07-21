import SwiftUI

extension CardDeckView {

    @ViewBuilder
    var quizButtons: some View {
        HStack(spacing: 40) {
            Button {
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
        if isAnkiMode {
            let correct = ankiRatings.values.filter { $0 != .again }.count
            let missed = ankiRatings.filter { $0.value == .again }.map { $0.key }.sorted()
            return (correct, ankiDueIndices.count, missed)
        } else if isLeitnerMode {
            let correct = leitnerResults.values.filter { $0 }.count
            let missed = leitnerResults.filter { !$0.value }.map { $0.key }.sorted()
            return (correct, ankiDueIndices.count, missed)
        } else {
            let correct = cardResults.values.filter { $0 }.count
            let missed = cardResults.filter { !$0.value }.map { $0.key }.sorted()
            return (correct, cards.count, missed)
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

                Text("Quiz Complete!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("\(correct) / \(total)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))

                Text("\(percentage)%")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Label(timerDisplay, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Missed Words")
                            .font(.headline)
                            .padding(.bottom, 4)

                        ForEach(missed, id: \.self) { index in
                            if index < cards.count {
                                HStack {
                                    Text(cards[index].germanWord)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(cards[index].englishTranslation)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Button {
                        // Skeleton: review missed cards
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
                        hasStarted = false
                        showQuizSummary = false
                        cardResults = [:]
                        currentIndex = 0
                        cardOrder = []
                        cardPosition = 0
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer().frame(height: 120)
            }
        }
    }

    /// The order the plain (non-SRS) deck is played in, falling back to deck order whenever the
    /// stored order is stale (deck swapped out from under us).
    var playOrder: [Int] {
        cardOrder.count == cards.count ? cardOrder : Array(cards.indices)
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
        let total = cards.count
        let missed = cardResults.filter { !$0.value }.map { $0.key }.sorted()
        onQuizComplete?(correct, total, missed, elapsedSeconds, localStyle, nil)
        clearPauseProgress()
        showQuizSummary = true
    }

    /// "Try Again": replay the whole session from the top in a fresh random order. Every mode's
    /// results *and* its position have to be cleared — leaving `ankiDuePosition` parked at the end
    /// used to drop you on the last card and finish the session on the first answer.
    func resetQuiz() {
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
            ankiDueIndices = ankiDueIndices.shuffled()
            ankiDuePosition = 0
            currentIndex = ankiDueIndices.first ?? 0
        } else {
            cardOrder = Array(cards.indices).shuffled()
            cardPosition = 0
            currentIndex = cardOrder.first ?? 0
        }
    }
}
