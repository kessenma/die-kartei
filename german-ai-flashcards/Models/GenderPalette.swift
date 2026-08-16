import SwiftUI

// MARK: - Gender

/// German grammatical gender. The signature pedagogy-as-identity move of the theme system:
/// color-code der/die/das everywhere it appears (article text, card corners, the article game,
/// the picker) so the classic learner mnemonic is always on screen.
///
/// Independent of `AppTheme` — the gender colors are the same in every theme, so the aid never
/// changes meaning. In **Grundform** these colors double as the Bauhaus primaries, so identity and
/// pedagogy share one palette (see `AppTheme.previewColors` / `accent`).
nonisolated enum Gender: String, CaseIterable, Identifiable {
    case der, die, das, plural

    var id: String { rawValue }

    /// The nominative singular article (or "die" for the plural), lowercased.
    var article: String {
        switch self {
        case .der:    "der"
        case .die:    "die"
        case .das:    "das"
        case .plural: "die"   // plural takes "die" regardless of singular gender
        }
    }

    /// Human label for pickers and legends.
    var label: String {
        switch self {
        case .der:    "der"
        case .die:    "die"
        case .das:    "das"
        case .plural: "Plural"
        }
    }

    /// This gender's color. Convenience for `GenderPalette.color(self)`.
    var color: Color { GenderPalette.color(self) }

    /// Best-effort parse from an article string (`"der"` / `"die"` / `"das"`, any case, with or
    /// without surrounding whitespace). Returns `nil` when the string isn't a bare article, so
    /// callers can fall back to an uncolored treatment. Deliberately does not guess plural — a bare
    /// "die" is read as feminine; plurals are tagged explicitly by the caller that knows the count.
    init?(article raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "der": self = .der
        case "die": self = .die
        case "das": self = .das
        default:    return nil
        }
    }
}

// MARK: - GenderPalette

/// The four gender colors, resolved for light and dark. Values are the plan's fixed hexes in light
/// mode; dark mode brightens each a notch so the saturated primaries stay legible on dark grounds
/// (per the theme system's "don't naively invert" rule — this is legibility, not a theme token).
nonisolated enum GenderPalette {
    static func color(_ gender: Gender) -> Color {
        switch gender {
        case .der:    Color(light: 0x2F6BFF, dark: 0x5B8CFF)   // blue
        case .die:    Color(light: 0xE23D4C, dark: 0xFF6B77)   // red
        case .das:    Color(light: 0x1FA971, dark: 0x3FD495)   // green
        case .plural: Color(light: 0xD9930E, dark: 0xF2B43C)   // gold
        }
    }
}

// MARK: - Rendering a noun with its article in color

extension Text {
    /// A noun with its article in gender color — "**der** Flug", `der` blue and the noun in whatever
    /// color the surrounding view sets. The display counterpart of `String.withArticle(_:)`, and the
    /// single place the signature move is rendered, so every screen colors articles identically.
    ///
    /// Returns one `Text`, not an `HStack`, so it wraps, truncates, scales, and inherits fonts
    /// exactly like the plain string it replaces. Built from an `AttributedString` (rather than
    /// `Text + Text`, which is deprecated on the current SDK): the article run carries its own
    /// color, and the noun run carries none, so the noun still follows whatever the surrounding
    /// view sets — which is what lets a caller paint it white over a photo and keep a colored
    /// article.
    ///
    /// Falls back to the bare word when there's no article, and to the plain combined string when
    /// the article isn't one of der/die/das — so an odd value degrades to today's rendering instead
    /// of vanishing.
    static func gendered(_ word: String, article: String?) -> Text {
        guard let article, !article.isEmpty else { return Text(word) }
        guard let gender = Gender(article: article) else { return Text(word.withArticle(article)) }

        // Older saved cards bake the article into the word itself; split it back off so it can be
        // colored separately (`withArticle` guards against the same case by not re-prefixing).
        var noun = word
        if word.lowercased().hasPrefix(article.lowercased() + " ") {
            noun = String(word.dropFirst(article.count + 1))
        }

        var styled = AttributedString(article + " ")
        styled.foregroundColor = gender.color
        return Text(styled + AttributedString(noun))
    }
}
