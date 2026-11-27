import Foundation
import SkipFuse
@testable import KarteiStore

/// The app's database, opened once at launch. `nil` only if opening failed (logged); screens
/// that need it keep working on the bundle data, without saving.
@MainActor
enum AppDatabase {
    private(set) static var shared: KarteiDatabase?
    /// The synced records (Wortschatz cards so far), written the way iOS sync writes them.
    private(set) static var records: RecordStore?

    static func open() {
        guard shared == nil else { return }
        do {
            let db = try KarteiDatabase(url: KarteiDatabase.defaultURL)
            let launches = (Int(try db.meta("debug.launches") ?? "") ?? 0) + 1
            try db.setMeta("debug.launches", String(launches))
            shared = db
            // The counter slot lives outside the database and outside Auto Backup (no_backup/).
            let replica = try ReplicaID.load()
            records = RecordStore(database: db, replica: replica)
            logger.info("KarteiStore: SQLite \(db.sqliteVersion) (C \(SQLiteC.libraryVersion)), schema \(db.schemaVersion), journal \(db.journalMode), launch \(launches), replica \(replica.prefix(8)), \(db.url.path)")
        } catch {
            logger.error("KarteiStore: could not open \(KarteiDatabase.defaultURL.path): \(error)")
        }
    }

    static func checkpoint() {
        shared?.checkpoint()
    }
}
