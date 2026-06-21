import SwiftUI

/// The full, categorized scenario list. Tap one to select it and pop back.
struct ScenarioPickerView: View {
    @Binding var selected: ConversationScenario
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(ScenarioCategory.allCases) { category in
                Section {
                    ForEach(category.scenarios) { scenario in
                        row(scenario)
                    }
                } header: {
                    Label("\(category.germanTitle) · \(category.englishTitle)", systemImage: category.systemImage)
                }
            }

            Section {
                row(.custom)
            } header: {
                Text("Your own")
            }
        }
        .navigationTitle("Scenarios")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selected = ConversationScenario.random()
                    dismiss()
                } label: {
                    Label("Surprise me", systemImage: "die.face.5.fill")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    PhraseLibraryView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Phrase library", systemImage: "ear.badge.waveform")
                }
            }
        }
    }

    private func row(_ scenario: ConversationScenario) -> some View {
        Button {
            selected = scenario
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: scenario.systemImage)
                    .frame(width: 26)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scenario.germanTitle).foregroundStyle(.primary)
                    Text(scenario.englishDescription)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected == scenario {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
