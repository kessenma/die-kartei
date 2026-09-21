//
//  GoetheEntryRow.swift
//  german-ai-flashcards
//
//  One Goethe word as a list row: article in its gender color, the word, its plural where the
//  lists know it, a word-type pill, the translation, and an optional trailing status badge
//  ("Neu", "fällig", "in 5 T.", "bekannt") from `WortschatzService`.
//

import SwiftUI

struct GoetheEntryRow: View {
    let word: GoetheWord
    /// The status badge, when the row is shown inside the Wortschatz browse list.
    var badge: String? = nil
    var badgeColor: Color = .secondary

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let article = word.article {
                    Text(article)
                        .font(.subheadline)
                        .foregroundStyle(articleColor(article))
                        .fontWeight(.medium)
                }
                Text(word.word)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if word.wordType == .noun, let plural = word.plural, !plural.isEmpty,
                   !plural.hasPrefix("only") {
                    Text(", \(plural)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.14), in: appTheme.pillShape)
                }
                if let wordType = word.rawWordType {
                    Text(wordType)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(wordTypeColor(wordType), in: appTheme.pillShape)
                }
            }
            if let translation = word.translation {
                Text(translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // der/die/das from the shared GenderPalette (der=blue, die=RED, das=green) so the article
    // colors match the flashcards, correction sheet, and article game — one gender code app-wide.
    private func articleColor(_ article: String) -> Color {
        Gender(article: article)?.color ?? .secondary
    }

    private func wordTypeColor(_ type: String) -> Color {
        switch type {
        case "verb": .blue
        case "adj": .purple
        case "noun": .green
        default: .gray
        }
    }
}
