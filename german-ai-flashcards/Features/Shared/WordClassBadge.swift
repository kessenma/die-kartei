//
//  WordClassBadge.swift
//  german-ai-flashcards
//
//  The one place a word class turns into a color, and the chip the document builder uses to show
//  and correct one.
//
//  Deliberately not in `GrammarPalette`. That file keeps gender and case codings apart on purpose
//  so a screen can show both without one color meaning two things; handing it a third meaning for
//  blue and green would undo that. The colors here are the ones the flashcard screens have always
//  used for a word type (verb blue, adjective purple, noun green) — this file just stops them
//  being written out three times. Adverb is pink rather than orange, which is Akkusativ and also
//  the "guessed split" dot on a builder row.
//

import SwiftUI

nonisolated enum WordClassPalette {
    /// Takes the stored string rather than `WordClass`, because the card screens read
    /// `VocabCard.wordType` and the Goethe lists spell adjective "adj".
    static func color(for wordType: String?) -> Color {
        switch wordType?.lowercased() {
        case "noun": .green
        case "verb": .blue
        case "adjective", "adj": .purple
        case "adverb", "adv": .pink
        // `CardKind.phrase`: not a word class, but the card screens show it like one.
        case "phrase": .indigo
        default: .gray
        }
    }

    static func color(for wordClass: WordClass?) -> Color {
        color(for: wordClass?.rawValue)
    }
}

/// A row's word class, tappable to correct it. A `Menu` rather than a picker or a sheet: one tap to
/// open and one to choose, and it works the same on the Mac.
struct WordClassChip: View {
    let wordClass: WordClass?
    var onPick: (WordClass?) -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Menu {
            Section("Wortart · Word class") {
                ForEach(WordClass.allCases) { option in
                    Button {
                        onPick(option)
                    } label: {
                        if option == wordClass {
                            Label(option.german, systemImage: "checkmark")
                        } else {
                            Text(option.german)
                        }
                    }
                }
                if wordClass != nil {
                    Button("Keine Angabe") { onPick(nil) }
                }
            }
        } label: {
            Text(wordClass?.german ?? "Wortart")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(wordClass == nil ? Color.secondary : WordClassPalette.color(for: wordClass))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    wordClass == nil
                        ? AnyShapeStyle(Color.secondary.opacity(0.10))
                        : AnyShapeStyle(WordClassPalette.color(for: wordClass).opacity(0.14)),
                    in: appTheme.pillShape
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(wordClass.map { "Word class: \($0.german)" } ?? "Word class not set")
    }
}
