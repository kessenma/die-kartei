import Foundation
import SkipSQLPlus

/// The app's one SQLite database: `files/kartei.sqlite` on Android (Application Support maps to
/// the app's private `files/`). SQLite comes from SkipSQLPlus, so every phone runs the same
/// build (JSON1, FTS5, SQLCipher) instead of whatever the OS ships.
///
/// One connection, MainActor only: SkipSQL does no locking of its own.
/// See docs/android-parity/persistence.md for the record schema that lands on top of this.
public final class KarteiDatabase {
    public let url: URL
    let context: SQLContext

    /// Schema steps, in order; `PRAGMA user_version` counts how many have run.
    /// Never edit a step that has shipped: append a new one.
    static let migrations: [(SQLContext) throws -> Void] = [
        // 1: store-wide key/value (store id, migration flags, schema notes).
        { db in
            try db.exec(sql: "CREATE TABLE meta (key TEXT PRIMARY KEY, value BLOB) WITHOUT ROWID")
        },
    ]

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        context = try SQLContext(path: url.path, flags: [.create, .readWrite],
                                 configuration: .plus)
        // WAL keeps readers off the writer; checkpoint() folds it back before a backup.
        _ = try context.selectAll(sql: "PRAGMA journal_mode=WAL")
        try context.exec(sql: "PRAGMA foreign_keys=ON")
        try context.migrate(migrations: Self.migrations)
    }

    /// `<Application Support>/kartei.sqlite`.
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("kartei.sqlite")
    }

    public var sqliteVersion: String { context.version }
    public var schemaVersion: Int64 { context.userVersion }
    public var journalMode: String {
        (try? context.selectAll(sql: "PRAGMA journal_mode").first?.first).flatMap { value -> String? in
            if case .text(let s) = value { return s }
            return nil
        } ?? "?"
    }

    // MARK: meta

    public func meta(_ key: String) throws -> String? {
        let rows = try context.selectAll(sql: "SELECT value FROM meta WHERE key = ?",
                                         parameters: [.text(key)])
        guard let value = rows.first?.first else { return nil }
        switch value {
        case .text(let s): return s
        case .blob(let d): return String(data: d, encoding: .utf8)
        case .long(let n): return String(n)
        default: return nil
        }
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        if let value {
            try context.exec(sql: "INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                             parameters: [.text(key), .text(value)])
        } else {
            try context.exec(sql: "DELETE FROM meta WHERE key = ?", parameters: [.text(key)])
        }
    }

    /// Fold the WAL into the main file (on backgrounding), so a backup never sees half of it.
    public func checkpoint() {
        _ = try? context.selectAll(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
    }

    public func close() throws {
        try context.close()
    }
}
