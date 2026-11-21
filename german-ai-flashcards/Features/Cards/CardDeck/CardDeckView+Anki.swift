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
                    if rating == .again, ankiRatings[currentIndex] != .again { askToWrite(currentIndex) }
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

    /// Each card's first rating this session, so the breakdown adds up to the cards reviewed.
    /// Only Didn't know re-queues a card, so a lapsed card's first rating was Didn't know, and
    /// every other card was rated exactly once (that rating still sits in `ankiRatings`).
    /// `ankiRatings` itself holds a re-queued card's *last* rating.
    var ankiFirstRatings: [Int: AnkiRating] {
        var first = ankiRatings.filter { !sessionLapses.contains($0.key) }
        for idx in sessionLapses { first[idx] = .again }
        return first
    }

    /// The Anki summary's centrepiece: four ratings don't fit an n / n score, so show how the
    /// session split across them, as a proportional bar plus a count per button.
    @ViewBuilder
    var ankiRatingBreakdown: some View {
        let counts = Dictionary(grouping: ankiFirstRatings.values, by: { $0 }).mapValues(\.count)
        let rated = AnkiRating.allCases.filter { counts[$0, default: 0] > 0 }
        let sum = rated.reduce(0) { $0 + counts[$1, default: 0] }
        let gap: CGFloat = 2

        VStack(spacing: 12) {
            GeometryReader { geo in
                let usable = max(0, geo.size.width - gap * CGFloat(max(0, rated.count - 1)))
                HStack(spacing: gap) {
                    ForEach(rated, id: \.rawValue) { rating in
                        ankiButtonColor(rating)
                            .frame(width: sum > 0 ? usable * CGFloat(counts[rating, default: 0]) / CGFloat(sum) : 0)
                    }
                }
            }
            .frame(height: 12)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                ForEach(AnkiRating.allCases, id: \.rawValue) { rating in
                    let n = counts[rating, default: 0]
                    VStack(spacing: 2) {
                        Text("\(n)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text(rating.label)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(n > 0 ? ankiButtonColor(rating) : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ankiButtonColor(rating).opacity(n > 0 ? 0.1 : 0.04))
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal)
    }

    func finishAnkiSession() {
        let total = sessionDueCount
        let missed = sessionLapses.sorted()
        let correct = max(0, total - missed.count)
        if isReviewingMissed {
            recordMissedReview(cards: total)
        } else {
            onQuizComplete?(correct, total, missed, elapsedSeconds, .anki, ankiFirstRatings)
            creditDeckMix(mode: .anki)
        }
        clearPauseProgress()
        showQuizSummary = true
    }
}
