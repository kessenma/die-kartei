import SwiftUI
import SwiftData

/// Every class handout, newest first. Reached from Library ▸ Reading.
struct ClassMaterialListView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \ClassMaterial.createdAt, order: .reverse) private var materials: [ClassMaterial]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if materials.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No handouts yet", systemImage: "graduationcap")
                    } description: {
                        Text("Add one from Home ▸ Deutschkurs, under the class it was given in.")
                    }
                }
                .themedListRow()
            } else {
                Section {
                    ForEach(materials) { material in
                        NavigationLink {
                            ClassMaterialDetailView(material: material, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            ClassMaterialRow(material: material, showsEntry: true)
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Swipe to remove a handout. The course's flashcard deck stays.")
                        .font(.caption2)
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Class handouts")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            ClassEntryStore.delete(materials[index], context: modelContext)
        }
        try? modelContext.save()
    }
}

#Preview("Class handouts · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            ClassMaterialListView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
        }
        .environment(ActivityRouter())
        .environment(\.appTheme, theme)
        .modelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self], inMemory: true)
    }
}
