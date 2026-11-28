import Foundation
import SwiftData

/// A phrase the learner heard out in the wild (e.g. a bakery clerk's "Sonst noch etwas?") and saved
/// to practice hearing. Tagged to one or more scenarios; when active, it's sampled into those
/// scenario chats so the AI's character naturally says it. Conventions mirror `SavedDeck`
/// (UUID set in `init`, enums persisted as raw strings).
@Model
final class LearnedPhrase {
    var id: UUID
    var german: String
    var english: String

    /// `ConversationScenario.rawValue`s this phrase belongs to.
    var scenarioTagsRaw: [String]
    /// Optional `GrammarFocus.rawValue`s — folded into the session's grammar steering when surfaced.
    var focusAreasRaw: [String]
    /// `MLXModel.rawValue` of the model that validated/created this phrase (drives the row logo).
    var creatorModelRaw: String

    /// Whether the phrase is in rotation. Inactive phrases are never sampled into a chat.
    var isActive: Bool

    // Least-recently-used rotation bookkeeping.
    var surfacedCount: Int
    var lastSurfacedAt: Date?

    var createdAt: Date
    /// A short note from the validation check (e.g. what was corrected), if any.
    var note: String?

    init(
        german: String,
        english: String,
        scenarios: [ConversationScenario] = [],
        focusAreas: [GrammarFocus] = [],
        creatorModelRaw: String = "",
        isActive: Bool = true,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.german = german
        self.english = english
        self.scenarioTagsRaw = scenarios.map(\.rawValue)
        self.focusAreasRaw = focusAreas.map(\.rawValue)
        self.creatorModelRaw = creatorModelRaw
        self.isActive = isActive
        self.surfacedCount = 0
        self.lastSurfacedAt = nil
        self.note = note
        self.createdAt = createdAt
    }

    // MARK: - Derived

    var scenarios: [ConversationScenario] {
        scenarioTagsRaw.compactMap { ConversationScenario(rawValue: $0) }
    }

    var focusAreas: [GrammarFocus] {
        focusAreasRaw.compactMap { GrammarFocus(rawValue: $0) }
    }

    /// The model that created this phrase, if it's still a known model.
    var creatorModel: MLXModel? { MLXModel(rawValue: creatorModelRaw) }

    /// Asset name for the creator-model logo, or nil if none (e.g. the built-in Apple model,
    /// which uses an SF Symbol). Mirrors `SavedDeck.generatorLogoName`.
    var creatorLogoName: String? {
        guard let model = creatorModel else { return nil }
        return model.usesSFSymbolLogo ? nil : model.logoName
    }

    // MARK: - Rotation (shared with Android: Models/PhraseRotation.swift)

    /// Pick up to `limit` active phrases for `scenario`, least-recently-surfaced first.
    static func sample(
        for scenario: ConversationScenario,
        from all: [LearnedPhrase],
        limit: Int = 5
    ) -> [LearnedPhrase] {
        PhraseRotation.sample(for: scenario, from: all, limit: limit)
    }

    /// Mark this phrase as surfaced in a session (advances it in the rotation).
    func markSurfaced(at date: Date = .now) {
        PhraseRotation.markSurfaced(count: &surfacedCount, last: &lastSurfacedAt, at: date)
    }
}

extension LearnedPhrase: RotatingPhrase {}
