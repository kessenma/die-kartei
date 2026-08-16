//
//  Achievement.swift
//  german-ai-flashcards
//
//  One Abzeichen (badge): static identity + presentation. The *rule* that earns it lives in
//  `AchievementService` next to the snapshot it reads, and the earned date lives in
//  UserDefaults — so badges add zero SwiftData schema.
//

import SwiftUI

struct Achievement: Identifiable, Hashable {
    let id: String
    /// German name — the badge's identity.
    let germanTitle: String
    /// English gloss of what it took.
    let englishSubtitle: String
    let systemImage: String
    let accent: Color
}
