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

    @State private var filter = StoryListFilter()

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

    /// The rows actually shown. `stories` stays the denominator — which pills the bar offers, and
    /// the "n of m" count — so the filters describe the whole library, not the current cut of it.
    private var visibleStories: [StudyStory] {
        filter.isActive ? stories.filter(filter.matches) : stories
    }

    private var presentLevels: [CEFRLevel] {
        let present = Set(stories.map(\.level))
        return CEFRLevel.allCases.filter(present.contains)
    }

    private var presentGenres: [StoryGenre] {
        let present = Set(stories.map(\.genre))
        return StoryGenre.allCases.filter(present.contains)
    }

    private var anyPictures: Bool { stories.contains { $0.coverImage != nil } }

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
            .themedListRow()

            // One story can't be filtered into anything but itself.
            if stories.count > 1 {
                filterSection
            }

            if !stories.isEmpty {
                storiesSection
            }
        }
        .themedListScreen()
        .navigationTitle("Short Stories")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    // MARK: - Sections

    private var filterSection: some View {
        Section {
            StoryFilterBar(
                filter: $filter,
                levels: presentLevels,
                genres: presentGenres,
                hasPictures: anyPictures
            )
            // The pills are their own chrome — a row card behind them would box in a strip that is
            // meant to scroll past the section's edges.
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            HStack {
                Text("Filter").themedSectionHeader()
                Spacer()
                if filter.isActive {
                    Button("Clear") {
                        withAnimation(.snappy(duration: 0.25)) { filter = StoryListFilter() }
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)          // grouped headers uppercase their text; a button isn't a header
                }
            }
        }
    }

    @ViewBuilder
    private var storiesSection: some View {
        if visibleStories.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No stories match", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing in your library fits these filters yet.")
                } actions: {
                    Button("Clear filters") {
                        withAnimation(.snappy(duration: 0.25)) { filter = StoryListFilter() }
                    }
                }
            }
            .themedListRow()
        } else {
            Section {
                ForEach(visibleStories, id: \.id) { story in
                    NavigationLink {
                        StoryDetailView(story: story, modelManager: modelManager, mlxService: mlxService)
                    } label: {
                        StoryRow(story: story, secondsRead: secondsByStory[story.id] ?? 0)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                HStack {
                    Text("Your Stories").themedSectionHeader()
                    Spacer()
                    if filter.isActive {
                        Text("\(visibleStories.count) of \(stories.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .themedListRow()
        }
    }

    // MARK: - Delete

    /// Offsets come from the rows on screen, so they index the filtered list — resolving them
    /// against `stories` would delete a different story whenever a filter is on.
    private func delete(at offsets: IndexSet) {
        let shown = visibleStories
        for story in offsets.compactMap({ $0 < shown.count ? shown[$0] : nil }) {
            StoryImageStore.deleteImages(for: story.id)
            modelContext.delete(story)
        }
        try? modelContext.save()
    }
}

// MARK: - Row

private struct StoryRow: View {
    let story: StudyStory
    /// Total time already spent reading or listening to this story, 0 if it's never been opened.
    let secondsRead: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only illustrated stories pay the extra row height.
            if let cover = story.coverImage {
                StoryIllustrationView(
                    record: cover,
                    storyID: story.id,
                    accent: story.genre.styleAccent,
                    maxHeight: 132
                )
                .accessibilityHidden(true)
            }

            HStack(alignment: .top, spacing: 11) {
                StoryStyleTile(genre: story.genre)

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

                    // The style name rides on the date line rather than the stats line: the tile
                    // beside it is only an icon, and the stats line has no room left on an iPhone.
                    HStack(spacing: 4) {
                        Text(story.genre.label)
                        Text("·")
                        Text(story.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The story's style as the same icon-on-gradient art the style gallery uses, at row size. Hidden
/// from VoiceOver because the row already names the style in words.
private struct StoryStyleTile: View {
    let genre: StoryGenre

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Image(systemName: genre.systemImage)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(
                genre.styleGradient,
                in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Level chip

extension CEFRLevel {
    /// The level's capsule color, shared by `CEFRLevelChip` and the list's level filter pills.
    var chipColor: Color {
        switch self {
        case .a1: .green
        case .a2: .teal
        case .b1: .blue
        case .b2: .indigo
        case .c1: .orange
        }
    }
}

/// Small colored capsule showing a CEFR level, shared by the story rows and detail header.
struct CEFRLevelChip: View {
    let level: CEFRLevel

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Text(level.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(level.chipColor, in: appTheme.pillShape)
    }
}

// MARK: - Preview

#Preview("Short stories · 4 themes") {
    let container = try! ModelContainer(
        for: StudyStory.self, StoryReadingSession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    // Enough spread that every filter has something to bite on. The picture files don't exist in a
    // preview, so illustrated rows show the placeholder — which is the row height that matters.
    let samples: [(String, CEFRLevel, StoryGenre, Int?, Bool)] = [
        ("Der verlorene Schlüssel", .a2, .krimi, 80, true),
        ("Ein Tag im Park", .a1, .alltag, nil, true),
        ("Die Reise zum Mars", .b2, .scifi, 100, false),
        ("Der Fuchs und die Krähe", .b1, .fabel, nil, false),
    ]
    for (title, level, genre, score, illustrated) in samples {
        let story = StudyStory(topic: title, level: level, genre: genre)
        story.title = title
        story.storyText = Array(repeating: "Wort", count: 140).joined(separator: " ")
        story.generationComplete = true
        story.bestScore = score
        if illustrated {
            story.setImages([
                StoryImageRecord(fileName: "00.png", prompt: "", paragraphAnchorIndex: nil)
            ])
        }
        container.mainContext.insert(story)
    }

    return ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            StoryListView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
        }
        .environment(\.appTheme, theme)
        .modelContainer(container)
    }
}
