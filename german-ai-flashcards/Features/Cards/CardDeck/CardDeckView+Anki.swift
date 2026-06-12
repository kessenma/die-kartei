import DieKarteiCore
import SwiftUI
import SwiftData

extension CardDeckView {

    @ViewBuilder
    var ankiRatingButtons: some View {
        let previews = SpacedRepetitionService.previewIntervals(
            for: currentIndex < savedCards.count ? savedCards[currentIndex] : savedCards[0]
        )

        HStack(spacing: 12) {
            ForEach(AnkiRating.allCases, id: \.rawValue) { rating in
                let preview = previews.first { $0.rating == rating }
                let isSelected = ankiRatings[currentIndex] == rating

                Button {
                    ankiRatings[currentIndex] = rating
                    if localAutoAdvance { ankiAdvance() }
                } label: {
                    VStack(spacing: 4) {
                        Text(rating.label)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .bold : .medium)
                        Text(preview?.label ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ankiButtonColor(rating).opacity(isSelected ? 0.25 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(ankiButtonColor(rating).opacity(isSelected ? 0.6 : 0.2), lineWidth: isSelected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(ankiButtonColor(rating))
            }
        }
        .padding(.horizontal)
    }

    func ankiButtonColor(_ rating: AnkiRating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    func ankiAdvance() {
        if let rating = ankiRatings[currentIndex], currentIndex < savedCards.count {
            SpacedRepetitionService.apply(rating: rating, to: savedCards[currentIndex])
            try? modelContext.save()
        }

        if ankiDuePosition < ankiDueIndices.count - 1 {
            isFlipped = false
            ankiDuePosition += 1
            currentIndex = ankiDueIndices[ankiDuePosition]
        } else {
            finishAnkiSession()
        }
    }

    func finishAnkiSession() {
        let correct = ankiRatings.values.filter { $0 != .again }.count
        let total = ankiDueIndices.count
        let missed = ankiRatings.filter { $0.value == .again }.map { $0.key }.sorted()
        onQuizComplete?(correct, total, missed, elapsedSeconds, .anki, ankiRatings)
        clearPauseProgress()
        showQuizSummary = true
    }
}
