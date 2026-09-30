//
//  UnifiedLibraryView.swift
//  german-ai-flashcards
//
//  The Library tab: a content archive for everything the user has made — flashcard decks,
//  conversations, imported papers/scans, and saved phrases. Purely browse/manage; launching
//  new activities lives on the Home hub. Replaces the flashcard-only SavedDecksView.
//

import SwiftUI
import SwiftData

struct UnifiedLibraryView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    enum Segment: String, CaseIterable, Identifiable {
        case decks = "Decks"
        case chats = "Chats"
        case reading = "Reading"
        case phrases = "Phrases"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .decks
    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var deckForStats: SavedDeck?
    /// The deck whose course is being chosen (the leading swipe's Course action).
    @State private var deckForCourse: SavedDeck?

    // Where each deck belongs and comes from, for the rows.
    @Query(sort: \ClassCourse.sortOrder) private var courses: [ClassCourse]
    @Query private var stories: [StudyStory]
    @Query private var papers: [StudyPaper]
    @Query private var handouts: [ClassMaterial]

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }
    private var browsableDecks: [SavedDeck] { decks.filter(\.isBrowsableContent) }

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .decks:
                    decksList
                case .chats:
                    ConversationListView(modelManager: modelManager, mlxService: mlxService, showsCreateActions: false)
                case .reading:
                    readingList
                case .phrases:
                    PhraseLibraryView(modelManager: modelManager, mlxService: mlxService, embedded: true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 340)
                }
            }
            .sheet(item: $deckForStats) { deck in
                DeckStatsSheet(deck: deck, sortedResults: deck.quizResults.sorted { $0.date > $1.date })
            }
            .confirmationDialog(
                "Which course is it for?",
                isPresented: Binding(get: { deckForCourse != nil }, set: { if !$0 { deckForCourse = nil } }),
                titleVisibility: .visible,
                presenting: deckForCourse
            ) { deck in
                ForEach(courses.filter { !$0.isArchived && $0.id != deck.courseID }) { course in
                    Button(course.name) { setCourse(course, for: deck) }
                }
                if let current = courses.first(where: { $0.id == deck.courseID }) {
                    Button("Take it off \(current.name)", role: .destructive) { setCourse(nil, for: deck) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { deck in
                Text("\(deck.topic) shows on the course's page under Deutschkurs. A deck is on one course at a time.")
            }
        }
    }

    // MARK: - Decks

    @ViewBuilder
    private var decksList: some View {
        List {
            if browsableDecks.isEmpty {
                ContentUnavailableView(
                    "No Saved Decks",
                    systemImage: "tray",
                    description: Text("Generate vocabulary and it will be saved here automatically.")
                )
            } else {
                let links = DeckLinks(courses: courses, stories: stories, papers: papers, handouts: handouts)
                DeckIconLegend()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(browsableDecks, id: \.id) { deck in
                    HStack(spacing: 0) {
                        Button {
                            router.launch(.cardDeck(deckStore.session(for: deck, style: modelManager.flashcardStyle)))
                        } label: {
                            SavedDeckRow(deck: deck, course: links.course(of: deck), source: links.source(of: deck))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                            .padding(.trailing, 16)

                        if !deck.quizResults.isEmpty {
                            Rectangle()
                                .fill(Color(uiColor: .separator))
                                .frame(width: 0.5)
                                .padding(.vertical, 8)
                            Button {
                                deckForStats = deck
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.tint)
                                    .frame(width: 60)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
                    .themedListRow()
                    // Leading edge, so the trailing swipe stays Delete where muscle memory puts
                    // it. `document(for:)` is nil for a deck that can't travel between devices.
                    .swipeActions(edge: .leading) {
                        if let document = DeckTransfer.document(for: deck) {
                            ShareLink(
                                item: document,
                                preview: SharePreview(
                                    deck.topic,
                                    image: Image(systemName: "rectangle.stack.fill")
                                )
                            ) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        // A course's own word deck stays on its course.
                        if !courses.isEmpty, !links.isCourseOwnDeck(deck) {
                            Button {
                                deckForCourse = deck
                            } label: {
                                Label("Course", systemImage: "graduationcap")
                            }
                            .tint(ClassNotesTile.tint)
                        }
                    }
                }
                .onDelete(perform: deleteDecks)
            }
        }
        .themedListScreen()
    }

    private func setCourse(_ course: ClassCourse?, for deck: SavedDeck) {
        deck.courseID = course?.id
        course?.updatedAt = .now
        try? modelContext.save()
        deckForCourse = nil
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            let deck = browsableDecks[index]
            // Stop an illustration run on this deck before the model objects go away, then drop
            // the whole picture directory — cards cascade-delete but their PNGs don't.
            if DeckIllustrationService.shared.illustratingDeckUUID == deck.id {
                DeckIllustrationService.shared.stop()
            }
            CardImageStore.deleteImages(for: deck.id)
            // A handout made from the document has its own copy of the file.
            ClassMaterialStore.delete(deck.sourceFile)
            modelContext.delete(deck)
        }
        try? modelContext.save()
    }

    // MARK: - Reading

    private var readingList: some View {
        List {
            Section {
                NavigationLink {
                    StoryListView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Short Stories", systemImage: "book.pages")
                }
                NavigationLink {
                    PaperListView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Papers & Links", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    PhotoScanListView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Photo Scans", systemImage: "camera.viewfinder")
                }
                NavigationLink {
                    JobPostingListView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Job Postings", systemImage: "briefcase.fill")
                }
                NavigationLink {
                    ClassMaterialListView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Class Handouts", systemImage: "graduationcap.fill")
                }
            } footer: {
                Text("AI-written stories at your level, German texts you've imported or scanned, the job ads you're studying, and the handouts from your German class. Open one to study its vocabulary and practice questions, or discuss it with the AI.")
            }
            .themedListRow()
        }
        .themedListScreen()
    }

}

// MARK: - Deck row components (moved from the retired SavedDecksView)

private struct DeckIconLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            Label("Examples", systemImage: "text.quote")
            Label("Verbs", systemImage: "character.book.closed")
            Label("Conjugations", systemImage: "tablecells")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.vertical, 2)
    }
}

/// What the Library says about where a deck belongs and where it came from: its course, and the
/// story, paper, scan or handout behind it. Built once per list render from four queries.
private struct DeckLinks {
    private let courseNames: [UUID: String]
    private let courseOwnDecks: Set<UUID>
    private let sources: [UUID: DeckSource]

    init(courses: [ClassCourse], stories: [StudyStory], papers: [StudyPaper], handouts: [ClassMaterial]) {
        courseNames = Dictionary(courses.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        courseOwnDecks = Set(courses.compactMap(\.deckID))
        var sources: [UUID: DeckSource] = [:]
        // A handout read with the deck says the least about where it came from, so it goes in
        // first and a story or paper that made the deck overwrites it.
        for handout in handouts {
            if let id = handout.glossaryDeckID {
                sources[id] = DeckSource(text: "Vocab for \u{201C}\(handout.title)\u{201D}", symbol: "doc.text")
            }
        }
        for paper in papers {
            if let id = paper.deckID {
                sources[id] = DeckSource(text: "From \u{201C}\(paper.title)\u{201D}", symbol: paper.sourceSymbol)
            }
        }
        for story in stories {
            if let id = story.deckID {
                sources[id] = DeckSource(text: "From the story \u{201C}\(story.title)\u{201D}", symbol: "book.pages")
            }
        }
        self.sources = sources
    }

    func course(of deck: SavedDeck) -> String? {
        deck.courseID.flatMap { courseNames[$0] }
    }

    func source(of deck: SavedDeck) -> DeckSource? {
        sources[deck.id]
    }

    func isCourseOwnDeck(_ deck: SavedDeck) -> Bool {
        courseOwnDecks.contains(deck.id)
    }
}

private struct DeckSource {
    let text: String
    let symbol: String
}

private struct SavedDeckRow: View {
    let deck: SavedDeck
    var course: String? = nil
    var source: DeckSource? = nil

    private var latestResult: QuizResult? {
        deck.quizResults.max(by: { $0.date < $1.date })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(deck.topic)
                    .font(.headline)
                Spacer()
                GeneratorBadge(deck: deck)
            }
            if course != nil || source != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { links }
                    VStack(alignment: .leading, spacing: 2) { links }
                }
                .font(.caption)
            }
            HStack(spacing: 10) {
                Label("\(deck.cards.count) cards", systemImage: "rectangle.stack")
                if deck.includeExamples {
                    Label("Examples", systemImage: "text.quote")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Examples")
                }
                if deck.wordTypeFilter.includesVerbs && deck.wordTypeFilter != .all {
                    Label("Verbs", systemImage: "character.book.closed")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Verbs")
                }
                if deck.includeConjugations {
                    Label("Conjugations", systemImage: "tablecells")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Conjugations")
                }
                if deck.hasPausedSession {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Paused session")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let latest = latestResult {
                HStack(spacing: 4) {
                    ModeIcon(mode: latest.studyMode)
                    Text("Last: \(latest.correctCount)/\(latest.totalCards) — \(latest.scorePercentage)%\(latest.durationSeconds > 0 ? " — \(latest.formattedDuration)" : "")")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(deck.createdAt, format: .dateTime.month(.abbreviated).day().year())
                if deck.generationTimeSeconds > 0 {
                    Text("·")
                    Label(generationTimeLabel(deck), systemImage: "timer")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var links: some View {
        if let course {
            Label(course, systemImage: "graduationcap.fill")
                .foregroundStyle(ClassNotesTile.tint)
                .lineLimit(1)
        }
        if let source {
            Label(source.text, systemImage: source.symbol)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func generationTimeLabel(_ deck: SavedDeck) -> String {
        let s = deck.generationTimeSeconds
        let cards = deck.cards.count
        if s < 60 {
            return cards > 0 ? "\(Int(s))s (\(String(format: "%.1f", s / Double(cards)))s/card)" : "\(Int(s))s"
        }
        let m = Int(s) / 60
        let rem = Int(s) % 60
        return "\(m)m \(rem)s"
    }
}

private struct GeneratorBadge: View {
    let deck: SavedDeck

    var body: some View {
        if let logoName = deck.generatorLogoName {
            Image(logoName)
                .resizable()
                .scaledToFit()
                .frame(height: 18)
        } else if let symbol = deck.kindSymbol {
            // Document decks (a story, a paper, a job posting) have no single generator to show.
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ModeIcon: View {
    let mode: FlashcardStyle

    var body: some View {
        switch mode {
        case .default:
            Image(systemName: "rectangle.on.rectangle")
        case .anki:
            Image(systemName: "brain")
        case .leitner:
            Image(systemName: "tray.2")
        }
    }
}

private struct DeckStatsSheet: View {
    let deck: SavedDeck
    let sortedResults: [QuizResult]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    private var averageScore: Int? {
        guard !sortedResults.isEmpty else { return nil }
        return sortedResults.reduce(0) { $0 + $1.scorePercentage } / sortedResults.count
    }

    private var bestScore: Int? {
        sortedResults.map(\.scorePercentage).max()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Cards", value: "\(deck.cards.count)")
                    LabeledContent("Quizzes taken", value: "\(sortedResults.count)")
                    if let avg = averageScore {
                        LabeledContent("Average score", value: "\(avg)%")
                    }
                    if let best = bestScore {
                        LabeledContent("Best score", value: "\(best)%")
                    }
                } header: {
                    Text("Overview").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    ForEach(sortedResults, id: \.id) { result in
                        HStack(spacing: 10) {
                            ModeIcon(mode: result.studyMode)
                                .frame(width: 16)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if result.incorrectCount > 0 {
                                    Text("\(result.incorrectCount) missed")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(result.correctCount)/\(result.totalCards)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(result.scorePercentage)%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Quiz History").themedSectionHeader()
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle(deck.topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let document = DeckTransfer.document(for: deck) {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(
                            item: document,
                            preview: SharePreview(
                                deck.topic,
                                image: Image(systemName: "rectangle.stack.fill")
                            )
                        )
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
