import SwiftUI
import SwiftData

/// Every posting the learner is studying, newest activity first. Reached from the Job prep hub
/// (when there are more than a few) and from Library ▸ Reading.
struct JobPostingListView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \JobPosting.updatedAt, order: .reverse) private var postings: [JobPosting]
    @Environment(\.modelContext) private var modelContext

    @State private var showImport = false
    @State private var openedPosting: JobPosting?

    var body: some View {
        List {
            if postings.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No postings yet", systemImage: "briefcase")
                    } description: {
                        Text("Bring a job ad over and read it with the tutor's help.")
                    } actions: {
                        Button("Study a job ad") { showImport = true }
                    }
                }
                .themedListRow()
            } else {
                Section {
                    ForEach(postings) { posting in
                        NavigationLink {
                            JobPostingDetailView(posting: posting, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            JobPostingRow(posting: posting, deck: JobDeckStore.deck(for: posting, context: modelContext))
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Swipe to remove a posting. Its flashcard deck stays in the Library.")
                        .font(.caption2)
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Job postings")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImport = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Study a job ad")
            }
        }
        .navigationDestination(item: $openedPosting) { posting in
            JobPostingDetailView(posting: posting, modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(isPresented: $showImport) {
            JobPostingImportView(modelManager: modelManager, mlxService: mlxService) { posting in
                DispatchQueue.main.async { openedPosting = posting }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let posting = postings[index]
            JobPostingSnapshotStore.delete(posting.snapshotFile)
            modelContext.delete(posting)
        }
        try? modelContext.save()
    }
}
