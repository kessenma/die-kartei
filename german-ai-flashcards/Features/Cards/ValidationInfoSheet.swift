import SwiftUI

struct ValidationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BadgeExplainerRow(
                        icon: "checkmark.seal.fill",
                        iconColor: .green,
                        label: "Verified",
                        explanation: "The word was found in the dictionary and the noun gender (der/die/das) matches what Wiktionary records. High confidence the card is correct."
                    )
                    BadgeExplainerRow(
                        icon: "info.circle",
                        iconColor: .blue,
                        label: "der/das",
                        explanation: "The dictionary records more than one valid gender for this noun, and the card uses one of them. Nothing to fix, both articles are correct German."
                    )
                    BadgeExplainerRow(
                        icon: "questionmark.circle",
                        iconColor: .secondary,
                        label: "Not in dictionary",
                        explanation: "The word wasn't in the dictionary and no gender rule could settle it. Usually proper nouns, slang, or very new words. These are the only cards that ask anything of you."
                    )
                } header: {
                    Text("What the badges mean")
                }

                Section {
                    ExplainerRow(
                        icon: "book.closed",
                        label: "Dictionary entry",
                        explanation: "The word is in Wiktionary with a single recorded gender. If the model disagreed, the dictionary wins and the article is fixed before you see the card."
                    )
                    ExplainerRow(
                        icon: "square.split.2x1",
                        label: "Compound nouns",
                        explanation: "A German compound takes the gender of its last part, so Wohnzimmertisch is der because Tisch is. This resolves most words a finite dictionary can't list."
                    )
                    ExplainerRow(
                        icon: "textformat.abc",
                        label: "Word endings",
                        explanation: "Some endings are near-certain: -ung, -keit, -heit, -tion and -schaft are die; -ismus and -lein are der and das. Weaker endings like -er and -chen are left alone rather than guessed at."
                    )
                } header: {
                    Text("How articles get corrected")
                } footer: {
                    Text("Corrections are applied automatically and listed on the deck screen under \u{201C}articles corrected\u{201D}, where you can change any of them back.")
                }

                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image("logo-wiktionary")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Warnings aren't verdicts")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("The dictionary is built from Wiktionary (via Kaikki.org), which documents standardised, formal German. The AI models are trained on a much broader mix of text — including forums, Reddit, and social media — so they sometimes produce valid informal or regional usage that simply isn't in a formal dictionary.\n\nA gender mismatch or 'not found' flag is a prompt to double-check, not proof the card is wrong. Trust your own German knowledge.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("A note on accuracy")
                } footer: {
                    Text("The German tutors produce the fewest warnings in practice, since they were trained on this app's grammar tasks. Size matters less than you'd expect here: some of the larger general-purpose models flag more often than much smaller ones.")
                }
            }
            .themedListScreen()
            .navigationTitle("Dictionary Validation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Same layout as a badge row, but for the rules behind a correction rather than a badge.
private struct ExplainerRow: View {
    let icon: String
    let label: String
    let explanation: String

    var body: some View {
        BadgeExplainerRow(icon: icon, iconColor: .secondary, label: label, explanation: explanation)
    }
}

private struct BadgeExplainerRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let explanation: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
