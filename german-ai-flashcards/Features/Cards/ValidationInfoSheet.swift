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
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .orange,
                        label: "Gender issue",
                        explanation: "The model used a different article than Wiktionary has on record. Worth a second look — but read the note below before assuming the card is wrong."
                    )
                    BadgeExplainerRow(
                        icon: "questionmark.circle",
                        iconColor: .secondary,
                        label: "Not in dictionary",
                        explanation: "The word wasn't found in the dictionary at all. Common for compound nouns, specialised vocabulary, proper nouns, or very informal terms."
                    )
                } header: {
                    Text("What the badges mean")
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
                    Text("Larger models (Gemma 3n, Gemma 4, Qwen3 4B) produce fewer warnings in practice because they have a stronger grasp of formal German grammar.")
                }
            }
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
