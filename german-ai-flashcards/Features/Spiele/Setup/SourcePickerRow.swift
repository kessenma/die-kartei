//
//  SourcePickerRow.swift
//  german-ai-flashcards
//
//  The "pick where the words come from" row, extracted.
//
//  This shape was already copy-pasted three times — `MatchingDeckPickerView.pickerRow`,
//  `ArticleGameSetupView.sourceRow`, `TabelleSetupView` — and the Spiele room needs it three more
//  times. One row, so a change to how a source reads lands everywhere at once.
//

import SwiftUI

struct SourcePickerRow: View {
    let title: String
    let subtitle: String
    let icon: String
    /// A source that can't field a round still gets a row — greyed, and tappable so the learner
    /// can top it up. Hiding it would leave them wondering where their deck went.
    var isEnough: Bool = true

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isEnough ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 34, height: 34)
                .background(
                    (isEnough ? Color.accentColor : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isEnough ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isEnough ? "chevron.right" : "plus.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
