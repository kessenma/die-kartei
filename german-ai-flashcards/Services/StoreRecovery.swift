import Foundation
import OSLog

/// What happens when the SwiftData store can't be opened.
///
/// It used to be deleted outright. It's now *moved aside* into `Recovered/` with its SQLite side
/// files, so a failed migration never destroys the only copy of someone's progress. With iCloud
/// Sync on, the fresh store then refills from iCloud; either way the old file can still be rescued.
///
/// The side files are `<store>-wal` and `<store>-shm`. The old fallback built `<store>.wal` and
/// `<store>.shm` with `appendingPathExtension`, which never matched, so it left the real ones behind
/// next to a new, empty store.
enum StoreRecovery {
    private static let log = Logger(subsystem: "kyle-essenmacher.german-ai-flashcards", category: "store")

    /// Keep this many moved-aside stores; older ones are removed to bound disk use.
    static let keepCount = 2

    /// Move the store and its side files out of the way. Returns the folder they went to.
    @discardableResult
    static func moveAside(storeURL: URL, reason: Error, now: Date = .now) -> URL? {
        let fm = FileManager.default
        let recovered = storeURL.deletingLastPathComponent().appendingPathComponent("Recovered", isDirectory: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let folder = recovered.appendingPathComponent("\(storeURL.lastPathComponent).broken-\(stamp)", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in [storeURL] + sideFiles(of: storeURL) where fm.fileExists(atPath: url.path) {
                try fm.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            }
            log.error("Store failed to open (\(reason.localizedDescription, privacy: .public)); moved aside to \(folder.lastPathComponent, privacy: .public)")
            prune(recovered)
            return folder
        } catch {
            // Moving failed (disk full?). Deleting is the only way the app can still launch.
            log.fault("Couldn't move the store aside (\(error.localizedDescription, privacy: .public)); deleting it")
            for url in [storeURL] + sideFiles(of: storeURL) { try? fm.removeItem(at: url) }
            return nil
        }
    }

    /// SQLite's write-ahead log and shared-memory index.
    static func sideFiles(of storeURL: URL) -> [URL] {
        let dir = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        return [dir.appendingPathComponent(name + "-wal"), dir.appendingPathComponent(name + "-shm")]
    }

    private static func prune(_ recovered: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: recovered, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let sorted = entries.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }
        for old in sorted.dropFirst(keepCount) { try? fm.removeItem(at: old) }
    }
}
