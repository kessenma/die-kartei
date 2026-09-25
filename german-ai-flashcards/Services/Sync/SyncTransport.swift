import Foundation

/// Moves records between this device and a server. `CloudKitSyncTransport` wraps CKSyncEngine;
/// `FakeSyncTransport` wraps `FakeSyncServer` for the DEBUG round trip. The coordinator above it
/// doesn't know which one it has.
@MainActor
protocol SyncTransport: AnyObject {
    var delegate: (any SyncTransportDelegate)? { get set }
    /// Queue records for upload or deletion. The transport asks the delegate for the payload when
    /// it actually sends, so a record edited again in between goes up once, current.
    func enqueue(saves: [String], deletes: [String])
    /// Send everything queued, then fetch.
    func syncNow() async throws
    /// Forget the server change token, so the next fetch returns the whole zone (Repair Sync).
    func resetFetchState()
}

/// What goes up for one record.
struct SyncOutgoing {
    var payload: SyncPayload
    /// The last server copy's system fields, so CloudKit can tell a stale save.
    var stamp: Data?
    /// A picture or handout that travels with the record as an asset.
    var fileURL: URL?
}

@MainActor
protocol SyncTransportDelegate: AnyObject {
    /// What to send for a queued record, or nil if nothing is pending.
    func outgoing(_ name: String) -> SyncOutgoing?
    func transportDidSave(_ name: String, sent: SyncPayload, stamp: Data, tag: String)
    /// The save was based on a stale copy; `server` is the current one.
    func transportConflict(_ name: String, server: SyncIncoming)
    /// The server no longer has the record the save was based on.
    func transportUnknownItem(_ name: String)
    func transportDidDelete(_ name: String)
    func transportFetched(_ records: [SyncIncoming], deleted: [String])
    /// A save failed for a reason that isn't a conflict or transient (too large, invalid).
    func transportFailed(_ name: String, error: String)
}

/// The in-memory transport: `FakeSyncServer` with CloudKit's conflict rules. For
/// `-sync.debugVerify` and for exercising the coordinator without iCloud.
@MainActor
final class FakeSyncTransport: SyncTransport {
    weak var delegate: (any SyncTransportDelegate)?
    let server: FakeSyncServer
    private var saves: [String] = []
    private var deletes: [String] = []
    private var token = 0

    init(server: FakeSyncServer) {
        self.server = server
    }

    func enqueue(saves: [String], deletes: [String]) {
        for s in saves where !self.saves.contains(s) { self.saves.append(s) }
        for d in deletes where !self.deletes.contains(d) { self.deletes.append(d) }
    }

    func resetFetchState() { token = 0 }

    func syncNow() async throws {
        guard let delegate else { return }
        let queue = saves
        saves = []
        for name in queue {
            for _ in 0..<5 {
                guard let out = delegate.outgoing(name) else { break }
                let payload = out.payload
                let tag = out.stamp.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
                switch server.save(name, payload: payload, basedOn: tag) {
                case .saved(let newTag):
                    delegate.transportDidSave(name, sent: payload, stamp: Data(String(newTag).utf8), tag: String(newTag))
                case let .conflict(serverPayload, serverTag):
                    delegate.transportConflict(name, server: SyncIncoming(
                        name: name, payload: serverPayload,
                        stamp: Data(String(serverTag).utf8), tag: String(serverTag)))
                    continue
                case .unknownItem:
                    delegate.transportUnknownItem(name)
                    continue
                }
                break
            }
        }
        let doomed = deletes
        deletes = []
        for name in doomed {
            server.delete(name)
            delegate.transportDidDelete(name)
        }
        let changes = server.changes(since: token)
        token = changes.token
        let incoming = changes.changed.map {
            SyncIncoming(name: $0.name, payload: $0.stored.payload,
                         stamp: Data(String($0.stored.tag).utf8), tag: String($0.stored.tag))
        }
        delegate.transportFetched(incoming, deleted: changes.deleted)
    }
}
