import SwiftUI

/// Reusable picker controls for study mode, which side to show first,
/// which side to display example sentences on, and auto-advance behaviour.
struct FlashcardPreviewOptionsView: View {
    @Binding var flashcardStyle: FlashcardStyle
    @Binding var showGermanFirst: Bool
    @Binding var showExamplesOnGermanSide: Bool
    @Binding var autoAdvance: Bool
    /// Deal the cards in a random order at Start. Nil where the launcher fixes the order itself.
    var shuffle: Binding<Bool>? = nil
    /// Phrase cards ask for a missing word. Nil when the deck has no phrase cards.
    var phraseGaps: Binding<Bool>? = nil
    /// A missed card asks to be written with the Pencil. Nil off the iPad.
    var writeAfterMiss: Binding<Bool>? = nil
    var showHints: Binding<Bool>? = nil
    var hasExamples: Bool
    var cards: [VocabCard] = []
    /// Opens the deck's Wortliste table. Nil hides the "See all words" link.
    var onShowWords: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text("Study mode")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Study mode", selection: $flashcardStyle) {
                ForEach(FlashcardStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Text(flashcardStyle.description)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }

        if !cards.isEmpty, let onShowWords {
            Button {
                onShowWords()
            } label: {
                Label("See all \(cards.count) words", systemImage: "tablecells")
                    .font(.subheadline)
            }
        }

        VStack(spacing: 12) {
            Text("Which side do you want to see first?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Front side", selection: $showGermanFirst) {
                Text("German").tag(true)
                Text("English").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }

        if hasExamples {
            VStack(spacing: 12) {
                Text("Show examples on which side?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Examples side", selection: $showExamplesOnGermanSide) {
                    Text("German side").tag(true)
                    Text("English side").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }

        if let shuffle {
            VStack(spacing: 8) {
                Toggle("Shuffle the cards", isOn: shuffle)
                    .frame(maxWidth: 280)
                Text("A different order every time you start. Off: the deck's own order.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }

        if let phraseGaps {
            VStack(spacing: 8) {
                Toggle("Gaps on phrase cards", isOn: phraseGaps)
                    .frame(maxWidth: 280)
                Text("A phrase shows with one word missing, the verb or the preposition, and four to choose from.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }

        if let writeAfterMiss {
            VStack(spacing: 8) {
                Toggle("Write it after a miss", isOn: writeAfterMiss)
                    .frame(maxWidth: 280)
                Text("Get a card wrong and it asks you to write the word with your Apple Pencil: once looking, once from memory.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }

        VStack(spacing: 8) {
            Toggle("Auto-advance after rating", isOn: $autoAdvance)
                .frame(maxWidth: 280)
            Text("Skip the Next button — moves to the next card as soon as you choose a rating.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }

        if let showHints {
            VStack(spacing: 8) {
                Toggle("Show sentence hints", isOn: showHints)
                    .frame(maxWidth: 280)
                Text("Highlights the verb and noun; shows the noun's gender below the blank.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }

    }
}

