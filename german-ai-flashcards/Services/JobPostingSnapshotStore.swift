import Foundation

/// Where a chat's saved copy of its job posting lives on disk:
/// `Application Support/JobPostings/<UUID>.pdf`. Application Support rather than Caches: postings
/// go offline, and the copy is the only version left to practise against.
nonisolated enum JobPostingSnapshotStore {
    private static var root: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("JobPostings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL {
        root.appendingPathComponent(fileName)
    }

    /// The copy exists on disk (a chat can name a file that a failed write never produced).
    static func exists(_ fileName: String?) -> Bool {
        guard let fileName, !fileName.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    /// Write a PDF under a fresh name and return that name, or nil if the write failed.
    static func save(_ data: Data) -> String? {
        let fileName = UUID().uuidString + ".pdf"
        do {
            try data.write(to: url(for: fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    /// A second chat for the same posting gets its own copy, so deleting either chat leaves the
    /// other's file alone.
    static func duplicate(_ fileName: String?) -> String? {
        guard let fileName, exists(fileName) else { return nil }
        let copy = UUID().uuidString + ".pdf"
        do {
            try FileManager.default.copyItem(at: url(for: fileName), to: url(for: copy))
            return copy
        } catch {
            return nil
        }
    }

    /// Best effort, called when the chat that owns the copy is deleted.
    static func delete(_ fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
