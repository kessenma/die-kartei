import Foundation

/// Repo-level HuggingFace hub-cache lookups, shared by the MLX language models and the
/// Stable Diffusion image model. One source of truth for the cache layout that
/// `ResumableModelDownloader` writes and `loadContainer` / `StableDiffusionPipeline` read.
nonisolated enum HubCacheLocation {
    /// The HuggingFace Hub cache root directory.
    static var hubCacheDirectory: URL {
        // Matches CacheLocationProvider logic: sandboxed apps use Library/Caches,
        // non-sandboxed macOS uses ~/.cache
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        return URL.cachesDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
        #else
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            return URL.cachesDirectory
                .appendingPathComponent("huggingface")
                .appendingPathComponent("hub")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
        #endif
    }

    /// The repo directory name for a repo ID (e.g. "models--Qwen--Qwen3-0.6B-4bit").
    static func repoDirectoryName(_ repoID: String) -> String {
        "models--" + repoID.replacingOccurrences(of: "/", with: "--")
    }

    static func repoDirectory(repoID: String) -> URL {
        hubCacheDirectory.appendingPathComponent(repoDirectoryName(repoID))
    }

    /// Whether a complete snapshot exists. `ResumableModelDownloader` publishes refs/main
    /// only after every file is stored, so this flips true atomically at the end.
    static func isDownloaded(repoID: String) -> Bool {
        let refsFile = repoDirectory(repoID: repoID)
            .appendingPathComponent("refs")
            .appendingPathComponent("main")
        return FileManager.default.fileExists(atPath: refsFile.path)
    }

    /// Disk size of the cached repo in bytes, or nil if nothing is on disk.
    static func cachedSizeBytes(repoID: String) -> Int64? {
        let repoDir = repoDirectory(repoID: repoID)
        guard FileManager.default.fileExists(atPath: repoDir.path) else { return nil }
        return directorySize(repoDir)
    }

    /// The snapshot directory for the commit refs/main points at, or nil if incomplete.
    static func snapshotDirectory(repoID: String) -> URL? {
        let repoDir = repoDirectory(repoID: repoID)
        let refsFile = repoDir.appendingPathComponent("refs").appendingPathComponent("main")
        guard let commit = try? String(contentsOf: refsFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !commit.isEmpty
        else { return nil }
        let snapshot = repoDir.appendingPathComponent("snapshots").appendingPathComponent(commit)
        guard FileManager.default.fileExists(atPath: snapshot.path) else { return nil }
        return snapshot
    }

    /// Delete the cached repo along with any partially downloaded files a resumable
    /// download left behind.
    static func delete(repoID: String) throws {
        try? FileManager.default.removeItem(
            at: ResumableModelDownloader.partialsDirectory(forRepo: repoID)
        )
        let repoDir = repoDirectory(repoID: repoID)
        guard FileManager.default.fileExists(atPath: repoDir.path) else { return }
        try FileManager.default.removeItem(at: repoDir)
    }

    /// Recursively compute the size of a directory.
    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
