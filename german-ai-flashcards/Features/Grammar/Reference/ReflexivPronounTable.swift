//
//  ReflexivPronounTable.swift
//  german-ai-flashcards
//
//  The reflexive pronouns by person and case, in the case colours: the topic screen's Merkhilfe
//  and the reference a reflexive drill may pin over the round (the article table's twin). A
//  neutral table: it never highlights the current answer.
//

import SwiftUI

struct ReflexivPronounTable: View {
    /// Smaller type and tighter rows, for the pinned strip.
    var compact = false

    @Environment(\.appTheme) private var appTheme

    private struct Row: Identifiable {
        let person: String
        let en: String
        let akk: String
        let dat: String
        var id: String { person }
    }

    private static let rows: [Row] = [
        Row(person: "ich", en: "I", akk: "mich", dat: "mir"),
        Row(person: "du", en: "you", akk: "dich", dat: "dir"),
        Row(person: "er · sie · es", en: "he · she · it", akk: "sich", dat: "sich"),
        Row(person: "wir", en: "we", akk: "uns", dat: "uns"),
        Row(person: "ihr", en: "you (pl.)", akk: "euch", dat: "euch"),
        Row(person: "sie · Sie", en: "they · you (formal)", akk: "sich", dat: "sich"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: compact ? 10 : 14, verticalSpacing: compact ? 4 : 8) {
            GridRow {
                Text("")
                header("Akkusativ", GrammarCase.akkusativ.color)
                header("Dativ", GrammarCase.dativ.color)
            }
            ForEach(Self.rows) { row in
                GridRow {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.person).font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                        if !compact {
                            Text(row.en).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    form(row.akk, GrammarCase.akkusativ.color, changes: row.akk != row.dat)
                    form(row.dat, GrammarCase.dativ.color, changes: row.akk != row.dat)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reflexive pronouns: " + Self.rows.map { "\($0.person): \($0.akk), \($0.dat)" }.joined(separator: "; "))
    }

    private func header(_ title: String, _ color: Color) -> some View {
        Text(title)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(color)
    }

    /// A form in its case colour; the ones that are the same in both cases stay neutral, so the
    /// eye lands on mich / mir and dich / dir.
    private func form(_ text: String, _ color: Color, changes: Bool) -> some View {
        Text(text)
            .font(compact ? .callout.weight(.semibold) : .title3.weight(.semibold))
            .foregroundStyle(changes ? color : .primary)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 2 : 4)
            .background(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous)
                    .fill(changes ? color.opacity(0.12) : Color.secondary.opacity(0.08))
            )
    }
}

#Preview("Reflexive pronouns · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            VStack(spacing: 24) {
                ReflexivPronounTable()
                ReflexivPronounTable(compact: true)
            }
            .padding()
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}
