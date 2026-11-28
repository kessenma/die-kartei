import Foundation

// A real file in the core, not a link to the app: iOS keeps its chats in SwiftData.
// Android's chats on disk: the in-memory chat the shared session runs on (`MemoryChatRecord`,
// `MemoryChatMessage`) to and from the sync records iOS's codecs write (`ChatConversationRecord`,
// `ChatMessageRecord`), field for field. `StoredConversationTests` holds both to the iOS golden.

extension MemoryChatMessage {
    convenience init(record r: ChatMessageRecord) {
        self.init(id: r.id, role: ChatRole(rawValue: r.roleRaw) ?? .assistant, text: r.text, sortOrder: r.sortOrder,
                  createdAt: r.createdAt)
        correctedText = r.correctedText
        correctionNote = r.correctionNote
        correctionHint = r.correctionHint
        confirmedClean = r.confirmedClean
        selfCorrected = r.selfCorrected
        correctionTranslationText = r.correctionTranslationText
        targetWordsUsed = r.targetWordsUsed
        reviewedWords = r.reviewedWords
        usedHint = r.usedHint
        usedPhraseHelper = r.usedPhraseHelper
        translationText = r.translationText
        translationViewed = r.translationViewed
    }

    /// The message as a record of `conversation`, over `base` (its last stored copy, whose fields
    /// from newer builds are kept).
    func record(conversation: UUID, base: ChatMessageRecord? = nil) -> ChatMessageRecord {
        var r = base ?? ChatMessageRecord(id: id, conversation: conversation, roleRaw: role.rawValue, text: text,
                                          sortOrder: sortOrder, createdAt: createdAt)
        r.conversation = conversation
        r.roleRaw = role.rawValue
        r.text = text
        r.sortOrder = sortOrder
        r.createdAt = createdAt
        r.correctedText = correctedText
        r.correctionNote = correctionNote
        r.correctionHint = correctionHint
        r.confirmedClean = confirmedClean
        r.selfCorrected = selfCorrected
        r.correctionTranslationText = correctionTranslationText
        r.targetWordsUsed = targetWordsUsed
        r.reviewedWords = reviewedWords
        r.usedHint = usedHint
        r.usedPhraseHelper = usedPhraseHelper
        r.translationText = translationText
        r.translationViewed = translationViewed
        return r
    }
}

extension MemoryChatRecord {
    /// A saved chat and its messages, ready for the session to run on again.
    convenience init(record r: ChatConversationRecord, messages: [ChatMessageRecord]) {
        self.init(id: r.id, inputModeRaw: r.inputModeRaw, durationSeconds: r.durationSeconds, updatedAt: r.updatedAt,
                  savedVocab: (try? r.savedVocab?.decoded(as: [SavedVocabItem].self)) ?? [],
                  summary: try? r.summary?.decoded(as: ConversationSummary.self),
                  messages: messages.map(MemoryChatMessage.init(record:)))
    }

    /// What the chat changed, onto its record: time, input mode, saved words, the summary.
    /// The setup and fields from newer builds stay as they were.
    func apply(to r: inout ChatConversationRecord) {
        r.durationSeconds = durationSeconds
        r.inputModeRaw = inputModeRaw
        r.updatedAt = updatedAt
        // As iOS: absent until a word is saved, an empty list once one was saved and removed.
        if !savedVocab.isEmpty || r.savedVocab != nil {
            r.savedVocab = (try? JSONEncoder().encode(savedVocab)).flatMap { try? SyncJSON(data: $0) }
        }
        if let summary {
            r.summary = (try? JSONEncoder().encode(summary)).flatMap { try? SyncJSON(data: $0) }
        }
    }
}
