import SwiftUI

// MARK: - Model Theme

/// The brand visual identity for a model, derived from its logo. Use this anywhere a model should
/// pick up its provider's colors — gradient headers, accent tints, chips, glows, progress bars —
/// so the look stays consistent across every screen that mentions the model.
///
/// Colors are grouped by provider (all Qwen sizes share one theme, all Gemma sizes share one, etc.),
/// matching how `logoName` groups the logo assets.
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

        case .gemma3_1B, .gemma3n_E4B, .gemma4_E4B:
            // Google / Gemma soft blue.
            ModelTheme(
                palette: [
                    Color(hex: 0xAECBFA), Color(hex: 0x669DF6),
                    Color(hex: 0x4285F4), Color(hex: 0x1A73E8),
                ],
                accent: Color(hex: 0x4285F4)
            )

        case .mistral7B:
            // Mistral flame: yellow → orange → red (top → bottom of the logo).
            ModelTheme(
                palette: [
                    Color(hex: 0xFFD200), Color(hex: 0xFF8A00), Color(hex: 0xFF5C00),
                    Color(hex: 0xF1370E), Color(hex: 0xE10500),
                ],
                accent: Color(hex: 0xFF6B00)
            )

        case .qwen3_0_6B, .qwen3_4B, .qwen3_8B:
            // Qwen indigo → violet.
            ModelTheme(
                palette: [
                    Color(hex: 0x8B7FF7), Color(hex: 0x6A5AE8),
                    Color(hex: 0x5B4FD6), Color(hex: 0x4B40B8),
                ],
                accent: Color(hex: 0x615CED)
            )

        case .llama3_2_1B:
            // Meta / LLaMA blue.
            ModelTheme(
                palette: [
                    Color(hex: 0x2AA8FF), Color(hex: 0x0091FF),
                    Color(hex: 0x0A6CF5), Color(hex: 0x0052D9),
                ],
                accent: Color(hex: 0x0668E1)
            )

        case .phi4Mini:
            // Microsoft / Phi four-square: red, green, blue, yellow.
            ModelTheme(
                palette: [
                    Color(hex: 0xF25022), Color(hex: 0x7FBA00),
                    Color(hex: 0x00A4EF), Color(hex: 0xFFB900),
                ],
                accent: Color(hex: 0x00A4EF)
            )
        }
    }
}

// MARK: - Color hex helper

extension Color {
    /// Build a color from a 24-bit RGB hex literal, e.g. `Color(hex: 0xFF6B00)`.
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
