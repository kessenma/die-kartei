//
//  LevelChoiceList.swift
//  german-ai-flashcards
//
//  The five CEFR levels as a list of tappable rows, for the two places a learner picks their own
//  level outright: Settings ▸ Learning ▸ Your Level, and the placement check's hard-select door.
//
//  Deliberately not the segmented `Picker` used in the setup sheets. A segmented control is right
//  for "A1 A2 B1 B2 C1" when you already know which one you are and you're adjusting one exercise.
//  Choosing your own level is a different question — it needs room for `selfAssessment`, the
//  first-person can-do line that's the only thing that actually helps someone decide.
//

import SwiftUI

/// Five tappable rows (chip · English label · can-do statement · checkmark), emitted as bare rows
/// so the caller supplies the enclosing `Section` / `Form`.
struct LevelChoiceList: View {
    @Binding var selection: CEFRLevel

    var body: some View {
        ForEach(CEFRLevel.allCases) { level in
            Button {
                selection = level
            } label: {
                row(level)
            }
            .buttonStyle(.plain)
            // A row is one element to VoiceOver, announced with its selected state rather than as
            // four unrelated fragments.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(level.rawValue), \(level.englishLabel). \(level.selfAssessment)")
            .accessibilityAddTraits(selection == level ? [.isButton, .isSelected] : .isButton)
        }
    }

    private func row(_ level: CEFRLevel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CEFRLevelChip(level: level)
                // Chips differ in width ("A1" vs "B2" render alike, but the frame keeps the two
                // text columns aligned no matter what the pill shape does per theme).
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.englishLabel)
                    .font(.subheadline.weight(.medium))
                Text(level.selfAssessment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .opacity(selection == level ? 1 : 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
