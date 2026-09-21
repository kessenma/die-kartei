import SwiftUI
import SwiftData

extension CardDeckView {

    @ViewBuilder
    var ankiRatingButtons: some View {
        let previews = SpacedRepetitionService.previewIntervals(
            for: currentIndex < savedCards.count ? savedCards[currentIndex] : savedCards[0]
        )

        VStack(spacing: 8) {
        Text("Only Didn't know counts as a miss. Hard, Good and Easy all mean you knew it.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
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
            let card = savedCards[currentIndex]
            let firstRating = card.totalReviews == 0
            SpacedRepetitionService.apply(rating: rating, to: card)
            try? modelContext.save()
            if firstRating, isWortschatzSession {
                StudyLogService.recordNewWords(1, in: modelContext)
            }
            // A miss comes back a few cards later. Ratings are keyed by card index, so clear this
            // one or the stale Again would pre-select the button (and enable Next) on its return.
            // Applying SM-2 again when the card comes back is intended.
            if rating == .again, requeue(currentIndex) {
                ankiRatings[currentIndex] = nil
            }
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
        let total = sessionDueCount
        let missed = sessionLapses.sorted()
        let correct = max(0, total - missed.count)
        onQuizComplete?(correct, total, missed, elapsedSeconds, .anki, ankiRatings)
        clearPauseProgress()
        showQuizSummary = true
    }
}
