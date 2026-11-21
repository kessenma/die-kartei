import SwiftUI

/// Full-screen viewer for a flashcard's AI picture. Tap the backdrop (or the close button) to
/// dismiss; pinch to zoom. Presented from `FlashCardView`'s expand button, or by the deck screen
/// around it when the session's own controls should come along.
struct FullScreenImageView: View {
    let image: UIImage
    var caption: String? = nil
    /// The answer, shown under the caption once the deck has revealed it.
    var subcaption: String? = nil
    /// The deck's own controls — grading, prev/next, reveal — kept over the picture so looking at
    /// one properly doesn't mean leaving the session. Erased because each deck screen passes a
    /// different set, and built only once the viewer is up. `nil` leaves this a plain viewer.
    var controls: (() -> AnyView)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack {
            // The backdrop is the only thing a bare tap dismisses, so a miss between the controls
            // doesn't throw the learner out of the session.
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(max(scale * pinch, 1))
                .gesture(
                    MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { value in scale = min(max(scale * value, 1), 4) }
                )
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(11)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    Spacer()
                }
                .padding(20)

                Spacer()

                VStack(spacing: 14) {
                    if let caption {
                        VStack(spacing: 2) {
                            Text(caption)
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                            if let subcaption {
                                Text(subcaption)
                                    .font(.system(size: 17, weight: .semibold, design: .serif))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .environment(\.colorScheme, .dark)
                    }

                    if let controls {
                        controls()
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            // The deck's buttons are drawn for a light card; over a picture they
                            // sit on dark material, where their secondary text needs dark mode.
                            .environment(\.colorScheme, .dark)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
