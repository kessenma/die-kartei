import SwiftUI

/// The wait between "keep these cards" and the deck opening, while its pictures are drawn.
///
/// Only `CardImageTiming.keptCards` shows this — the other timing has already drawn everything by
/// the time the review appears. It reads `DeckIllustrationService.shared` directly rather than
/// taking progress as parameters, since that service is the single source of truth for the run and
/// the deck's own setup screen reads it the same way.
///
/// "Start studying now" is the escape hatch, not a cancel: the run keeps going in its background
/// task and the pictures land on the cards as they finish.
struct IllustratingDeckView: View {
    var topic: String
    var model: MLXModel
    var onStudyNow: () -> Void

    private var service: DeckIllustrationService { .shared }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 52))
                    .foregroundStyle(model.theme.accent)
                    .symbolEffect(.pulse)

                VStack(spacing: 4) {
                    Text("Drawing Pictures")
                        .font(.title3)
                        .fontWeight(.semibold)
                    if !topic.isEmpty {
                        Text(topic)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                ProgressView(value: service.progress)
                    .tint(model.theme.accent)
                    .frame(maxWidth: 240)
                    .animation(.linear(duration: 0.3), value: service.progress)

                Text(service.totalCount > 0
                     ? "Picture \(min(service.completedCount + 1, service.totalCount)) of \(service.totalCount)"
                     : "Starting up…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text("Your deck is saved. It opens as soon as the pictures are done.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                Button(action: onStudyNow) {
                    Label("Start Studying Now", systemImage: "play.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)

                Text("The rest keep drawing while you study.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
        }
    }
}
