import SwiftUI

/// A compact loading indicator built around a model's brand logo: the logo sits inside a ring that
/// either fills with the real download fraction or spins while indeterminate (connecting / loading
/// into memory). Small and self-contained, so it can live inline in a card without taking over the
/// screen.
struct ModelLoadingIndicator: View {
    let model: MLXModel
    /// Real download fraction (0…1), or `nil` for the indeterminate phases (spins).
    let progress: Double?
    var size: CGFloat = 30

    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.22), lineWidth: 2.5)

            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }

            model.logoImage
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.58, height: size * 0.58)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityHidden(true)
    }
}
