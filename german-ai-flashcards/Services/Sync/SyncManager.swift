import CloudKit
import CoreData
import Foundation
import SwiftData
import UIKit

/// App-level owner of iCloud Sync: the on/off setting, the iCloud account, and the coordinator +
/// CloudKit transport for the app's store. The iCloud Sync screen reads everything from here.
///
/// There's no sign-in: sync uses whatever Apple Account the device is signed into. Debug builds
/// talk to CloudKit's Development database and TestFlight/App Store builds to Production. Those
/// are two separate copies of the learner's data, and Debug builds start with sync off.
@MainActor
@Observable
final class SyncManager {
    static let shared = SyncManager()

    enum Account: Equatable {
        case unknown, available, noAccount, restricted, temporarilyUnavailable
    }

    private(set) var account: Account = .unknown
    private(set) var coordinator: SyncCoordinator?
    /// CKSyncEngine is fetching or sending right now.
    private(set) var engineBusy = false
    private(set) var storageFull = false
    /// A different Apple Account signed in: sync is paused until the learner chooses.
    /// Kept across launches: a relaunch must not quietly merge into the other account.
    private(set) var accountSwitchPending = UserDefaults.standard.bool(forKey: "sync.accountSwitchPending") {
        didSet { UserDefaults.standard.set(accountSwitchPending, forKey: "sync.accountSwitchPending") }
    }
    /// Why sync turned itself off, shown on the screen (iCloud data deleted elsewhere).
    private(set) var notice: String?

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var transport: CloudKitSyncTransport?
    @ObservationIgnored private var accountObserver: NSObjectProtocol?
    /// Runs after server changes land (reminders re-plan when another device studied today).
    @ObservationIgnored var onRemoteChanges: ((Set<String>) -> Void)?
    /// The model manager caches the level and a few records in memory; synced values are written
    /// through it so the UI sees them.
    @ObservationIgnored weak var modelManager: MLXModelManager?

    static let enabledKey = "sync.enabled"
    static let userRecordKey = "sync.userRecordID"

    static var environmentName: String {
        #if DEBUG || targetEnvironment(simulator)
        "Development"
        #else
        "Production"
        #endif
    }

    // MARK: Setting

    /// On by default in TestFlight/App Store builds, off in Debug builds (whose data lives in the
    /// separate Development database). `-sync.enable 1` / `-sync.disabled 1` override one launch.
    var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "sync.disabled") { return false }
        if defaults.bool(forKey: "sync.enable") { return true }
        #if DEBUG
        let fallback = false
        #else
        let fallback = true
        #endif
        return defaults.object(forKey: Self.enabledKey) as? Bool ?? fallback
    }

    /// Screenshot and Wortschatz seeding put invented progress in the store. That must never reach
    /// iCloud, where it would land on every device.
    var refusalReason: String? {
        if ScreenshotDataSeeder.seededAt != nil { return "This device holds screenshot seed data." }
        if WortschatzDebugSeeder.hasBackup { return "This device holds Wortschatz seed data." }
        return nil
    }

    var isRunning: Bool { coordinator != nil }

    /// What the seeders answer while sync runs: their invented progress would reach every device.
    static let seedRefusal = "iCloud Sync is on. Seeding would copy invented progress to every device. Turn sync off first."

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        notice = nil
        if on { startIfPossible() } else { stopSync() }
    }

    // MARK: Lifecycle

    /// Called once from `App.init`, straight after the container opens, so a silent push that
    /// launches the app in the background finds the engine running.
    func configure(container: ModelContainer) {
        self.container = container
        observeAccount()
        // Just after launch rather than inside App.init: the first scan of a large store takes a
        // moment, and it mustn't hold up the first frame. A silent-push launch still gets here
        // within the same wake.
        Task { @MainActor in
            startIfPossible()
            await refreshAccount()
        }
    }

    private func startIfPossible() {
        guard coordinator == nil, isEnabled, refusalReason == nil, !accountSwitchPending,
              let container else { return }
        let storeTag = Self.storeIdentifier(for: container) ?? "unknown"
        let identity = SyncIdentity(replica: SyncIdentity.replicaID(), store: storeTag)
        // The engine's saved state belongs to one store *and* one CloudKit database: a Debug build
        // (Development) must not reuse a TestFlight build's (Production) change tokens.
        let transport = CloudKitSyncTransport(storeTag: storeTag + "|" + Self.environmentName)
        transport.zoneWasSeen = { [weak self] in self?.coordinator?.knownZoneInstance != nil }
        let coordinator = SyncCoordinator(context: container.mainContext, identity: identity, transport: transport)
        transport.onAccountChange = { [weak self] change in self?.accountChanged(change) }
        transport.onZoneDeleted = { [weak self] reason in self?.zoneDeleted(reason) }
        transport.onQuotaExceeded = { [weak self] in self?.storageFull = true }
        transport.onActivity = { [weak self] busy in self?.engineBusy = busy }
        coordinator.didApplyRemoteChanges = { [weak self] kinds in self?.onRemoteChanges?(kinds) }
        self.transport = transport
        self.coordinator = coordinator
        transport.start()
        coordinator.start()
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func stopSync() {
        coordinator?.stop()
        transport?.stop()
        coordinator = nil
        transport = nil
    }

    /// Foreground: push anything saved while away, then fetch (pushes can be dropped or late).
    func appBecameActive() async {
        await refreshAccount()
        storageFull = false
        await coordinator?.syncNow()
    }

    /// Background: make sure the latest edits are queued before the app is suspended.
    func appWillResignActive() {
        try? container?.mainContext.save()
        coordinator?.pushLocalChanges()
    }

    func syncNow() async { await coordinator?.syncNow() }

    /// Wait (up to `timeout`) for the first completed fetch: onboarding on a new device waits for
    /// the learner's level to arrive before asking for it.
    func waitForFirstFetch(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if coordinator == nil || coordinator?.hasCompletedFetch == true { return }
            if account == .noAccount || account == .restricted { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func repair() async { await coordinator?.repair() }

    /// Delete this app's data from iCloud (every device's copy there). Local data stays; sync turns
    /// off here, and the other devices turn off when they see the zone go.
    func deleteICloudData() async throws {
        // Stop first, so nothing re-creates the zone or re-sends while it goes.
        let coordinator = self.coordinator
        stopSync()
        let database = CKContainer(identifier: CloudKitSyncTransport.containerID).privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [], deleting: [CloudKitSyncTransport.zoneID])
        coordinator?.forgetServerCopies()
        coordinator?.knownZoneInstance = nil
        CloudKitSyncTransport.discardSavedState()
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        notice = "iCloud data deleted. This device keeps its data; turn sync on to upload it again."
    }

    #if DEBUG
    /// `-sync.debugSeedSchema 1`: save one record that sets every `KarteiItem` field, so the
    /// Development schema has them all before it's deployed to Production. (`payloadAsset` and `file`
    /// only exist after a large payload or a picture has been saved, and Production rejects fields
    /// it doesn't know.)
    func seedDevelopmentSchema() async -> String {
        let database = CKContainer(identifier: CloudKitSyncTransport.containerID).privateCloudDatabase
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: CloudKitSyncTransport.zoneID)], deleting: [])
            let asset = FileManager.default.temporaryDirectory.appendingPathComponent("schema-seed.json")
            try Data("{}".utf8).write(to: asset)
            let record = CKRecord(recordType: CloudKitSyncTransport.recordType,
                                  recordID: CloudKitSyncTransport.recordID("Meta:schema-seed"))
            record["kind"] = "Meta" as CKRecordValue
            record["payload"] = Data("{}".utf8) as CKRecordValue
            record["payloadAsset"] = CKAsset(fileURL: asset)
            record["file"] = CKAsset(fileURL: asset)
            _ = try await database.modifyRecords(saving: [record], deleting: [])
            _ = try await database.modifyRecords(saving: [], deleting: [record.recordID])
            return "schema seeded: KarteiItem has kind, payload, payloadAsset, file. Deploy it in the CloudKit Console."
        } catch {
            return "schema seed failed: \(error.localizedDescription)"
        }
    }
    #endif

    // MARK: Account

    func refreshAccount() async {
        let status = try? await CKContainer(identifier: CloudKitSyncTransport.containerID).accountStatus()
        account = switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        default: .unknown
        }
    }

    private func observeAccount() {
        guard accountObserver == nil else { return }
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        let defaults = UserDefaults.standard
        switch change {
        case .signIn(let user):
            let previous = defaults.string(forKey: Self.userRecordKey)
            if let previous, previous != user.recordName {
                // Someone else's account: don't merge this device into it without asking.
                accountSwitchPending = true
                stopSync()
                return
            }
            defaults.set(user.recordName, forKey: Self.userRecordKey)
            // A fresh engine state has no pending list; everything owed goes back in.
            coordinator?.requeueOwed()
        case .signOut:
            // Keep local data: it's the learner's primary copy. The engine idles until sign-in.
            break
        case .switchAccounts:
            accountSwitchPending = true
            stopSync()
        @unknown default:
            break
        }
    }

    /// The learner's answer to "a different Apple Account is signed in".
    func resolveAccountSwitch(mergeIntoNewAccount: Bool) {
        accountSwitchPending = false
        UserDefaults.standard.removeObject(forKey: Self.userRecordKey)
        guard mergeIntoNewAccount else {
            setEnabled(false)
            return
        }
        startIfPossible()
        coordinator?.forgetServer()
    }

    private func zoneDeleted(_ reason: CKDatabase.DatabaseChange.Deletion.Reason) {
        // The next zone gets a new fingerprint.
        coordinator?.knownZoneInstance = nil
        switch reason {
        case .encryptedDataReset:
            // iCloud reset its end-to-end keys: upload everything again.
            coordinator?.forgetServer()
        default:
            // Deleted from another device or from iOS Settings: stop here, keep local data, and
            // upload again only if the learner turns sync back on.
            coordinator?.forgetServer()
            setEnabled(false)
            notice = "Your iCloud data for Die Kartei was deleted. This device kept its data."
        }
    }

    // MARK: Store

    /// The store file's UUID: the bootstrap slot for counters that predate sync. A restored backup
    /// of the same store carries the same UUID.
    static func storeIdentifier(for container: ModelContainer) -> String? {
        guard let url = container.configurations.first?.url,
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        else { return nil }
        return metadata[NSStoreUUIDKey] as? String
    }
}
