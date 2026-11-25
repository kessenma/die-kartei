//
//  HangmanKeyboardView.swift
//  german-ai-flashcards
//
//  Thirty keys: the alphabet plus Ä, Ö, Ü and ß.
//
//  The umlauts are keys of their own because the game treats them as letters of their own — press
//  A on „Mädchen“ and it is a miss. Folding them onto the base letters would make the keyboard
//  smaller and the spelling wrong.
//
//  Colour follows the house rule: never green or red. A hit fills with the tint, a miss greys out
//  and strikes through.
//

import SwiftUI

struct HangmanKeyboardView: View {
    let state: HangmanState
    let onGuess: (Character) -> Void

    @Environment(\.appTheme) private var appTheme

    /// Three rows of ten.
    private var rows: [[Character]] {
        stride(from: 0, to: GameLetters.hangmanKeys.count, by: 10).map {
            Array(GameLetters.hangmanKeys[$0..<min($0 + 10, GameLetters.hangmanKeys.count)])
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { letter in
                        key(letter)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func key(_ letter: Character) -> some View {
        let tried = state.guessed.contains(letter)
        let hit = tried && state.letters.contains { GameLetters.equal($0, letter) }

        Button {
            onGuess(letter)
        } label: {
            Text(String(letter))
                .font(.callout.weight(.semibold))
                .monospaced()
                // Dimmed rather than struck through: a line through a 15pt glyph turns Q, J and
                // X into something unreadable, and three states already read clearly as
                // filled (hit) · plain (untried) · faded (missed).
                .foregroundStyle(hit ? AnyShapeStyle(.white) : AnyShapeStyle(tried ? .tertiary : .primary))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous)
                        .fill(hit ? AnyShapeStyle(Color.accentColor)
                                  : AnyShapeStyle(Color.secondary.opacity(tried ? 0.06 : 0.14)))
                )
        }
        .buttonStyle(.plain)
        .disabled(tried || state.isOver)
        .accessibilityLabel(String(letter))
        .accessibilityValue(tried ? (hit ? "richtig" : "nicht im Wort") : "")
    }
}
