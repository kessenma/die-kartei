import SwiftUI

/// Full-sheet brand background for a model: a white (system) base plus a soft `MeshGradient` wash
/// built from the model's brand palette (`MLXModel.theme`) that spans the entire sheet — a light
/// tint at the top deepening to full color at the bottom.
///
/// Apply behind a `List` that has `.scrollContentBackground(.hidden)`, and place a `ModelLogoMark`
/// in the last section so the logo sits over the densest part of the wash.
struct ModelSheetBackground: View {
    /// Stored as a theme rather than a model so non-`MLXModel` sheets (the image model's card) can
    /// use the same background. Language models keep the `init(model:)` spelling.
    let theme: ModelTheme
    /// `nil` follows the Reduce Motion setting; pass `false` to force a still wash.
    var animated: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(theme: ModelTheme, animated: Bool? = nil) {
        self.theme = theme
        self.animated = animated
    }

    init(model: MLXModel, animated: Bool? = nil) {
        self.init(theme: model.theme, animated: animated)
    }

    var body: some View {
        let isAnimated = animated ?? !reduceMotion
        ZStack {
            Color(.systemBackground)
            ModelBrandWash(palette: theme.palette, animated: isAnimated)
                .mask(
                    // Present (faint) at the very top, deepening to full color at the bottom.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.12), location: 0.0),
                            .init(color: .black.opacity(0.22), location: 0.45),
                            .init(color: .black.opacity(0.60), location: 0.80),
                            .init(color: .black, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }
}

/// The model's logo at a fixed size, centered, with a soft white glow so it lifts off the brand
/// color — no tile, no border. Meant for the last section of a model sheet, over the deepest part
/// of `ModelSheetBackground`.
struct ModelLogoMark: View {
    let model: MLXModel
    var height: CGFloat = 168

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            logo.padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(model.rawValue) logo")
    }

    @ViewBuilder
    private var logo: some View {
        Group {
            if model.usesSFSymbolLogo {
                Image(systemName: model.sfSymbolLogo)
                    .font(.system(size: 60))
                    .symbolRenderingMode(.multicolor)
            } else {
                model.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            }
        }
        .background(
            // A single soft white halo so the logo lifts off its brand color — no second ring.
            Circle()
                .fill(.white)
                .blur(radius: 26)
                .opacity(0.65)
                .scaleEffect(1.7)
        )
    }
}

// MARK: - Animated brand wash

/// A 3×3 `MeshGradient` whose interior points drift slowly. Colors run from the lightest brand color
/// at the top row to the deepest at the bottom row; the caller controls where it shows (and the fade
/// direction) by applying its own `.mask(...)`. Calm by design — small amplitudes, slow speeds.
/// Reused by the model sheet background and the conversation top wash.
struct ModelBrandWash: View {
    let palette: [Color]
    var animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation) { timeline in
                mesh(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            mesh(at: 0)
        }
    }

    private func mesh(at t: TimeInterval) -> some View {
        MeshGradient(width: 3, height: 3, points: points(at: t), colors: meshColors)
    }

    /// Light brand colors in the top row, deepest in the bottom row, so the wash darkens downward.
    private var meshColors: [Color] {
        let p = palette.isEmpty ? [.gray] : palette
        func c(_ i: Int) -> Color { p[min(i, p.count - 1)] }
        return [
            c(0), c(1), c(0),
            c(1), c(2), c(1),
            c(2), c(3), c(2),
        ]
    }

    /// Edges stay pinned (no gaps); the center and bottom-middle drift gently.
    private func points(at t: TimeInterval) -> [SIMD2<Float>] {
        func w(_ base: Float, _ amp: Float, _ speed: Double, _ phase: Double) -> Float {
            base + amp * Float(sin(t * speed + phase))
        }
        return [
            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
            [0.0, 0.5],
            [w(0.5, 0.10, 0.42, 0.0), w(0.5, 0.07, 0.36, 1.0)],
            [1.0, 0.5],
            [0.0, 1.0],
            [w(0.5, 0.10, 0.38, 2.4), 1.0],
            [1.0, 1.0],
        ]
    }
}

// MARK: - Preview

#Preview("Sheet background + logo") {
    NavigationStack {
        List {
            Section {
                Text(MLXModel.hero.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Label("View on HuggingFace", systemImage: "arrow.up.right.square")
                Label("Learn more about \(MLXModel.hero.rawValue)", systemImage: "globe")
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ModelLogoMark(model: .hero)
        }
        .background {
            ModelSheetBackground(model: .hero)
        }
    }
}
