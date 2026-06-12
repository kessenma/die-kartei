import SwiftUI

struct ModelGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    GuideRow(model: .qwen3_8B, badge: "Best Overall", badgeColor: .purple)
                    GuideRow(model: .mistral7B, badge: "Best Multilingual", badgeColor: .blue)
                } header: {
                    Text("Premium (6–8 GB RAM)")
                } footer: {
                    Text("These 7–8B models produce the most accurate German flashcards — better grammar annotations, more natural sentences, and fewer validation warnings than the 4B models.")
                }

                Section {
                    GuideRow(model: .gemma4_E4B, badge: "Best Quality", badgeColor: .purple)
                    GuideRow(model: .gemma3n_E4B, badge: "Recommended", badgeColor: .blue)
                } header: {
                    Text("Best for German (6 GB Devices)")
                } footer: {
                    Text("Both 4B-class models are significantly more reliable for grammar annotations, noun genders, and case notes — the best choice for 6 GB devices like iPhone 14 Pro or iPhone 15.")
                }

                Section {
                    GuideRow(model: .qwen3_4B, badge: nil, badgeColor: nil)
                    GuideRow(model: .phi4Mini, badge: nil, badgeColor: nil)
                } header: {
                    Text("Mid-range")
                } footer: {
                    Text("Good choices if your device can't handle the 4 GB+ Gemma models but you still want reliable grammar accuracy beyond what the 1B models offer.")
                }

                Section {
                    GuideRow(model: .gemma3_1B, badge: nil, badgeColor: nil)
                    GuideRow(model: .qwen3_0_6B, badge: "Fastest", badgeColor: .orange)
                    GuideRow(model: .llama3_2_1B, badge: nil, badgeColor: nil)
                } header: {
                    Text("Lightweight (iPhone 12+)")
                } footer: {
                    Text("At 1B parameters or fewer, all models struggle with German's complex grammar. Noun genders (der/die/das), grammatical cases, and separable verbs may be unreliable — review output carefully.")
                }

                Section {
                    Text("German has one of the more complex grammars among European languages: four grammatical cases, three noun genders, separable verbs, and long compound words. Smaller models are trained on fewer tokens and have less capacity to internalize these patterns reliably.\n\nThe 4B-class models (Gemma 3n and Gemma 4) produce significantly more accurate flashcards — better definitions, natural example sentences, and trustworthy grammar annotations.\n\nThe premium 7–8B models (Mistral 7B, Qwen3 8B) go further still, with richer vocabularies and more nuanced grammar notes. If your device has 6–8 GB RAM, these are worth downloading.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Why does model size matter?")
                }

                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image("logo-wiktionary")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Every flashcard is validated on-device")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("After the model generates a card, the app automatically looks up the word in a dictionary built from Wiktionary data (via Kaikki.org). It checks the noun gender (der/die/das) and part of speech against the dictionary and flags any mismatches.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("A warning doesn't mean the card is wrong. Wiktionary documents standardised, formal German — but the models are trained on a broad mix of web text (forums, Reddit, social media) and may produce valid informal or regional usage that isn't in the dictionary. Use the flag as a prompt to double-check, not as a verdict.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Built-in validation")
                } footer: {
                    Text("This safety net makes smaller models more usable in practice — gender errors are caught automatically rather than silently ending up on your cards.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The best way to choose is to try a few yourself. Download a model, generate a handful of cards on a topic you know well, and look at the example sentences and grammar notes. Switch to another model and compare.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Things to look for:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            BulletRow("Are the example sentences natural German, or do they feel translated?")
                            BulletRow("Are grammar notes (case, verb type, separability) accurate?")
                            BulletRow("How many cards come back with a validation warning?")
                            BulletRow("How fast does generation feel on your device?")
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Try them yourself")
                }
            }
            .navigationTitle("Which Model Should I Use?")
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

// MARK: - Subviews

private struct GuideRow: View {
    let model: MLXModel
    let badge: String?
    let badgeColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(model.logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.rawValue)
                            .font(.headline)
                        if let badge, let color = badgeColor {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.15))
                                .foregroundStyle(color)
                                .clipShape(Capsule())
                        }
                    }

                    Text(model.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label(model.deviceNote, systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .imageScale(.small)
                        Text("~\(formattedSize(model.approximateSizeMB))")
                        Text("·")
                        Text(model.parameterCount)
                        Text("·")
                        Text(model.quantization)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 16) {
                Link(destination: model.huggingFaceRepoURL) {
                    Label("HuggingFace", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                Link(destination: model.promoPageURL) {
                    Label("Learn more", systemImage: "globe")
                        .font(.caption)
                }
            }
            .padding(.leading, 48)
        }
        .padding(.vertical, 4)
    }

    private func formattedSize(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
    }
}

private struct BulletRow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
