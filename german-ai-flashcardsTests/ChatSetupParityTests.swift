//
//  ChatSetupParityTests.swift
//  german-ai-flashcardsTests
//
//  A new chat is stored the same by both apps: iOS's `ChatConversation(config:)` and Android's
//  `ChatConversationRecord(setup:)` (both through the shared `ChatSetup`) sync as the same payload,
//  and a reopened chat gets its setup back the same way.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct ChatSetupParityTests {
    static func configs() -> [ConversationConfig] {
        var plain = ConversationConfig(model: .hero)
        plain.inputMode = .type

        var rich = ConversationConfig(model: .hero)
        rich.mode = .interview
        rich.focusAreas = [.dativ, .perfekt]
        rich.level = .b1
        rich.formality = .sie
        rich.strictness = .strict
        rich.feedbackStyle = .nudgeMe
        rich.correctionsEnabled = false
        rich.autoPlay = false
        rich.deckIDs = [UUID(uuidString: "0F0F0F0F-0F0F-4F0F-8F0F-0F0F0F0F0F0F")!]
        rich.deckLabel = "Reise"
        rich.jobTitle = "Pflegefachkraft"
        rich.jobCompany = "Charité"
        rich.jobLocation = "Berlin"
        rich.interviewRound = InterviewRound.allCases.first
        rich.interviewFormat = InterviewFormat.allCases.first
        rich.jobPostingID = UUID(uuidString: "1A1A1A1A-1A1A-4A1A-8A1A-1A1A1A1A1A1A")
        rich.stammtisch = StammtischOptions()

        var scenario = ConversationConfig(model: .hero)
        scenario.mode = .scenario
        scenario.scenario = ConversationScenario.allCases.first
        scenario.customScenario = "Beim Bäcker"
        return [plain, rich, scenario]
    }

    @Test func newChatsSyncTheSame() {
        let context = ModelContext(ModelContainer.inMemory([ChatConversation.self, ChatMessage.self]))
        let created = Date(timeIntervalSinceReferenceDate: 816_900_000)
        for config in Self.configs() {
            let ios = ChatConversation(config: config, createdAt: created)
            context.insert(ios)
            let android = ChatConversationRecord(id: ios.id, setup: ChatSetup(config: config), createdAt: created)
            #expect(ChatConversationCodec.known(ios) == android.payload, "\(config.mode)")
            #expect(ios.setup == android.setup)
        }
    }

    @Test func reopenedChatsGetTheirSetupBack() {
        let manager = MLXModelManager()
        for config in Self.configs() {
            let convo = ChatConversation(config: config)
            let reopened = convo.makeConfig(modelManager: manager, decks: [])
            #expect(ChatSetup(config: reopened).modeRaw == convo.modeRaw)
            var android = ConversationConfig(model: reopened.model)
            convo.setup.apply(to: &android)
            var iosSetup = ChatSetup(config: reopened)
            var androidSetup = ChatSetup(config: android)
            // The résumé is re-read on iOS only (it stays on that device).
            iosSetup.usesResume = false
            androidSetup.usesResume = false
            #expect(iosSetup == androidSetup, "\(config.mode)")
        }
    }
}
