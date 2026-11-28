import Foundation
import Observation
import SkipFuse
@testable import DieKarteiCore
@testable import KarteiStore

/// The coach's memory on Android: what the tutor remembers about the learner between chats. The
/// rules are iOS's own (`LearnerMemory`, Models/LearnerMemory.swift); the profile is the one
/// `LearnerProfileRecord` both apps sync, and what leaves it is kept as `ArchivedMemoryRecord`s.
@MainActor
@Observable
final class CoachMemory {
    static let shared = CoachMemory()

    private(set) var memory = LearnerMemory()
    /// Newest first.
    private(set) var archive: [ArchivedMemoryRecord] = []
    @ObservationIgnored private let records: RecordStore?

    init(records: RecordStore? = AppDatabase.records) {
        self.records = records
        reload()
    }

    /// Settings ▸ Coaching ▸ Personalized coaching (iOS's key and default: on).
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: LearnerMemory.personalizedCoachingKey) as? Bool ?? true
    }

    var isEmpty: Bool {
        memory.sessionCount == 0 && memory.grammar.isEmpty && memory.vocab.isEmpty && memory.slips.isEmpty
            && memory.selfReports.isEmpty && archive.isEmpty
    }

    /// What a new chat starts with (iOS `ConversationEngine`): the briefing and the correction
    /// hint, when personalized coaching is on.
    func prime(_ config: inout ConversationConfig) {
        guard Self.isOn else { return }
        config.learnerBriefing = memory.briefing
        config.correctionMemoryHint = memory.correctionHint
    }

    /// A chat's summary is in (iOS `ConversationEngine.sessionSummarized`): with personalized
    /// coaching on, fold it in and count the conversation on today; off, nothing is kept.
    func sessionSummarized(raw: String, messages: [MemoryChatMessage], savedVocab: [SavedVocabItem],
                           wordsPracticed: [String]) {
        guard Self.isOn else { return }
        let lines = messages.map { SessionLine(isUser: $0.isUser, text: $0.text, correctedText: $0.correctedText) }
        write { try $0.applySession(summaryRaw: raw, lines: lines, savedVocab: savedVocab, wordsPracticed: wordsPracticed) }
        StudyLog.shared.reload()
    }

    // MARK: Coach's Notes

    func removeVocab(_ id: String) { update { $0.archiveVocab(id: id).map { [$0] } ?? [] } }
    func removeSlip(_ id: String) { update { $0.archiveSlip(id: id).map { [$0] } ?? [] } }
    func removeNote(_ id: String) { update { $0.archiveSelfReport(id: id).map { [$0] } ?? [] } }

    func setVocabPinned(_ id: String, _ pinned: Bool) { update { $0.setVocabPinned(id, pinned: pinned); return [] } }
    func setSlipPinned(_ id: String, _ pinned: Bool) { update { $0.setSlipPinned(id, pinned: pinned); return [] } }
    func setNotePinned(_ id: String, _ pinned: Bool) { update { $0.setSelfReportPinned(id, pinned: pinned); return [] } }

    func restore(_ item: ArchivedMemoryRecord) { write { try $0.restore(item) } }
    func forget(_ item: ArchivedMemoryRecord) { write { try $0.forget(item) } }
    func reset() { write { try $0.resetLearnerMemory() } }

    private func update(_ rule: @escaping (inout LearnerMemory) -> [MemoryArchive]) {
        write { try $0.updateLearnerMemory(rule) }
    }

    private func write(_ body: (RecordStore) throws -> Void) {
        guard let records else { return }
        do {
            try body(records)
        } catch {
            logger.error("CoachMemory: could not save: \(error)")
        }
        reload()
    }

    func reload() {
        guard let records else { return }
        memory = records.learnerMemory
        archive = records.archivedMemories()
    }
}
