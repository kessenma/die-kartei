import CryptoKit
import Foundation
import SwiftData
import UIKit

// How a device notices it drifted from the others, or that it's talking to a different database,
// and puts itself right. Every remedy here comes down to a re-sync, which is always safe: merges
// are idempotent and counters are per-device (docs/ICLOUD_SYNC.md).

// MARK: - Heartbeats

/// Each device publishes one small `Device` record: what it is, which app version, when it last
/// synced, and a digest per kind of record of what it believes the server holds. The iCloud Sync
/// screen lists them ("Your devices"). Two settled devices with different digests means one
/// drifted, and a repair runs.
struct DeviceSyncDocument: SyncDocumentKind {
    /// Supplied by the running coordinator.
    @MainActor static var current: (() -> (name: SyncRecordName, known: SyncPayload)?)?

    let spec = SyncKindSpec(kind: "Device")

    func localRecords() -> [(name: SyncRecordName, known: SyncPayload)] {
        Self.current?().map { [$0] } ?? []
    }

    /// Other devices' heartbeats stay in their sync state, where the screen reads them.
    func apply(_ flat: SyncPayload, name: SyncRecordName) {}
}

/// One device's heartbeat, as the screen shows it.
struct SyncPeer: Identifiable, Equatable {
    let id: String
    let model: String
    let appVersion: String
    let lastSyncAt: Date?
    let writtenAt: Date?
    let hasPending: Bool
    let stuck: Int
    let digests: [String: SyncDigest]
    let isThisDevice: Bool
}

extension SyncCoordinator {
    static let heartbeatKind = "Device"
    static let metaKind = "Meta"
    /// Kinds left out of digests: the heartbeats themselves (a digest that covered them would change
    /// every time one was written) and the zone fingerprint.
    static let digestExcluded: Set<String> = [heartbeatKind, metaKind]

    var heartbeatName: SyncRecordName {
        SyncRecordName(kind: Self.heartbeatKind, id: UUID(uuidString: identity.replica) ?? SyncNameUUID.make(identity.replica))
    }

    /// What this device believes the server holds, per kind. Hashes the stored server copies
    /// directly (they're canonical bytes), so thousands of records cost milliseconds.
    func digests() -> [String: SyncDigest] {
        if let cached = digestCache, cached.version == serverCopiesVersion { return cached.value }
        var byKind: [String: [(name: String, payloadHash: String)]] = [:]
        for state in SyncStoreMeta.allStates(in: context) where !Self.digestExcluded.contains(state.kind) {
            guard let data = state.serverPayload else { continue }
            let hash = Data(SHA256.hash(data: data)).base64EncodedString()
            byKind[state.kind, default: []].append((state.recordName, hash))
        }
        let value = byKind.mapValues { SyncDigest(entries: $0) }
        digestCache = (serverCopiesVersion, value)
        return value
    }

    /// This device's heartbeat. Unchanged facts return the previous payload as it was, so a
    /// heartbeat only goes up when something it reports actually changed.
    func heartbeat() -> (name: SyncRecordName, known: SyncPayload)? {
        let hasPending = learnerPendingCount > 0
        let digestJSON: [String: SyncJSON] = digests().mapValues {
            .object(["count": .int(Int64($0.count)), "hash": .string($0.hash)])
        }
        // Coarse on purpose: a timestamp that changed on every pass would upload every pass.
        let bucket = lastSyncedAt.map { floor($0.timeIntervalSinceReferenceDate / 900) * 900 }
        let info = Bundle.main.infoDictionary
        var f = SyncFields()
        f.set("replica", identity.replica)
        f.set("model", UIDevice.current.model)
        f.set("appVersion", "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
        f.set("environment", SyncManager.environmentName)
        f.set("lastSyncAt", bucket)
        f.set("hasPending", hasPending)
        f.set("stuck", stuckCount)
        f.set("digests", json: .object(digestJSON))

        let name = heartbeatName
        let previous = SyncStoreMeta.states(named: [name.description], in: context)[name.description]?.copies.base
        if let previous, SyncMerge.flatten(previous, spec: DeviceSyncDocument().spec).filter({ $0.key != "writtenAt" && $0.value != .null })
            == f.payload.filter({ $0.value != .null }) {
            return (name, SyncMerge.flatten(previous, spec: DeviceSyncDocument().spec))
        }
        f.set("writtenAt", Date.now)
        return (name, f.payload)
    }

    /// Every device's heartbeat, this one first.
    func peers() -> [SyncPeer] {
        let kind = Self.heartbeatKind
        return ((try? context.fetch(FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.kind == kind }))) ?? [])
            .compactMap { state -> SyncPeer? in
                guard let payload = state.copies.base else { return nil }
                let flat = SyncMerge.flatten(payload, spec: DeviceSyncDocument().spec)
                var digests: [String: SyncDigest] = [:]
                for (kind, value) in flat["digests"]?.objectValue ?? [:] {
                    guard let count = value["count"]?.int64Value, let hash = value["hash"]?.stringValue else { continue }
                    var d = SyncDigest(entries: [])
                    d.count = Int(count)
                    d.hash = hash
                    digests[kind] = d
                }
                return SyncPeer(
                    id: flat.string("replica") ?? state.recordName,
                    model: flat.string("model") ?? "Device",
                    appVersion: flat.string("appVersion") ?? "?",
                    lastSyncAt: flat.date("lastSyncAt"),
                    writtenAt: flat.date("writtenAt"),
                    hasPending: flat.bool("hasPending") ?? false,
                    stuck: flat.int("stuck") ?? 0,
                    digests: digests,
                    isThisDevice: flat.string("replica") == identity.replica
                )
            }
            .sorted { ($0.isThisDevice ? 0 : 1, $0.model) < ($1.isThisDevice ? 0 : 1, $1.model) }
    }

    /// Kinds where another settled device disagrees with this one. Empty when in step, or when
    /// either side is still busy (then a difference is just changes in flight).
    func disagreements(with peer: SyncPeer, lastLocalChangeAt: Date?) -> [String] {
        guard !peer.isThisDevice, !peer.hasPending, learnerPendingCount == 0,
              let written = peer.writtenAt,
              written > (lastLocalChangeAt ?? .distantPast).addingTimeInterval(60)
        else { return [] }
        let mine = digests()
        let kinds = Set(mine.keys).union(peer.digests.keys)
        return kinds.filter { mine[$0] != peer.digests[$0] }.sorted()
    }
}

// MARK: - Zone fingerprint

/// A `Meta` record holding a random id for the zone. Every device remembers the id it last saw.
/// A different one means this device is now talking to a different database: a Debug build (the
/// Development database) after a TestFlight build (Production), a zone that was deleted and made
/// again, or another account. The device then forgets its server copies and re-syncs; counters keep
/// their per-device slots, so nothing doubles.
extension SyncCoordinator {
    static var zoneRecordName: String { SyncRecordName(kind: metaKind, id: SyncNameUUID.make("zone")).description }

    /// The server has this zone's fingerprint: it was saved there, or fetched from there. Only
    /// then does a missing zone mean "deleted". A fingerprint made locally before the zone ever
    /// existed on the server (a first fetch that found nothing) proves nothing.
    var zoneConfirmed: Bool {
        let name = Self.zoneRecordName
        let state = SyncStoreMeta.states(named: [name], in: context)[name]
        return knownZoneInstance != nil && (state?.serverStamp != nil || state?.serverPayload != nil)
    }

    var knownZoneInstance: String? {
        get { UserDefaults.standard.string(forKey: zoneInstanceKey) }
        set { UserDefaults.standard.set(newValue, forKey: zoneInstanceKey) }
    }

    /// Pull the fingerprint out of a batch before it's applied. Returns the rest of the batch.
    /// `fromConflict`: the server already had one when this device tried to create its own, the
    /// same zone raced by two devices, so the server's simply wins.
    func interceptZoneFingerprint(_ records: [SyncIncoming], fromConflict: Bool) -> [SyncIncoming] {
        guard let meta = records.first(where: { $0.name == Self.zoneRecordName }),
              let remote = meta.payload["instance"]?.stringValue
        else { return records }
        sawZoneFingerprint = true
        // A fingerprint this device made but the server never confirmed was only a race with
        // another device's first sync: adopt theirs. A confirmed one that differs means another
        // database.
        let metaState = SyncStoreMeta.states(named: [meta.name], in: context)[meta.name]
        let confirmed = metaState?.serverStamp != nil || metaState?.serverPayload != nil
        if let known = knownZoneInstance, known != remote, !fromConflict, confirmed {
            note("different iCloud database (zone \(remote.prefix(8)) ≠ \(known.prefix(8))): re-syncing")
            forgetServerCopies()
            scheduleFullResync()
        }
        knownZoneInstance = remote
        _ = try? SyncWriter.write(context) {
            let state = SyncStoreMeta.states(named: [meta.name], in: context)[meta.name] ?? {
                let s = SyncRecordState(recordName: meta.name, kind: Self.metaKind)
                context.insert(s)
                return s
            }()
            state.copies = SyncRecordCopies(server: meta.payload, pending: nil)
            state.serverStamp = meta.stamp
            state.lastSeenTag = meta.tag
            state.needsUpload = false
        }
        return records.filter { $0.name != Self.zoneRecordName }
    }

    /// After a fetch found no fingerprint, this device creates one for the zone.
    func createZoneFingerprintIfNeeded() {
        guard knownZoneInstance == nil else { return }
        let instance = UUID().uuidString
        knownZoneInstance = instance
        let name = Self.zoneRecordName
        _ = try? SyncWriter.write(context) {
            let state = SyncStoreMeta.states(named: [name], in: context)[name] ?? {
                let s = SyncRecordState(recordName: name, kind: Self.metaKind)
                context.insert(s)
                return s
            }()
            state.copies = SyncRecordCopies(server: nil, pending: [
                "instance": .string(instance), SyncPayloadKey.generation: .int(1),
            ])
            state.needsUpload = true
        }
        transport.enqueue(saves: [name], deletes: [])
    }
}
