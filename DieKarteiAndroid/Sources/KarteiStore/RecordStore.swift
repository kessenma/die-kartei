import Foundation
import SkipSQLPlus
@testable import DieKarteiCore

/// The app's synced data, kept the way iOS sync keeps it, so any transport (and iPhone ↔
/// Android) is plumbing on top. See docs/android-parity/persistence.md.
///
/// - One `record` row per record name (`<Kind>:<UUID>`), with the same ids iOS derives
///   (`SyncSingletonDecks`, `SyncDayKey`, …).
/// - `payload` holds the flat record (`KarteiRecord.payload`), which is exactly the iOS codec's
///   `known` shape: `sync_golden.json` and the golden tests on both sides hold the two together.
/// - Every write goes through the shared `SyncRecordLogic.noteLocal` with this install's replica
///   slot, so counters (reviews, lapses, study time) are per device from the first write, and
///   the composed copy waits in `pending` for a transport. Nothing is credited to a bootstrap
///   slot later, and nothing needs migrating when sync arrives.
///
/// One connection, MainActor only, like `KarteiDatabase`.
final class RecordStore {
    let database: KarteiDatabase
    /// This install's counter slot (`ReplicaID`). Never shared between two live devices.
    let replica: String
    /// Bumped per kind after every committed write, so stores can tell their caches are stale.
    private(set) var revisions: [String: Int] = [:]

    private var db: SQLContext { database.context }
    private var inTransaction = false
    private var touched: Set<String> = []

    init(database: KarteiDatabase, replica: String) {
        self.database = database
        self.replica = replica
    }

    // MARK: Reading

    func record<R: KarteiRecord>(_ type: R.Type, id: UUID) -> R? {
        rows(R.self, where: "kind = ? AND id = ?", [.text(R.spec.kind), .text(id.uuidString)]).first
    }

    /// Every record of a kind, in its `sort` order.
    func records<R: KarteiRecord>(_ type: R.Type) -> [R] {
        rows(R.self, where: "kind = ?", [.text(R.spec.kind)], order: "sort, id")
    }

    /// The records hanging off a parent (a deck's cards), in `sort` order.
    func records<R: KarteiRecord>(_ type: R.Type, parent: UUID) -> [R] {
        rows(R.self, where: "kind = ? AND parent = ?", [.text(R.spec.kind), .text(parent.uuidString)], order: "sort, id")
    }

    func records<R: KarteiRecord>(_ type: R.Type, naturalKey: String) -> [R] {
        rows(R.self, where: "kind = ? AND natural_key = ?", [.text(R.spec.kind), .text(naturalKey)], order: "sort, id")
    }

    /// Records under `parent` due at or before `date`, oldest due first.
    func due<R: KarteiRecord>(_ type: R.Type, parent: UUID, asOf date: Date) -> [R] {
        rows(R.self, where: "kind = ? AND parent = ? AND due IS NOT NULL AND due <= ?",
             [.text(R.spec.kind), .text(parent.uuidString), .real(date.timeIntervalSinceReferenceDate)],
             order: "due, sort")
    }

    /// Records whose `day` key lies in `from...to` (`yyyy-MM-dd` sorts as text).
    func records<R: KarteiRecord>(_ type: R.Type, days from: String, _ to: String) -> [R] {
        rows(R.self, where: "kind = ? AND day >= ? AND day <= ?", [.text(R.spec.kind), .text(from), .text(to)], order: "day")
    }

    func count(kind: String, parent: UUID? = nil) -> Int {
        let sql = parent == nil
            ? "SELECT COUNT(*) FROM record WHERE kind = ?"
            : "SELECT COUNT(*) FROM record WHERE kind = ? AND parent = ?"
        let params: [SQLValue] = parent.map { [.text(kind), .text($0.uuidString)] } ?? [.text(kind)]
        guard case .long(let n)? = (try? db.selectAll(sql: sql, parameters: params))?.first?.first else { return 0 }
        return Int(n)
    }

    /// What sync knows about a record: the last server copy and the composed copy waiting to go up.
    func copies(of name: SyncRecordName) -> SyncRecordCopies? {
        let rows = (try? db.selectAll(sql: "SELECT server, pending FROM record WHERE kind = ? AND id = ?",
                                      parameters: [.text(name.kind), .text(name.id.uuidString)])) ?? []
        guard let row = rows.first else { return nil }
        return SyncRecordCopies(server: Self.payload(row[0]), pending: Self.payload(row[1]))
    }

    /// Record names with a pending copy for a transport to send.
    func pendingUploads() -> [SyncRecordName] {
        let rows = (try? db.selectAll(sql: "SELECT kind, id FROM record WHERE needs_upload = 1 ORDER BY kind, id")) ?? []
        return rows.compactMap(Self.name)
    }

    func tombstones() -> [SyncRecordName] {
        let rows = (try? db.selectAll(sql: "SELECT kind, id FROM tombstone ORDER BY kind, id")) ?? []
        return rows.compactMap(Self.name)
    }

    // MARK: Writing

    /// Save a record: compose it on its last copy (unknown fields and other devices' counter
    /// slots survive), credit counter changes to this replica, and update the indexes.
    func put<R: KarteiRecord>(_ record: R, now: Date = Date()) throws {
        try transaction { try write(record, now: now) }
    }

    func put<R: KarteiRecord>(_ records: [R], now: Date = Date()) throws {
        try transaction { for r in records { try write(r, now: now) } }
    }

    /// Delete a record and everything hanging off it (a deck's cards and results). Records the
    /// server already has leave a tombstone for the transport to send.
    func delete(kind: String, id: UUID, now: Date = Date()) throws {
        try transaction { try remove(kind: kind, id: id, now: now) }
    }

    func delete<R: KarteiRecord>(_ record: R, now: Date = Date()) throws {
        try delete(kind: record.name.kind, id: record.name.id, now: now)
    }

    /// A transport sent a record's pending copy and the server accepted exactly that.
    func didSend(_ name: SyncRecordName, sent: SyncPayload) throws {
        guard var copies = copies(of: name) else { return }
        SyncRecordLogic.didSave(&copies, sent: sent)
        try db.exec(sql: "UPDATE record SET server = ?, pending = ?, needs_upload = ? WHERE kind = ? AND id = ?",
                    parameters: [Self.blob(copies.server), Self.blob(copies.pending), .long(copies.pending == nil ? 0 : 1),
                                 .text(name.kind), .text(name.id.uuidString)])
    }

    /// Run several writes as one transaction; revisions bump once, after the commit.
    func transaction(_ block: () throws -> Void) throws {
        if inTransaction { try block(); return }
        inTransaction = true
        defer { inTransaction = false }
        do {
            try db.transaction(.immediate) { try block() }
        } catch {
            touched = []
            throw error
        }
        for kind in touched { revisions[kind, default: 0] += 1 }
        touched = []
    }

    // MARK: Internals

    private func write<R: KarteiRecord>(_ record: R, now: Date) throws {
        let name = record.name
        var copies = copies(of: name) ?? SyncRecordCopies()
        let known = record.payload
        SyncRecordLogic.noteLocal(&copies, known: known, spec: R.spec, slot: replica,
                                  now: now.timeIntervalSinceReferenceDate)
        let index = record.index
        try db.exec(sql: """
            INSERT INTO record (kind, id, payload, parent, natural_key, day, due, sort, updated_at, server, pending, needs_upload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(kind, id) DO UPDATE SET
              payload = excluded.payload, parent = excluded.parent, natural_key = excluded.natural_key,
              day = excluded.day, due = excluded.due, sort = excluded.sort, updated_at = excluded.updated_at,
              server = excluded.server, pending = excluded.pending, needs_upload = excluded.needs_upload
            """, parameters: [
                .text(name.kind), .text(name.id.uuidString), .blob(known.syncCanonicalData),
                Self.text(index.parent?.uuidString), Self.text(index.naturalKey), Self.text(index.day),
                Self.real(index.due), Self.real(index.sort), .real(now.timeIntervalSinceReferenceDate),
                Self.blob(copies.server), Self.blob(copies.pending), .long(copies.pending == nil ? 0 : 1),
            ])
        // The same record name can't move to another id; drop a tombstone if it comes back.
        try db.exec(sql: "DELETE FROM tombstone WHERE kind = ? AND id = ?", parameters: [.text(name.kind), .text(name.id.uuidString)])
        touched.insert(name.kind)
    }

    private func remove(kind: String, id: UUID, now: Date) throws {
        let children = try db.selectAll(sql: "SELECT kind, id FROM record WHERE parent = ?", parameters: [.text(id.uuidString)])
        for child in children.compactMap(Self.name) {
            try remove(kind: child.kind, id: child.id, now: now)
        }
        let rows = try db.selectAll(sql: "SELECT server FROM record WHERE kind = ? AND id = ?",
                                    parameters: [.text(kind), .text(id.uuidString)])
        guard let row = rows.first else { return }
        if let server = Self.payload(row[0]) {
            try db.exec(sql: """
                INSERT INTO tombstone (kind, id, deleted_at, server) VALUES (?, ?, ?, ?)
                ON CONFLICT(kind, id) DO UPDATE SET deleted_at = excluded.deleted_at, server = excluded.server
                """, parameters: [.text(kind), .text(id.uuidString), .real(now.timeIntervalSinceReferenceDate),
                                  .blob(server.syncCanonicalData)])
        }
        try db.exec(sql: "DELETE FROM record WHERE kind = ? AND id = ?", parameters: [.text(kind), .text(id.uuidString)])
        touched.insert(kind)
    }

    private func rows<R: KarteiRecord>(_ type: R.Type, where clause: String, _ params: [SQLValue], order: String? = nil) -> [R] {
        var sql = "SELECT payload FROM record WHERE " + clause
        if let order { sql += " ORDER BY " + order }
        let rows = (try? db.selectAll(sql: sql, parameters: params)) ?? []
        return rows.compactMap { row in Self.payload(row[0]).map(R.init(payload:)) }
    }

    private static func payload(_ value: SQLValue) -> SyncPayload? {
        guard case .blob(let data) = value else { return nil }
        return (try? SyncJSON(data: data))?.objectValue
    }

    private static func name(_ row: [SQLValue]) -> SyncRecordName? {
        guard row.count >= 2, case .text(let kind) = row[0], case .text(let id) = row[1],
              let uuid = UUID(uuidString: id) else { return nil }
        return SyncRecordName(kind: kind, id: uuid)
    }

    private static func text(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }
    private static func real(_ d: Double?) -> SQLValue { d.map { .real($0) } ?? .null }
    private static func blob(_ p: SyncPayload?) -> SQLValue { p.map { .blob($0.syncCanonicalData) } ?? .null }
}

/// This install's counter slot for sync: a random id, made once and kept in a file **outside**
/// the database and outside Android Auto Backup (`no_backup/`), so a phone restored from a backup
/// gets a new slot. Two live devices sharing a slot would undercount reviews when they merge
/// (counters merge by per-slot max). iOS keeps its slot in the Keychain for the same reason.
enum ReplicaID {
    static let fileName = "sync-replica-id"

    /// `no_backup/` next to the app's `files/` on Android (excluded from Auto Backup by
    /// definition); Application Support elsewhere.
    static var defaultDirectory: URL {
        let support = KarteiDatabase.defaultURL.deletingLastPathComponent()
        #if os(Android)
        return support.deletingLastPathComponent().appendingPathComponent("no_backup")
        #else
        return support
        #endif
    }

    static func load(directory: URL = defaultDirectory) throws -> String {
        let url = directory.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url), let id = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), UUID(uuidString: id) != nil {
            return id
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try Data(id.utf8).write(to: url, options: .atomic)
        return id
    }
}
