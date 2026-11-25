import Foundation
import OSLog
import SwiftData

/// Turns local edits into "this record must go up".
///
/// The app writes through ~70 insert sites and ~150 saves. Rather than hook each one, the tracker
/// reads SwiftData's persistent history: every transaction the learner's edits produced
/// (`author == nil`) since the last processed token. That covers autosave, explicit saves, cascade
/// deletes and batch deletes alike, and it survives the app being killed between an edit and its
/// upload.
///
/// Transactions by `"sync"` (the applier and this tracker) and by Core Data's schema migrator
/// (`com.apple.coredata.*`) are skipped.
@MainActor
final class SyncChangeTracker {
    struct Outcome {
        var saves: [String] = []
        var deletes: [String] = []
        var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
    }

    private let context: ModelContext
    private let identity: SyncIdentity
    /// Records outside SwiftData. Empty in the DEBUG round trip, whose two stores share one app's
    /// UserDefaults and files.
    var documents: [any SyncDocumentKind] = SyncDocuments.kinds
    private let log = Logger(subsystem: "kyle-essenmacher.german-ai-flashcards", category: "sync")
    static let pageSize = 200

    init(context: ModelContext, identity: SyncIdentity) {
        self.context = context
        self.identity = identity
    }

    // MARK: Incremental

    /// Process history since the stored token. Falls back to a full reconciliation if the token has
    /// expired or the first scan hasn't happened yet.
    func processHistory() throws -> Outcome {
        let meta = SyncStoreMeta.meta(in: context)
        guard meta.initialScanDone else { return try reconcileAll() }

        var token = decodeToken(meta.historyToken)
        var changed: [PersistentIdentifier] = []
        var changedSet = Set<PersistentIdentifier>()
        var deleted = Set<PersistentIdentifier>()
        var lastToken = token

        do {
            while true {
                let page = try fetchTransactions(after: token, limit: Self.pageSize)
                for tx in page {
                    lastToken = tx.token
                    guard tx.author == nil else { continue }
                    for change in tx.changes {
                        let id = change.changedPersistentIdentifier
                        guard SyncRegistry.byEntity[id.entityName] != nil else { continue }
                        if case .delete = change {
                            deleted.insert(id)
                        } else if changedSet.insert(id).inserted {
                            changed.append(id)
                        }
                    }
                }
                if page.count < Self.pageSize { break }
                token = lastToken
            }
        } catch let error as SwiftDataError where error == .historyTokenExpired {
            log.notice("History token expired; reconciling everything")
            return try reconcileAll()
        }

        return try SyncWriter.write(context) {
            var outcome = Outcome()
            for id in changed where !deleted.contains(id) {
                guard let handler = SyncRegistry.byEntity[id.entityName],
                      let model = handler.model(for: id, in: context)
                else { continue }
                if let name = noteLocal(model, handler: handler, bootstrapping: false) { outcome.saves.append(name) }
            }
            for id in deleted {
                guard let key = id.syncKey, let state = SyncStoreMeta.state(localKey: key, in: context) else { continue }
                if markDeleted(state) { outcome.deletes.append(state.recordName) }
            }
            let docs = noteDocuments(bootstrapping: false)
            outcome.saves += docs.saves
            outcome.deletes += docs.deletes
            if let lastToken { meta.historyToken = encodeToken(lastToken) }
            return outcome
        }
    }

    // MARK: Full reconciliation

    /// Compare every syncable row with its sync state, the way a first enable, an expired token, or
    /// Repair Sync needs. On the first run, pre-sync counters are credited to the bootstrap slots.
    func reconcileAll() throws -> Outcome {
        let meta = SyncStoreMeta.meta(in: context)
        let bootstrapping = !meta.initialScanDone
        // The token first: edits made while the scan runs come after it and are processed again,
        // which is harmless.
        let latest = try latestToken()

        return try SyncWriter.write(context) {
            var outcome = Outcome()
            var byKey: [String: SyncRecordState] = [:]
            var byName: [String: SyncRecordState] = [:]
            for state in SyncStoreMeta.allStates(in: context) {
                if let key = state.localKey { byKey[key] = state }
                byName[state.recordName] = state
            }
            var seen = Set<String>()

            for handler in SyncRegistry.handlers {
                var offset = 0
                while true {
                    let models = handler.allModels(in: context, offset: offset, limit: Self.pageSize)
                    for model in models {
                        guard handler.includes(model), let key = model.persistentModelID.syncKey else { continue }
                        seen.insert(key)
                        // Resolve (or create) the state from the maps loaded above, never with a
                        // fetch per row: fetches see every unsaved insert of this pass, which made the
                        // first scan quadratic in the number of rows.
                        var state = byKey[key] ?? handler.recordName(for: model).flatMap { byName[$0.description] }
                        if state == nil, let name = handler.recordName(for: model) {
                            let created = SyncRecordState(recordName: name.description, kind: handler.kind)
                            context.insert(created)
                            byName[name.description] = created
                            state = created
                        }
                        if let name = noteLocal(model, handler: handler, bootstrapping: bootstrapping, existing: state) {
                            outcome.saves.append(name)
                        }
                        if let state, state.localKey == key { byKey[key] = state }
                    }
                    // A page at a time, so an interrupted first scan resumes rather than restarts.
                    try context.save()
                    if models.count < Self.pageSize { break }
                    offset += Self.pageSize
                }
            }

            // Rows gone since the last look: their deletes still have to reach the server.
            for (key, state) in byKey where !seen.contains(key) && state.heldPayload == nil {
                if SyncStoreMeta.model(for: state, in: context) == nil, markDeleted(state) {
                    outcome.deletes.append(state.recordName)
                }
            }

            let docs = noteDocuments(bootstrapping: bootstrapping)
            outcome.saves += docs.saves
            outcome.deletes += docs.deletes
            meta.initialScanDone = true
            if let latest { meta.historyToken = encodeToken(latest) }
            return outcome
        }
    }

    // MARK: Per record

    /// Recompute a row's pending copy. Returns its record name when it needs uploading.
    @discardableResult
    func noteLocal(
        _ model: any PersistentModel,
        handler: any SyncKindHandling,
        bootstrapping: Bool,
        existing: SyncRecordState? = nil
    ) -> String? {
        guard handler.includes(model), let known = handler.known(model),
              let key = model.persistentModelID.syncKey
        else { return nil }

        let state: SyncRecordState
        if let existing {
            state = existing
        } else if let found = SyncStoreMeta.state(localKey: key, in: context) {
            state = found
        } else {
            guard let name = handler.recordName(for: model) else { return nil }
            if let byName = SyncStoreMeta.states(named: [name.description], in: context)[name.description] {
                state = byName
            } else {
                state = SyncRecordState(recordName: name.description, kind: handler.kind)
                context.insert(state)
            }
        }
        // A delete from another device is waiting for this row's screen to close: the delete wins,
        // so edits made meanwhile aren't sent (they'd re-create the record on the server).
        if state.heldReason == SyncApplier.deferredDelete { return nil }
        // Two live rows claiming one record (StudyDay twins before they're folded): keep the
        // binding rather than flip it, which would move one row's counts onto the other.
        if let bound = state.localKey, bound != key, SyncStoreMeta.modelExists(localKey: bound, kind: handler.kind, in: context) {
            log.error("Two rows map to \(state.recordName, privacy: .public); keeping the first")
            return nil
        }
        state.localKey = key

        var copies = state.copies
        let previousPending = copies.pending
        // Counters first seen during the initial scan predate sync: bootstrap slot. Anything else
        // was studied on this install since sync came on: this replica's slot.
        let slot = bootstrapping && copies.base == nil
            ? identity.slot(for: handler.bootstrap(for: model))
            : identity.replica
        let upload = SyncRecordLogic.noteLocal(
            &copies, known: known, spec: handler.spec, slot: slot,
            now: Date().timeIntervalSinceReferenceDate
        )
        state.copies = copies
        state.pendingDelete = false
        state.needsUpload = upload
        state.updatedAt = .now
        // A new version gets a fresh set of tries: a record stuck on an old error can recover.
        if upload, copies.pending != previousPending {
            state.failureCount = 0
            state.lastError = nil
        }
        return upload ? state.recordName : nil
    }

    /// Records outside SwiftData (UserDefaults progress, the journey and placement files): compared
    /// with their last synced copy every pass, since history can't see them.
    private func noteDocuments(bootstrapping: Bool) -> Outcome {
        var names: [String] = []
        var deletedDocuments: [String] = []
        for kind in documents {
            let local = kind.localRecords()
            // One fetch per kind: the File kind can have hundreds of records.
            let kindName = kind.spec.kind
            let d = FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.kind == kindName })
            var existing = Dictionary(((try? context.fetch(d)) ?? []).map { ($0.recordName, $0) }, uniquingKeysWith: { a, _ in a })
            if kind.tracksDeletions {
                let present = Set(local.map { $0.name.description })
                for state in existing.values where !present.contains(state.recordName) && !state.pendingDelete
                    && state.heldReason == nil {
                    if markDeleted(state) { deletedDocuments.append(state.recordName) }
                }
            }
            for (name, known) in local {
                let key = name.description
                let state = existing[key] ?? {
                    let s = SyncRecordState(recordName: key, kind: name.kind)
                    context.insert(s)
                    existing[key] = s
                    return s
                }()
                var copies = state.copies
                let fresh = bootstrapping && copies.base == nil
                let slot = fresh ? identity.slot(for: .perStore) : identity.replica
                // A fresh device's first look at its settings is mostly defaults. Stamped as the
                // oldest possible change, they never beat a real choice already on the server.
                let upload = SyncRecordLogic.noteLocal(
                    &copies, known: known, spec: kind.spec, slot: slot,
                    now: fresh ? 0 : Date().timeIntervalSinceReferenceDate
                )
                if copies != state.copies { state.copies = copies }
                if state.needsUpload != upload { state.needsUpload = upload }
                if upload { names.append(key) }
            }
        }
        return Outcome(saves: names, deletes: deletedDocuments)
    }

    /// A local delete. Returns true if the server must hear about it. A record the server never
    /// had just loses its state.
    private func markDeleted(_ state: SyncRecordState) -> Bool {
        // Only a record that was never handed to the server can go quietly. One with an upload
        // owed may already be on its way (a save in flight); its delete must follow it, and a
        // delete of a record the server never got is harmless (`unknownItem` counts as done).
        if state.serverPayload == nil && state.serverStamp == nil && !state.needsUpload {
            context.delete(state)
            return false
        }
        state.pendingDelete = true
        state.needsUpload = false
        state.updatedAt = .now
        return true
    }

    // MARK: History plumbing

    private func fetchTransactions(after token: DefaultHistoryToken?, limit: Int) throws -> [DefaultHistoryTransaction] {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            predicate: token.map { t in #Predicate<DefaultHistoryTransaction> { $0.token > t } },
            sortBy: [SortDescriptor(\.transactionIdentifier)]
        )
        descriptor.fetchLimit = UInt64(limit)
        return try context.fetchHistory(descriptor)
    }

    private func latestToken() throws -> DefaultHistoryToken? {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetchHistory(descriptor).first?.token
    }

    /// Drop history the tracker has already processed; the store never trimmed it before sync.
    func trimProcessedHistory() {
        let meta = SyncStoreMeta.meta(in: context)
        guard let token = decodeToken(meta.historyToken) else { return }
        let descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            predicate: #Predicate { $0.token <= token }
        )
        try? context.deleteHistory(descriptor)
    }

    private func decodeToken(_ data: Data?) -> DefaultHistoryToken? {
        data.flatMap { try? JSONDecoder().decode(DefaultHistoryToken.self, from: $0) }
    }

    private func encodeToken(_ token: DefaultHistoryToken) -> Data? {
        try? JSONEncoder().encode(token)
    }
}
