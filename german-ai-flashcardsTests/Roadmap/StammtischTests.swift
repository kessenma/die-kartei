//
//  StammtischTests.swift
//  german-ai-flashcardsTests
//
//  Roadmap phase 6 (item 8): the app, not the tutor, changes the topic; the persona; the silent turn.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct StammtischTests {

    @Test func topicsComeOnSchedule() {
        #expect(StammtischTopics.topic(learnerTurns: 0, every: 3, seed: 0) == nil)
        #expect(StammtischTopics.topic(learnerTurns: 2, every: 3, seed: 0) == nil)
        let first = StammtischTopics.topic(learnerTurns: 3, every: 3, seed: 0)
        let second = StammtischTopics.topic(learnerTurns: 6, every: 3, seed: 0)
        #expect(first != nil && second != nil && first != second)
        // A different chat starts elsewhere in the list.
        #expect(StammtischTopics.topic(learnerTurns: 3, every: 3, seed: 5) != first)
    }

    @Test func promptAndNotes() {
        var config = ConversationConfig(model: .hero)
        #expect(!ConversationPrompts.systemPrompt(for: config).contains("Stammtisch"))
        #expect(ConversationPrompts.stammtischNote(for: config, learnerTurns: 3, seed: 0) == nil)
        config.stammtisch = StammtischOptions(topicEvery: 3, replySeconds: 20, backgroundNoise: false)
        #expect(ConversationPrompts.systemPrompt(for: config).contains("Stammtisch"))
        #expect(ConversationPrompts.stammtischNote(for: config, learnerTurns: 3, seed: 0)?.hasPrefix("Wechsle jetzt das Thema") == true)
        #expect(ConversationPrompts.stammtischNote(for: config, learnerTurns: 4, seed: 0) == nil)
    }

    @Test func aSilentTurnStillAlternates() {
        // The hidden line keeps user/assistant alternating for the chat templates.
        let turns: [ChatTurnNormalizer.Turn] = [
            (role: .assistant, content: "Na, wie war dein Wochenende?"),
            (role: .user, content: ConversationPrompts.silentLearnerLine),
        ]
        let normalized = ChatTurnNormalizer.normalized(turns, openerSeed: ConversationPrompts.openerSeed)
        #expect(normalized.last?.role == .user)
    }

    @Test func optionsRoundTrip() throws {
        let options = StammtischOptions(topicEvery: 3, replySeconds: 25, backgroundNoise: true)
        let decoded = try JSONDecoder().decode(StammtischOptions.self, from: JSONEncoder().encode(options))
        #expect(decoded == options)
    }
}
