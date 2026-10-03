import Foundation
import Security
import SwiftData

/// Every synced kind, parents before children: a batch is applied in this order, so a deck lands
/// before the cards that point at it.
@MainActor
enum SyncRegistry {
    static let handlers: [any SyncKindHandling] = [
        // Decks and what hangs off them.
        SyncHandler<SavedDeckCodec>(),
        SyncHandler<SavedCardCodec>(),
        SyncHandler<QuizResultCodec>(),
        // Study log and per-word stats.
        SyncHandler<StudyDayCodec>(),
        SyncHandler<MatchingPairStatCodec>(),
        SyncHandler<MatchingRoundCodec>(),
        SyncHandler<ArticleWordStatCodec>(),
        SyncHandler<ArticleRoundCodec>(),
        SyncHandler<PrepositionStatCodec>(),
        SyncHandler<PrepositionRoundCodec>(),
        // Grammatik path: tutor-written stories before the rounds that key on them.
        SyncHandler<GeneratedKasusStoryCodec>(),
        SyncHandler<KasusRoundCodec>(),
        // Coaching memory.
        SyncHandler<LearnerProfileCodec>(),
        SyncHandler<ArchivedMemoryItemCodec>(),
        // Stories and papers.
        SyncHandler<StudyStoryCodec>(),
        SyncHandler<StoryReadingSessionCodec>(),
        SyncHandler<StoryQuizAttemptCodec>(),
        SyncHandler<StudyPaperCodec>(),
        // Conversations, job postings, phrases.
        SyncHandler<ChatConversationCodec>(),
        SyncHandler<ChatMessageCodec>(),
        SyncHandler<JobPostingCodec>(),
        SyncHandler<LearnedPhraseCodec>(),
        // Deutschkurs: course → entry → handout.
        SyncHandler<ClassCourseCodec>(),
        SyncHandler<ClassEntryCodec>(),
        SyncHandler<ClassMaterialCodec>(),
    ]

    static let byKind: [String: any SyncKindHandling] =
        Dictionary(uniqueKeysWithValues: handlers.map { ($0.kind, $0) })
    static let byEntity: [String: any SyncKindHandling] =
        Dictionary(uniqueKeysWithValues: handlers.map { ($0.entityName, $0) })
    static let order: [String: Int] =
        Dictionary(uniqueKeysWithValues: handlers.enumerated().map { ($1.kind, $0) })
}

/// Who gets credit for counter changes made on this device.
struct SyncIdentity {
    /// This install's replica slot. Kept in the Keychain with this-device-only access, so a backup
    /// restored onto a *second* device doesn't bring the same slot along. Two live devices sharing a
    /// slot would lose increments under pointwise max.
    let replica: String
    /// The bootstrap slot for pre-sync counters on per-store rows (`SyncBootstrap.perStore`).
    let store: String

    func slot(for bootstrap: SyncBootstrap) -> String {
        switch bootstrap {
        case .perStore: "store-" + store
        case .shared: SyncBootstrap.sharedSlot
        }
    }

    static func replicaID() -> String {
        let service = "kyle-essenmacher.german-ai-flashcards.sync", account = "replica"
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        #if os(macOS)
        // The Mac's legacy file keychain ignores `ThisDeviceOnly`, so a Migration Assistant copy
        // of this Mac would carry the same replica. The data-protection keychain honours it.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(id.utf8),
        ]
        #if os(macOS)
        add[kSecUseDataProtectionKeychain as String] = true
        #endif
        SecItemAdd(add as CFDictionary, nil)
        return id
    }
}

/// The write discipline for everything sync does to the store (docs/ICLOUD_SYNC.md, invariant 3):
/// flush the learner's pending edits under the normal author, then write under `"sync"`, with no
/// suspension point in between. The change tracker only reads `author == nil` history, so it
/// never sees sync's own writes, and never loses a learner edit that got swept into one.
@MainActor
enum SyncWriter {
    static let author = "sync"

    static func write<T>(_ context: ModelContext, _ body: () throws -> T) throws -> T {
        try context.save()
        context.author = author
        defer { context.author = nil }
        let result = try body()
        try context.save()
        return result
    }
}

/// The single `SyncMeta` row.
@MainActor
enum SyncStoreMeta {
    static func meta(in context: ModelContext) -> SyncMeta {
        if let meta = try? context.fetch(FetchDescriptor<SyncMeta>()).first { return meta }
        let meta = SyncMeta()
        context.insert(meta)
        return meta
    }

    static func states(named names: [String], in context: ModelContext) -> [String: SyncRecordState] {
        guard !names.isEmpty else { return [:] }
        let d = FetchDescriptor<SyncRecordState>(predicate: #Predicate { names.contains($0.recordName) })
        let rows = (try? context.fetch(d)) ?? []
        return Dictionary(rows.map { ($0.recordName, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func state(localKey: String, in context: ModelContext) -> SyncRecordState? {
        var d = FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.localKey == localKey })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func allStates(in context: ModelContext) -> [SyncRecordState] {
        (try? context.fetch(FetchDescriptor<SyncRecordState>())) ?? []
    }

    /// Whether the row behind a stored local key still exists.
    static func modelExists(localKey: String, kind: String, in context: ModelContext) -> Bool {
        guard let data = localKey.data(using: .utf8),
              let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data),
              let handler = SyncRegistry.byKind[kind]
        else { return false }
        return handler.model(for: id, in: context) != nil
    }

    /// The local row a state points at, if it still exists.
    static func model(for state: SyncRecordState, in context: ModelContext) -> (any PersistentModel)? {
        guard let key = state.localKey, let data = key.data(using: .utf8),
              let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data),
              let handler = SyncRegistry.byKind[state.kind]
        else { return nil }
        return handler.model(for: id, in: context)
    }
}
