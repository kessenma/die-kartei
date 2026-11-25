//
//  JourneyService.swift
//  german-ai-flashcards
//
//  Assembles „Dein Weg" — the learner's journey — from records the app already keeps. Almost
//  everything here is *derived*, not stored: placement checks carry their own dates, mastered
//  slips their `archivedAt`, badges their earned date, and the never-pruned `StudyDay` log lets
//  streak milestones and level-ups be replayed years later. Only what no record dates (layer
//  completions, comeback words, probe outcomes) arrives via `RecordedMilestone`.
//
//  Earned-only, like the pyramid: placement rows are *blueprint* events — the check drew or
//  redrew the outline — never progress. The moment a retake could manufacture a milestone, the
//  timeline would stop meaning anything.
//

import SwiftUI

/// One dated row on the timeline.
struct JourneyEvent: Identifiable {
    let id: String
    let date: Date
    let systemImage: String
    /// Bauhaus icon asset slug (`pyramid-icon-<slug>`), where one exists; SF Symbol otherwise.
    let assetSlug: String?
    let tint: Color
    let title: String
    let subtitle: String
}

@MainActor
enum JourneyService {

    /// Mirrors `CelebrationCenter.streakMilestones` (private there); a run crossing one of these
    /// is worth a timeline row.
    static let streakMilestones = [7, 14, 30, 50, 100, 200, 365]

    // MARK: - Assembly

    static func events(
        studyDays: [StudyDay],
        attempts: [PlacementAttempt],
        archived: [ArchivedMemoryItem],
        badges: [AchievementService.State],
        storyAttempts: [StoryQuizAttempt],
        conversations: [ChatConversation],
        recorded: [RecordedMilestone]
    ) -> [JourneyEvent] {
        var out: [JourneyEvent] = []
        out += startEvent(studyDays)
        out += placementEvents(attempts)
        out += masteredEvents(archived)
        out += badgeEvents(badges)
        out += storyEvents(storyAttempts)
        out += conversationEvent(conversations)
        out += streakEvents(studyDays)
        out += levelEvents(studyDays)
        out += recorded.map(event(for:))
        return out.sorted { $0.date > $1.date }
    }

    // MARK: - Sources

    private static func startEvent(_ studyDays: [StudyDay]) -> [JourneyEvent] {
        guard let first = studyDays.filter(\.hasActivity).min(by: { $0.dayStart < $1.dayStart }) else { return [] }
        return [JourneyEvent(
            id: "start", date: first.dayStart,
            systemImage: "square.grid.3x3.bottomleft.filled", assetSlug: "grundstein", tint: .orange,
            title: "Der erste Stein",
            subtitle: "You started building"
        )]
    }

    /// Blueprint events, one per kept check — including "starting from zero" declarations, which
    /// are real dated decisions. The comparison reads against the next-older check, the same
    /// pairing the placement review uses.
    private static func placementEvents(_ attempts: [PlacementAttempt]) -> [JourneyEvent] {
        // Newest first, as the store hands them out.
        attempts.enumerated().map { index, attempt in
            let previous = index + 1 < attempts.count ? attempts[index + 1] : nil
            if attempt.isBeginnerDeclaration {
                return JourneyEvent(
                    id: "placement-\(attempt.id)", date: attempt.takenAt,
                    systemImage: "square.dashed", assetSlug: "bauplan", tint: .blue,
                    title: "Von null gestartet",
                    subtitle: "No blueprint — building from scratch"
                )
            }
            let level = attempt.result.estimatedLevel.rawValue
            var subtitle = index == attempts.count - 1
                ? "Where you started — the check drew your first blueprint"
                : "The check redrew the blueprint"
            if let previous, !previous.isBeginnerDeclaration,
               previous.result.estimatedLevel != attempt.result.estimatedLevel {
                subtitle = "\(previous.result.estimatedLevel.rawValue) → \(level) since the last check"
            }
            return JourneyEvent(
                id: "placement-\(attempt.id)", date: attempt.takenAt,
                systemImage: "square.dashed", assetSlug: "bauplan", tint: .blue,
                title: "Bauplan gezeichnet · \(level)",
                subtitle: subtitle
            )
        }
    }

    private static func masteredEvents(_ archived: [ArchivedMemoryItem]) -> [JourneyEvent] {
        archived.filter { $0.reason == .mastered }.map { item in
            JourneyEvent(
                id: "mastered-\(item.id)", date: item.archivedAt,
                systemImage: "checkmark.seal", assetSlug: "gemeistert", tint: .green,
                title: "«\(item.title)» gemeistert",
                subtitle: "You used it correctly — the coach let it go"
            )
        }
    }

    /// Earned Abzeichen. Caveat: the first-ever badge evaluation seeds silently, so anything
    /// earned *before* gamification landed carries the seed date, not the true one.
    private static func badgeEvents(_ badges: [AchievementService.State]) -> [JourneyEvent] {
        badges.compactMap { state in
            guard state.isEarned, let earnedAt = state.earnedAt else { return nil }
            return JourneyEvent(
                id: "badge-\(state.achievement.id)", date: earnedAt,
                systemImage: state.achievement.systemImage, assetSlug: state.achievement.assetSlug,
                tint: state.achievement.accent,
                title: "\(state.achievement.germanTitle) · Abzeichen",
                subtitle: state.achievement.englishSubtitle
            )
        }
    }

    /// The first story understood per level — one row each, not one per quiz.
    private static func storyEvents(_ attempts: [StoryQuizAttempt]) -> [JourneyEvent] {
        let passed = attempts.filter { $0.scorePercentage >= PyramidService.storyPassScore }
        return Dictionary(grouping: passed, by: \.levelRaw).compactMap { levelRaw, group in
            guard let first = group.min(by: { $0.date < $1.date }) else { return nil }
            return JourneyEvent(
                id: "story-\(levelRaw)", date: first.date,
                systemImage: "book.pages", assetSlug: "geschichtenA1", tint: .pink,
                title: "Erste \(levelRaw)-Geschichte verstanden",
                subtitle: "«\(first.storyTitle)» — your first \(levelRaw) story"
            )
        }
    }

    private static func conversationEvent(_ conversations: [ChatConversation]) -> [JourneyEvent] {
        let first = conversations
            .sorted { $0.createdAt < $1.createdAt }
            .first { ConversationQualityService.isWellHeld($0) }
        guard let first else { return [] }
        return [JourneyEvent(
            id: "conversation-first-well-held", date: first.createdAt,
            systemImage: "bubble.left.and.bubble.right.fill", assetSlug: "spitze", tint: .green,
            title: "Erstes gutes Gespräch",
            subtitle: "A conversation held well — the peak is speaking"
        )]
    }

    /// Streak milestones replayed from the study log: walk the active days in order and emit a
    /// row whenever a consecutive run first reaches a milestone length.
    private static func streakEvents(_ studyDays: [StudyDay]) -> [JourneyEvent] {
        let calendar = Calendar.current
        let days = studyDays.filter(\.hasActivity).map(\.dayStart).sorted()
        guard !days.isEmpty else { return [] }

        var out: [JourneyEvent] = []
        var reached: Set<Int> = []
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(day, inSameDayAs: next) {
                run += 1
            } else {
                run = 1
            }
            previous = day
            for milestone in streakMilestones where run == milestone && !reached.contains(milestone) {
                reached.insert(milestone)
                out.append(JourneyEvent(
                    id: "streak-\(milestone)", date: day,
                    systemImage: "flame.fill", assetSlug: "flamme", tint: .orange,
                    title: "\(milestone) Tage am Stück",
                    subtitle: "A \(milestone)-day streak, the first time"
                ))
            }
        }
        return out
    }

    /// Level-ups replayed from the study log's XP. Every level would drown a long timeline, so
    /// rows stop at level 10 except where a level starts a new rank (Kenner, Meister, …).
    private static func levelEvents(_ studyDays: [StudyDay]) -> [JourneyEvent] {
        let days = studyDays.sorted { $0.dayStart < $1.dayStart }
        var out: [JourneyEvent] = []
        var totalXP = 0
        var level = 1
        for day in days {
            totalXP += ExperienceService.xp(for: day)
            while LearnerLevel.threshold(forLevel: level + 1) <= totalXP {
                level += 1
                let rank = LearnerRank.rank(for: level)
                let isRankStart = rank.firstLevel == level
                guard level <= 10 || isRankStart else { continue }
                out.append(JourneyEvent(
                    id: "level-\(level)", date: day.dayStart,
                    systemImage: "star.fill", assetSlug: "rang", tint: rank.tint,
                    title: isRankStart ? "Neuer Rang: \(rank.germanName)" : "Level \(level) erreicht",
                    subtitle: isRankStart ? "\(rank.englishName) — level \(level)" : rank.germanName
                ))
            }
        }
        return out
    }

    private static func event(for milestone: RecordedMilestone) -> JourneyEvent {
        let (icon, slug, tint): (String, String?, Color) = switch milestone.kind {
        case .layerComplete:  ("checkmark.seal.fill", "schicht-fertig", .green)
        case .comebackWord:   ("arrow.uturn.backward.circle", "zurueckgeholt", .indigo)
        case .stillSolid:     ("checkmark.circle.fill", "sitzt-noch", .teal)
        // Its own mark now: it used to borrow the indigo `zurueckgeholt` icon under an orange
        // tint, which the baked accent ignored — the row read as a comeback, not a setback.
        case .backInTraining: ("figure.strengthtraining.traditional", "zurueck-im-training", .orange)
        }
        return JourneyEvent(
            id: "recorded-\(milestone.id)", date: milestone.date,
            systemImage: icon, assetSlug: slug, tint: tint,
            title: milestone.title, subtitle: milestone.subtitle
        )
    }
}
