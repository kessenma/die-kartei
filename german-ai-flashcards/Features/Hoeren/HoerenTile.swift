//
//  HoerenTile.swift
//  german-ai-flashcards
//
//  The Hören room's wide card on Home, under Schreiben. Styled like `SchreibenTile`: same emblem
//  logic, same title face, same card surface.
//

import SwiftUI

struct HoerenTile: View {
    static let title = "Hören"
    static let subtitle = "Numbers heard once, dictation, and the gist of a story in your own words"
    static let systemImage = "headphones"
    /// Grundform's mark: a sound wave.
    static let glyph = "≈"
    /// Ochre. Teal (Job prep), brown (Deutschkurs), graphite (Schreibblatt), carmine (Zeichnen)
    /// and ink blue (Schreiben) are taken.
    static let tint = Color(light: 0x9A6A0C, dark: 0xE8B44C)

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            emblem
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title)
                    .themedLabel(.headline, size: 19)
                    .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
                    .tracking(theme.uppercaseSectionHeaders ? 0.8 : 0)
                    .foregroundStyle(.primary)
                Text(Self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(13)
        .themedCard()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var emblem: some View {
        if theme == .grundform {
            Text(Self.glyph)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Self.tint)
        } else {
            Image(systemName: Self.systemImage)
                .font(.title3)
                .foregroundStyle(Self.tint)
                .frame(width: 40, height: 40)
                .background(Self.tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: theme.innerRadius(10), style: .continuous))
        }
    }
}

#Preview("Hören tile") {
    VStack(spacing: 14) {
        SchreibenTile()
        HoerenTile()
    }
    .padding(20)
    .themedScreen()
}
