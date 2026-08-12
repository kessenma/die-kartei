//
//  PrepositionExampleRows.swift
//  german-ai-flashcards
//
//  The worked-sentence stack every preposition surface shows: an optional Wohin/Wo tag for
//  two-way words, the German in quotes, the English beneath. One component instead of the
//  three near-identical copies the drill reveal, the animation gallery, and the card back
//  used to carry — which is what let their layouts drift apart in the first place.
//

import SwiftUI

struct PrepositionExampleRows: View {
    /// Two densities, not a free font parameter: `.regular` is the drill reveal and the
    /// gallery; `.compact` is the card back, which stacks every sentence on one card face.
    enum Density { case regular, compact }

    let examples: [PrepositionExample]
    let governs: PrepositionCase
    var density: Density = .regular
    /// Dims everything after the primary sentence(s). The card back lists the extra examples
    /// beneath the scene-depicting ones, and they should read as extras rather than as a wall
    /// of equals. "Primary" matches `revealExamples()`: the first sentence of each case for a
    /// two-way word, the first sentence otherwise.
    var dimsExtras: Bool = false

    var body: some View {
        ForEach(Array(examples.enumerated()), id: \.element.id) { position, example in
            VStack(spacing: 2) {
                if governs == .wechsel {
                    Text(example.caseUsed == .akkusativ ? "Wohin? → Akkusativ" : "Wo? → Dativ")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(example.caseUsed.color)
                }
                Text("„\(example.german)“")
                    .font(density == .regular ? .subheadline.weight(.medium)
                                              : .footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(example.english)
                    .font(density == .regular ? .caption : .caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(dimsExtras && !isPrimary(position, example) ? 0.55 : 1)
        }
    }

    private func isPrimary(_ position: Int, _ example: PrepositionExample) -> Bool {
        guard governs == .wechsel else { return position == 0 }
        return examples.firstIndex { $0.caseUsed == example.caseUsed } == position
    }
}
