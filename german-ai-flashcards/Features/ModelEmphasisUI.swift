import SwiftUI

// Shared visual language for promoting the hero model across every model picker, so the emphasis
// looks identical on Home, Settings, the conversation setup, and the model guide.

/// The badge that marks the app's hero model wherever it appears in a list.
struct RecommendedBadge: View {
    var text: String = "Recommended"

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text(text)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(MLXModel.hero.theme.accent.opacity(0.16))
        .foregroundStyle(MLXModel.hero.theme.accent)
        .clipShape(Capsule())
    }
}

extension View {
    /// A subtle tinted background + border used to lift the hero model's row above the muted
    /// "other models" rows in a settings/list picker.
    func heroRowHighlight() -> some View {
        self
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(MLXModel.hero.theme.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(MLXModel.hero.theme.accent.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
            )
    }
}

/// Applies `heroRowHighlight()` only for the hero row, leaving other rows with the default list
/// background. Keeps the row-building code branch-free.
struct ConditionalHeroHighlight: ViewModifier {
    let isHero: Bool

    func body(content: Content) -> some View {
        if isHero {
            content.heroRowHighlight()
        } else {
            content
        }
    }
}
