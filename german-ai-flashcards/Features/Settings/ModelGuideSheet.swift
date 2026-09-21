import SwiftUI

struct ModelGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    /// Only the two rows that mark a real decision point: the best measured tutor, and the best
    /// one for a phone that can't hold a Gemma. The middle two need no badge — their size line
    /// already says where they sit, and badging every row would badge nothing.
    private func guideBadge(_ model: MLXModel) -> String? {
        switch model {
        case .gemma4_E4B_german:   "Best measured"
        case .granite41_3B_german: "Best under 2 GB"
        default:                   nil
        }
    }

    private func guideBadgeColor(_ model: MLXModel) -> Color? {
        guideBadge(model) == nil ? nil : model.theme.accent
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MLXModel.germanTutors) { model in
                        GuideRow(
                            model: model,
                            badge: guideBadge(model),
                            badgeColor: guideBadgeColor(model)
                        )
                    }
                } header: {
                    Text("The German tutors")
                        .themedSectionHeader()
                } footer: {
                    Text("If your phone runs one of these, use it. All four were fine-tuned on the same German material for this app, on the parts learners actually get wrong: verbs with prepositions, separable and reflexive verbs, da-/wo-compounds, relative pronouns, Konjunktiv II. On the app's own 203-item test the E4B tutor scores 90%, the E2B 83%, the Granite 3B 81%, and the Granite 2B 75%. They differ in download size and memory, not in what they were taught, so pick the largest one your phone runs comfortably. They're also trained to correct you without inventing mistakes you didn't make, which is what makes conversation practice worth trusting.")
                }
                .themedListRow()

                Section {
                    GuideRow(model: .appleIntelligence, badge: "No download", badgeColor: .secondary)
                } header: {
                    Text("Built in to iOS")
                        .themedSectionHeader()
                } footer: {
                    Text("Apple's on-device model, on phones that support it. Nothing to download and it starts instantly, but it's weaker at German than the tutors: 60% on the same test, 0 of 15 on da-/wo-compounds, and it flags about one already-correct sentence in six as wrong. Good for quick vocabulary work while a tutor downloads; for correction practice, use a tutor.")
                }
                .themedListRow()

                Section {
                    Text("Not reliably. Parameter count turned out to be a poor predictor of German quality in testing.\n\nThe Granite 2B tutor, at 1.4 GB, scores 75% on this app's grammar test. Several general-purpose models of 7\u{2013}8B parameters were measured on the same test and landed in the 40s and 50s, at roughly four times the download. German is unusually demanding, with four cases, three genders, separable verbs, and long compounds, and a model either picked those patterns up in training or it didn't.\n\nWhat matters more is whether a model was trained for this particular job. The E4B tutor scores 90% where the same model untuned scores 80%, so the fine-tuning alone is worth about ten points. That's why this app ships its own tutors instead of a general-purpose model.\n\nIt's also why the app checks every flashcard against a dictionary instead of trusting the model.")
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
