//
//  LevelCardSection.swift
//  german-ai-flashcards
//
//  The gamification strip at the top of the Home hub's For You mode: the level card (rank,
//  progress to next, "+N heute"), the Tagesziel ring (today's minutes against the goal), and
//  the pyramid teaser. Everything derives from the `StudyDay` log via `ExperienceService` /
//  `PyramidService` — this section stores nothing. Hidden entirely when Settings ▸ Gamification
//  is off; the ring and pyramid rows also follow their own per-feature switches.
//

import SwiftUI
import SwiftData

struct LevelCardSection: View {
    @Bindable var coordinator: GenerationCoordinator


    @Query private var studyDays: [StudyDay]
    @Query private var profiles: [LearnerProfile]
    @Query private var cards: [SavedCard]
    @Query private var prepositionStats: [PrepositionStat]
    @Query private var storyAttempts: [StoryQuizAttempt]
    @Query private var articleStats: [ArticleWordStat]
    @Query private var matchingStats: [MatchingPairStat]
    @Query private var conversations: [ChatConversation]

    private var level: LearnerLevel { ExperienceService.level(for: studyDays) }

    private var goalMinutes: Int { coordinator.modelManager.dailyGoalMinutes }

    private var goalProgress: Double {
        ExperienceService.dailyGoalProgress(studyDays, goalMinutes: goalMinutes)
    }

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

    private func pyramidCaption(_ layers: [PyramidLayerState]) -> String {
        let earned = PyramidService.overallEarnedFill(layers)
        let total = PyramidService.overallFill(layers)
        let built = "\(Int((earned * 100).rounded()))% built"
        guard total > earned + 0.005 else { return built }
        return "\(built) · \(Int(((total - earned) * 100).rounded()))% estimated"
    }

    var body: some View {
        Section {
            // Level card → Fortschritt.
            NavigationLink {
                FortschrittView(coordinator: coordinator)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(level.rank.tint, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Level \(level.level) · \(level.rank.germanName) (\(level.rank.englishName))")
                            .themedLabel(.subheadline, size: 15)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        ProgressView(value: level.progress)
                            .tint(level.rank.tint)
                    }
                    let today = ExperienceService.todayXP(studyDays)
                    if today > 0 {
                        Text("+\(today)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            }

            // Tagesziel ring.
            HStack(spacing: 12) {
                DailyGoalRing(progress: goalProgress, met: goalProgress >= 1)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tagesziel · Daily Goal")
                        .themedLabel(.subheadline, size: 15)
                        .fontWeight(.semibold)
                    Text(goalCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if goalProgress >= 1 {
                    Text("Geschafft! · Done!")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)

            // Pyramid teaser → Lernpyramide.
            if coordinator.modelManager.gamificationPyramidEnabled {
                let layers = pyramidLayers
                NavigationLink {
                    PyramidView(coordinator: coordinator)
                } label: {
                    HStack(spacing: 12) {
                        PyramidGlyph(layers: layers)
                            .frame(width: 38, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Deine Pyramide · Your Pyramid")
                                .themedLabel(.subheadline, size: 15)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            // "Built" always means proven. An estimate is reported beside it, never
                            // folded into it — the teaser must not quietly inflate the headline.
                            Text(pyramidCaption(layers))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Fortschritt · Progress").themedSectionHeader()
        }
        .themedListRow()
    }

    private var goalCaption: String {
        let minutes = ExperienceService.todaySeconds(studyDays) / 60
        if goalProgress >= 1 {
            return "\(minutes) of \(goalMinutes) minutes — goal met"
        }
        return "\(minutes) of \(goalMinutes) minutes today"
    }
}

// MARK: - Daily goal ring

/// The Apple-Watch-style ring: fills clockwise with today's minutes, closes into a check.
struct DailyGoalRing: View {
    let progress: Double
    let met: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(met ? Color.green : Color.orange,
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)
            if met {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily goal")
        .accessibilityValue("\(Int((min(1, progress) * 100).rounded())) percent")
    }
}
