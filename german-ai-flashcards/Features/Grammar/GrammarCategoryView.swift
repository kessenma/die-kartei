import DieKarteiCore
import SwiftUI

struct GrammarCategoryView: View {
    var onStartFlipCards: ((_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void)?
    var onStartMultipleChoice: ((_ category: GrammarCategory, _ showHints: Bool) -> Void)?

    @State private var categories: [GrammarCategory] = []
    @State private var isLoading = true

    private var grouped: [String: [GrammarCategory]] {
        Dictionary(grouping: categories, by: \.grammaticalCase)
    }

    private let caseOrder = ["akkusativ", "dativ"]

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().padding()
                    Spacer()
                }
            } else {
                ForEach(caseOrder.filter { grouped[$0] != nil }, id: \.self) { caseKey in
                    Section {
                        ForEach(grouped[caseKey]!) { category in
                            NavigationLink {
                                GrammarCategoryDetailView(
                                    category: category,
                                    onStartFlipCards: onStartFlipCards,
                                    onStartMultipleChoice: onStartMultipleChoice
                                )
                            } label: {
                                GrammarCategoryRow(category: category)
                            }
                        }
                    } header: {
                        Text(caseKey.capitalized)
                    }
                }
            }
        }
        .navigationTitle("Grammar Exercises")
        .navigationBarTitleDisplayMode(.large)
        .task {
            categories = GrammarExerciseService.loadCategories()
            isLoading = false
        }
    }
}

private struct GrammarCategoryRow: View {
    let category: GrammarCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(category.title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 6) {
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(category.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
