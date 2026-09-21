//
//  JobPrepTile.swift
//  german-ai-flashcards
//
//  The wide card under the six category tiles on the Home hub. Job prep is not a seventh language
//  skill, it's a goal that borrows from two of them (speaking and reading), so it sits below the
//  grid as one full-width row rather than leaving a lone tile in a third row. Styled like
//  `ActivityCategoryTile`: same emblem logic, same title face, same card surface.
//

import SwiftUI

struct JobPrepTile: View {
    static let title = "Job prep"
    static let subtitle = "Interview practice · study a job ad"
    static let systemImage = "briefcase.fill"
    /// Grundform's geometric mark: a halved square, the closest the Bauhaus set has to a case.
    static let glyph = "◧"
    /// Teal: the six category colors are taken, and this one reads as neither of the two it draws on.
    static let tint: Color = .teal

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
private func jobPrepTilePreview(_ theme: AppTheme) -> some View {
    ScrollView {
        VStack(spacing: 14) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(ActivityCategory.allCases) { ActivityCategoryTile(category: $0) }
            }
            JobPrepTile()
        }
        .padding(20)
    }
    .themedScreen()
    .environment(\.appTheme, theme)
}

#Preview("Job prep tile · System")   { jobPrepTilePreview(.klar) }
#Preview("Job prep tile · Soft")     { jobPrepTilePreview(.sanft) }
#Preview("Job prep tile · Notebook") { jobPrepTilePreview(.kritzel) }
#Preview("Job prep tile · Bauhaus")  { jobPrepTilePreview(.grundform) }
#Preview("Job prep tile · Bauhaus dark") { jobPrepTilePreview(.grundform).preferredColorScheme(.dark) }
