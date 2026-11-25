//
//  AchievementService.swift
//  german-ai-flashcards
//
//  The Abzeichen (badge) catalog + evaluation. Every badge is a pure rule over an
//  `AchievementSnapshot` gathered from the stats the app already keeps — StudyDay, QuizResult,
//  the game rounds, story attempts, the learner profile. Earned dates live in one UserDefaults
//  dictionary, so badges add zero SwiftData schema.
//
//  Evaluation *seeds silently* on first run: badges earned in the past get their dates recorded
//  without a celebration, and only badges earned from then on throw one.
//

import Foundation
import SwiftUI

// MARK: - Snapshot

/// Everything the badge rules read, gathered once per evaluation. Pure data — the views do the
/// querying, this type just makes the rules testable.
struct AchievementSnapshot {
    var streak: Int
    /// Cards saved across all decks (the learner's vocabulary library).
    var savedCards: Int
    /// Lifetime flashcards reviewed.
    var cardsReviewed: Int
    /// Lifetime conversations finished.
    var conversations: Int
    var perfectMatchingRound: Bool
    var perfectArticleRound: Bool
    var perfectPrepositionRound: Bool
    /// Story quizzes attempted, any score.
    var storyQuizzes: Int
    var perfectStoryQuiz: Bool
    /// Grammar skills currently Solid (struggle below the shaky threshold), out of
    /// `GrammarFocus.allCases.count`. An untouched skill counts as not-yet-solid here — the
    /// badge is for *proven* structures.
    var solidGrammarSkills: Int
    /// Completed pyramid layers, bottom-up.
    var completedPyramidLayers: Int
}

// MARK: - Service

enum AchievementService {

    /// The catalog, in grid order. Each entry pairs a badge with its rule.
    static let catalog: [(achievement: Achievement, rule: (AchievementSnapshot) -> Bool)] = [
        (Achievement(id: "first-steps", germanTitle: "Erste Schritte",
                     englishSubtitle: "Finish your first activity",
                     systemImage: "figure.walk", accent: .blue),
         { $0.cardsReviewed > 0 || $0.conversations > 0 || $0.storyQuizzes > 0 }),

        (Achievement(id: "streak-7", germanTitle: "Woche geschafft",
                     englishSubtitle: "A 7-day streak",
                     systemImage: "flame.fill", accent: .orange),
         { $0.streak >= 7 }),

        (Achievement(id: "streak-30", germanTitle: "Monatsmeisterschaft",
                     englishSubtitle: "A 30-day streak",
                     systemImage: "flame.circle.fill", accent: .orange),
         { $0.streak >= 30 }),

        (Achievement(id: "streak-100", germanTitle: "Unaufhaltsam",
                     englishSubtitle: "A 100-day streak",
                     systemImage: "bolt.fill", accent: .yellow),
         { $0.streak >= 100 }),

        (Achievement(id: "words-100", germanTitle: "Wortsammler",
                     englishSubtitle: "100 words in your library",
                     systemImage: "character.book.closed.fill", accent: .blue),
         { $0.savedCards >= 100 }),

        (Achievement(id: "words-500", germanTitle: "Wortschmied",
                     englishSubtitle: "500 words in your library",
                     systemImage: "text.book.closed.fill", accent: .indigo),
         { $0.savedCards >= 500 }),

        (Achievement(id: "words-1000", germanTitle: "Lexikon",
                     englishSubtitle: "1,000 words in your library",
                     systemImage: "books.vertical.fill", accent: .purple),
         { $0.savedCards >= 1000 }),

        (Achievement(id: "reviews-500", germanTitle: "Karteikasten",
                     englishSubtitle: "500 flashcards reviewed",
                     systemImage: "rectangle.stack.fill", accent: .blue),
         { $0.cardsReviewed >= 500 }),

        (Achievement(id: "perfect-match", germanTitle: "Fehlerfrei",
                     englishSubtitle: "A perfect matching round",
                     systemImage: "square.grid.2x2.fill", accent: .green),
         { $0.perfectMatchingRound }),

        (Achievement(id: "perfect-article", germanTitle: "Der Perfektionist",
                     englishSubtitle: "A perfect der · die · das round",
                     systemImage: "textformat.abc", accent: .purple),
         { $0.perfectArticleRound }),

        (Achievement(id: "perfect-case", germanTitle: "Fall gelöst",
                     englishSubtitle: "A perfect preposition-case round",
                     systemImage: "arrow.triangle.branch", accent: .orange),
         { $0.perfectPrepositionRound }),

        (Achievement(id: "story-first", germanTitle: "Buchwurm",
                     englishSubtitle: "Finish a story quiz",
                     systemImage: "book.pages", accent: .pink),
         { $0.storyQuizzes > 0 }),

        (Achievement(id: "story-perfect", germanTitle: "Fehlerlos gelesen",
                     englishSubtitle: "A perfect story quiz",
                     systemImage: "book.closed.fill", accent: .pink),
         { $0.perfectStoryQuiz }),

        (Achievement(id: "chat-10", germanTitle: "Plaudertasche",
                     englishSubtitle: "10 conversations finished",
                     systemImage: "bubble.left.and.bubble.right.fill", accent: .green),
         { $0.conversations >= 10 }),

        (Achievement(id: "grammar-solid", germanTitle: "Grammatik-Guru",
                     englishSubtitle: "Half of all grammar structures Solid",
                     systemImage: "checkmark.seal.fill", accent: .purple),
         { $0.solidGrammarSkills >= GrammarFocus.allCases.count / 2 }),

        (Achievement(id: "pyramid-base", germanTitle: "Fundament gelegt",
                     englishSubtitle: "Complete the pyramid's foundation layer",
                     systemImage: "pyramid.fill", accent: .orange),
         { $0.completedPyramidLayers >= 1 }),
    ]

    // MARK: - Earned dates (UserDefaults — no schema)

    private static let earnedKey = "achievements.earnedAt"
    private static let seededKey = "achievements.seeded"

    private static func earnedDates() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: earnedKey),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return dict
    }

    private static func store(_ dates: [String: Date]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(dates), forKey: earnedKey)
    }

    // MARK: - Evaluation

    /// A badge's current state for the grid.
    struct State: Identifiable {
        let achievement: Achievement
        let earnedAt: Date?
        var id: String { achievement.id }
        var isEarned: Bool { earnedAt != nil }
    }

    /// Evaluates the catalog against the snapshot, recording newly earned badges. Returns the
    /// full grid state. Newly earned badges are handed to `onNewlyEarned` (one call each, in
    /// catalog order) — except on the first-ever evaluation, which seeds dates silently so a
    /// learner with history isn't ambushed by overdue confetti.
    @MainActor
    static func evaluate(
        snapshot: AchievementSnapshot,
        manager: MLXModelManager,
        celebrate: Bool,
        onNewlyEarned: (Achievement) -> Void
    ) -> [State] {
        var dates = earnedDates()
        let seeded = UserDefaults.standard.bool(forKey: seededKey)
        var changed = false

        for entry in catalog where dates[entry.achievement.id] == nil && entry.rule(snapshot) {
            dates[entry.achievement.id] = Date()
            changed = true
            if seeded && celebrate {
                CelebrationCenter.shared.presentAchievement(entry.achievement, manager: manager)
                onNewlyEarned(entry.achievement)
            }
        }
        if changed { store(dates) }
        if !seeded { UserDefaults.standard.set(true, forKey: seededKey) }

        return catalog.map { State(achievement: $0.achievement, earnedAt: dates[$0.achievement.id]) }
    }

    /// Read-only grid state (no recording, no celebrations).
    static func states() -> [State] {
        let dates = earnedDates()
        return catalog.map { State(achievement: $0.achievement, earnedAt: dates[$0.achievement.id]) }
    }

    // MARK: - Developer screenshot seeding
    //
    // `ScreenshotDataSeeder` is the only caller. Badges are otherwise *earned* — nothing else in
    // the app may assign a date — but the seeder has to backdate a whole wall of them onto real
    // study days, and its restore has to put the learner's own dates back byte for byte.

    static func earnedDatesForBackup() -> [String: Date] { earnedDates() }

    static var hasSeededBadges: Bool { UserDefaults.standard.bool(forKey: seededKey) }

    /// Replaces the earned-date record wholesale. `seeded: true` keeps the next evaluation quiet,
    /// which is what stops a freshly seeded device throwing sixteen celebrations at once.
    static func replaceEarnedDates(_ dates: [String: Date], seeded: Bool) {
        store(dates)
        UserDefaults.standard.set(seeded, forKey: seededKey)
    }
}
