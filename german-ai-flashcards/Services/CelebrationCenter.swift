//
//  CelebrationCenter.swift
//  german-ai-flashcards
//
//  The one place celebrations are decided and shown from. A shared observable holds the current
//  celebration; `ContentView` overlays it above whichever tab is on screen. Every trigger is
//  deduped through UserDefaults (`celebration.*` keys) — a moment fires exactly once, ever, and
//  nothing here touches the SwiftData schema.
//
//  Fired from the data the app already keeps: the `StudyDay` log feeds goal/level/streak checks
//  (`evaluate`), badges fire from `AchievementService` when the Fortschritt screen evaluates
//  them, and a finished pyramid layer fires from the pyramid screen. First-ever evaluation
//  *seeds silently* — a learner with three months of history shouldn't be ambushed by twelve
//  overdue parties the first time they open Home.
//

import Foundation
import SwiftUI

// MARK: - Celebration

/// One celebratory moment. German-led copy with an English gloss, matching the app's voice.
enum Celebration: Identifiable {
    case dailyGoal(minutes: Int)
    case levelUp(level: Int, rank: LearnerRank)
    case streak(days: Int)
    case achievement(Achievement)
    case pyramidLayer(PyramidLayerID)

    var id: String {
        switch self {
        case .dailyGoal:                    "dailyGoal"
        case .levelUp(let level, _):        "levelUp.\(level)"
        case .streak(let days):             "streak.\(days)"
        case .achievement(let a):           "achievement.\(a.id)"
        case .pyramidLayer(let layer):      "pyramidLayer.\(layer.rawValue)"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyGoal:                    "checkmark.circle.fill"
        case .levelUp:                      "star.fill"
        case .streak:                       "flame.fill"
        case .achievement(let a):           a.systemImage
        case .pyramidLayer(let layer):      layer.systemImage
        }
    }

    var accent: Color {
        switch self {
        case .dailyGoal:                    .green
        case .levelUp(_, let rank):         rank.tint
        case .streak:                       .orange
        case .achievement(let a):           a.accent
        case .pyramidLayer(let layer):      layer.tint
        }
    }

    var title: String {
        switch self {
        case .dailyGoal:                    "Tagesziel erreicht!"
        case .levelUp:                      "Aufgestiegen!"
        case .streak(let days):             "\(days) Tage in Folge!"
        case .achievement(let a):           a.germanTitle
        case .pyramidLayer(let layer):      "„\(layer.germanTitle)“ fertig!"
        }
    }

    var subtitle: String {
        switch self {
        case .dailyGoal(let minutes):       "Daily goal met — \(minutes) minutes of German today. Weiter so!"
        case .levelUp(let level, let rank): "Level \(level) · \(rank.germanName) (\(rank.englishName)) — keep climbing."
        case .streak:                       "Your streak keeps growing. Dranbleiben!"
        case .achievement(let a):           "Badge unlocked — \(a.englishSubtitle)"
        case .pyramidLayer:                 "A layer of your pyramid is complete."
        }
    }
}

// MARK: - Center

@Observable
final class CelebrationCenter {
    static let shared = CelebrationCenter()
    private init() {}

    /// The celebration currently on screen, if any. One at a time — a second trigger waits
    /// rather than stacking.
    private(set) var current: Celebration?

    func present(_ celebration: Celebration, allowed: Bool = true) {
        guard allowed, current == nil else { return }
        current = celebration
    }

    /// Clears the moment, and hands it to `ReviewPromptService` — a dismissed streak milestone is
    /// the one thing in the app that earns an App Store ask. Guarded on `current`, so the overlay's
    /// tap and its auto-dismiss timer both landing can't offer the same moment twice.
    func dismiss() {
        guard let celebration = current else { return }
        current = nil
        ReviewPromptService.shared.celebrationDismissed(celebration)
    }

    // MARK: Dedupe

    private func fired(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: "celebration.\(key)")
    }

    private func markFired(_ key: String) {
        UserDefaults.standard.set(true, forKey: "celebration.\(key)")
    }

    // MARK: - Goal / level / streak (fed purely by the StudyDay log)

    /// The streak lengths worth a party.
    static let streakMilestones = [7, 14, 30, 50, 100, 200, 365]

    /// Checks the Home-visible triggers against the current log. Call on appear and whenever
    /// the study days change; every branch dedupes, so calling often is cheap and safe.
    @MainActor
    func evaluate(studyDays: [StudyDay], manager: MLXModelManager) {
        guard manager.gamificationEnabled, manager.gamificationCelebrationsEnabled else { return }

        // Level-up — seeded silently on first run so an existing history doesn't throw a
        // surprise party for a level the learner reached weeks ago.
        let level = ExperienceService.level(for: studyDays)
        let maxSeenKey = "celebration.maxLevelSeen"
        if let maxSeen = UserDefaults.standard.object(forKey: maxSeenKey) as? Int {
            if level.level > maxSeen {
                UserDefaults.standard.set(level.level, forKey: maxSeenKey)
                present(.levelUp(level: level.level, rank: level.rank))
            }
        } else {
            UserDefaults.standard.set(level.level, forKey: maxSeenKey)
        }

        // Daily goal — once per day.
        if ExperienceService.dailyGoalMet(studyDays, goalMinutes: manager.dailyGoalMinutes) {
            let key = "goal.\(Self.dayStamp(Date()))"
            if !fired(key) {
                markFired(key)
                present(.dailyGoal(minutes: manager.dailyGoalMinutes))
            }
        }

        // Streak milestones — once each, ever.
        let streak = StudyLogService.currentStreak(studyDays)
        for milestone in Self.streakMilestones where streak >= milestone {
            let key = "streak.\(milestone)"
            if !fired(key) {
                markFired(key)
                present(.streak(days: milestone))
                break   // one moment at a time; the next milestone gets its own day
            }
        }
    }

    // MARK: - Achievement + pyramid entry points

    /// A newly earned badge, called by `AchievementService.evaluate`. Dates are recorded by the
    /// service; this only decides whether the moment shows.
    func presentAchievement(_ achievement: Achievement, manager: MLXModelManager) {
        guard manager.gamificationEnabled, manager.gamificationBadgesEnabled else { return }
        present(.achievement(achievement), allowed: manager.gamificationCelebrationsEnabled)
    }

    /// A pyramid layer that just completed. Deduped per layer — rebuilding the Fundament twice
    /// doesn't congratulate twice.
    func presentLayerComplete(_ layer: PyramidLayerID, manager: MLXModelManager) {
        guard manager.gamificationEnabled, manager.gamificationPyramidEnabled else { return }
        let key = "layer.\(layer.rawValue)"
        guard !fired(key) else { return }
        markFired(key)
        present(.pyramidLayer(layer), allowed: manager.gamificationCelebrationsEnabled)
    }

    private static func dayStamp(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
