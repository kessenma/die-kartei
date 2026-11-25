import Foundation

/// An in-memory stand-in for one CloudKit zone, for tests and the DEBUG `-sync.debugVerify` round
/// trip. It keeps the CloudKit rules that matter for merging:
/// - A save must name the change tag it was based on. A stale tag is a conflict that hands back
///   the server copy (`serverRecordChanged`).
/// - Saving a record the server no longer has, with a tag, is `unknownItem`.
/// - Deletes skip conflict checks.
/// - Changes are fetched from a token, and each record appears at most once, at its latest state.
///
/// Not thread-safe; drive it from one actor.
nonisolated final class FakeSyncServer {
    struct Stored: Equatable {
        var payload: SyncPayload
        var tag: Int
    }

    enum SaveResult: Equatable {
        case saved(tag: Int)
        case conflict(server: SyncPayload, tag: Int)
        case unknownItem
    }

    struct Changes {
        var changed: [(name: String, stored: Stored)]
        var deleted: [String]
        var token: Int
    }

    private(set) var records: [String: Stored] = [:]
    private var feed: [(seq: Int, name: String)] = []
    private var seq = 0
    /// Bumped by `wipe()`, so a replica holding an old token can notice (the `Meta:zone` check).
    private(set) var zoneInstance = UUID()

    init() {}

    func save(_ name: String, payload: SyncPayload, basedOn tag: Int?) -> SaveResult {
        if let current = records[name] {
            if tag != current.tag { return .conflict(server: current.payload, tag: current.tag) }
        } else if tag != nil {
            return .unknownItem
        }
        seq += 1
        records[name] = Stored(payload: payload, tag: seq)
        feed.append((seq, name))
        return .saved(tag: seq)
    }

    func delete(_ name: String) {
        guard records[name] != nil else { return }
        records[name] = nil
        seq += 1
        feed.append((seq, name))
    }

    func changes(since token: Int) -> Changes {
        var latest: [String: Int] = [:]
        for entry in feed where entry.seq > token { latest[entry.name] = entry.seq }
        var changed: [(String, Stored)] = []
        var deleted: [String] = []
        for name in latest.keys.sorted() {
            if let stored = records[name] { changed.append((name, stored)) } else { deleted.append(name) }
        }
        return Changes(changed: changed, deleted: deleted, token: seq)
    }

    /// Delete the whole zone: Delete iCloud Data, or iOS Settings ▸ iCloud ▸ this app.
    func wipe() {
        records = [:]
        feed = []
        zoneInstance = UUID()
    }
}
