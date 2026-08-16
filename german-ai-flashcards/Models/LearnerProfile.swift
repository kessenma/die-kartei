import Foundation
import SwiftData

// MARK: - Value types (the "sections" inside the profile)

/// How shaky the learner is on one fixed grammar structure (keyed by `GrammarFocus.rawValue`).
struct GrammarSkill: Codable {
    /// 0 = solid, 1 = very shaky. Decays toward 0 each session so old weaknesses fade.
    var struggle: Double
    var lastSeen: Date
    /// Up to `LearnerProfile.sampleCap` recent "you said → better" examples, for the coach screen.
    var samples: [String]

    /// At or above this struggle level a structure counts as "shaky" — worth surfacing a
    /// just-in-time lesson / drill for. Matches the coach's briefing threshold so the Today
    /// plan and Coach's Notes agree on what's weak.
    static let shakyThreshold = 0.2
}

/// A word the learner has been exposed to and is working to retain.
struct VocabTouch: Codable, Identifiable, Hashable {
    var german: String
    var english: String
    var lastSeen: Date
    var timesUsed: Int
    /// Pinned items are exempt from automatic cleaning.
    var pinned: Bool = false
    /// Where this came from, when it wasn't a conversation — currently only
    /// `MemorySource.placement`. Optional so items stored before it existed decode unchanged, and
    /// deliberately *not* part of `id`: a word is the same word however the learner met it, so a
    /// placement miss should merge with a matching-game touch rather than sit beside it.
    var source: String? = nil
    var id: String { german.lowercased() }
}

/// A recurring word-level slip (wrong form → right form) — e.g. a case or gender error.
struct LexicalSlip: Codable, Identifiable, Hashable {
    var wrong: String
    var right: String
    var note: String
    var lastSeen: Date
    var timesSeen: Int
    /// Pinned items are exempt from automatic cleaning.
    var pinned: Bool = false
    /// The learner's own corrected sentence this slip came from — the seed for a personalized
    /// cloze ("fill in the blank") card. Optional so slips recorded before this was captured
    /// (and any that weren't single-sentence swaps) decode cleanly and are simply not drillable.
    var sentence: String? = nil
    /// Word index (into `sentence` split on spaces) of the token to blank — the corrected form.
    var blankIndex: Int? = nil
    /// Where this came from, when it wasn't the learner's own production — currently only
    /// `MemorySource.placement`. Optional so items stored before it existed decode unchanged.
    var source: String? = nil

    /// Unlike `VocabTouch`, the source **is** part of the identity here, and it has to be.
    ///
    /// Placement distractors are generic function words — "der", "die", "kein" — so a placement
    /// `die→der` would otherwise share an id with a real conversation `die→der`, and the merge
    /// branch in `LearnerMemoryService` overwrites `sentence`/`blankIndex`. That would replace the
    /// learner's own corrected sentence (and the personalized cloze card built from it) with a
    /// bank sentence. Existing slips have `source == nil`, so their ids stay byte-identical and
    /// pins, archives and self-heal keep working untouched.
    var id: String {
        (wrong + "→" + right + (source.map { "@" + $0 } ?? "")).lowercased()
    }

    /// True when this slip carries enough context to build a fill-in-the-blank card.
    var isClozeReady: Bool { sentence != nil && blankIndex != nil }
}

/// Where a memory came from, when it wasn't the learner's own conversation. Absent means the
/// ordinary path — a chat turn, a saved word, a story lookup.
enum MemorySource {
    /// Handed over from the placement check by the explicit button on the review screen.
    static let placement = "placement"
}

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

    /// Encoded `[String: GrammarSkill]` keyed by `GrammarFocus.rawValue` — fixed keys, cannot grow.
    var grammarData: Data?
    /// Encoded `[VocabTouch]` — LRU-capped at `vocabCap`.
    var vocabData: Data?
    /// Encoded `[LexicalSlip]` — LRU-capped at `slipCap`, self-heals on correct use.
    var slipsData: Data?

    init() {
        self.id = UUID()
        self.sessionCount = 0
        self.lastSessionAt = nil
    }

    // Bounds
    static let vocabCap = 60
    static let slipCap = 20
    static let sampleCap = 2

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

    private func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Archive (never injected into the model; user-facing + restore)

enum MemoryKind: String, Codable {
    case vocab
    case slip
}

/// Why an item left the active profile — shown on the archive screen.
enum ArchiveReason: String, Codable {
    case mastered        // the learner used it correctly, so the coach let it go
    case agedOut         // grew stale
    case replacedByLRU   // pushed out by newer items past the cap
    case removedByUser

    var label: String {
        switch self {
        case .mastered:      "Mastered"
        case .agedOut:       "Aged out"
        case .replacedByLRU: "Made room for newer"
        case .removedByUser: "Removed by you"
        }
    }
}

/// One cleaned-out memory the learner can review and restore. Stored as its own row so the
/// history can grow freely and be paged lazily — it never touches a prompt.
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
