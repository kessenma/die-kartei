import Foundation
import Testing
@testable import DieKarteiCore

/// Android's chats on disk against the rows iOS's codecs write (sync_golden.json): a stored chat
/// read into the session's in-memory chat and written back is byte for byte what iOS has.
@MainActor
@Suite struct StoredConversationTests {
    @Test("A message survives the session unchanged, every field")
    func messagesRoundTrip() throws {
        for label in ["full", "bare"] {
            let golden = SyncRecordTests.golden("ChatMessage", label)
            let record = ChatMessageRecord(payload: golden)
            let conversation = try #require(record.conversation)
            let back = MemoryChatMessage(record: record).record(conversation: conversation, base: record)
            #expect(back.payload == golden, "\(label)")
            // Without its stored copy (a message the session just made), the same fields come out.
            let fresh = MemoryChatMessage(record: record).record(conversation: conversation)
            #expect(fresh.payload == golden, "\(label), fresh")
        }
    }

    @Test("A chat reopened and saved again keeps its setup, words and summary")
    func chatsRoundTrip() {
        for label in ["full", "bare"] {
            let golden = SyncRecordTests.golden("ChatConversation", label)
            var record = ChatConversationRecord(payload: golden)
            let chat = MemoryChatRecord(record: record, messages: [])
            chat.apply(to: &record)
            #expect(record.payload == golden, "\(label)")
            // The setup alone rebuilds the same record.
            var rebuilt = ChatConversationRecord(id: record.id, setup: record.setup, createdAt: record.createdAt)
            chat.apply(to: &rebuilt)
            #expect(rebuilt.setup == record.setup, "\(label)")
        }
    }

    @Test("A stored setup reopens as the same config")
    func setupReopens() {
        var config = ConversationConfig(model: MLXModel.allCases.first!)
        config.mode = .scenario
        config.scenario = ConversationScenario.allCases.last
        config.focusAreas = [.dativ, .perfekt]
        config.level = .b1
        config.formality = .sie
        config.feedbackStyle = .nudgeMe
        config.inputMode = .type
        config.autoPlay = false
        config.stammtisch = StammtischOptions()
        let setup = ChatSetup(config: config)
        var reopened = ConversationConfig(model: config.model)
        setup.apply(to: &reopened)
        #expect(ChatSetup(config: reopened) == setup)
        #expect(ChatConversationRecord(setup: setup).setup.stammtischData.map { _ in true } == true)
    }
}
