import SwiftUI

/// Why a job posting is trimmed before the recruiter reads it, and to how much on this phone.
/// Same shape as the dictionary-validation explainer: a list of short rows and a Done button.
struct JobContextInfoSheet: View {
    let model: MLXModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Your budget")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(JobContextBudget.characters(for: model).formatted()) characters")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(JobContextBudget.reason(for: model))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("\(model.rawValue) on this phone")
                }

                Section {
                    BudgetExplainerRow(
                        icon: "text.book.closed",
                        label: "One window for everything",
                        explanation: "The tutor reads the posting, its recruiter instructions, and the whole conversation through one window of text. A posting that fills the window leaves no room for the interview, so the posting is trimmed first."
                    )
                    BudgetExplainerRow(
                        icon: "cpu",
                        label: "Bigger tutors read more",
                        explanation: "The window grows with the tutor. Gemma E4B reads about twice what the Granite tutors do, which is why the number changes when you pick a different model."
                    )
                    BudgetExplainerRow(
                        icon: "leaf",
                        label: "Memory Saver trims it further",
                        explanation: "On a phone close to its memory limit, Memory Saver keeps the tutor's memory of the chat to about a thousand words. The posting budget drops to fit inside that."
                    )
                } header: {
                    Text("Why there is a limit")
                }

                Section {
                    BudgetExplainerRow(
                        icon: "checklist",
                        label: "Tasks and profile first",
                        explanation: "The recruiter asks about what the role involves and what you bring. The Aufgaben and Profil sections carry nearly all of that."
                    )
                    BudgetExplainerRow(
                        icon: "scissors",
                        label: "Leave the rest",
                        explanation: "Benefits, the application process, and the company blurb rarely come up in the interview. Skip them when the meter runs orange."
                    )
                } header: {
                    Text("What to bring")
                } footer: {
                    Text("Anything past the budget is cut from the end, so the order you add sections in is the order the recruiter keeps.")
                }
            }
            .themedListScreen()
            .navigationTitle("Posting budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct BudgetExplainerRow: View {
    let icon: String
    let label: String
    let explanation: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
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
