import DieKarteiCore
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

    @ViewBuilder
    var quizSummaryScreen: some View {
        let correct = cardResults.values.filter { $0 }.count
        let total = cards.count
        let missed = cardResults.filter { !$0.value }.map { $0.key }.sorted()
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

    func advanceOrFinish() {
        if currentIndex < cards.count - 1 {
            isFlipped = false
            currentIndex += 1
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

    func resetQuiz() {
        cardResults = [:]
        currentIndex = 0
        isFlipped = false
        showQuizSummary = false
        sessionStartTime = .now
        elapsedSeconds = 0
    }
}
