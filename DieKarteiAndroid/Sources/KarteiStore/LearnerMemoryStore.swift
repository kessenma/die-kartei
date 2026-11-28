import Foundation
@testable import DieKarteiCore

/// The coach's memory on Android: the shared rules (`LearnerMemory`, the same ones iOS's
/// `LearnerMemoryService` runs) on the one `LearnerProfileRecord` every device shares, and what
/// they archive as `ArchivedMemoryRecord`s.
extension RecordStore {
    /// The profile record, or a new empty one.
    var learnerProfile: LearnerProfileRecord {
        record(LearnerProfileRecord.self, id: SyncKinds.learnerProfileName.id) ?? LearnerProfileRecord()
    }

    var learnerMemory: LearnerMemory { LearnerMemory(record: learnerProfile) }

    /// Apply one shared rule: the sections it changed are written (unknown fields and the
    /// Förderplan kept), and what it archived is stored, in one transaction.
    func updateLearnerMemory(now: Date = Date(), _ rule: (inout LearnerMemory) -> [MemoryArchive]) throws {
        var record = learnerProfile
        let old = LearnerMemory(record: record)
        var memory = old
        let archived = rule(&memory)
        guard memory != old || !archived.isEmpty else { return }
        try transaction {
            memory.write(to: &record, from: old)
            try put(record, now: now)
            for a in archived { try archive(a, now: now) }
        }
    }

    /// A finished conversation (`LearnerMemoryService.applySession`): folded into the memory and
    /// counted as a conversation on today's study day.
    func applySession(summaryRaw: String, lines: [SessionLine], savedVocab: [SavedVocabItem],
                      wordsPracticed: [String], now: Date = Date(), calendar: Calendar = .current) throws {
        try transaction {
            try updateLearnerMemory(now: now) {
                $0.applySession(summaryRaw: summaryRaw, lines: lines, savedVocab: savedVocab,
                                wordsPracticed: wordsPracticed, now: now)
            }
            try recordStudy(.conversation, now: now, calendar: calendar)
        }
    }

    /// The archive, newest first.
    func archivedMemories() -> [ArchivedMemoryRecord] {
        records(ArchivedMemoryRecord.self).sorted { $0.archivedAt > $1.archivedAt }
    }

    /// Put an archived item back (pinned) and drop it from the archive.
    func restore(_ item: ArchivedMemoryRecord, now: Date = Date()) throws {
        try transaction {
            try updateLearnerMemory(now: now) {
                $0.restore(kindRaw: item.kindRaw, payload: item.payloadData)
                return []
            }
            try delete(item, now: now)
        }
    }

    func forget(_ item: ArchivedMemoryRecord, now: Date = Date()) throws {
        try delete(item, now: now)
    }

    /// Everything the coach remembers, active and archived (`LearnerMemoryService.reset`).
    func resetLearnerMemory(now: Date = Date()) throws {
        try transaction {
            var record = learnerProfile
            LearnerMemory().write(to: &record, from: LearnerMemory(record: record))
            record.grammar = nil
            record.vocab = nil
            record.slips = nil
            record.selfReports = nil
            try put(record, now: now)
            for item in records(ArchivedMemoryRecord.self) { try delete(item, now: now) }
        }
    }

    /// One archived row per item: iOS can hold several local rows for one item but syncs only the
    /// earliest, so an item archived again here keeps the record it already has.
    private func archive(_ a: MemoryArchive, now: Date) throws {
        let fresh = ArchivedMemoryRecord(a, archivedAt: now)
        if record(ArchivedMemoryRecord.self, id: fresh.name.id) != nil { return }
        try put(fresh, now: now)
    }
}
