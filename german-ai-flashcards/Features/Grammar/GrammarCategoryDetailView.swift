import DieKarteiCore
import SwiftUI

struct GrammarCategoryDetailView: View {
    let category: GrammarCategory
    var onStartFlipCards: ((_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void)?
    var onStartMultipleChoice: ((_ category: GrammarCategory, _ showHints: Bool) -> Void)?

    @State private var studyMode: GrammarStudyMode = .multipleChoice
    @State private var selectedFlipStyle: FlashcardStyle = .default
    @State private var showHints = false

    var body: some View {
        List {
            ruleSection
            studyOptionsSection
            exerciseListSection
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var ruleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(category.ruleNote)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Rule")
        }
    }

    private var studyOptionsSection: some View {
        Section {
            Picker("Study Mode", selection: $studyMode) {
                ForEach(GrammarStudyMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if studyMode == .flipCards {
                Picker("Flip Card Style", selection: $selectedFlipStyle) {
                    ForEach(FlashcardStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }

            if studyMode == .multipleChoice {
                Toggle("Show hints", isOn: $showHints)
            }

            Button(action: startStudy) {
                Label(
                    "Study \(category.exercises.count) Exercises",
                    systemImage: studyMode == .multipleChoice ? "checklist" : "rectangle.stack.fill"
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(category.exercises.isEmpty)
        } header: {
            HStack {
                Text("Study")
                Spacer()
                Text("\(category.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if studyMode == .multipleChoice {
                if showHints {
                    Text("Verb shown in green, noun in orange. Gender badge appears below the blank.")
                } else {
                    Text("See the sentence, pick from 3 options — the card reveals if you were right or wrong.")
                }
            } else {
                Text("Front shows the sentence with a blank. Flip to reveal the correct answer.")
            }
        }
    }

    private var exerciseListSection: some View {
        Section("Exercises") {
            ForEach(category.exercises) { exercise in
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.sentence)
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        Text(exercise.correctAnswer)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                        if !exercise.noun.isEmpty {
                            Text("· \(exercise.noun) (\(exercise.gender))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func startStudy() {
        switch studyMode {
        case .multipleChoice:
            onStartMultipleChoice?(category, showHints)
        case .flipCards:
            let cards = GrammarExerciseService.toVocabCards(category: category)
            let label = "\(cards.count) exercises · \(category.subtitle)"
            onStartFlipCards?(cards, category.title, selectedFlipStyle, label)
        }
    }
}
