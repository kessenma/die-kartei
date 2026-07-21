import Foundation
import HuggingFace

// MARK: - Resumable Model Downloader

/// Downloads a HuggingFace model repo through iOS background URLSession tasks, then hands the
/// files to `HubCache.default` — the exact cache that `loadContainer`'s stock downloader reads —
/// so the follow-up `loadContainer` call finds everything locally and never re-downloads.
///
/// Why this exists: the stock path (`#hubDownloader()` → `HubClient.downloadSnapshot`) only
/// persists *fully completed* files. Whatever file is mid-flight when the network drops, the
/// user cancels, or iOS suspends the app is discarded along with URLSession's temp file and
/// restarts from byte 0 — and for these models that file is a multi-GB weight shard. This
/// downloader instead keeps completed file chunks in a `.partial` on disk and continues from
/// that offset with an HTTP `Range` request on the next attempt. The active transfer itself is
/// owned by a background URLSession, so iOS can keep moving bytes after the user leaves the app.
/// It also reports true byte-level progress, replacing the old heuristic of polling
/// `CFNetworkDownload_*.tmp` growth.
///
/// Partials are keyed by the file's etag (for LFS weight files that's the SHA-256 of the
/// content): if the repo changes upstream between attempts, the stale partial is discarded
/// rather than risking a mixed-content file. The whole download is pinned to the commit hash
/// resolved on the first request, so one snapshot never mixes two revisions.
actor ResumableModelDownloader {
    /// Mirrors mlx-swift-lm's `modelDownloadPatterns` — weights plus config/tokenizer files.
    nonisolated static let modelFilePatterns = ["*.safetensors", "*.json", "*.jinja"]

    /// Flush-to-disk granularity for the streaming loop.
    nonisolated fileprivate static let writeChunkSize = 256 * 1024

    /// Attempts per file before giving up (each retry resumes from the bytes already on disk).
    nonisolated private static let maxAttemptsPerFile = 8

    private let session: URLSession
    private let backgroundSession = BackgroundModelDownloadSession.shared
    private let hub = HubClient()
    private let cache = HubCache.default

    init() {
        let config = URLSessionConfiguration.default
        // Brief connectivity gaps: wait for the network to come back instead of failing.
        config.waitsForConnectivity = true
        // Fail a stalled transfer after 60s of silence so the retry loop can re-issue a
        // ranged request from the bytes already persisted.
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    /// Where in-flight partial files live for a repo (e.g. "mlx-community/Foo-4bit").
    /// Deleted by `MLXModel.deleteFromCache()` alongside the model itself.
    nonisolated static func partialsDirectory(forRepo repoID: String) -> URL {
        URL.cachesDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("downloads")
            .appendingPathComponent("models--" + repoID.replacingOccurrences(of: "/", with: "--"))
    }

    /// Download every repo file matching `patterns` into the shared HuggingFace cache.
    ///
    /// Safe to call again after any failure or cancellation: files already in the cache are
    /// skipped, and a partially-transferred file resumes from its `.partial` on disk.
    /// `refs/main` is only written once every file is stored, so `MLXModel.isDownloaded`
    /// stays false until the snapshot is actually complete.
    ///
    /// - Parameter onProgress: called on the main actor with (bytesDownloaded, totalBytes).
    func download(
        repoID: String,
        revision: String = "main",
        matching patterns: [String] = ResumableModelDownloader.modelFilePatterns,
        onProgress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) async throws {
        guard let repo = Repo.ID(rawValue: repoID) else {
            throw ModelDownloadError.invalidRepo(repoID)
        }

        // Plan: the tree API reports true byte sizes (including LFS), giving an exact total.
        // Small files first so config/tokenizer land before the multi-GB weight shards.
        let entries = try await hub.listFiles(in: repo, revision: revision)
            .filter { $0.type == .file && Self.matchesAny(patterns: patterns, path: $0.path) }
            .sorted { ($0.size ?? 0) < ($1.size ?? 0) }
        guard !entries.isEmpty else {
            throw ModelDownloadError.invalidRepo(repoID)
        }

        let totalBytes = entries.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }
        var completedBytes: [String: Int64] = [:]
        var lastEmit = Date.distantPast

        func emit(_ path: String, _ bytes: Int64, force: Bool = false) async {
            completedBytes[path] = bytes
            let now = Date()
            guard force || now.timeIntervalSince(lastEmit) >= 0.15 else { return }
            lastEmit = now
            let done = completedBytes.values.reduce(0, +)
            await onProgress(min(done, totalBytes), totalBytes)
        }

        // Start the bar where a previous attempt left off, not at zero. Partial sizes are
        // optimistic (etag validation happens per file below); `min` above keeps them sane.
        for entry in entries {
            let existing = Self.existingPartialSize(
                repoID: repoID,
                path: entry.path,
                expectedSize: entry.size.map(Int64.init)
            )
            if existing > 0 { completedBytes[entry.path] = existing }
        }
        await emit(entries[0].path, completedBytes[entries[0].path] ?? 0, force: true)

        // Pin the whole download to one commit so files can't mix revisions if the repo
        // updates mid-download. refs/main is pointed at this commit at the very end.
        let pin = try await remoteMetadata(repo: repo, revision: revision, path: entries[0].path)

        for entry in entries {
            try Task.checkCancellation()
            let meta = entry.path == entries[0].path
                ? pin
                : try await remoteMetadata(repo: repo, revision: pin.commitHash, path: entry.path)
            let expectedSize: Int64? = (entry.size.map(Int64.init) ?? meta.size).flatMap { $0 > 0 ? $0 : nil }

            // Already in the cache (content-addressed by etag)? Re-link it into this commit's
            // snapshot — storeFile skips the blob copy when the blob exists.
            if let blob = cache.cachedBlobPath(repo: repo, kind: .model, etag: meta.etag) {
                let blobSize = (try? blob.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                if expectedSize == nil || blobSize == expectedSize {
                    try await cache.storeFile(
                        at: blob, repo: repo, kind: .model,
                        revision: pin.commitHash, filename: entry.path, etag: meta.etag
                    )
                    await emit(entry.path, expectedSize ?? 0, force: true)
                    continue
                }
                try? FileManager.default.removeItem(at: blob)
            }

            // Transfer with retries; every retry resumes from the bytes already on disk.
            var attempt = 0
            while true {
                try Task.checkCancellation()
                do {
                    try await fetchFile(
                        repo: repo, repoID: repoID, revision: pin.commitHash,
                        path: entry.path, etag: meta.etag, expectedSize: expectedSize,
                        downloadURL: meta.downloadURL
                    ) { fileBytes in
                        await emit(entry.path, fileBytes)
                    }
                    break
                } catch let error where Self.isRetryable(error) {
                    attempt += 1
                    guard attempt < Self.maxAttemptsPerFile else { throw error }
                    try await Task.sleep(for: .seconds(min(pow(2.0, Double(attempt)), 15.0)))
                }
            }

            let partial = partialURL(repoID: repoID, path: entry.path, etag: meta.etag)
            try await cache.storeFile(
                at: partial, repo: repo, kind: .model,
                revision: pin.commitHash, filename: entry.path, etag: meta.etag
            )
            try? FileManager.default.removeItem(at: partial)
            await emit(entry.path, expectedSize ?? 0, force: true)
        }

        // Everything stored — publish the ref so cache lookups (and the app's isDownloaded
        // check, which looks for refs/main) see a complete snapshot.
        try cache.updateRef(repo: repo, kind: .model, ref: revision, commit: pin.commitHash)
        await onProgress(totalBytes, totalBytes)
    }

    // MARK: - Single-file transfer

    /// Download one file into its `.partial`, resuming from the current partial size.
    /// The URLSession task may continue while the app is backgrounded; once it finishes, the
    /// downloaded temp file is appended to the partial and committed into the Hub cache.
    private func fetchFile(
        repo: Repo.ID,
        repoID: String,
        revision: String,
        path: String,
        etag: String,
        expectedSize: Int64?,
        downloadURL: URL?,
        onFileProgress: @escaping (Int64) async -> Void
    ) async throws {
        let partial = partialURL(repoID: repoID, path: path, etag: etag)
        try FileManager.default.createDirectory(
            at: partial.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        Self.removeStalePartials(repoID: repoID, path: path, keepingEtag: etag)

        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        var offset = Int64(try handle.seekToEnd())

        if let expectedSize {
            // A previous attempt may have finished the transfer but died before storeFile.
            if offset == expectedSize { return }
            // Larger than the file should be — corrupt; start over.
            if offset > expectedSize {
                try handle.truncate(atOffset: 0)
                offset = 0
            }
            // The background URLSession path only appends a completed task segment. A tiny
            // partial for a large file is usually a stale redirect/error body from an older
            // broken attempt, not meaningful model data.
            if expectedSize > Self.writeChunkSize && offset > 0 && offset < Self.writeChunkSize {
                try handle.truncate(atOffset: 0)
                offset = 0
            }
        }

        var request = URLRequest(url: downloadURL ?? Self.resolveURL(repo: repo, revision: revision, path: path))
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        try handle.close()

        try await backgroundSession.download(
            request,
            appendingTo: partial,
            initialBytes: offset,
            expectedSize: expectedSize,
            filePath: path
        ) { transferred in
            await onFileProgress(transferred)
        }

        let written = (try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        // A cleanly-closed-but-short body (dropped connection the OS didn't flag, proxy hiccup)
        // is not done — signal a retry, which resumes from the bytes just persisted.
        if let expectedSize, written != expectedSize {
            throw ModelDownloadError.incompleteTransfer(file: path)
        }
    }

    /// HEAD the resolve endpoint without following the CDN redirect: the etag, size, and
    /// commit-hash headers for LFS files live on the first response, not the CDN's.
    private func remoteMetadata(
        repo: Repo.ID, revision: String, path: String
    ) async throws -> RemoteFileMetadata {
        var request = URLRequest(url: Self.resolveURL(repo: repo, revision: revision, path: path))
        request.httpMethod = "HEAD"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (_, response) = try await session.data(for: request, delegate: NoRedirectDelegate())
        guard let http = response as? HTTPURLResponse else {
            throw ModelDownloadError.missingMetadata(file: path)
        }
        guard http.statusCode == 200 || (300..<400).contains(http.statusCode) else {
            throw ModelDownloadError.httpStatus(http.statusCode, file: path)
        }
        guard
            let rawEtag = http.value(forHTTPHeaderField: "X-Linked-Etag")
                ?? http.value(forHTTPHeaderField: "Etag"),
            let commit = http.value(forHTTPHeaderField: "X-Repo-Commit")
        else {
            throw ModelDownloadError.missingMetadata(file: path)
        }
        let linkedSize = http.value(forHTTPHeaderField: "X-Linked-Size")
        let contentLength = http.statusCode == 200 ? http.value(forHTTPHeaderField: "Content-Length") : nil
        let size = (linkedSize ?? contentLength).flatMap { Int64($0) }
        let location = http.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: request.url) }
        return RemoteFileMetadata(
            etag: cache.normalizeEtag(rawEtag),
            size: size,
            commitHash: commit,
            downloadURL: location?.absoluteURL
        )
    }

    // MARK: - Paths & helpers

    nonisolated private func partialURL(repoID: String, path: String, etag: String) -> URL {
        Self.partialsDirectory(forRepo: repoID)
            .appendingPathComponent(path + ".\(etag).partial")
    }

    nonisolated private static func resolveURL(repo: Repo.ID, revision: String, path: String) -> URL {
        URL(string: "https://huggingface.co")!
            .appending(path: repo.namespace)
            .appending(path: repo.name)
            .appending(path: "resolve")
            .appending(component: revision)
            .appending(path: path)
    }

    /// Delete partials for this file written against a different etag (the repo updated
    /// upstream since they were started) — resuming into them would corrupt the file.
    nonisolated private static func removeStalePartials(repoID: String, path: String, keepingEtag etag: String) {
        let filename = (path as NSString).lastPathComponent
        let keep = "\(filename).\(etag).partial"
        let dir = partialsDirectory(forRepo: repoID)
            .appendingPathComponent((path as NSString).deletingLastPathComponent)
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for item in items
        where item.lastPathComponent.hasPrefix("\(filename).")
            && item.lastPathComponent.hasSuffix(".partial")
            && item.lastPathComponent != keep
        {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Size of any existing partial for this file (largest across etags), for the initial
    /// progress baseline before per-file etag validation happens.
    nonisolated private static func existingPartialSize(repoID: String, path: String, expectedSize: Int64?) -> Int64 {
        let filename = (path as NSString).lastPathComponent
        let dir = partialsDirectory(forRepo: repoID)
            .appendingPathComponent((path as NSString).deletingLastPathComponent)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return items
            .filter { $0.lastPathComponent.hasPrefix("\(filename).") && $0.lastPathComponent.hasSuffix(".partial") }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .map(Int64.init)
            .filter { size in
                guard let expectedSize, expectedSize > writeChunkSize else { return true }
                return size >= writeChunkSize
            }
            .max() ?? 0
    }

    nonisolated private static func matchesAny(patterns: [String], path: String) -> Bool {
        patterns.contains { pattern in
            fnmatch(pattern, path, 0) == 0
                || fnmatch(pattern, (path as NSString).lastPathComponent, 0) == 0
        }
    }

    /// Network-flavored failures are retried (each retry resumes from disk); everything else —
    /// cancellation, HTTP client errors, filesystem errors — propagates immediately.
    nonisolated private static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        if case ModelDownloadError.incompleteTransfer = error { return true }
        return false
    }
}

// MARK: - Background URLSession bridge

/// Owns the app-wide background URLSession used for large Hugging Face model files. iOS may
/// wake the app later to deliver these delegate callbacks, so this object is a process singleton
/// and is also referenced from the app delegate's background-session hook.
final class BackgroundModelDownloadSession: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    static let shared = BackgroundModelDownloadSession()

    private struct Transfer {
        let destination: URL
        let initialBytes: Int64
        let expectedSize: Int64?
        let filePath: String
        let progress: @Sendable (Int64) async -> Void
        let continuation: CheckedContinuation<Void, Error>
        var temporaryFile: URL?
        var completionError: Error?
    }

    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    private let temporaryDirectory = URL.cachesDirectory
        .appendingPathComponent("huggingface")
        .appendingPathComponent("downloads")
        .appendingPathComponent("background-tasks")

    private lazy var session: URLSession = {
        let bundleID = Bundle.main.bundleIdentifier ?? "de.germanflashcards"
        let config = URLSessionConfiguration.background(withIdentifier: "\(bundleID).model-downloads")
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        lock.lock()
        backgroundCompletionHandler = completionHandler
        lock.unlock()
        _ = session
    }

    func download(
        _ request: URLRequest,
        appendingTo destination: URL,
        initialBytes: Int64,
        expectedSize: Int64?,
        filePath: String,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        final class TaskBox: @unchecked Sendable {
            var task: URLSessionDownloadTask?
        }
        let box = TaskBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request)
                box.task = task
                let transfer = Transfer(
                    destination: destination,
                    initialBytes: initialBytes,
                    expectedSize: expectedSize,
                    filePath: filePath,
                    progress: progress,
                    continuation: continuation
                )
                lock.lock()
                transfers[task.taskIdentifier] = transfer
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let transfer = transfer(for: downloadTask.taskIdentifier) else { return }
        Task {
            await transfer.progress(transfer.initialBytes + totalBytesWritten)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskTemporaryFile = temporaryDirectory
            .appendingPathComponent("\(downloadTask.taskIdentifier).download")
        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory, withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: taskTemporaryFile)
            try FileManager.default.moveItem(at: location, to: taskTemporaryFile)
        } catch {
            lock.lock()
            if var transfer = transfers[downloadTask.taskIdentifier] {
                transfer.completionError = error
                transfers[downloadTask.taskIdentifier] = transfer
            }
            lock.unlock()
            return
        }

        lock.lock()
        if var transfer = transfers[downloadTask.taskIdentifier] {
            transfer.temporaryFile = taskTemporaryFile
            transfers[downloadTask.taskIdentifier] = transfer
        }
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let transfer = removeTransfer(for: task.taskIdentifier) else { return }
        if let error {
            transfer.continuation.resume(throwing: error)
            return
        }
        if let error = transfer.completionError {
            transfer.continuation.resume(throwing: error)
            return
        }
        guard let http = task.response as? HTTPURLResponse, let temporaryFile = transfer.temporaryFile else {
            transfer.continuation.resume(throwing: ModelDownloadError.incompleteTransfer(file: transfer.filePath))
            return
        }

        do {
            try finish(transfer: transfer, response: http, temporaryFile: temporaryFile)
            transfer.continuation.resume()
        } catch {
            transfer.continuation.resume(throwing: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        lock.unlock()

        DispatchQueue.main.async {
            handler?()
        }
    }

    private func finish(transfer: Transfer, response http: HTTPURLResponse, temporaryFile: URL) throws {
        switch http.statusCode {
        case 200:
            // Full body — either no Range was sent or the server ignored it.
            if transfer.initialBytes > 0 {
                let handle = try FileHandle(forWritingTo: transfer.destination)
                try handle.truncate(atOffset: 0)
                try handle.close()
            }
        case 206:
            guard http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(transfer.initialBytes)-") == true else {
                let handle = try FileHandle(forWritingTo: transfer.destination)
                try handle.truncate(atOffset: 0)
                try handle.close()
                throw ModelDownloadError.incompleteTransfer(file: transfer.filePath)
            }
        case 416:
            let handle = try FileHandle(forWritingTo: transfer.destination)
            try handle.truncate(atOffset: 0)
            try handle.close()
            throw ModelDownloadError.incompleteTransfer(file: transfer.filePath)
        default:
            throw ModelDownloadError.httpStatus(http.statusCode, file: transfer.filePath)
        }

        if let expectedSize = transfer.expectedSize,
           let contentLength = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
        {
            let expectedRemaining = max(expectedSize - transfer.initialBytes, 0)
            guard contentLength == expectedRemaining else {
                try truncate(transfer.destination, to: transfer.initialBytes)
                throw ModelDownloadError.incompleteTransfer(file: transfer.filePath)
            }
        }

        let readHandle = try FileHandle(forReadingFrom: temporaryFile)
        defer { try? readHandle.close() }
        let writeHandle = try FileHandle(forWritingTo: transfer.destination)
        defer { try? writeHandle.close() }
        try writeHandle.seekToEnd()

        while true {
            let shouldContinue = try autoreleasepool {
                let data = try readHandle.read(upToCount: ResumableModelDownloader.writeChunkSize)
                guard let data, !data.isEmpty else { return false }
                try writeHandle.write(contentsOf: data)
                return true
            }
            if !shouldContinue { break }
        }
        try? FileManager.default.removeItem(at: temporaryFile)

        if let expectedSize = transfer.expectedSize {
            let finalSize = Int64(try writeHandle.seekToEnd())
            guard finalSize == expectedSize else {
                try truncate(transfer.destination, to: transfer.initialBytes)
                throw ModelDownloadError.incompleteTransfer(file: transfer.filePath)
            }
        }
    }

    private func truncate(_ file: URL, to offset: Int64) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(max(offset, 0)))
    }

    private func transfer(for taskIdentifier: Int) -> Transfer? {
        lock.lock()
        defer { lock.unlock() }
        return transfers[taskIdentifier]
    }

    private func removeTransfer(for taskIdentifier: Int) -> Transfer? {
        lock.lock()
        defer { lock.unlock() }
        return transfers.removeValue(forKey: taskIdentifier)
    }
}

// MARK: - Supporting types

nonisolated private struct RemoteFileMetadata: Sendable {
    let etag: String
    let size: Int64?
    let commitHash: String
    let downloadURL: URL?
}

/// Blocks the resolve→CDN redirect so metadata headers can be read off the first response.
/// (Completion-handler variant: the async override crashes the Swift 6.2 compiler's thunk
/// emission under default MainActor isolation.)
nonisolated private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

nonisolated enum ModelDownloadError: LocalizedError {
    case invalidRepo(String)
    case httpStatus(Int, file: String)
    case missingMetadata(file: String)
    /// Transfer ended before the full file arrived; retried internally with a Range resume.
    case incompleteTransfer(file: String)

    var errorDescription: String? {
        switch self {
        case .invalidRepo(let id):
            "Invalid model repository: \(id)"
        case .httpStatus(let code, let file):
            "Server returned HTTP \(code) for \(file)"
        case .missingMetadata(let file):
            "Missing file metadata for \(file)"
        case .incompleteTransfer(let file):
            "Connection lost while downloading \(file)"
        }
    }
}
