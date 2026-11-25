//
//  SchreibblattTile.swift
//  german-ai-flashcards
//
//  The third wide card under the six category tiles, beneath Deutschkurs. Writing words out by
//  hand is a habit rather than a seventh skill — the teacher's own homework, a page of tables
//  copied again and again — so it sits below the grid as a full-width row. Styled like
//  `JobPrepTile` and `ClassNotesTile`: same emblem logic, same title face, same card surface.
//

import SwiftUI

struct SchreibblattTile: View {
    static let title = "Schreibblatt"
    static let subtitle = "Write your words by hand, or print the tables"
    static let systemImage = "hand.draw"
    /// Grundform's geometric mark: a ruled grid, the Bauhaus set's nearest thing to a table of
    /// words. Deutschkurs already has the plain ruled square.
    static let glyph = "▦"
    /// Graphite. The six category colours, Job prep's teal and Deutschkurs's brown are taken, and
    /// the nearest free system colours (mint, cyan) read as teal when the cards are stacked.
    /// Graphite is also what the sheet is written in.
    static let tint = Color(light: 0x3A3F4A, dark: 0xC9CFD8)

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

    /// Mirrors `ActivityCategoryTile.emblem`: the geometric mark on a solid block for Grundform,
    /// the SF Symbol on a tinted chip everywhere else.
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

// MARK: - Previews

@MainActor
private func schreibblattTilePreview(_ theme: AppTheme) -> some View {
    ScrollView {
        VStack(spacing: 14) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(ActivityCategory.allCases) { ActivityCategoryTile(category: $0) }
            }
            JobPrepTile()
            ClassNotesTile()
            SchreibblattTile()
        }
        .padding(20)
    }
    .themedScreen()
    .environment(\.appTheme, theme)
}

#Preview("Schreibblatt tile · System")   { schreibblattTilePreview(.klar) }
#Preview("Schreibblatt tile · Soft")     { schreibblattTilePreview(.sanft) }
#Preview("Schreibblatt tile · Notebook") { schreibblattTilePreview(.kritzel) }
#Preview("Schreibblatt tile · Bauhaus")  { schreibblattTilePreview(.grundform) }
#Preview("Schreibblatt tile · Bauhaus dark") { schreibblattTilePreview(.grundform).preferredColorScheme(.dark) }
