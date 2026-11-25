//
//  ZeichnenTile.swift
//  german-ai-flashcards
//
//  The Zeichnen room's wide card on Home, under Schreibblatt. Styled like `SchreibblattTile`:
//  same emblem logic, same title face, same card surface.
//

import SwiftUI

struct ZeichnenTile: View {
    static let title = "Zeichnen"
    static let subtitle = "Draw your words: quick sketches, slow studies, paint by number"
    static let systemImage = "pencil.and.scribble"
    /// Grundform's mark: a half-filled circle, a drawing's light and shade.
    static let glyph = "◐"
    /// Carmine, from the palette the room's styles were drawn from. The category colours, Job
    /// prep's teal, Deutschkurs's brown and Schreibblatt's graphite are taken.
    static let tint = Color(light: 0xB8304A, dark: 0xF2788A)

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
                .font(.system(size: 22))
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

#Preview("Zeichnen tile") {
    VStack(spacing: 14) {
        SchreibblattTile()
        ZeichnenTile()
    }
    .padding(20)
    .themedScreen()
}
