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
    /// Whether this device has ever synced with the zone. A zone that goes missing after that was
    /// deleted on purpose (Delete iCloud Data, iOS Settings) and must not be made again.
    var zoneWasSeen: () -> Bool = { false }

    let container = CKContainer(identifier: containerID)
    private var engine: CKSyncEngine?
    /// The engine started without saved state, so its next fetch covers the whole zone.
    private var fullFetchPending = false
    /// The Kartei zone's part of the current fetch failed, so it can't count as complete.
    private var fetchFailed = false
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
        // Only a device that has never met the zone creates it. Recreating it on every launch would
        // undo a Delete iCloud Data made on another device before this one heard about it.
        if !zoneWasSeen() {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
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
        // Off the main actor. The delegate is main-actor isolated, and CKSyncEngine traps
        // ("cannot await a call into CKSyncEngine from within a delegate callback") when a caller on
        // the delegate's actor awaits it while one of its callbacks is in flight. A detached task
        // leaves the main actor free for those callbacks to run.
        try await Task.detached {
            try await engine.sendChanges()
            try await engine.fetchChanges()
        }.value
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
            // One file per record, overwritten on each send, so retries don't pile up files.
            let dir = URL.cachesDirectory.appendingPathComponent("SyncOutbox", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(SyncNameUUID.make(id.recordName).uuidString + ".json")
            try? data.write(to: url, options: .atomic)
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

    /// What a record weighs on the wire: its JSON (inline or as an asset) plus any file it carries.
    static func byteSize(_ record: CKRecord) -> Int64 {
        func size(_ asset: CKAsset?) -> Int64 {
            guard let url = asset?.fileURL,
                  let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
            return Int64(bytes)
        }
        let inline = Int64((record["payload"] as? Data)?.count ?? 0)
        return inline + size(record["payloadAsset"] as? CKAsset) + size(record["file"] as? CKAsset)
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

    /// Forget the saved engine state (after the zone was deleted): the next engine starts fresh.
    static func discardSavedState() {
        let url = URL.applicationSupportDirectory.appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("engine-state.json")
        try? FileManager.default.removeItem(at: url)
    }

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
        // An engine replaced by `resetFetchState` may still deliver a last event or two; its state
        // and results belong to the old engine.
        guard syncEngine === engine else { return }
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
            delegate?.transportProgress(.received(
                records: changes.modifications.count + changes.deletions.count,
                bytes: changes.modifications.reduce(0) { $0 + Self.byteSize($1.record) }))

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                guard let payload = Self.payload(of: record) else { continue }
                delegate?.transportDidSave(record.recordID.recordName, sent: payload,
                                           stamp: Self.encodeSystemFields(record),
                                           tag: record.recordChangeTag ?? "")
            }
            for id in sent.deletedRecordIDs { delegate?.transportDidDelete(id.recordName) }
            delegate?.transportProgress(.sent(
                records: sent.savedRecords.count + sent.deletedRecordIDs.count,
                bytes: sent.savedRecords.reduce(0) { $0 + Self.byteSize($1) }))
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            var needZone = false
            var zoneGone = false
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    // Retry only after a merge. A big record's server copy can arrive without its
                    // payload asset; then the next fetch brings it and re-queues the merge.
                    if let server = failure.error.serverRecord, let incoming = Self.incoming(server) {
                        delegate?.transportConflict(name, server: incoming)
                        retry.append(.saveRecord(failure.record.recordID))
                    }
                case .userDeletedZone:
                    zoneGone = true
                case .zoneNotFound:
                    if zoneWasSeen() {
                        zoneGone = true
                    } else {
                        needZone = true
                        delegate?.transportUnknownItem(name)
                        retry.append(.saveRecord(failure.record.recordID))
                    }
                case .unknownItem:
                    delegate?.transportUnknownItem(name)
                    retry.append(.saveRecord(failure.record.recordID))
                case .quotaExceeded:
                    parked.insert(name)
                    onQuotaExceeded?()
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .notAuthenticated, .requestRateLimited, .accountTemporarilyUnavailable,
                     .operationCancelled, .serverResponseLost:
                    break  // the engine retries these itself
                default:
                    delegate?.transportFailed(name, error: failure.error.localizedDescription)
                }
            }
            for (id, error) in sent.failedRecordDeletes where error.code == .unknownItem {
                delegate?.transportDidDelete(id.recordName)  // already gone
            }
            if zoneGone {
                // Deleted on purpose somewhere: stop, don't make it again.
                onZoneDeleted?(.deleted)
                return
            }
            if needZone {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }

        case .willFetchChanges:
            onActivity?(true)
            delegate?.transportProgress(.fetchStarted)
        case .willSendChanges:
            onActivity?(true)
            delegate?.transportProgress(.sendStarted)
        case .didFetchChanges:
            onActivity?(false)
            delegate?.transportProgress(.fetchFinished)
            // Complete only if the zone's part succeeded; a failed first fetch stays "pending full".
            delegate?.transportDidFinishFetch(wasFullFetch: fullFetchPending && !fetchFailed)
            if !fetchFailed { fullFetchPending = false }
            fetchFailed = false
        case .didFetchRecordZoneChanges(let done):
            if done.zoneID == Self.zoneID, done.error != nil { fetchFailed = true }
        case .didSendChanges:
            onActivity?(false)
            delegate?.transportProgress(.sendFinished)

        case .sentDatabaseChanges, .willFetchRecordZoneChanges:
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
