import Foundation
import Observation
import SkipFuse
@testable import DieKarteiCore
@testable import KarteiStore

/// Saved chats on Android (iOS's chats list): every chat is stored as it runs, as the
/// `ChatConversationRecord` and `ChatMessageRecord`s iOS's chats sync as, and can be reopened.
@MainActor
@Observable
final class ChatHistory {
    static let shared = ChatHistory()

    /// Newest activity first.
    private(set) var chats: [ChatConversationRecord] = []
    @ObservationIgnored private let records: RecordStore?

    init(records: RecordStore? = AppDatabase.records) {
        self.records = records
        reload()
    }

    /// A new chat's record (what iOS's `ChatConversation(config:)` stores), saved right away as
    /// iOS saves it before the first message.
    func start(_ config: ConversationConfig) -> (chat: MemoryChatRecord, base: ChatConversationRecord) {
        let base = ChatConversationRecord(setup: ChatSetup(config: config))
        let chat = MemoryChatRecord(id: base.id, inputMode: config.inputMode)
        save(chat, base: base)
        return (chat, base)
    }

    /// A saved chat with its messages, ready to run again.
    func open(_ record: ChatConversationRecord) -> MemoryChatRecord {
        MemoryChatRecord(record: records?.chat(record.id) ?? record, messages: records?.messages(of: record.id) ?? [])
    }

    /// The session saves after every change; only what changed is written.
    func save(_ chat: MemoryChatRecord, base: ChatConversationRecord) {
        guard let records else { return }
        do {
            if try records.saveChat(chat, base: base) { reload() }
        } catch {
            logger.error("ChatHistory: could not save: \(error)")
        }
    }

    func delete(_ id: UUID) {
        guard let records else { return }
        do {
            try records.deleteChat(id)
        } catch {
            logger.error("ChatHistory: could not delete: \(error)")
        }
        reload()
    }

    func reload() {
        chats = records?.chats() ?? []
    }
}
