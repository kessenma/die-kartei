import SwiftUI

struct ModelGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    GuideRow(model: .gemma4_E4B_german, badge: "Best", badgeColor: MLXModel.hero.theme.accent)
                    GuideRow(model: .gemma4_E2B_german, badge: "Lighter", badgeColor: MLXModel.gemma4_E2B_german.theme.accent)
                } header: {
                    Text("Built for this app")
                        .themedSectionHeader()
                } footer: {
                    Text("Short version: if your device runs one of these, use it. Both are Google's Gemma 4 fine-tuned on German grammar for this app, on the parts learners actually get wrong: verbs with prepositions, separable and reflexive verbs, da-/wo-compounds, and haben/sein. On the app's own grammar test the E4B tutor scores 90% and the E2B tutor 83%. The best general-purpose model below scores 58%. The tutors are also the only models here trained to correct you without inventing mistakes you didn't make, which is what makes conversation practice trustworthy.")
                }
                .themedListRow()

                Section {
                    GuideRow(model: .qwen3_8B, badge: nil, badgeColor: nil)
                    GuideRow(model: .mistral7B, badge: nil, badgeColor: nil)
                    GuideRow(model: .qwen3_4B, badge: nil, badgeColor: nil)
                    GuideRow(model: .phi4Mini, badge: nil, badgeColor: nil)
                } header: {
                    Text("Large, but weaker at German")
                        .themedSectionHeader()
                } footer: {
                    Text("These have strong general reputations and all four underperformed on German grammar here. Qwen3 8B scores 58% and misses about half of a learner's real mistakes. Mistral 7B scores 48%, is worst on da-/wo-compounds, 'fixes' 59% of sentences that were already correct, and is the slowest model in the app. Qwen3 4B scores 52%; Phi-4 Mini scores 47% and misses 77% of real mistakes. They're listed for completeness, not as recommendations.")
                }
                .themedListRow()

                Section {
                    GuideRow(model: .granite2B_german, badge: "Best small", badgeColor: .green)
                    GuideRow(model: .gemma3_1B, badge: nil, badgeColor: nil)
                    GuideRow(model: .qwen3_0_6B, badge: "Fastest", badgeColor: .orange)
                    GuideRow(model: .llama3_2_1B, badge: nil, badgeColor: nil)
                } header: {
                    Text("Small devices (iPhone 12+)")
                        .themedSectionHeader()
                } footer: {
                    Text("If your device can't run a Gemma tutor, the Granite tutor is the pick: 62% on the app's grammar test, higher than both 7–8B models above at a fraction of the size, and it never flagged a correct sentence as wrong. It is slower per word than its size suggests. The two models below it can write vocabulary cards but cannot correct you. Gemma 3 1B scores 33% and missed all 69 real mistakes it was shown; LLaMA 3.2 1B scores 28% and did the same. Neither will catch anything, so don't read their silence as approval.")
                }
                .themedListRow()

                Section {
                    Text("Not reliably. Parameter count turned out to be a poor predictor of German quality in testing.\n\nOn the app's grammar test, a fine-tuned 2B Granite (62%) beat Mistral 7B (48%), a model three times its size, and Qwen3 8B (58%), four times its size. Qwen3 8B is the same download size as the E4B tutor and scored 58% against the tutor's 90%. German is unusually demanding, with four cases, three genders, separable verbs, and long compounds, and a model either picked those patterns up in training or it didn't.\n\nWhat matters more is what a model was trained on, and whether it was trained for this particular job. The E2B tutor is the smallest capable model here at around 2B parameters, and it outscores every general-purpose model tested, including the 8B ones, because it was fine-tuned on the exact correction format this app uses. The same holds one size up: the E4B tutor scores 90% where that model untuned scores 80%, so the training alone is worth about 10 points.\n\nThat gap is also why the app checks every flashcard against a dictionary instead of trusting the model.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Does a bigger model mean better German?")
                        .themedSectionHeader()
                }
                .themedListRow()

                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image("logo-wiktionary")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))

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
                        .themedSectionHeader()
                } footer: {
                    Text("This safety net makes smaller models more usable in practice — gender errors are caught automatically rather than silently ending up on your cards.")
                }
                .themedListRow()

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
                        .themedSectionHeader()
                }
                .themedListRow()
            }
            .themedListScreen()
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
    @Environment(\.appTheme) private var appTheme
    let model: MLXModel
    let badge: String?
    let badgeColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                model.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))

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
                                .clipShape(appTheme.pillShape)
                        }
                    }

                    Text(model.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label(model.deviceNote, systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 4) {
                        if !model.isAppleIntelligence {
                            Image(systemName: "arrow.down.circle")
                                .imageScale(.small)
                            Text("~\(formattedSize(model.approximateSizeMB))")
                            Text("·")
                        }
                        Text(model.parameterCount)
                        Text("·")
                        Text(model.quantization)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 16) {
                if let repoURL = model.huggingFaceRepoURL {
                    Link(destination: repoURL) {
                        Label("HuggingFace", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
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
