import SwiftUI

/// Full-screen viewer for a flashcard's AI picture. Tap anywhere (or the close button) to dismiss;
/// pinch to zoom. Presented from `FlashCardView`'s expand button.
struct FullScreenImageView: View {
    let image: UIImage
    var caption: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

            VStack {
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
                Spacer()
                if let caption {
                    Text(caption)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                }
            }
            .padding(20)
        }
        // Single tap on the backdrop dismisses; the pinch gesture on the image still works.
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }
}
