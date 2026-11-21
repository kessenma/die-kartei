//
//  SchreibenTile.swift
//  german-ai-flashcards
//
//  The Schreiben room's wide card on Home, under Zeichnen. Styled like `ZeichnenTile`: same
//  emblem logic, same title face, same card surface.
//

import SwiftUI

struct SchreibenTile: View {
    static let title = "Schreiben"
    static let subtitle = "Keep a journal or write an essay, by keyboard or with the Pencil, and have it checked"
    static let systemImage = "square.and.pencil"
    /// Grundform's mark: three rules, a page of writing.
    static let glyph = "≡"
    /// Ink blue. Teal (Job prep), brown (Deutschkurs), graphite (Schreibblatt) and carmine
    /// (Zeichnen) are taken.
    static let tint = Color(light: 0x2F4FA0, dark: 0x8FA6F0)

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

#Preview("Schreiben tile") {
    VStack(spacing: 14) {
        ZeichnenTile()
        SchreibenTile()
    }
    .padding(20)
    .themedScreen()
}
