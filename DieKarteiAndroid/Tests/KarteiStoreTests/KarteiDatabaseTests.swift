import Foundation
import Testing
@testable import KarteiStore

@MainActor
@Suite("KarteiDatabase")
struct KarteiDatabaseTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kartei-\(UUID().uuidString)")
            .appendingPathComponent("kartei.sqlite")
    }

    @Test("Opens on SkipSQLPlus' own SQLite, in WAL mode, at the latest schema")
    func opens() throws {
        let db = try KarteiDatabase(url: tempURL())
        #expect(db.sqliteVersion.hasPrefix("3."))
        #expect(db.sqliteVersion == SQLiteC.libraryVersion)
        #expect(db.journalMode == "wal")
        #expect(db.schemaVersion == Int64(KarteiDatabase.migrations.count))
        try db.close()
    }

    @Test("Meta values survive closing and reopening; migrating twice changes nothing")
    func persists() throws {
        let url = tempURL()
        var db = try KarteiDatabase(url: url)
        try db.setMeta("store.id", "abc")
        try db.setMeta("store.id", "def")          // upsert
        try db.setMeta("gone", "x")
        try db.setMeta("gone", nil)
        try db.close()

        db = try KarteiDatabase(url: url)
        #expect(try db.meta("store.id") == "def")
        #expect(try db.meta("gone") == nil)
        #expect(db.schemaVersion == Int64(KarteiDatabase.migrations.count))
        db.checkpoint()
        try db.close()
    }
}
