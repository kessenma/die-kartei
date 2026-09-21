//
//  ProgressSnapshotStore.swift
//  german-ai-flashcards
//
//  The journey record behind „Dein Weg": `Application Support/Progress/journey.json`.
//
//  Two kinds of history live here, and the split matters:
//
//  * **Snapshots** — a small numeric row (per-layer earned fill, learned-word counts, streak,
//    level) taken about once a week. Most of the app's history is reconstructable from records
//    that already carry dates, but the pyramid's fills, matured words and comeback words are
//    computed live and leave no trail — a snapshot is the only way "watch the building rise"
//    can ever exist. Starts paying off the day it starts recording, which is why it ships first.
//  * **Milestones** — dated events detected *at record time* by diffing against the detection
//    state (`seenComebackWords`, `seenCompletedLayers`): things worth a timeline row that no
//    existing record dates (a layer newly complete, a word forgotten once and re-proven).
//
//  Same storage rationale as `PlacementAttemptStore` (the template for this file): not SwiftData
//  — the store deletes and recreates itself on migration failure, so gamification data stays out
//  of the schema; not UserDefaults — that plist is parsed on the launch path; Application Support
//  rather than Caches because this is user content and must survive cache eviction. A decode
//  failure yields an empty journey rather than a crash; nothing else depends on this data.
//

import Foundation
import SwiftData

// MARK: - Document

/// Everything in the file, one root value. Snapshots are stored oldest-first (append-only);
/// milestones likewise — readers sort for display.
struct JourneyDocument: Codable {
    var snapshots: [ProgressSnapshot] = []
    var milestones: [RecordedMilestone] = []
    /// Detection state, single copy each — what the recorder has already turned into a milestone
    /// (or silently seeded on the first run), so nothing is announced twice.
    var seenComebackWords: [String] = []
    var seenCompletedLayers: [String] = []
    /// „Weißt du es noch?" throttle state; nil until the first probe.
    var probe: ProbeState? = nil
}

/// One weekly trend row. Deliberately small and fixed-size: no word lists, no free text —
/// growth is bounded by the cap, not by how much the learner studies.
struct ProgressSnapshot: Codable {
    var takenAt: Date
    /// `PyramidLayerID.rawValue` → earned fill (0…1). Earned only — a blueprint is not history.
    var earnedFill: [String: Double]
    /// The blueprint share at the time (`overallFill − overallEarnedFill`), for context lines.
    var blueprintFill: Double
    var learnedA1: Int
    var learnedA2: Int
    var solidCoreGrammar: Int
    var wellHeldConversations: Int
    var streak: Int
    var level: Int
    var totalXP: Int
}

/// A dated journey event no existing record could date — recorded once, at detection time.
struct RecordedMilestone: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var kindRaw: String
    var title: String
    var subtitle: String

    var kind: MilestoneKind { MilestoneKind(rawValue: kindRaw) ?? .comebackWord }

    init(kind: MilestoneKind, date: Date, title: String, subtitle: String) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.title = title
        self.subtitle = subtitle
    }
}

enum MilestoneKind: String, Codable {
    case layerComplete
    case comebackWord
    /// „Weißt du es noch?" answered right — the mastered item held up months later.
    case stillSolid
    /// …answered wrong — the item went back to the coach's active memory.
    case backInTraining
}

/// „Weißt du es noch?" bookkeeping: when the last probe was shown, so return visits get at most
/// one question a week.
struct ProbeState: Codable {
    var lastAskedAt: Date
}

// MARK: - Store

enum ProgressSnapshotStore {

    /// Runaway backstops, not product limits: 520 weekly snapshots is ten years; 600 milestones
    /// is a long journey. Oldest rows fall off first only at these extremes.
    static let snapshotCap = 520
    static let milestoneCap = 600

    private static let directoryName = "Progress"
    private static let fileName = "journey.json"

    private static var fileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(directoryName)
            .appendingPathComponent(fileName)
    }

    private static var cache: JourneyDocument?

    static func document() -> JourneyDocument {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(JourneyDocument.self, from: data)
        else {
            cache = JourneyDocument()
            return JourneyDocument()
        }
        cache = decoded
        return decoded
    }

    static func save(_ document: JourneyDocument) {
        var trimmed = document
        if trimmed.snapshots.count > snapshotCap {
            trimmed.snapshots = Array(trimmed.snapshots.suffix(snapshotCap))
        }
        if trimmed.milestones.count > milestoneCap {
            trimmed.milestones = Array(trimmed.milestones.suffix(milestoneCap))
        }
        cache = trimmed
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(trimmed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func appendMilestone(_ milestone: RecordedMilestone) {
        var doc = document()
        doc.milestones.append(milestone)
        save(doc)
    }

    static func markProbeAsked(at date: Date = Date()) {
        var doc = document()
        doc.probe = ProbeState(lastAskedAt: date)
        save(doc)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// MARK: - Recorder

@MainActor
enum ProgressSnapshotService {

    /// About weekly. The hook fires on every Home appear; this is what makes it cheap.
    static let cadenceDays = 7

    /// Take a snapshot if one is due, detecting fresh milestones along the way. The very first
    /// run seeds the detection state *silently* — a learner with three complete layers on install
    /// day should not get three "vollendet!" rows all dated today (the badge seeder's precedent).
    static func recordIfDue(in context: ModelContext, now: Date = Date()) {
        var doc = ProgressSnapshotStore.document()
        if let last = doc.snapshots.last?.takenAt,
           now.timeIntervalSince(last) < Double(cadenceDays) * 86_400 {
            return
        }
        let seeding = doc.snapshots.isEmpty

        let prepositionStats = (try? context.fetch(FetchDescriptor<PrepositionStat>())) ?? []
        let cards = (try? context.fetch(FetchDescriptor<SavedCard>())) ?? []
        let storyAttempts = (try? context.fetch(FetchDescriptor<StoryQuizAttempt>())) ?? []
        let profile = (try? context.fetch(FetchDescriptor<LearnerProfile>()))?.first
        let studyDays = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let articleStats = (try? context.fetch(FetchDescriptor<ArticleWordStat>())) ?? []
        let matchingStats = (try? context.fetch(FetchDescriptor<MatchingPairStat>())) ?? []
        let conversations = (try? context.fetch(FetchDescriptor<ChatConversation>())) ?? []

        let snapshot = PyramidService.snapshot(
            prepositionStats: prepositionStats,
            cards: cards,
            storyAttempts: storyAttempts,
            profile: profile,
            studyDays: studyDays,
            articleStats: articleStats,
            matchingStats: matchingStats,
            placement: PlacementService.current,
            conversations: conversations
        )
        let layers = PyramidService.layers(from: snapshot)
        let level = ExperienceService.level(for: studyDays)

        doc.snapshots.append(ProgressSnapshot(
            takenAt: now,
            earnedFill: Dictionary(uniqueKeysWithValues: layers.map { ($0.id.rawValue, $0.earnedFill) }),
            blueprintFill: PyramidService.overallFill(layers) - PyramidService.overallEarnedFill(layers),
            learnedA1: snapshot.learnedA1Words,
            learnedA2: snapshot.learnedA2Words,
            solidCoreGrammar: snapshot.solidCoreGrammar,
            wellHeldConversations: ConversationQualityService.wellHeldCount(
                conversations.filter { ConversationQualityService.density($0) != nil }
            ),
            streak: StudyLogService.currentStreak(studyDays),
            level: level.level,
            totalXP: level.totalXP
        ))

        // Newly complete layers → dated milestones (silently seeded on the first run).
        for layer in layers where layer.isComplete && !doc.seenCompletedLayers.contains(layer.id.rawValue) {
            doc.seenCompletedLayers.append(layer.id.rawValue)
            guard !seeding else { continue }
            doc.milestones.append(RecordedMilestone(
                kind: .layerComplete, date: now,
                title: "\(layer.id.germanTitle) vollendet",
                subtitle: "A whole layer stands — built, not outlined."
            ))
        }

        // Comeback words: forgotten at least once, now re-proven. `repetitions` resets on a
        // lapse, so `>= provenRepetitions` after any lapse means "right three times running,
        // right now" — the same bar the pyramid's learned-words rule uses.
        for card in cards where card.lapses > 0 && card.repetitions >= PyramidService.provenRepetitions {
            let key = card.germanWord.lowercased()
            guard !doc.seenComebackWords.contains(key) else { continue }
            doc.seenComebackWords.append(key)
            guard !seeding else { continue }
            doc.milestones.append(RecordedMilestone(
                kind: .comebackWord, date: now,
                title: "«\(card.germanWord)» zurückgeholt",
                subtitle: "Forgotten once — yours again."
            ))
        }

        ProgressSnapshotStore.save(doc)
    }
}
