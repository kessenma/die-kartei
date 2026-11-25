@testable import DieKarteiCore
import SwiftUI

/// The gender and case colours, the same hexes as the iOS app's GrammarPalette (light / dark).
/// The iOS palette builds on the app's theme helpers, so Android keeps its own copy for now.
enum AndroidPalette {
    static func gender(_ gender: Gender, dark: Bool) -> Color {
        switch gender {
        case .der:    hex(dark ? 0x5B8CFF : 0x2F6BFF)
        case .die:    hex(dark ? 0xFF6B77 : 0xE23D4C)
        case .das:    hex(dark ? 0x3FD495 : 0x1FA971)
        case .plural: hex(dark ? 0xF2B43C : 0xD9930E)
        }
    }

    static func kasus(_ kasus: GrammarCase, dark: Bool) -> Color {
        switch kasus {
        case .nominativ: hex(dark ? 0xC3CAD4 : 0x4A5260)
        case .akkusativ: hex(dark ? 0xF79542 : 0xE2701A)
        case .dativ:     hex(dark ? 0x36C3D2 : 0x0E8794)
        case .genitiv:   hex(dark ? 0xC99562 : 0x8A5A2B)
        }
    }

    static func hex(_ value: Int) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// A word with its article in gender colour, like `Text.gendered` on iOS.
struct GenderedWord: View {
    let word: String
    let article: String?
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(spacing: 6) {
            if let article, !article.isEmpty {
                Text(article)
                    .fontWeight(.semibold)
                    .foregroundStyle(Gender(article: article).map { AndroidPalette.gender($0, dark: scheme == .dark) } ?? Color.secondary)
            }
            Text(word)
        }
    }
}
