//
//  ClassNotesTile.swift
//  german-ai-flashcards
//
//  The second wide card under the six category tiles, beneath Job prep. A German course the
//  learner takes elsewhere is, like a job search, a goal that borrows from every skill rather than
//  a seventh one, so it sits below the grid as a full-width row. Styled like `JobPrepTile`: same
//  emblem logic, same title face, same card surface.
//

import SwiftUI

struct ClassNotesTile: View {
    static let title = "Deutschkurs"
    static let subtitle = "Class notes, handouts, homework"
    static let systemImage = "graduationcap.fill"
    /// Grundform's geometric mark: a ruled square, the Bauhaus set's nearest thing to a notebook page.
    static let glyph = "▤"
    /// Brown: the six category colors and Job prep's teal are taken, and brown reads as paper.
    static let tint: Color = .brown

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
private func classNotesTilePreview(_ theme: AppTheme) -> some View {
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
        }
        .padding(20)
    }
    .themedScreen()
    .environment(\.appTheme, theme)
}

#Preview("Class notes tile · System")   { classNotesTilePreview(.klar) }
#Preview("Class notes tile · Soft")     { classNotesTilePreview(.sanft) }
#Preview("Class notes tile · Notebook") { classNotesTilePreview(.kritzel) }
#Preview("Class notes tile · Bauhaus")  { classNotesTilePreview(.grundform) }
#Preview("Class notes tile · Bauhaus dark") { classNotesTilePreview(.grundform).preferredColorScheme(.dark) }
