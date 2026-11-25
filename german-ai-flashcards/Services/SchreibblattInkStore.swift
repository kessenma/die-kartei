import Foundation

/// Where a writing sheet's handwriting lives on disk: `Application Support/Schreibblatt/<UUID>.drawing`,
/// a `PKDrawing.dataRepresentation()`. Application Support rather than Caches, for
/// `ClassMaterialStore`'s reason: this is the only copy of what the learner wrote.
///
/// On disk rather than a `Data` on the model, which is the obvious alternative. A pencil-filled
/// two-page drawing runs to megabytes, and SwiftData keeps an inline `Data` in the SQLite row —
/// so an autosave would rewrite that row every few seconds, bloating the WAL and the persistent
/// history that `SyncChangeTracker` pages through on every pass, and a `@Query` over sheets would
/// fault the whole blob in just to draw a list row (docs/MEMORY.md). `SchreibblattSheet.strokeCount`
/// is on the row instead, so a list never opens a file.
///
/// Unlike a handout, ink is re-saved continuously: `save` mints a name once and `overwrite` keeps
/// it, so one sheet owns one file for its lifetime rather than littering a new UUID per autosave.
nonisolated enum SchreibblattInkStore {
    static let fileExtension = "drawing"

    private static var root: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Schreibblatt")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL {
        root.appendingPathComponent(fileName)
    }

    /// The ink exists on disk (a sheet can name a file that a failed write never produced).
    static func exists(_ fileName: String?) -> Bool {
        guard let fileName, !fileName.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    /// Write the ink under a fresh name and return that name, or nil if the write failed. Called
    /// once per sheet, the first time anything is written on it; after that, `overwrite`.
    static func save(_ data: Data) -> String? {
        let fileName = UUID().uuidString + "." + fileExtension
        return overwrite(data, as: fileName) ? fileName : nil
    }

    /// Replace a sheet's ink in place, keeping its file name. True when the bytes landed.
    @discardableResult
    static func overwrite(_ data: Data, as fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        do {
            try data.write(to: url(for: fileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The ink, or nil when the sheet has none or the file went missing.
    static func read(_ fileName: String?) -> Data? {
        guard let fileName, exists(fileName) else { return nil }
        return try? Data(contentsOf: url(for: fileName))
    }

    /// Best effort, called before the sheet that owns the file is deleted.
    static func delete(_ fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Ink files no sheet names any more. A sheet deleted while the app was not running, or a
    /// failed cascade, would otherwise leave megabytes behind with nothing pointing at them.
    static func orphans(keeping named: Set<String>) -> [String] {
        let listed = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return listed.filter { $0.hasSuffix("." + fileExtension) && !named.contains($0) }
    }
}
