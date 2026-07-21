import SwiftUI
import SwiftData

/// Browse AI-written short stories and start a new one. Reached from Home ▸ Reading and
/// Library ▸ Reading.
struct StoryListView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \StudyStory.createdAt, order: .reverse) private var allStories: [StudyStory]
    @Query private var readingSessions: [StoryReadingSession]
    @Environment(\.modelContext) private var modelContext

    /// `storyID → seconds read`, so each row can show how much time it has actually taken.
    /// One query for the whole list beats a fetch per row.
    private var secondsByStory: [UUID: Int] {
        readingSessions.reduce(into: [:]) { map, session in
            map[session.storyID, default: 0] += session.seconds
        }
    }

    /// Stories that finished generating; stopped/failed runs are deleted by the setup screen,
    /// and anything orphaned mid-generation stays hidden here.
    private var stories: [StudyStory] { allStories.filter(\.generationComplete) }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    StorySetupView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("New Story", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            } footer: {
                Text("The German Tutor writes a short story at your level, then quizzes you on it — like the Lesen and Hören parts of the Goethe exams.")
            }

            if !stories.isEmpty {
                Section("Your Stories") {
                    ForEach(stories, id: \.id) { story in
                        NavigationLink {
                            StoryDetailView(story: story, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            StoryRow(story: story, secondsRead: secondsByStory[story.id] ?? 0)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Short Stories")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            StoryImageStore.deleteImages(for: stories[index].id)
            modelContext.delete(stories[index])
        }
        try? modelContext.save()
    }
}

private struct StoryRow: View {
    let story: StudyStory
    /// Total time already spent reading or listening to this story, 0 if it's never been opened.
    let secondsRead: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(story.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                CEFRLevelChip(level: story.level)
            }

            HStack(spacing: 10) {
                Label("\(story.wordCount) Wörter", systemImage: "text.alignleft")
                Text(story.genre.label)
                if story.lastStudiedAsListening {
                    Label("Hören", systemImage: "ear")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Listened")
                }
                if let best = story.bestScore {
                    Label("\(best)%", systemImage: "checkmark.seal")
                }
                if secondsRead > 0 {
                    Label(StoryProgressService.formatShort(secondsRead), systemImage: "timer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(story.createdAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// Small colored capsule showing a CEFR level, shared by the story rows and detail header.
struct CEFRLevelChip: View {
    let level: CEFRLevel

    private var color: Color {
        switch level {
        case .a1: .green
        case .a2: .teal
        case .b1: .blue
        case .b2: .indigo
        case .c1: .orange
        }
    }

    var body: some View {
        Text(level.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}
