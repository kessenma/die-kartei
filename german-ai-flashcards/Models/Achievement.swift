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

    /// The badge's Bauhaus icon (`pyramid-icon-abzeichen-<id>`), rendered by
    /// `tools/blender/pyramid_icons.py`. Derived from the id rather than stored, so the catalog
    /// and the render set can only drift by someone renaming a badge — and `BauhausIcon` falls
    /// back to ``systemImage`` whenever the image set is missing, which is what makes adding a
    /// badge before its icon safe.
    var assetSlug: String { "abzeichen-\(id)" }
}
