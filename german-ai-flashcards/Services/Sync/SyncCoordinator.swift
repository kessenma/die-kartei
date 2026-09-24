import Foundation
import OSLog
import SwiftData

/// Runs iCloud Sync for one store: local changes out (tracker), server changes in (applier), and
/// the transport between them. Transport events arrive here and are handled synchronously on the
/// main actor.
@MainActor
@Observable
final class SyncCoordinator {
    // What the iCloud Sync screen shows.
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var pendingCount = 0
    private(set) var stuckCount = 0
    /// Recent engine events, newest first (shown in DEBUG builds).
    private(set) var events: [String] = []

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let identity: SyncIdentity
    @ObservationIgnored let transport: any SyncTransport
    @ObservationIgnored private let tracker: SyncChangeTracker
    @ObservationIgnored let applier: SyncApplier
    @ObservationIgnored private var saveObserver: NSObjectProtocol?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "kyle-essenmacher.german-ai-flashcards", category: "sync")

    /// Called after server changes landed, with the kinds that changed (reminders, backfills).
    @ObservationIgnored var didApplyRemoteChanges: ((Set<String>) -> Void)?

    init(context: ModelContext, identity: SyncIdentity, transport: any SyncTransport) {
        self.context = context
        self.identity = identity
        self.transport = transport
        self.tracker = SyncChangeTracker(context: context, identity: identity)
        self.applier = SyncApplier(context: context, identity: identity)
        transport.delegate = self
    }

    // MARK: Lifecycle

    /// Scan for local changes (the first scan credits pre-sync data to its bootstrap slots), queue
    /// everything still owed to the server, and start watching saves.
    func start() {
        // Singleton rows need their canonical ids before the first scan names their records.
        SyncCanonicalizer.runIfNeeded(in: context)
        pushLocalChanges()
        requeueOwed()
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: .main
        ) { [weak self] note in
            // Sync's own saves carry the "sync" author and are ignored. Reading it now is safe:
            // didSave is posted during the save, before the author is reset.
            let author = (note.object as? ModelContext)?.author
            MainActor.assumeIsolated {
                guard author != SyncWriter.author else { return }
                self?.scheduleLocalPush()
            }
        }
    }

    func stop() {
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
        debounce?.cancel()
    }

    /// Push local changes, then send and fetch.
    func syncNow() async {
        pushLocalChanges()
        isSyncing = true
        defer { isSyncing = false; refreshCounts() }
        do {
            try await transport.syncNow()
            lastSyncedAt = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            note("sync failed: \(error.localizedDescription)")
        }
    }

    /// Repair Sync: rescan every row against its state, then refetch the whole zone. Merges are
    /// idempotent, so this is safe at any time.
    func repair() async {
        do {
            let outcome = try tracker.reconcileAll()
            transport.enqueue(saves: outcome.saves, deletes: outcome.deletes)
            note("repair: \(outcome.saves.count) to send, \(outcome.deletes.count) to delete")
        } catch {
            note("repair scan failed: \(error.localizedDescription)")
        }
        transport.resetFetchState()
        await syncNow()
    }

    /// Forget the server's copies (zone deleted, database or account switched) while keeping every
    /// counter slot, so a later re-upload merges by max and can't double anything.
    func forgetServer() {
        _ = try? SyncWriter.write(context) {
            for state in SyncStoreMeta.allStates(in: context) {
                var copies = state.copies
                SyncRecordLogic.forgetServer(&copies)
                state.copies = copies
                state.serverStamp = nil
                state.lastSeenTag = nil
                state.needsUpload = copies.pending != nil && !state.pendingDelete
                if state.pendingDelete { context.delete(state) }
            }
        }
        transport.resetFetchState()
        requeueOwed()
        refreshCounts()
    }

    // MARK: Local changes

    private func scheduleLocalPush() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.pushLocalChanges()
        }
    }

    /// Read history and queue what changed.
    func pushLocalChanges() {
        do {
            let outcome = try tracker.processHistory()
            if !outcome.isEmpty {
                transport.enqueue(saves: outcome.saves, deletes: outcome.deletes)
                note("local: \(outcome.saves.count) changed, \(outcome.deletes.count) deleted")
            }
        } catch {
            note("change tracking failed: \(error.localizedDescription)")
        }
        refreshCounts()
    }

    /// Everything the store says is still owed, re-queued: after a relaunch, or an account change
    /// (CKSyncEngine drops its pending list then).
    func requeueOwed() {
        let owed = SyncStoreMeta.allStates(in: context)
        transport.enqueue(
            saves: owed.filter { $0.needsUpload && !$0.pendingDelete }.map(\.recordName),
            deletes: owed.filter(\.pendingDelete).map(\.recordName)
        )
    }

    private func refreshCounts() {
        let states = SyncStoreMeta.allStates(in: context)
        pendingCount = states.filter { $0.needsUpload || $0.pendingDelete }.count
        stuckCount = states.filter(\.isStuck).count
    }

    private func note(_ message: String) {
        log.info("\(message, privacy: .public)")
        events.insert("\(Date.now.formatted(date: .omitted, time: .standard))  \(message)", at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }
}

// MARK: - Transport events

extension SyncCoordinator: SyncTransportDelegate {
    func outgoing(_ name: String) -> (payload: SyncPayload, stamp: Data?)? {
        guard let state = SyncStoreMeta.states(named: [name], in: context)[name],
              state.needsUpload, !state.pendingDelete, !state.isStuck,
              let pending = state.copies.pending
        else { return nil }
        return (pending, state.serverStamp)
    }

    func transportDidSave(_ name: String, sent: SyncPayload, stamp: Data, tag: String) {
        _ = try? SyncWriter.write(context) {
            guard let state = SyncStoreMeta.states(named: [name], in: context)[name] else { return }
            var copies = state.copies
            SyncRecordLogic.didSave(&copies, sent: sent)
            state.copies = copies
            state.serverStamp = stamp
            state.lastSeenTag = tag
            state.needsUpload = copies.pending != nil
            state.failureCount = 0
            state.lastError = nil
        }
    }

    func transportConflict(_ name: String, server: SyncIncoming) {
        do {
            let outcome = try applier.apply([server], deleted: [])
            if !outcome.changedKinds.isEmpty { didApplyRemoteChanges?(outcome.changedKinds) }
        } catch {
            note("conflict merge failed for \(name): \(error.localizedDescription)")
        }
    }

    func transportUnknownItem(_ name: String) {
        _ = try? SyncWriter.write(context) {
            guard let state = SyncStoreMeta.states(named: [name], in: context)[name] else { return }
            var copies = state.copies
            SyncRecordLogic.forgetServer(&copies)
            state.copies = copies
            state.serverStamp = nil
            state.lastSeenTag = nil
            state.needsUpload = copies.pending != nil
        }
    }

    func transportDidDelete(_ name: String) {
        _ = try? SyncWriter.write(context) {
            if let state = SyncStoreMeta.states(named: [name], in: context)[name], state.pendingDelete {
                context.delete(state)
            }
        }
    }

    func transportFetched(_ records: [SyncIncoming], deleted: [String]) {
        guard !records.isEmpty || !deleted.isEmpty else { return }
        do {
            let outcome = try applier.apply(records, deleted: deleted)
            transport.enqueue(saves: outcome.uploads, deletes: [])
            if outcome.inserted + outcome.updated + outcome.deleted + outcome.held > 0 {
                note("fetched: +\(outcome.inserted) ~\(outcome.updated) −\(outcome.deleted) held \(outcome.held)")
            }
            if !outcome.changedKinds.isEmpty { didApplyRemoteChanges?(outcome.changedKinds) }
        } catch {
            note("applying fetched changes failed: \(error.localizedDescription)")
        }
    }

    func transportFailed(_ name: String, error: String) {
        _ = try? SyncWriter.write(context) {
            guard let state = SyncStoreMeta.states(named: [name], in: context)[name] else { return }
            state.failureCount += 1
            state.lastError = error
        }
        note("send failed for \(name): \(error)")
    }
}
