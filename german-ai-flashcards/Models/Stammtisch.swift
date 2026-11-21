//
//  Stammtisch.swift
//  german-ai-flashcards
//
//  Stammtisch mode (roadmap item 8, FSI lesson 10): conversation under pressure. The app, not the
//  tutor, changes the topic every few turns; an optional reply timer has the tutor move on when the
//  learner says nothing; optional background noise plays under the tutor's voice; listener phrases
//  (Ach so, Genau, Echt?) are one tap away and can become phrase cards.
//

import Foundation

nonisolated struct StammtischOptions: Codable, Hashable, Sendable {
    /// The app injects a new topic after this many learner turns.
    var topicEvery: Int = 3
    /// Seconds the learner has to start answering; nil = no timer.
    var replySeconds: Int? = nil
    /// Soft background noise under the tutor's voice.
    var backgroundNoise: Bool = false
}

nonisolated enum StammtischTopics {
    static let all: [String] = [
        "das Wochenende", "Essen und Kochen", "die Arbeit", "das Wetter", "Fußball und Sport",
        "die Wohnung und die Nachbarn", "Urlaub und Reisen", "Filme und Serien", "die Familie",
        "Einkaufen und Preise", "Bus, Bahn und Verkehr", "das Handy und Apps", "Musik",
        "Pläne für nächste Woche", "eine lustige Geschichte von früher", "Haustiere",
    ]

    /// The topic for the injection after `learnerTurns`, or nil when no change is due. Rotates
    /// through the list from a per-conversation offset, so two chats don't share an order.
    static func topic(learnerTurns: Int, every: Int, seed: Int) -> String? {
        guard every > 0, learnerTurns > 0, learnerTurns % every == 0 else { return nil }
        let index = (learnerTurns / every + seed) % all.count
        return all[(index + all.count) % all.count]
    }

    /// Short listener signals (FSI lesson 10: "displaying understanding and involvement").
    static let listenerPhrases: [(german: String, english: String)] = [
        ("Ach so!", "Oh, I see!"), ("Genau.", "Exactly."), ("Echt?", "Really?"), ("Stimmt.", "That's true."),
        ("Na ja …", "Well …"), ("Wirklich?", "Really?"), ("Klingt gut!", "Sounds good!"),
        ("Keine Ahnung.", "No idea."), ("Ach, wirklich?", "Oh, really?"), ("Das gibt's doch nicht!", "No way!"),
    ]

    /// A stable small number from a conversation's id.
    static func seed(_ id: UUID) -> Int {
        Int(id.uuid.0) + Int(id.uuid.1)
    }
}
