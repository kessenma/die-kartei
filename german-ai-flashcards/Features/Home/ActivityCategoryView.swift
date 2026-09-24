//
//  ActivityCategoryView.swift
//  german-ai-flashcards
//
//  The spoke half of the Home hub. `HomeHubView`'s "All Activities" mode used to be one long
//  scrolling list of every tool grouped under six section headers — the tester's "too long a scroll".
//  Those six headers are now six tiles, and each tile pushes here: one category, its tools, nothing
//  else. The rows themselves are unchanged, just moved down a level.
//
//  Only categories holding more than one tool get this page. Speaking, Listening, and Batch hold
//  exactly one each, and a list of one is a tap in the way — their tiles push the tool itself.
//  Grammar does the same: its tile pushes the Grammar hub, which already holds every grammar tool.
//  `ActivityCategoryDestination` is the one place that decides which of the two a tile gets.
//
//  Card-producing launchers still route into the shared flashcard player via `ActivityRouter`;
//  reading tools are still pushed directly.
//

import SwiftUI
import SwiftData

// MARK: - Category

/// The six language-skill groupings the Home hub offers, in the order they appear in the grid.
///
/// Colors are the app's existing activity language (blue = cards, purple = grammar, pink = reading,
/// green = conversation, orange = listening, indigo = batch — the same assignments `DayDetailSheet`
/// uses for its timeline), so a category reads the same wherever the learner meets it. They're
/// *content*, not chrome: the theme reshapes a tile without recoloring it.
enum ActivityCategory: String, CaseIterable, Identifiable {
    case vocabulary, grammar, reading, speaking, listening, batch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary: "Vocabulary"
        case .grammar:    "Grammar"
        case .reading:    "Reading"
        case .speaking:   "Speaking"
        case .listening:  "Listening"
        case .batch:      "Batch"
        }
    }

    /// What's inside — deliberately a description rather than a tool count, which would drift the
    /// moment a tool is added.
    var subtitle: String {
        switch self {
        case .vocabulary: "Flashcards, Wortschatz, matching"
        case .grammar:    "Die vier Fälle · der · die · das · Präpositionen"
        case .reading:    "Stories, papers, scans"
        case .speaking:   "Conversation practice"
        case .listening:  "Your phrase library"
        case .batch:      "Queue jobs, run together"
        }
    }

    var systemImage: String {
        switch self {
        case .vocabulary: "rectangle.stack.fill"
        case .grammar:    "checklist"
        case .reading:    "book.pages"
        case .speaking:   "bubble.left.and.bubble.right.fill"
        case .listening:  "ear.badge.waveform"
        case .batch:      "moon.stars.fill"
        }
    }

    /// Grundform states each category as a geometric mark instead of a symbol — square, triangle,
    /// circle, half-circle, quarter-circle, diamond. The Bauhaus vocabulary, and the one place the
    /// theme changes *what* is drawn rather than how.
    var glyph: String {
        switch self {
        case .vocabulary: "■"
        case .grammar:    "▲"
        case .reading:    "●"
        case .speaking:   "◐"
        case .listening:  "◔"
        case .batch:      "◆"
        }
    }

    var tint: Color {
        switch self {
        case .vocabulary: .blue
        case .grammar:    .purple
        case .reading:    .pink
        case .speaking:   .green
        case .listening:  .orange
        case .batch:      .indigo
        }
    }
}

// MARK: - Destination

/// What a hub tile pushes to.
///
/// Vocabulary and Reading hold several tools each, so their tiles push the category page below — a
/// screen worth landing on. Speaking, Listening, and Batch hold exactly one tool, so their tiles
/// push that tool straight away rather than a page offering a single row. Grammar pushes its hub
/// directly for the same reason: the hub is already the page of grammar tools. Keeping the choice
/// here means `HomeHubView` builds every tile the same way.
struct ActivityCategoryDestination: View {
    let category: ActivityCategory
    @Bindable var coordinator: GenerationCoordinator
    /// Forwarded to the Create screen, which lives under Vocabulary.
    var onGenerationComplete: () -> Void

    var body: some View {
        switch category {
        case .vocabulary, .reading:
            ActivityCategoryView(
                category: category,
                coordinator: coordinator,
                onGenerationComplete: onGenerationComplete
            )
        case .grammar:
            GrammarHubView(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            )
        case .speaking:
            ConversationListView(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            )
        case .listening:
            PhraseLibraryView(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService
            )
        case .batch:
            BatchQueueView(coordinator: coordinator)
        }
    }
}

// MARK: - Category page

struct ActivityCategoryView: View {
    let category: ActivityCategory
    @Bindable var coordinator: GenerationCoordinator
    /// Forwarded to the Create screen, which is the one tool here that produces cards inline.
    var onGenerationComplete: () -> Void

    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    /// Vocabulary ▸ Flashcards from a document.
    @State private var showDocumentDeck = false

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    var body: some View {
        List {
            Section {
                rows
            } footer: {
                Text(category.subtitle).font(.caption2)
            }
            .themedListRow()
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .themedListScreen()
        .sheet(isPresented: $showDocumentDeck) {
            DocumentDeckImportView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService) { deck in
                // Let the sheet finish dismissing before the player covers the screen.
                DispatchQueue.main.async {
                    router.launch(.cardDeck(deckStore.session(for: deck, style: coordinator.modelManager.flashcardStyle)))
                }
            }
        }
    }

    // MARK: Rows (moved verbatim from HomeHubView's old sections)

    @ViewBuilder
    private var rows: some View {
        switch category {
        case .vocabulary:
            NavigationLink {
                HomeView(service: coordinator, onGenerationComplete: onGenerationComplete)
            } label: {
                ActivityRow("Generate Flashcards", "Create AI vocabulary on any topic", "sparkles")
            }
            Button {
                showDocumentDeck = true
            } label: {
                ActivityRow("Flashcards from a Document", "A vocab sheet, a handout, a story: paired or highlighted", "doc.plaintext")
            }
            .buttonStyle(.plain)
            NavigationLink {
                WortschatzHubView(coordinator: coordinator)
            } label: {
                ActivityRow("Wortschatz · Goethe", "A1–B1 word lists · due today · your word box", "archivebox")
            }
            NavigationLink {
                MatchingDeckPickerView(modelManager: coordinator.modelManager)
            } label: {
                ActivityRow("Card Matching", "Fast form ↔ meaning warm-up", "square.grid.2x2.fill")
            }

        case .reading:
            NavigationLink {
                StoryListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                ActivityRow("Read a Short Story", "The AI writes at your level, then quizzes you", "book.pages")
            }
            NavigationLink {
                PaperListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                ActivityRow("Study a Paper or Link", "Import a PDF or web page to study", "doc.text.magnifyingglass")
            }
            NavigationLink {
                PhotoScanListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                ActivityRow("Scan a Photo", "Extract German text from an image", "camera.viewfinder")
            }

        // One tool apiece (Grammar: its own hub), so their tiles push it directly
        // (`ActivityCategoryDestination`) and this page is never built for them.
        case .grammar, .speaking, .listening, .batch:
            EmptyView()
        }
    }
}

// MARK: - Row

/// One tool inside a category — the old `HomeHubView.hubRow`, unchanged apart from living here now.
struct ActivityRow: View {
    let title: String
    let subtitle: String
    let icon: String

    @Environment(\.appTheme) private var theme

    init(_ title: String, _ subtitle: String, _ icon: String) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                // `.tint` rather than a fixed accent, so the chip follows the theme (and, on Klar,
                // the loaded model) the same way the glyph on top of it already does.
                .background(.tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: theme.innerRadius(8), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .themedLabel(.subheadline, size: 15)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tile

/// One category on the hub grid. `LazyVGrid` already equalizes heights within a row, so the minimum
/// only has to stop a one-line tile from collapsing — it's kept low on purpose so all six tiles fit
/// above the tab bar without scrolling, which was the whole point of replacing the list.
struct ActivityCategoryTile: View {
    let category: ActivityCategory

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            emblem
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .themedLabel(.headline, size: 19)
                    .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
                    .tracking(theme.uppercaseSectionHeaders ? 0.8 : 0)
                    .foregroundStyle(.primary)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(13)
        .themedCard()
        .contentShape(Rectangle())
    }

    /// Grundform gets the geometric mark on a solid block; every other theme keeps the SF Symbol on
    /// a tinted chip, which is what the row it replaced already looked like.
    @ViewBuilder
    private var emblem: some View {
        if theme == .grundform {
            Text(category.glyph)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(category.tint)
        } else {
            Image(systemName: category.systemImage)
                .font(.title3)
                .foregroundStyle(category.tint)
                .frame(width: 40, height: 40)
                .background(category.tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: theme.innerRadius(10), style: .continuous))
        }
    }
}

// MARK: - Previews

@MainActor
private func categoryPreview(_ theme: AppTheme) -> some View {
    NavigationStack {
        ActivityCategoryView(
            category: .vocabulary,
            coordinator: GenerationCoordinator(modelManager: MLXModelManager()),
            onGenerationComplete: {}
        )
    }
    .environment(ActivityRouter())
    .environment(\.appTheme, theme)
    .modelContainer(for: [SavedDeck.self, StudyDay.self], inMemory: true)
}

#Preview("Category · System")   { categoryPreview(.klar) }
#Preview("Category · Notebook") { categoryPreview(.kritzel) }
#Preview("Category · Bauhaus")  { categoryPreview(.grundform) }

/// The hub grid itself. `HomeHubView` picks its mode from `@AppStorage`, which a preview can't
/// force, so the grid is previewed here from the same tile view the hub renders.
@MainActor
private func tileGridPreview(_ theme: AppTheme) -> some View {
    ScrollView {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
            spacing: 14
        ) {
            ForEach(ActivityCategory.allCases) { ActivityCategoryTile(category: $0) }
        }
        .padding(20)
    }
    .themedScreen()
    .environment(\.appTheme, theme)
}

#Preview("Hub grid · System")   { tileGridPreview(.klar) }
#Preview("Hub grid · Soft")     { tileGridPreview(.sanft) }
#Preview("Hub grid · Notebook") { tileGridPreview(.kritzel) }
#Preview("Hub grid · Bauhaus")  { tileGridPreview(.grundform) }
#Preview("Hub grid · Bauhaus dark") { tileGridPreview(.grundform).preferredColorScheme(.dark) }
