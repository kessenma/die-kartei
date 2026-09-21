import Foundation

/// Where a class handout's original lives on disk: `Application Support/ClassNotes/<UUID>.pdf` or
/// `.jpg`. Application Support rather than Caches: the handout is the only copy the learner has
/// once the paper one is gone.
nonisolated enum ClassMaterialStore {
    private static var root: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("ClassNotes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL {
        root.appendingPathComponent(fileName)
    }

    /// The original exists on disk (a material can name a file that a failed write never produced).
    static func exists(_ fileName: String?) -> Bool {
        guard let fileName, !fileName.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    /// Write the original under a fresh name and return that name, or nil if the write failed.
    /// `ext` is `pdf` or `jpg`.
    static func save(_ data: Data, ext: String) -> String? {
        let fileName = UUID().uuidString + "." + ext
        do {
            try data.write(to: url(for: fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    /// Best effort, called before the material that owns the file is deleted.
    static func delete(_ fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
