//
//  HomeHubView.swift
//  german-ai-flashcards
//
//  The Home tab. Two modes, switched by the segmented control at the top:
//  "For You" surfaces one recommended next exercise (from TodayPlanner + the learner profile)
//  so there's nothing to decide; "All Activities" is the full launcher grouped by language
//  skill (the hub in hub-and-spoke). Card-producing launchers route into the shared flashcard
//  player via `ActivityRouter`; reading/speaking/listening tools are pushed directly.
//

import SwiftUI
import SwiftData

struct HomeHubView: View {
    @Bindable var coordinator: GenerationCoordinator
    /// Bubbles up to ContentView, which owns the card-selection sheet + generated-deck save.
    var onGenerationComplete: () -> Void
    /// Bumped by ContentView on every Home tab press; the `.id` below recreates the stack,
    /// popping any pushed screens so the Home button always lands on this hub.
    var resetToken: Int = 0

    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    /// Off = "For You" (one picked next exercise), on = the full activity catalog.
    @AppStorage("home.showAllActivities") private var showAllActivities = false

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                modeSection

                if showAllActivities {
                    vocabularySection
                    grammarSection
                    readingSection
                    speakingSection
                    listeningSection
                    batchSection
                } else {
                    StreakCalendarSection()
                    WeekInReviewSection(coordinator: coordinator)
                    TodaySection(
                        coordinator: coordinator,
                        onGenerationComplete: onGenerationComplete,
                        style: .hero
                    )
                }
            }
            .navigationTitle("Home")
            .contentMargins(.bottom, 120, for: .scrollContent)
        }
        .id(resetToken)
    }

    // MARK: - Sections

    private var modeSection: some View {
        Section {
            Picker("Home mode", selection: $showAllActivities) {
                Text("For You").tag(false)
                Text("All Activities").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var vocabularySection: some View {
        Section {
            NavigationLink {
                HomeView(service: coordinator, onGenerationComplete: onGenerationComplete)
            } label: {
                hubRow("Generate Flashcards", "Create AI vocabulary on any topic", "sparkles")
            }
            ForEach(GoetheLevel.allCases) { level in
                NavigationLink {
                    GoetheVocabListView(
                        level: level,
                        onStartStudy: launchGoethe,
                        onStartPastTenseStudy: launchPastTense
                    )
                } label: {
                    hubRow("Goethe \(level.rawValue) Vocabulary", level.examName, "text.book.closed")
                }
            }
            NavigationLink {
                MatchingDeckPickerView(modelManager: coordinator.modelManager)
            } label: {
                hubRow("Card Matching", "Fast form ↔ meaning warm-up", "square.grid.2x2.fill")
            }
        } header: {
            Text("Vocabulary")
        }
    }

    private var grammarSection: some View {
        Section {
            NavigationLink {
                GrammarHubView(
                    modelManager: coordinator.modelManager,
                    mlxService: coordinator.mlxService,
                    onStartFlipCards: launchGrammarFlip,
                    onStartMultipleChoice: launchGrammarMC,
                    onStartPastTenseStudy: launchPastTense
                )
            } label: {
                hubRow("Grammar Exercises", "Akkusativ · Dativ · Perfekt · create your own with AI", "checklist")
            }
            NavigationLink {
                ArticleGameSetupView(
                    modelManager: coordinator.modelManager,
                    mlxService: coordinator.mlxService
                )
            } label: {
                hubRow("Der · Die · Das", "The article game — guess each noun's gender", "textformat.abc")
            }
        } header: {
            Text("Grammar")
        }
    }

    private var readingSection: some View {
        Section {
            NavigationLink {
                StoryListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                hubRow("Read a Short Story", "The AI writes at your level, then quizzes you", "book.pages")
            }
            NavigationLink {
                PaperListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                hubRow("Study a Paper or Link", "Import a PDF or web page to study", "doc.text.magnifyingglass")
            }
            NavigationLink {
                PhotoScanListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                hubRow("Scan a Photo", "Extract German text from an image", "camera.viewfinder")
            }
        } header: {
            Text("Reading")
        }
    }

    private var speakingSection: some View {
        Section {
            NavigationLink {
                ConversationListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                hubRow("Conversation Practice", "Talk with the on-device AI", "bubble.left.and.bubble.right")
            }
        } header: {
            Text("Speaking")
        }
    }

    private var listeningSection: some View {
        Section {
            NavigationLink {
                PhraseLibraryView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                hubRow("Phrase Library", "Phrases you've heard in the wild", "ear.badge.waveform")
            }
        } header: {
            Text("Listening")
        }
    }

    private var batchSection: some View {
        Section {
            NavigationLink {
                BatchQueueView(coordinator: coordinator)
            } label: {
                hubRow("Batch Queue", "Line up decks, stories, and pictures; run them all at once", "moon.stars.fill")
            }
        } header: {
            Text("Batch")
        }
    }

    @ViewBuilder
    private func hubRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Launch helpers (card-producing → router)

    private func launchGoethe(_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ label: String) {
        router.launch(.cardDeck(deckStore.goetheSession(cards: cards, topic: topic, style: style, label: label)))
    }

    private func launchPastTense(_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ label: String) {
        router.launch(.cardDeck(deckStore.pastTenseSession(cards: cards, topic: topic, style: style, label: label)))
    }

    private func launchGrammarFlip(_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ label: String) {
        router.launch(.cardDeck(deckStore.grammarFlipSession(cards: cards, topic: topic, style: style, label: label)))
    }

    private func launchGrammarMC(_ category: GrammarCategory, _ hints: Bool) {
        router.launch(.grammarMultipleChoice(category: category, showHints: hints))
    }
}
