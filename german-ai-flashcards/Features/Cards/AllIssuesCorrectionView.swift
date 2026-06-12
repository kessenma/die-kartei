import DieKarteiCore
import SwiftUI

struct AllIssuesCorrectionView: View {
    @Binding var cards: [VocabCard]
    @Binding var validationResults: [ValidationResult]
    var savedCards: [SavedCard]
    var onApplyCorrection: (Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var issueIndices: [Int] {
        validationResults.indices.filter { validationResults[$0].status.isCorrectable }
    }

    var body: some View {
        NavigationStack {
            Group {
                if issueIndices.isEmpty {
                    allFixedState
                } else {
                    issueList
                }
            }
            .navigationTitle("Fix Issues")
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

    @ViewBuilder
    private var issueList: some View {
        List {
            Section {
                ForEach(issueIndices, id: \.self) { index in
                    NavigationLink {
                        CorrectionSheetView(
                            germanWord: cards[index].germanWord,
                            englishWord: cards[index].englishTranslation,
                            validationResult: validationResults[index],
                            wordType: cards[index].wordType,
                            onApply: { newArticle in
                                applyCorrection(at: index, newArticle: newArticle)
                            }
                        )
                    } label: {
                        issueRow(index: index)
                    }
                }
            } header: {
                Text("\(issueIndices.count) issue\(issueIndices.count == 1 ? "" : "s") remaining")
            } footer: {
                Text("Tap a word to open the correction sheet.")
            }
        }
    }

    @ViewBuilder
    private func issueRow(index: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cards[index].germanWord)
                    .fontWeight(.medium)
                if let english = cards[index].englishTranslation as String?, !english.isEmpty {
                    Text(english)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ValidationBadgeView(result: validationResults[index])
        }
    }

    @ViewBuilder
    private var allFixedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("All Issues Fixed")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Every card has been corrected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applyCorrection(at index: Int, newArticle: String?) {
        if newArticle != nil {
            cards[index].article = newArticle
        }
        validationResults[index].status = .verified
        onApplyCorrection(index, newArticle)
    }
}
