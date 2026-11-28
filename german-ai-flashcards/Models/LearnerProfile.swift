import Foundation
import SwiftData

// The value types (GrammarSkill, VocabTouch, LexicalSlip, SelfReportNote, MemorySource,
// MemoryKind, ArchiveReason) and the rules that change them live in LearnerMemory.swift, shared
// with Android.

// MARK: - Active profile (bounded; the only thing ever shown to the model)

/// The learner's persistent, self-cleaning coaching profile. A singleton row.
///
/// Buckets are stored as encoded `Data` (mirroring `ChatConversation.summaryData`) so the
/// SwiftData model stays a thin container and the shape can evolve without migrations.
@Model
final class LearnerProfile {
    var id: UUID
    var sessionCount: Int
    var lastSessionAt: Date?

    /// Encoded `[String: GrammarSkill]` keyed by `GrammarFocus.rawValue`: the keys are the enum's
    /// cases, so the set grows only with a new focus in code (`reflexivverben`, 2026-10), never at
    /// runtime.
    var grammarData: Data?
    /// Encoded `[VocabTouch]` — LRU-capped at `vocabCap`.
    var vocabData: Data?
    /// Encoded `[LexicalSlip]` — LRU-capped at `slipCap`, self-heals on correct use.
    var slipsData: Data?
    /// Encoded `[SelfReportNote]` — LRU-capped at `selfReportCap`. Defaulted so profiles stored
    /// before the journal existed migrate unchanged.
    var selfReportsData: Data? = nil
    /// Encoded `FoerderplanRecord`: the ten-day plan on one weak spot, and past plans' outcomes
    /// (roadmap item 9). Nil until the first plan.
    var foerderplanData: Data? = nil

    init() {
        self.id = UUID()
        self.sessionCount = 0
        self.lastSessionAt = nil
    }

    // Bounds
    static let vocabCap = LearnerMemory.vocabCap
    static let slipCap = LearnerMemory.slipCap
    static let selfReportCap = LearnerMemory.selfReportCap
    static let sampleCap = LearnerMemory.sampleCap

    var grammar: [String: GrammarSkill] {
        get { decode([String: GrammarSkill].self, from: grammarData) ?? [:] }
        set { grammarData = try? JSONEncoder().encode(newValue) }
    }
    var vocab: [VocabTouch] {
        get { decode([VocabTouch].self, from: vocabData) ?? [] }
        set { vocabData = try? JSONEncoder().encode(newValue) }
    }
    var slips: [LexicalSlip] {
        get { decode([LexicalSlip].self, from: slipsData) ?? [] }
        set { slipsData = try? JSONEncoder().encode(newValue) }
    }
    var selfReports: [SelfReportNote] {
        get { decode([SelfReportNote].self, from: selfReportsData) ?? [] }
        set { selfReportsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Archive (never injected into the model; user-facing + restore)

@Model
final class ArchivedMemoryItem {
    var id: UUID
    var kindRaw: String
    var reasonRaw: String
    var archivedAt: Date
    /// Human-readable primary text (vocab: the German word; slip: "wrong → right").
    var title: String
    /// Secondary text (vocab: English; slip: the note).
    var subtitle: String
    /// Encoded original `VocabTouch` / `LexicalSlip` for exact restore into the active set.
    var payload: Data?

    init(kind: MemoryKind, reason: ArchiveReason, title: String, subtitle: String, payload: Data?) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.reasonRaw = reason.rawValue
        self.archivedAt = Date()
        self.title = title
        self.subtitle = subtitle
        self.payload = payload
    }

    var kind: MemoryKind { MemoryKind(rawValue: kindRaw) ?? .vocab }
    var reason: ArchiveReason { ArchiveReason(rawValue: reasonRaw) ?? .agedOut }
}
