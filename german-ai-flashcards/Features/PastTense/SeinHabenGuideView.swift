import SwiftUI

struct SeinHabenGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About 80% of German verbs use **haben** in the Perfekt tense. The remaining 20% use **sein**. Rather than memorizing each verb individually, learn to recognize the patterns — most sein verbs fall into just a few categories.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("The 80/20 Rule")
                }

                Section {
                    RuleRow(
                        icon: "arrow.right.circle.fill",
                        iconColor: .green,
                        title: "Movement / Change of Location",
                        examples: "gehen, fahren, fliegen, kommen, laufen, reisen, reiten, steigen"
                    )
                    RuleRow(
                        icon: "waveform.path.ecg",
                        iconColor: .orange,
                        title: "Change of State",
                        examples: "einschlafen, aufwachen, sterben, werden, wachsen, aufwachsen"
                    )
                    RuleRow(
                        icon: "staroflife.fill",
                        iconColor: .blue,
                        title: "sein, bleiben & a few fixed exceptions",
                        examples: "sein → gewesen, bleiben → geblieben, passieren → passiert, gelingen → gelungen, entstehen → entstanden, erscheinen → erschienen"
                    )
                } header: {
                    HStack(spacing: 6) {
                        Text("sein")
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                        Text("verbs — when to use it")
                    }
                } footer: {
                    Text("If the verb describes movement or a change in state, it's likely sein.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Austrian German uses **sein** for liegen, stehen, and sitzen:")
                            .font(.subheadline)
                        dialectRow("liegen", austrianForm: "ist gelegen", germanForm: "hat gelegen")
                        dialectRow("stehen", austrianForm: "ist gestanden", germanForm: "hat gestanden")
                        dialectRow("sitzen", austrianForm: "ist gesessen", germanForm: "hat gesessen")
                        Text("The flashcard decks in this app use standard German (haben) for these verbs.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Regional Variation")
                } footer: {
                    Text("Austria uses sein; Germany uses haben for these three verbs.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        tipRow("Trennbare (separable) verbs inherit the auxiliary of their base verb: abfahren → ist abgefahren (fahren = sein).")
                        tipRow("Inseparable prefix verbs (be-, er-, ver-, ent-...) almost always use haben, even if the base verb takes sein: besteigen → hat bestiegen.")
                        tipRow("Reflexive verbs always use haben: sich waschen → hat sich gewaschen.")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Extra Tips")
                }
            }
            .navigationTitle("sein vs. haben")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func dialectRow(_ verb: String, austrianForm: String, germanForm: String) -> some View {
        HStack(spacing: 12) {
            Text(verb)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("🇦🇹")
                    Text(austrianForm)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text("🇩🇪")
                    Text(germanForm)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RuleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let examples: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(examples)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
