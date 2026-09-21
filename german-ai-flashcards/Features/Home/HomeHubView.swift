//
//  HomeHubView.swift
//  german-ai-flashcards
//
//  The Home tab. Two modes, switched by the segmented control at the top:
//  "For You" surfaces one recommended next exercise (from TodayPlanner + the learner profile)
//  so there's nothing to decide; "All Activities" is a six-tile grid of language-skill categories
//  — the hub in hub-and-spoke. Each tile pushes its `ActivityCategoryDestination`: a category page
//  listing the tools where there are several, or the tool itself where the category holds only one.
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

    /// Off = "For You" (one picked next exercise), on = the six-tile activity hub.
    @AppStorage("home.showAllActivities") private var showAllActivities = false

    /// Feeds the gamification triggers (goal met / level up / streak milestone). All three
    /// dedupe in `CelebrationCenter`, so re-evaluating on every log change is cheap and safe.
    @Query private var studyDays: [StudyDay]

    /// For the weekly journey snapshot, which self-throttles inside `recordIfDue`.
    @Environment(\.modelContext) private var modelContext

    /// Two columns; each tile sizes itself (`ActivityCategoryTile`), giving a 3×2 grid.
    private let tileColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    /// Matches the inset a grouped `List` gives its section cards, so the mode picker doesn't jump
    /// sideways when you switch between the two modes.
    private let hubInset: CGFloat = 20

    var body: some View {
        NavigationStack {
            if showAllActivities {
                activityHub
            } else {
                forYouList
            }
        }
        .id(resetToken)
    }

    // MARK: - For You

    private var forYouList: some View {
        List {
            Section {
                modePicker
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            // Sits above everything, in both Home modes, until a tutor is on disk. Renders nothing
            // once one is — and nothing at all on a device no tutor fits.
            Section {
                ModelUpgradeNudge(kind: .tutor, mlxService: coordinator.mlxService)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if coordinator.modelManager.gamificationEnabled {
                LevelCardSection(coordinator: coordinator)
            }
            StreakCalendarSection()
            WeekInReviewSection(coordinator: coordinator)
            TodaySection(
                coordinator: coordinator,
                onGenerationComplete: onGenerationComplete,
                style: .hero
            )
        }
        .navigationTitle("Home")
        .contentMargins(.bottom, 120, for: .scrollContent)
        .themedListScreen()
        .onAppear { evaluateGamification() }
        .onChange(of: studyDays) { evaluateGamification() }
    }

    private func evaluateGamification() {
        CelebrationCenter.shared.evaluate(studyDays: studyDays, manager: coordinator.modelManager)
        // The journey record: a ~weekly numeric snapshot + newly detected milestones. Returns
        // immediately when the last snapshot is fresh, so riding this hook costs nothing.
        ProgressSnapshotService.recordIfDue(in: modelContext)
    }

    // MARK: - All Activities — the six-tile hub

    /// Six categories, one screenful, instead of the thirteen-row scroll this replaces, plus the
    /// wide Job prep card beneath them (a goal, not a seventh skill — see `JobPrepTile`). A
    /// `ScrollView` rather than a `List` on purpose: the grid is the point, and stepping outside
    /// grouped chrome is also what lets Grundform's tiles keep genuinely square corners (a grouped
    /// section clips its rows to a rounded rect we don't control — see docs/theme-upgrade.md §3).
    private var activityHub: some View {
        ScrollView {
            VStack(spacing: 18) {
                modePicker

                ModelUpgradeNudge(kind: .tutor, mlxService: coordinator.mlxService)

                VStack(spacing: 14) {
                    LazyVGrid(columns: tileColumns, spacing: 14) {
                        ForEach(ActivityCategory.allCases) { category in
                            NavigationLink {
                                ActivityCategoryDestination(
                                    category: category,
                                    coordinator: coordinator,
                                    onGenerationComplete: onGenerationComplete
                                )
                            } label: {
                                ActivityCategoryTile(category: category)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NavigationLink {
                        JobPrepHubView(
                            modelManager: coordinator.modelManager,
                            mlxService: coordinator.mlxService
                        )
                    } label: {
                        JobPrepTile()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, hubInset)
            .padding(.top, 8)
        }
        .navigationTitle("Home")
        .contentMargins(.bottom, 120, for: .scrollContent)
        .themedScreen()
    }

    // MARK: - Shared

    private var modePicker: some View {
        Picker("Home mode", selection: $showAllActivities) {
            Text("For You").tag(false)
            Text("All Activities").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Previews

/// The Home hub under one theme. Separate `#Preview`s rather than one that loops, because each
/// carries a full `NavigationStack` and they're easier to read side by side in the canvas.
@MainActor
private func homeHubPreview(_ theme: AppTheme) -> some View {
    HomeHubView(
        coordinator: GenerationCoordinator(modelManager: MLXModelManager()),
        onGenerationComplete: {}
    )
    .environment(ActivityRouter())
    .environment(\.appTheme, theme)
    .modelContainer(
        for: [SavedDeck.self, SavedCard.self, StudyDay.self, LearnerProfile.self,
              ChatConversation.self, PrepositionStat.self, StoryQuizAttempt.self, JobPosting.self],
        inMemory: true
    )
}

#Preview("For You · System")   { homeHubPreview(.klar) }
#Preview("For You · Soft")     { homeHubPreview(.sanft) }
#Preview("For You · Notebook") { homeHubPreview(.kritzel) }
#Preview("For You · Bauhaus")  { homeHubPreview(.grundform) }
#Preview("For You · Bauhaus dark") {
    homeHubPreview(.grundform).preferredColorScheme(.dark)
}
