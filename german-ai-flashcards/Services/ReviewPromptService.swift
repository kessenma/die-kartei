//
//  ReviewPromptService.swift
//  german-ai-flashcards
//
//  Decides when to ask for an App Store rating, and is the only thing that may decide it.
//
//  The ask rides on `CelebrationCenter`: when a celebration is dismissed, the center hands it
//  here, and a 7-day (or longer) streak — and nothing else — earns the prompt. That moment is
//  already deduped-forever by the center, the learner has just been told they're doing well, and
//  no sheet or task is on screen. The daily-goal party is deliberately *not* a trigger: it fires
//  every day, and the system caps the prompt at three per year, so goal-day one would spend the
//  whole budget before the app had earned anything.
//
//  iOS throttles `requestReview` silently — a call may simply do nothing, with no callback — so
//  the gates below are ours, not Apple's: at most one ask per app version, and at least 90 days
//  between attempts. We record the attempt when we *ask*, since we can never learn whether the
//  sheet actually appeared.
//
//  Nothing here writes the SwiftData schema; the two keys are UserDefaults.
//

import Foundation
import SwiftUI

@Observable
final class ReviewPromptService {
    static let shared = ReviewPromptService()
    private init() {}

    /// Raised when a celebration earned the ask. `CelebrationOverlayHost` watches this, lets the
    /// confetti clear, fires the system sheet, then calls `consume()`. A flag rather than a direct
    /// call because `requestReview` is a SwiftUI environment action — it needs a view, not a
    /// singleton.
    private(set) var pending = false

    /// The streak worth asking on. Matches the first entry in `CelebrationCenter.streakMilestones`;
    /// the later milestones (14, 30, …) qualify too, but the version/cooldown gates mean they only
    /// get a turn if the 7-day ask was skipped or has long since aged out.
    static let streakThreshold = 7

    /// Days between attempts. Deliberately longer than a release cycle, so the per-version gate is
    /// usually the one that bites.
    private static let cooldownDays = 90

    private let lastVersionKey = "review.lastPromptedVersion"
    private let lastDateKey = "review.lastPromptedAt"

    /// Straight to the write-review sheet for this app. Used by the Settings row, which is an
    /// explicit tap and so bypasses every gate above — the throttle applies to the *system* prompt,
    /// not to a link the learner chose to follow.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6770390331?action=write-review")!

    /// Called by `CelebrationCenter.dismiss()` with the moment that just left the screen.
    func celebrationDismissed(_ celebration: Celebration) {
        guard case .streak(let days) = celebration, days >= Self.streakThreshold else { return }
        requestIfEligible()
    }

    func consume() { pending = false }

    private func requestIfEligible() {
        guard !pending, isEligible else { return }
        let defaults = UserDefaults.standard
        defaults.set(Self.currentVersion, forKey: lastVersionKey)
        defaults.set(Date(), forKey: lastDateKey)
        pending = true
    }

    private var isEligible: Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: lastVersionKey) != Self.currentVersion else { return false }
        if let last = defaults.object(forKey: lastDateKey) as? Date,
           let nextAllowed = Calendar.current.date(byAdding: .day, value: Self.cooldownDays, to: last),
           Date() < nextAllowed {
            return false
        }
        return true
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    #if DEBUG
    /// `-review.debugForce 1` clears both gates and raises the ask on launch:
    ///
    ///     xcrun simctl launch <udid> <bundle-id> -review.debugForce 1
    ///
    /// The real path needs a seven-day streak in the study log, which the simulator can't tap its
    /// way to — this is the only way to see the sheet. DEBUG builds only.
    func applyDebugLaunchArgumentIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "review.debugForce") else { return }
        UserDefaults.standard.removeObject(forKey: lastVersionKey)
        UserDefaults.standard.removeObject(forKey: lastDateKey)
        requestIfEligible()
    }
    #endif
}
