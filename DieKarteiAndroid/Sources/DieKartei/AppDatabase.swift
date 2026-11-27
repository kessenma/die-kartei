import Foundation
import SkipFuse
import KarteiStore

/// The app's database, opened once at launch. `nil` only if opening failed (logged); screens
/// that need it keep working on the bundle data until the stores move onto it.
@MainActor
enum AppDatabase {
    private(set) static var shared: KarteiDatabase?

    static func open() {
        guard shared == nil else { return }
        do {
            let db = try KarteiDatabase(url: KarteiDatabase.defaultURL)
            let launches = (Int(try db.meta("debug.launches") ?? "") ?? 0) + 1
            try db.setMeta("debug.launches", String(launches))
            shared = db
            logger.info("KarteiStore: SQLite \(db.sqliteVersion) (C \(SQLiteC.libraryVersion)), schema \(db.schemaVersion), journal \(db.journalMode), launch \(launches), \(db.url.path)")
        } catch {
            logger.error("KarteiStore: could not open \(KarteiDatabase.defaultURL.path): \(error)")
        }
    }

    static func checkpoint() {
        shared?.checkpoint()
    }
}
