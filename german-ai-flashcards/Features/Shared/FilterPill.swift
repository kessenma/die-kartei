//
//  FilterPill.swift
//  german-ai-flashcards
//
//  The shared pill used by every filter strip in the app. Extracted from `StoryListFilterBar`, the
//  first screen to grow one, when the placement review needed the same control — the strips differ
//  (each speaks its own screen's vocabulary), but the pill itself is a general control and shouldn't
//  be re-typed per screen.
//

import SwiftUI

/// One filter pill: tinted when off, filled when on, with an ✕ that reads as "tap to clear".
struct FilterPill: View {
    let label: String
    var systemImage: String?
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
                if isOn {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? tint : tint.opacity(0.12), in: appTheme.pillShape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
