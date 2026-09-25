import Foundation
import SwiftData

/// What a sync is doing right now. CloudKit gives no totals for a fetch, so receiving is counted
/// as it goes; sending is measured against what was waiting when the send began.
struct SyncActivity: Equatable {
    var sending = false
    var receiving = false
    var sendTotal = 0
    var sent = 0
    var sentBytes: Int64 = 0
    var received = 0
    var receivedBytes: Int64 = 0

    var isActive: Bool { sending || receiving }
}

/// The last finished sync, kept across launches for the screen.
struct SyncSessionSummary: Codable, Equatable {
    var finishedAt: Date
    var sent: Int
    var sentBytes: Int64
    var received: Int
    var receivedBytes: Int64
}

/// One row of "In your iCloud": a kind of learner data, how many records, how much space.
struct SyncStorageLine: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    var records: Int = 0
    var bytes: Int64 = 0
}

extension SyncCoordinator {

    func transportProgress(_ progress: SyncTransportProgress) {
        switch progress {
        case .sendStarted:
            beginSessionIfIdle()
            refreshCountsForProgress()
            activity.sending = true
            activity.sendTotal = max(activity.sent + learnerPendingCount, activity.sendTotal)
        case let .sent(records, bytes):
            activity.sent += records
            activity.sentBytes += bytes
            activity.sendTotal = max(activity.sendTotal, activity.sent)
        case .sendFinished:
            activity.sending = false
            finishSessionIfIdle()
        case .fetchStarted:
            beginSessionIfIdle()
            activity.receiving = true
        case let .received(records, bytes):
            activity.received += records
            activity.receivedBytes += bytes
        case .fetchFinished:
            activity.receiving = false
            finishSessionIfIdle()
        }
    }

    private func beginSessionIfIdle() {
        guard !activity.isActive else { return }
        activity = SyncActivity()
    }

    private func finishSessionIfIdle() {
        guard !activity.isActive, activity.sent + activity.received > 0 else { return }
        let summary = SyncSessionSummary(finishedAt: .now, sent: activity.sent, sentBytes: activity.sentBytes,
                                         received: activity.received, receivedBytes: activity.receivedBytes)
        lastSession = summary
        if let data = try? JSONEncoder().encode(summary) { UserDefaults.standard.set(data, forKey: lastSessionKey) }
    }

    static func loadLastSession(key: String) -> SyncSessionSummary? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SyncSessionSummary.self, from: $0) }
    }

    // MARK: Storage

    /// What this learner's data takes up in iCloud, by kind: the server copies this device holds
    /// (their JSON) plus the pictures and PDFs that travel as files.
    func storageSummary() -> [SyncStorageLine] {
        backfillStorageSizes()
        var descriptor = FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.serverBytes > 0 })
        descriptor.propertiesToFetch = [\.kind, \.serverBytes, \.fileBytes]
        let states = (try? context.fetch(descriptor)) ?? []
        var lines: [String: SyncStorageLine] = [:]
        for state in states {
            guard let category = Self.storageCategory(for: state.kind) else { continue }
            var line = lines[category.id] ?? category
            line.records += 1
            line.bytes += Int64(state.serverBytes + state.fileBytes)
            lines[category.id] = line
        }
        return Self.storageCategories.compactMap { lines[$0.id] }
    }

    /// Records synced before sizes were kept have 0 bytes: measure them once from their stored copy.
    private func backfillStorageSizes() {
        let missing = (try? context.fetch(FetchDescriptor<SyncRecordState>(
            predicate: #Predicate { $0.serverBytes == 0 && $0.serverPayload != nil }
        ))) ?? []
        guard !missing.isEmpty else { return }
        _ = try? SyncWriter.write(context) {
            for state in missing {
                state.serverBytes = state.serverPayload?.count ?? 0
                if state.kind == "File", let size = state.copies.server?["size"]?.int64Value {
                    state.fileBytes = Int(size)
                }
            }
        }
    }

    static let storageCategories: [SyncStorageLine] = [
        SyncStorageLine(id: "cards", title: "Flashcards and Wortschatz", symbol: "rectangle.stack"),
        SyncStorageLine(id: "log", title: "Study days, rounds and stats", symbol: "flame"),
        SyncStorageLine(id: "stories", title: "Stories and papers", symbol: "book.pages"),
        SyncStorageLine(id: "chats", title: "Conversations and coaching memory", symbol: "bubble.left.and.bubble.right"),
        SyncStorageLine(id: "class", title: "Deutschkurs and job postings", symbol: "graduationcap"),
        SyncStorageLine(id: "files", title: "Pictures and PDFs", symbol: "photo.on.rectangle"),
        SyncStorageLine(id: "progress", title: "Level, placement and journey", symbol: "figure.stairs"),
    ]

    private static func storageCategory(for kind: String) -> SyncStorageLine? {
        let id: String? = switch kind {
        case "SavedDeck", "SavedCard", "QuizResult": "cards"
        case "StudyDay", "MatchingPairStat", "MatchingRound", "ArticleWordStat", "ArticleRound",
             "PrepositionStat", "PrepositionRound", "KasusRound": "log"
        case "StudyStory", "StoryReadingSession", "StoryQuizAttempt", "StudyPaper", "GeneratedKasusStory": "stories"
        case "ChatConversation", "ChatMessage", "LearnerProfile", "ArchivedMemoryItem", "LearnedPhrase": "chats"
        case "ClassCourse", "ClassEntry", "ClassMaterial", "JobPosting": "class"
        case "File": "files"
        case "Progress", "Journey", "PlacementAttempts": "progress"
        default: nil  // heartbeats and the zone fingerprint
        }
        return id.flatMap { id in storageCategories.first { $0.id == id } }
    }
}
