//
//  GrammarPalette.swift
//  german-ai-flashcards
//
//  The app's one home for grammar color-coding and iconography. Two codings, kept apart on
//  purpose so a screen can show both without one color meaning two things:
//
//    Gender — der blue · die red · das green · plural gold, with the figure glyphs
//    Case   — Nominativ graphite · Akkusativ orange · Dativ teal · Genitiv brown,
//             plus violet for a two-way (Wechsel) preposition, “it depends”
//
//  Anything that shows a gender or a case takes its color and symbol from here.
//
//  A third kind of imagery lives next door: the task-preview drawings each exercise is announced by
//  on a launcher row (`GrammarTaskArt`, drawn by Features/Grammar/Shared/GrammarTaskArtView.swift).
//  They carry no coding of their own — a row passes its own tint, so neither palette above gains a
//  meaning there.
//

import SwiftUI

// `Gender` and `GrammarCase` themselves live in GrammarTerms.swift (Foundation-only, shared with
// the Android core); this file adds their colors and the colored rendering.

nonisolated extension Gender {
    /// This gender's color. Convenience for `GenderPalette.color(self)`.
    var color: Color { GenderPalette.color(self) }
}

nonisolated extension GrammarCase {
    var color: Color { CasePalette.color(self) }
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


/// The case colors, resolved for light and dark. Deliberately clear of the gender hues, since a
/// case table or a preposition card shows both codings at once.
nonisolated enum CasePalette {
    static func color(_ kasus: GrammarCase) -> Color {
        switch kasus {
        case .nominativ: Color(light: 0x4A5260, dark: 0xC3CAD4)   // graphite: the plain, dictionary form
        case .akkusativ: Color(light: 0xE2701A, dark: 0xF79542)   // orange
        case .dativ:     Color(light: 0x0E8794, dark: 0x36C3D2)   // teal
        case .genitiv:   Color(light: 0x8A5A2B, dark: 0xC99562)   // brown
        }
    }

    /// A two-way preposition: Akkusativ or Dativ depending on Wohin? / Wo?
    static let wechsel = Color(light: 0x7B4FD6, dark: 0xA98BF5)   // violet
    static let wechselSymbol = "arrow.left.arrow.right"
}

nonisolated extension KasusUnit {
    /// The case color, or neutral for Alle Fälle: graphite already means Nominativ.
    var color: Color { focusCase?.color ?? .secondary }
}

nonisolated extension PrepositionCase {
    /// This group's fixed identity color, used on the drill buttons, the card's case tab and the
    /// rules sheet so the color itself becomes a memory hook. From `CasePalette`, so a
    /// preposition's case reads the same as that case everywhere else in the app.
    var color: Color {
        switch self {
        case .akkusativ: GrammarCase.akkusativ.color
        case .dativ:     GrammarCase.dativ.color
        case .wechsel:   CasePalette.wechsel
        case .genitiv:   GrammarCase.genitiv.color
        }
    }

    var symbol: String {
        switch self {
        case .akkusativ: GrammarCase.akkusativ.symbol
        case .dativ:     GrammarCase.dativ.symbol
        case .wechsel:   CasePalette.wechselSymbol
        case .genitiv:   GrammarCase.genitiv.symbol
        }
    }
}

nonisolated extension GermanArticle {
    /// The fixed identity color. Delegates to `GenderPalette` — previously this was plain
    /// `.blue`/`.red`/`.green`, which read *close* to the flashcard colors without matching them,
    /// so the same noun could be two different blues in two screens.
    var color: Color { gender.color }
}
