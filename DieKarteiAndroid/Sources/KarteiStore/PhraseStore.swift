import Foundation
@testable import DieKarteiCore

/// The phrase library on Android: `LearnedPhraseRecord`s, the records iOS's `LearnedPhrase`s sync
/// as. Which ones a chat works in is the shared `PhraseRotation`.
extension RecordStore {
    /// Newest first (iOS's phrase library).
    func phrases() -> [LearnedPhraseRecord] {
        records(LearnedPhraseRecord.self).sorted { $0.createdAt > $1.createdAt }
    }

    func savePhrase(_ phrase: LearnedPhraseRecord, now: Date = Date()) throws {
        try put(phrase, now: now)
    }

    func deletePhrase(_ id: UUID, now: Date = Date()) throws {
        try delete(kind: LearnedPhraseRecord.spec.kind, id: id, now: now)
    }

    /// The learner started a chat with these: each advances in the rotation.
    func markSurfaced(_ ids: [UUID], at date: Date = Date()) throws {
        try transaction {
            for id in ids {
                guard var phrase = record(LearnedPhraseRecord.self, id: id) else { continue }
                phrase.markSurfaced(at: date)
                try put(phrase, now: date)
            }
        }
    }
}
