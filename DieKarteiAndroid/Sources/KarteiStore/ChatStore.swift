import Foundation
@testable import DieKarteiCore

/// Saved chats on Android: `ChatConversationRecord`s with their `ChatMessageRecord`s hanging off
/// them (deleting a chat deletes its messages), the same records iOS's chats sync as.
extension RecordStore {
    /// Every chat, newest activity first (iOS's chats list).
    func chats() -> [ChatConversationRecord] {
        records(ChatConversationRecord.self).sorted { $0.updatedAt > $1.updatedAt }
    }

    func chat(_ id: UUID) -> ChatConversationRecord? { record(ChatConversationRecord.self, id: id) }

    /// A chat's messages in order.
    func messages(of chat: UUID) -> [ChatMessageRecord] {
        records(ChatMessageRecord.self, parent: chat).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Save a running chat: its record and every message, writing only what changed since the
    /// last save (the session saves after every change). Returns false when nothing changed.
    @discardableResult
    func saveChat(_ chat: MemoryChatRecord, base: ChatConversationRecord, now: Date = Date()) throws -> Bool {
        var record = self.chat(chat.id) ?? base
        let stored = record.payload
        chat.apply(to: &record)
        let old = Dictionary(uniqueKeysWithValues: messages(of: chat.id).map { ($0.id, $0) })
        var changed: [ChatMessageRecord] = []
        for message in chat.messages {
            let new = message.record(conversation: chat.id, base: old[message.id])
            if old[message.id]?.payload != new.payload { changed.append(new) }
        }
        let recordChanged = record.payload != stored || self.chat(chat.id) == nil
        guard recordChanged || !changed.isEmpty else { return false }
        try transaction {
            if recordChanged { try put(record, now: now) }
            try put(changed, now: now)
        }
        return true
    }

    /// Delete a chat and its messages.
    func deleteChat(_ id: UUID, now: Date = Date()) throws {
        try delete(kind: ChatConversationRecord.spec.kind, id: id, now: now)
    }
}
