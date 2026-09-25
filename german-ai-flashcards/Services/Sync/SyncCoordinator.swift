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
    /// The sync in progress, for the screen's progress bar (`SyncProgress.swift`).
    var activity = SyncActivity()
    /// The last finished sync: what went up and what came down.
    var lastSession: SyncSessionSummary? = SyncCoordinator.loadLastSession(key: "sync.lastSession")
    /// Where `lastSession` is kept. The DEBUG round trip uses its own keys (like `zoneInstanceKey`).
    @ObservationIgnored var lastSessionKey = "sync.lastSession" {
        didSet { lastSession = Self.loadLastSession(key: lastSessionKey) }
    }

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
    /// Where the zone fingerprint this device last saw is kept (see `SyncHealth.swift`).
    @ObservationIgnored var zoneInstanceKey = "sync.zoneInstance"
    /// When a learner-made record last changed here or arrived from the server. Heartbeats written
    /// before it can't be compared.
    private(set) var lastRecordChangeAt: Date?
    /// Kinds this device and a settled peer still disagree on after a repair.
    private(set) var disagreement: [String] = []
    @ObservationIgnored static let autoRepairKey = "sync.lastAutoRepairAt"
    /// Bumped whenever a server copy changes; digests are cached against it.
    @ObservationIgnored var serverCopiesVersion = 0
    @ObservationIgnored var digestCache: (version: Int, value: [String: SyncDigest])?
    /// The current fetch cycle delivered the zone fingerprint.
    @ObservationIgnored var sawZoneFingerprint = false
    /// At least one fetch has finished since launch.
    private(set) var hasCompletedFetch = false
    /// Waiting uploads, not counting heartbeats and the fingerprint.
    private(set) var learnerPendingCount = 0

    init(context: ModelContext, identity: SyncIdentity, transport: any SyncTransport, includeDocuments: Bool = true) {
        self.context = context
        self.identity = identity
        self.transport = transport
        self.tracker = SyncChangeTracker(context: context, identity: identity)
        self.applier = SyncApplier(context: context, identity: identity)
        if !includeDocuments {
            tracker.documents = []
            applier.documents = [:]
        }
        transport.delegate = self
    }

    // MARK: Lifecycle

    /// Scan for local changes (the first scan credits pre-sync data to its bootstrap slots), queue
    /// everything still owed to the server, and start watching saves.
    func start() {
        // Singleton rows need their canonical ids before the first scan names their records.
        SyncCanonicalizer.runIfNeeded(in: context)
        if tracker.documents.contains(where: { $0.spec.kind == Self.heartbeatKind }) {
            DeviceSyncDocument.current = { [weak self] in self?.heartbeat() }
        }
        pushLocalChanges()
        requeueOwed()
        // Nothing is open at launch: deletes deferred for a screen the app was killed on apply now.
        applyDeferredDeletes()
        retryHeldGenerations()
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
        requeueOwed()
        isSyncing = true
        defer { isSyncing = false; refreshCounts() }
        do {
            try await transport.syncNow()
            lastSyncedAt = .now
            lastError = nil
            await checkDrift()
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
        forgetServerCopies()
        transport.resetFetchState()
        requeueOwed()
        refreshCounts()
    }

    /// The store half of `forgetServer`, safe to run inside a transport event.
    func forgetServerCopies() {
        serverCopiesVersion += 1
        _ = try? SyncWriter.write(context) {
            for state in SyncStoreMeta.allStates(in: context) {
                var copies = state.copies
                SyncRecordLogic.forgetServer(&copies)
                state.copies = copies
                state.serverStamp = nil
                state.lastSeenTag = nil
                // A pending delete stays owed: it goes to whichever server comes next.
                state.needsUpload = copies.pending != nil && !state.pendingDelete
            }
        }
    }

    /// Refetch the whole zone and re-send everything owed, outside the current transport event
    /// (CKSyncEngine mustn't be rebuilt from inside its own handler).
    func scheduleFullResync() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            transport.resetFetchState()
            requeueOwed()
            refreshCounts()
        }
    }

    /// Two settled devices that disagree: repair once, at most once a day. If they still disagree
    /// afterwards, the screen says so and offers Repair Sync.
    func checkDrift() async {
        let peers = peers().filter { !$0.isThisDevice }
        let differing = Set(peers.flatMap { disagreements(with: $0, lastLocalChangeAt: lastRecordChangeAt) })
        guard !differing.isEmpty else {
            disagreement = []
            return
        }
        let last = UserDefaults.standard.object(forKey: Self.autoRepairKey) as? Date ?? .distantPast
        if Date.now.timeIntervalSince(last) > 24 * 3600 {
            UserDefaults.standard.set(Date.now, forKey: Self.autoRepairKey)
            note("devices disagree on \(differing.sorted().joined(separator: ", ")): repairing")
            await repair()
        } else {
            disagreement = differing.sorted()
        }
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
                let learnerRecords = (outcome.saves + outcome.deletes).filter {
                    !Self.digestExcluded.contains(String($0.prefix { $0 != ":" }))
                }
                if !learnerRecords.isEmpty { lastRecordChangeAt = .now }
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

    /// Counts before a send starts, so the progress bar knows what's waiting.
    func refreshCountsForProgress() { refreshCounts() }

    private func refreshCounts() {
        let device = Self.heartbeatKind, meta = Self.metaKind
        pendingCount = count(#Predicate { $0.needsUpload || $0.pendingDelete })
        learnerPendingCount = count(#Predicate {
            ($0.needsUpload || $0.pendingDelete) && $0.kind != device && $0.kind != meta
        })
        stuckCount = count(#Predicate { $0.failureCount >= 5 })
    }

    private func count(_ predicate: Predicate<SyncRecordState>) -> Int {
        (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    func note(_ message: String) {
        log.info("\(message, privacy: .public)")
        events.insert("\(Date.now.formatted(date: .omitted, time: .standard))  \(message)", at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
    }
}

// MARK: - Transport events

extension SyncCoordinator: SyncTransportDelegate {
    func outgoing(_ name: String) -> SyncOutgoing? {
        guard let state = SyncStoreMeta.states(named: [name], in: context)[name],
              state.needsUpload, !state.pendingDelete, !state.isStuck,
              state.heldReason != "generation",  // never save over a newer build's record
              let pending = state.copies.pending
        else { return nil }
        let file = SyncRecordName(name).flatMap { recordName in
            SyncDocuments.byKind[recordName.kind]?.fileURL(for: recordName, payload: pending)
        }
        return SyncOutgoing(payload: pending, stamp: state.serverStamp, fileURL: file)
    }

    func transportDidSave(_ name: String, sent: SyncPayload, stamp: Data, tag: String) {
        serverCopiesVersion += 1
        var follow: (saves: [String], deletes: [String]) = ([], [])
        defer { transport.enqueue(saves: follow.saves, deletes: follow.deletes) }
        _ = try? SyncWriter.write(context) {
            guard let state = SyncStoreMeta.states(named: [name], in: context)[name], !state.pendingDelete else {
                // Deleted here while this save was in flight: the delete has to follow it.
                follow.deletes.append(name)
                return
            }
            var copies = state.copies
            SyncRecordLogic.didSave(&copies, sent: sent)
            state.copies = copies
            state.serverStamp = stamp
            state.lastSeenTag = tag
            state.needsUpload = copies.pending != nil
            state.failureCount = 0
            state.lastError = nil
            // Edited again while this save was in flight. The engine dropped the queued change
            // when the save succeeded, so queue the newer copy now.
            if state.needsUpload { follow.saves.append(name) }
        }
    }

    func transportConflict(_ name: String, server: SyncIncoming) {
        let records = interceptZoneFingerprint([server], fromConflict: true)
        guard !records.isEmpty else { return }
        do {
            let outcome = try applier.apply(records, deleted: [])
            if !outcome.changedKinds.isEmpty { didApplyRemoteChanges?(outcome.changedKinds) }
        } catch {
            note("conflict merge failed for \(name): \(error.localizedDescription)")
        }
    }

    func transportUnknownItem(_ name: String) {
        serverCopiesVersion += 1
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
        serverCopiesVersion += 1
        _ = try? SyncWriter.write(context) {
            if let state = SyncStoreMeta.states(named: [name], in: context)[name], state.pendingDelete {
                context.delete(state)
            }
        }
    }

    func transportFetched(_ records: [SyncIncoming], deleted: [String]) {
        guard !records.isEmpty || !deleted.isEmpty else { return }
        let records = interceptZoneFingerprint(records, fromConflict: false)
        serverCopiesVersion += 1
        do {
            let outcome = try applier.apply(records, deleted: deleted)
            if !outcome.changedKinds.subtracting(Self.digestExcluded).isEmpty { lastRecordChangeAt = .now }
            transport.enqueue(saves: outcome.uploads, deletes: [])
            if outcome.inserted + outcome.updated + outcome.deleted + outcome.held > 0 {
                note("fetched: +\(outcome.inserted) ~\(outcome.updated) −\(outcome.deleted) held \(outcome.held)")
            }
            if !outcome.changedKinds.isEmpty { didApplyRemoteChanges?(outcome.changedKinds) }
        } catch {
            // The engine's change token has already moved past these; fetch the zone again.
            note("applying fetched changes failed: \(error.localizedDescription); refetching")
            scheduleFullResync()
        }
    }

    func transportDidFinishFetch(wasFullFetch: Bool) {
        let metaName = Self.zoneRecordName
        let metaState = SyncStoreMeta.states(named: [metaName], in: context)[metaName]
        let confirmed = metaState?.serverStamp != nil || metaState?.serverPayload != nil
        if wasFullFetch, !sawZoneFingerprint, knownZoneInstance != nil, confirmed {
            // The whole zone came back without the fingerprint this device knows: a database that
            // never had this learner's data (a first Debug run on Development) or a new zone.
            note("full fetch found no zone fingerprint: new or different database, sending everything")
            forgetServerCopies()
            knownZoneInstance = nil
            requeueOwed()
        }
        sawZoneFingerprint = false
        hasCompletedFetch = true
        createZoneFingerprintIfNeeded()
    }

    /// Records held because an older build couldn't read them: this build may be the update.
    func retryHeldGenerations() {
        let reason = "generation"
        let held = (try? context.fetch(FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.heldReason == reason }))) ?? []
        let readable = held.compactMap { state -> SyncIncoming? in
            guard let data = state.heldPayload, let payload = try? SyncJSON(data: data).objectValue,
                  let name = SyncRecordName(state.recordName),
                  let spec = SyncRegistry.byKind[name.kind]?.spec ?? SyncDocuments.byKind[name.kind]?.spec,
                  spec.canRead(payload)
            else { return nil }
            return SyncIncoming(name: state.recordName, payload: payload, stamp: state.serverStamp ?? Data(), tag: "")
        }
        if !readable.isEmpty { transportFetched(readable, deleted: []) }
    }

    /// Deletes that arrived while their row was open on screen.
    func applyDeferredDeletes() {
        let reason = SyncApplier.deferredDelete
        let held = (try? context.fetch(FetchDescriptor<SyncRecordState>(
            predicate: #Predicate { $0.heldReason == reason }
        ))) ?? []
        guard !held.isEmpty else { return }
        let names = held.map(\.recordName)
        for state in held { state.heldReason = nil }
        transportFetched([], deleted: names)
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
