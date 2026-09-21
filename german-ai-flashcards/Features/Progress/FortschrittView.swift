//
//  FortschrittView.swift
//  german-ai-flashcards
//
//  Fortschritt — the gamification home, pushed from the level card on Home. Three parts:
//  the level (rank, progress to the next), the Abzeichen grid (badges earned from real
//  milestones — evaluated here on appear, where new ones celebrate), and the pyramid teaser
//  into the Lernpyramide. Everything is derived from the study log + stats; this screen stores
//  nothing of its own.
//

import SwiftUI
import SwiftData

struct FortschrittView: View {
    @Bindable var coordinator: GenerationCoordinator

    @Environment(\.appTheme) private var theme

    @Query private var studyDays: [StudyDay]
    @Query private var profiles: [LearnerProfile]
    @Query private var cards: [SavedCard]
    @Query private var matchingRounds: [MatchingRound]
    @Query private var articleRounds: [ArticleRound]
    @Query private var prepositionRounds: [PrepositionRound]
    @Query private var storyAttempts: [StoryQuizAttempt]
    @Query private var prepositionStats: [PrepositionStat]
    @Query private var articleStats: [ArticleWordStat]
    @Query private var matchingStats: [MatchingPairStat]
    @Query private var conversations: [ChatConversation]

    @State private var badgeStates: [AchievementService.State] = []

    private var level: LearnerLevel { ExperienceService.level(for: studyDays) }

    private var pyramidLayers: [PyramidLayerState] {
        PyramidService.layers(from: PyramidService.snapshot(
            prepositionStats: prepositionStats,
            cards: cards,
            storyAttempts: storyAttempts,
            profile: profiles.first,
            studyDays: studyDays,
            articleStats: articleStats,
            matchingStats: matchingStats,
            placement: PlacementService.current,
            conversations: conversations
        ))
    }

    private let badgeColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        List {
            levelSection

            if coordinator.modelManager.gamificationBadgesEnabled {
                badgeSection
            }

            if coordinator.modelManager.gamificationPyramidEnabled {
                pyramidSection
            }

            journeySection
        }
        .navigationTitle("Fortschritt")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .themedListScreen()
        .onAppear { evaluateAchievements() }
    }

    // MARK: - Level

    private var levelSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(level.rank.tint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Level \(level.level) · \(level.rank.germanName)")
                        .themedLabel(.headline, size: 18)
                    Text(level.rank.englishName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(level.totalXP) XP")
                        .themedNumber(20)
                        .foregroundStyle(.primary)
                    let today = ExperienceService.todayXP(studyDays)
                    if today > 0 {
                        Text("+\(today) today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: level.progress)
                    .tint(level.rank.tint)
                Text("\(level.xpIntoLevel) / \(level.xpForNextLevel) XP to Level \(level.level + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Dein Level · Your Level").themedSectionHeader()
        } footer: {
            Text("XP is earned for everything: reviewing cards, drills, stories, conversations — and every minute you stick with it.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Badges

    private var badgeSection: some View {
        Section {
            LazyVGrid(columns: badgeColumns, spacing: 14) {
                ForEach(badgeStates) { state in
                    BadgeCell(state: state)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Abzeichen · Badges").themedSectionHeader()
        } footer: {
            Text("Badges come from real milestones — streaks, mastered words, perfect rounds. Earned in color, still waiting in grey.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Pyramid teaser

    private var pyramidSection: some View {
        let layers = pyramidLayers
        let fill = PyramidService.overallEarnedFill(layers)
        let estimated = PyramidService.overallFill(layers) - fill
        return Section {
            NavigationLink {
                PyramidView(coordinator: coordinator)
            } label: {
                HStack(spacing: 12) {
                    PyramidGlyph(layers: layers)
                        .frame(width: 44, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lernpyramide · Learning Pyramid")
                            .themedLabel(.subheadline, size: 15)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("\(Int((fill * 100).rounded()))% built — \(layers.filter(\.isComplete).count) of \(layers.count) layers"
                             + (estimated > 0.005 ? " · blueprint applied" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            if !conversations.isEmpty {
                NavigationLink {
                    ConversationQualityView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title3)
                            .foregroundStyle(PyramidLayerID.spitze.tint)
                            .frame(width: 44, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gespräche · Conversations")
                                .themedLabel(.subheadline, size: 15)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("How well you're holding them, and what the Spitze asks for")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Der Weg · The Path").themedSectionHeader()
        }
        .themedListRow()
    }

    // MARK: - Journey

    /// „Dein Weg" — the timeline of where the learner started and everything conquered since.
    /// Not gated on the pyramid switch: the journey is broader than one visualization.
    private var journeySection: some View {
        Section {
            NavigationLink {
                JourneyView(modelManager: coordinator.modelManager)
            } label: {
                HStack(spacing: 12) {
                    BauhausIcon(assetName: "pyramid-icon-weiterbauen",
                                fallbackSystemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                fallbackTint: .orange,
                                fallbackBackground: Color.orange.opacity(0.14),
                                size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dein Weg · Your Journey")
                            .themedLabel(.subheadline, size: 15)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("Where you started, what you've conquered, how far you've come")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .themedListRow()
    }

    // MARK: - Evaluation

    /// Builds the snapshot from live data and runs the badge rules. Newly earned badges fire
    /// their celebration through the shared center (shown by the overlay at the app root).
    @MainActor
    private func evaluateAchievements() {
        let snapshot = AchievementSnapshot(
            streak: StudyLogService.currentStreak(studyDays),
            savedCards: cards.count,
            cardsReviewed: studyDays.reduce(0) { $0 + $1.cardsReviewed },
            conversations: studyDays.reduce(0) { $0 + $1.conversations },
            perfectMatchingRound: matchingRounds.contains(where: \.isPerfect),
            perfectArticleRound: articleRounds.contains(where: \.isPerfect),
            perfectPrepositionRound: prepositionRounds.contains(where: \.isPerfect),
            storyQuizzes: storyAttempts.count,
            perfectStoryQuiz: storyAttempts.contains(where: \.isPerfect),
            solidGrammarSkills: solidGrammarCount,
            completedPyramidLayers: pyramidLayers.filter(\.isComplete).count
        )
        badgeStates = AchievementService.evaluate(
            snapshot: snapshot,
            manager: coordinator.modelManager,
            celebrate: true
        ) { _ in /* the center presents; nothing extra to do here */ }
    }

    /// Skills the coach has seen and currently rates below the shaky threshold.
    private var solidGrammarCount: Int {
        let grammar = profiles.first?.grammar ?? [:]
        return GrammarFocus.allCases.filter { focus in
            guard let skill = grammar[focus.rawValue] else { return false }
            return skill.struggle < GrammarSkill.shakyThreshold
        }.count
    }
}

// MARK: - Badge cell

/// One badge in the grid: earned = its accent on a filled circle; unearned = grey outline,
/// dimmed icon, no date. Tapping an earned badge names the date.
private struct BadgeCell: View {
    let state: AchievementService.State

    @State private var showingDate = false

    var body: some View {
        Button {
            if state.isEarned { showingDate = true }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: state.achievement.systemImage)
                    .font(.title3)
                    .foregroundStyle(state.isEarned ? .white : .secondary)
                    .frame(width: 52, height: 52)
                    .background(
                        state.isEarned ? state.achievement.accent : Color(.tertiarySystemFill),
                        in: Circle()
                    )
                Text(state.achievement.germanTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.isEarned ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.achievement.englishSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.achievement.germanTitle)
        .accessibilityHint(state.isEarned ? "Earned" : "Not yet earned — \(state.achievement.englishSubtitle)")
        .alert(state.achievement.germanTitle, isPresented: $showingDate) {
            Button("OK") {}
        } message: {
            if let date = state.earnedAt {
                Text("\(state.achievement.englishSubtitle)\n\nEarned \(date.formatted(date: .abbreviated, time: .omitted))")
            }
        }
    }
}
