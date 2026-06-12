import DieKarteiCore
import SwiftUI
import SwiftData

extension CardDeckView {

    var leitnerSessionNumber: Int {
        guard let deckID, let deck = modelContext.model(for: deckID) as? SavedDeck else {
            return 0
        }
        return deck.quizResults.count
    }

    var srsDueCount: Int {
        if isAnkiMode {
            return savedCards.filter { card in
                guard let next = card.nextReviewDate else { return true }
                return next <= .now
            }.count
        } else if isLeitnerMode {
            let session = leitnerSessionNumber
            return savedCards.filter { LeitnerService.isDue(box: $0.leitnerBox, sessionNumber: session) }.count
        }
        return cards.count
    }

    @ViewBuilder
    var leitnerSetupInfo: some View {
        let session = leitnerSessionNumber
        let dueCards = LeitnerService.dueCards(in: savedCards, sessionNumber: session)
        let distribution = LeitnerService.boxDistribution(savedCards)

        VStack(spacing: 8) {
            Text("\(dueCards.count) cards due for review")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if dueCards.isEmpty {
                Text("All caught up! Come back later.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                ForEach(distribution, id: \.box) { item in
                    VStack(spacing: 2) {
                        Text("\(item.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text(item.box == 0 ? "New" : "B\(item.box)")
                            .font(.caption2)
                    }
                    .foregroundStyle(leitnerBoxSwiftUIColor(item.box))
                    .frame(minWidth: 32)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(leitnerBoxSwiftUIColor(item.box).opacity(0.12))
                    )
                }
            }
        }
    }

    @ViewBuilder
    var leitnerRatingButtons: some View {
        let isCorrectSelected = leitnerResults[currentIndex] == true
        let isWrongSelected = leitnerResults[currentIndex] == false

        HStack(spacing: 20) {
            Button {
                leitnerResults[currentIndex] = false
                if localAutoAdvance { leitnerAdvance() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isWrongSelected ? "xmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 36))
                    Text("Wrong")
                        .font(.caption)
                        .fontWeight(isWrongSelected ? .bold : .medium)
                    Text("→ Box 1")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(isWrongSelected ? 0.25 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(isWrongSelected ? 0.6 : 0.2), lineWidth: isWrongSelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)

            Button {
                leitnerResults[currentIndex] = true
                if localAutoAdvance { leitnerAdvance() }
            } label: {
                let nextBox = currentIndex < savedCards.count
                    ? min(savedCards[currentIndex].leitnerBox + 1, LeitnerService.maxBox)
                    : 1

                VStack(spacing: 4) {
                    Image(systemName: isCorrectSelected ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 36))
                    Text("Correct")
                        .font(.caption)
                        .fontWeight(isCorrectSelected ? .bold : .medium)
                    Text("→ Box \(nextBox)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(isCorrectSelected ? 0.25 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(isCorrectSelected ? 0.6 : 0.2), lineWidth: isCorrectSelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    func leitnerBoxBadge(_ box: Int) -> some View {
        Text(LeitnerService.boxLabel(box))
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(leitnerBoxSwiftUIColor(box))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(leitnerBoxSwiftUIColor(box).opacity(0.15), in: Capsule())
    }

    func leitnerBoxSwiftUIColor(_ box: Int) -> Color {
        switch box {
        case 0: .gray
        case 1: .red
        case 2: .orange
        case 3: .yellow
        case 4: .green
        case 5: .blue
        default: .gray
        }
    }

    func leitnerAdvance() {
        if let correct = leitnerResults[currentIndex], currentIndex < savedCards.count {
            if correct {
                LeitnerService.markCorrect(savedCards[currentIndex])
            } else {
                LeitnerService.markWrong(savedCards[currentIndex])
            }
            try? modelContext.save()
        }

        if ankiDuePosition < ankiDueIndices.count - 1 {
            isFlipped = false
            ankiDuePosition += 1
            currentIndex = ankiDueIndices[ankiDuePosition]
        } else {
            finishLeitnerSession()
        }
    }

    func finishLeitnerSession() {
        let correct = leitnerResults.values.filter { $0 }.count
        let total = ankiDueIndices.count
        let missed = leitnerResults.filter { !$0.value }.map { $0.key }.sorted()
        onQuizComplete?(correct, total, missed, elapsedSeconds, .leitner, nil)
        clearPauseProgress()
        showQuizSummary = true
    }
}
