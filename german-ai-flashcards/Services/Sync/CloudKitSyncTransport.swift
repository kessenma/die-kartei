import CloudKit
import Foundation
import OSLog

/// The real transport: CKSyncEngine on the learner's private CloudKit database.
///
/// - One zone, "Kartei", and one record type, "KarteiItem", with fixed fields `kind`, `payload`
///   (JSON bytes), `payloadAsset` (for payloads over 512 KB) and `file` (for pictures and
///   handouts). Model changes only change the JSON, so the Production schema is deployed once.
/// - The engine's state (server change tokens and the pending list) is saved to a file after every
///   `stateUpdate`. It's tagged with the store it belongs to, so a moved-aside store starts over
///   with a full fetch.
/// - Conflicts (`serverRecordChanged`) go back to the coordinator to merge, then re-queue.
///   `quotaExceeded` is parked rather than retried in a loop.
@MainActor
final class CloudKitSyncTransport: SyncTransport {
    static let containerID = "iCloud.kyle-essenmacher.german-ai-flashcards"
    static let zoneID = CKRecordZone.ID(zoneName: "Kartei", ownerName: CKCurrentUserDefaultName)
    static let recordType = "KarteiItem"
    static let inlinePayloadLimit = 512 * 1024

    weak var delegate: (any SyncTransportDelegate)?
    /// Account changes, zone deletions and storage-full, for `SyncManager`.
    var onAccountChange: ((CKSyncEngine.Event.AccountChange.ChangeType) -> Void)?
    var onZoneDeleted: ((CKDatabase.DatabaseChange.Deletion.Reason) -> Void)?
    var onQuotaExceeded: (() -> Void)?
    var onActivity: ((Bool) -> Void)?

    let container = CKContainer(identifier: containerID)
    private var engine: CKSyncEngine?
    /// The engine started without saved state, so its next fetch covers the whole zone.
    private var fullFetchPending = false
    private let storeTag: String
    private let stateURL: URL
    /// Records parked after `quotaExceeded`, re-added on the next foreground or Sync Now.
    private var parked: Set<String> = []
    private let log = Logger(subsystem: "kyle-essenmacher.german-ai-flashcards", category: "sync")

    init(storeTag: String) {
        self.storeTag = storeTag
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stateURL = dir.appendingPathComponent("engine-state.json")
    }

    // MARK: Lifecycle

    func start() {
        guard engine == nil else { return }
        let saved = loadState()
        fullFetchPending = saved == nil
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: saved,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        // Idempotent: saving an existing zone is a no-op on the server.
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
    }

    func stop() {
        engine = nil
    }

    // MARK: SyncTransport

    func enqueue(saves: [String], deletes: [String]) {
        guard let engine, !(saves.isEmpty && deletes.isEmpty) else { return }
        let changes: [CKSyncEngine.PendingRecordZoneChange] =
            saves.map { .saveRecord(Self.recordID($0)) } + deletes.map { .deleteRecord(Self.recordID($0)) }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    func syncNow() async throws {
        guard let engine else { return }
        if !parked.isEmpty {
            enqueue(saves: Array(parked), deletes: [])
            parked = []
        }
        try await engine.sendChanges()
        try await engine.fetchChanges()
    }

    /// CKSyncEngine has no "forget my change token" call, so start a fresh engine with no saved
    /// state: its first fetch returns the whole zone. Pending changes are re-added by the
    /// coordinator (`requeueOwed`) after the `signIn` event a fresh engine always sends.
    func resetFetchState() {
        try? FileManager.default.removeItem(at: stateURL)
        engine = nil
        start()
    }

    // MARK: Records

    static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// The CKRecord to send for a queued name, or nil if nothing is pending for it any more.
    private func record(for id: CKRecord.ID) -> CKRecord? {
        guard let out = delegate?.outgoing(id.recordName) else { return nil }
        let record = out.stamp.flatMap(Self.decodeSystemFields) ?? CKRecord(recordType: Self.recordType, recordID: id)
        let data = SyncJSON.object(out.payload).canonicalData
        if let file = out.fileURL, FileManager.default.fileExists(atPath: file.path) {
            record["file"] = CKAsset(fileURL: file)
        }
        record["kind"] = String(id.recordName.prefix { $0 != ":" }) as CKRecordValue
        if data.count <= Self.inlinePayloadLimit {
            record["payload"] = data as CKRecordValue
            record["payloadAsset"] = nil
        } else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString).json")
            try? data.write(to: url)
            record["payload"] = nil
            record["payloadAsset"] = CKAsset(fileURL: url)
        }
        return record
    }

    static func payload(of record: CKRecord) -> SyncPayload? {
        if let data = record["payload"] as? Data { return try? SyncJSON(data: data).objectValue }
        if let asset = record["payloadAsset"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            return try? SyncJSON(data: data).objectValue
        }
        return nil
    }

    static func incoming(_ record: CKRecord) -> SyncIncoming? {
        guard let payload = payload(of: record) else { return nil }
        return SyncIncoming(name: record.recordID.recordName, payload: payload,
                            stamp: encodeSystemFields(record), tag: record.recordChangeTag ?? "",
                            fileURL: (record["file"] as? CKAsset)?.fileURL)
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Engine state

    private struct SavedState: Codable {
        var storeTag: String
        var state: CKSyncEngine.State.Serialization
    }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data),
              saved.storeTag == storeTag
        else { return nil }
        return saved.state
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(SavedState(storeTag: storeTag, state: state)) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncTransport: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            onAccountChange?(change.changeType)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
                onZoneDeleted?(deletion.reason)
            }

        case .fetchedRecordZoneChanges(let changes):
            let incoming = changes.modifications.compactMap { Self.incoming($0.record) }
            let deleted = changes.deletions.map(\.recordID.recordName)
            delegate?.transportFetched(incoming, deleted: deleted)

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                guard let payload = Self.payload(of: record) else { continue }
                delegate?.transportDidSave(record.recordID.recordName, sent: payload,
                                           stamp: Self.encodeSystemFields(record),
                                           tag: record.recordChangeTag ?? "")
            }
            for id in sent.deletedRecordIDs { delegate?.transportDidDelete(id.recordName) }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            var needZone = false
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    if let server = failure.error.serverRecord, let incoming = Self.incoming(server) {
                        delegate?.transportConflict(name, server: incoming)
                    }
                    retry.append(.saveRecord(failure.record.recordID))
                case .zoneNotFound, .userDeletedZone:
                    needZone = true
                    delegate?.transportUnknownItem(name)
                    retry.append(.saveRecord(failure.record.recordID))
                case .unknownItem:
                    delegate?.transportUnknownItem(name)
                    retry.append(.saveRecord(failure.record.recordID))
                case .quotaExceeded:
                    parked.insert(name)
                    onQuotaExceeded?()
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .notAuthenticated, .requestRateLimited, .accountTemporarilyUnavailable:
                    break  // the engine retries these itself
                default:
                    delegate?.transportFailed(name, error: failure.error.localizedDescription)
                }
            }
            for (id, error) in sent.failedRecordDeletes where error.code == .unknownItem {
                delegate?.transportDidDelete(id.recordName)  // already gone
            }
            if needZone {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }

        case .willFetchChanges, .willSendChanges:
            onActivity?(true)
        case .didFetchChanges:
            onActivity?(false)
            delegate?.transportDidFinishFetch(wasFullFetch: fullFetchPending)
            fullFetchPending = false
        case .didSendChanges:
            onActivity?(false)

        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            log.info("Unhandled CKSyncEngine event")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await MainActor.run {
                if let record = self.record(for: id) { return record }
                // Nothing to send any more (already in step with the server): drop it, or the
                // engine keeps asking.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                return nil
            }
        }
    }
}
