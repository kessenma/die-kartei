import Foundation
import Testing
@testable import DieKarteiCore
@testable import KarteiStore

@MainActor
@Suite struct ChatStoreTests {
    func store() throws -> RecordStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kartei-\(UUID().uuidString)")
            .appendingPathComponent("kartei.sqlite")
        return RecordStore(database: try KarteiDatabase(url: url), replica: "android-a")
    }

    func chat() -> (MemoryChatRecord, ChatConversationRecord) {
        var config = ConversationConfig(model: MLXModel.allCases.first!)
        config.inputMode = .type
        config.mode = .scenario
        config.scenario = ConversationScenario.allCases.first
        let base = ChatConversationRecord(setup: ChatSetup(config: config))
        let memory = MemoryChatRecord(id: base.id, inputMode: .type)
        let hello = MemoryChatMessage(role: .assistant, text: "Hallo! Wie geht's?", sortOrder: 0)
        let reply = MemoryChatMessage(role: .user, text: "Ich gehe in die Park.", sortOrder: 1)
        reply.correctedText = "Ich gehe in den Park."
        reply.correctionNote = "in + Akkusativ"
        memory.messages = [hello, reply]
        return (memory, base)
    }

    @Test("A chat comes back with its setup, messages, corrections, words and summary")
    func chatRoundTrips() throws {
        let records = try store()
        let (memory, base) = chat()
        memory.saveVocab(german: "der Park", english: "the park")
        memory.durationSeconds = 95
        memory.setSummary(ConversationSummary(strengths: ["Fragen"], improvements: ["Akkusativ"], patternNote: "",
                                              wordsPracticed: [], correctionCount: 1, turnCount: 1,
                                              generatedAt: Date(timeIntervalSinceReferenceDate: 816_000_000)))
        #expect(try records.saveChat(memory, base: base))
        #expect(try !records.saveChat(memory, base: base), "nothing changed: nothing written")

        let saved = try #require(records.chat(base.id))
        #expect(saved.setup == base.setup)
        #expect(saved.durationSeconds == 95)
        let back = MemoryChatRecord(record: saved, messages: records.messages(of: base.id))
        #expect(back.sortedMessages.map(\.text) == ["Hallo! Wie geht's?", "Ich gehe in die Park."])
        #expect(back.sortedMessages[1].correctedText == "Ich gehe in den Park.")
        #expect(back.sortedMessages[1].id == memory.messages[1].id)
        #expect(back.savedVocab.map(\.german) == ["der Park"])
        #expect(back.summary?.improvements == ["Akkusativ"])
        #expect(back.durationSeconds == 95)
    }

    @Test("Only changed messages are written again")
    func savesOnlyChanges() throws {
        let records = try store()
        let (memory, base) = chat()
        try records.saveChat(memory, base: base)
        let before = records.messages(of: base.id).map(\.payload)
        memory.messages[0].translationText = "Hello! How are you?"
        #expect(try records.saveChat(memory, base: base))
        let after = records.messages(of: base.id).map(\.payload)
        #expect(after[0] != before[0])
        #expect(after[1] == before[1])
    }

    @Test("Deleting a chat deletes its messages, and the list is newest first")
    func deleteCascades() throws {
        let records = try store()
        let (a, baseA) = chat()
        let (b, baseB) = chat()
        b.updatedAt = a.updatedAt.addingTimeInterval(60)
        try records.saveChat(a, base: baseA)
        try records.saveChat(b, base: baseB)
        #expect(records.chats().map(\.id) == [baseB.id, baseA.id])
        try records.deleteChat(baseA.id)
        #expect(records.chats().map(\.id) == [baseB.id])
        #expect(records.messages(of: baseA.id).isEmpty)
        #expect(records.count(kind: "ChatMessage") == 2)
    }
}
