import SwiftUI

// MARK: - Model Theme

/// The brand visual identity for a model, derived from its logo. Use this anywhere a model should
/// pick up its provider's colors — gradient headers, accent tints, chips, glows, progress bars —
/// so the look stays consistent across every screen that mentions the model.
///
/// Colors are grouped by provider (both Gemma tutors share one theme, both Granite tutors
/// another), matching how `logoName` groups the logo assets.
struct ModelTheme {
    /// Brand colors ordered light → deep (roughly top → bottom of the logo). Drives gradients and
    /// the animated mesh in `ModelGradientHero`.
    let palette: [Color]

    /// The single most representative brand color. Use for tints, chips, glows, and shadows.
    let accent: Color

    /// A two-stop linear gradient (light → deep) for simple fills like capsules or strokes.
    var linear: LinearGradient {
        LinearGradient(
            colors: palette.isEmpty ? [accent] : palette,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Recommended foreground color for text/icons drawn directly on top of the gradient.
    var onGradient: Color { .white }
}

extension MLXModel {
    /// This model's brand theme. Reuse it anywhere the model appears.
    var theme: ModelTheme {
        switch self {
        case .appleIntelligence:
            // Iridescent Apple Intelligence glow: pink → violet → indigo → blue → teal.
            ModelTheme(
                palette: [
                    Color(hex: 0xFF5E8A), Color(hex: 0xC95EF2), Color(hex: 0x7A6FF0),
                    Color(hex: 0x46A6FF), Color(hex: 0x5BD6E2),
                ],
                accent: Color(hex: 0xBF5AF2)
            )

        case .gemma4_E4B_german, .gemma4_E2B_german:
            // Google / Gemma soft blue.
            ModelTheme(
                palette: [
                    Color(hex: 0xAECBFA), Color(hex: 0x669DF6),
                    Color(hex: 0x4285F4), Color(hex: 0x1A73E8),
                ],
                accent: Color(hex: 0x4285F4)
            )

        case .granite2B_german, .granite41_3B_german:
            // IBM blue, darker and cooler than Meta's so the two don't read as the same brand.
            ModelTheme(
                palette: [
                    Color(hex: 0x78A9FF), Color(hex: 0x4589FF),
                    Color(hex: 0x0F62FE), Color(hex: 0x0043CE),
                ],
                accent: Color(hex: 0x0F62FE)
            )
        }
    }
}

// MARK: - Color hex helper

extension Color {
    /// Build a color from a 24-bit RGB hex literal, e.g. `Color(hex: 0xFF6B00)`.
    /// `nonisolated` so `nonisolated` value types (e.g. `AppTheme`) can build color tokens off-main.
    nonisolated init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
