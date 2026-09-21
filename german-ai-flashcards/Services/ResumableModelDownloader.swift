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
///
/// All of this survives the *process* dying mid-download, not just the network dropping:
/// `BackgroundModelDownloadSession` records every task on disk before starting it, settles
/// tasks that finished while the app was gone into their partials when its callbacks replay
/// on the next launch, keeps a failed or cancelled task's segment via URLSession resume data,
/// and re-adopts a task that is *still running* from a previous launch instead of starting a
/// duplicate. iOS killing the app at 4 GB of 5 costs nothing but the reconnection.
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

    /// The root every repo's partials live under. Separate from the hub cache, so anything
    /// sweeping for abandoned downloads (``OrphanedModelCache``) has to look in both places.
    nonisolated static var partialsRootDirectory: URL {
        URL.cachesDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("downloads")
    }

    /// Where in-flight partial files live for a repo (e.g. "mlx-community/Foo-4bit").
    /// Deleted by `MLXModel.deleteFromCache()` alongside the model itself.
    nonisolated static func partialsDirectory(forRepo repoID: String) -> URL {
        partialsRootDirectory
            .appendingPathComponent(HubCacheLocation.repoDirectoryName(repoID))
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

        // A failed or cancelled earlier task may have left resume data covering bytes it
        // transferred beyond the partial. Hand it back to URLSession — consumed once; a
        // failed resume writes a fresh blob — as long as the partial still ends exactly
        // where that task began.
        var resumeData: Data?
        let blobURL = BackgroundModelDownloadSession.resumeBlobURL(forPartial: partial)
        if let blobData = try? Data(contentsOf: blobURL) {
            try? FileManager.default.removeItem(at: blobURL)
            if let blob = try? JSONDecoder().decode(BackgroundModelDownloadSession.ResumeBlob.self, from: blobData),
               blob.initialBytes == offset {
                resumeData = blob.data
            }
        }

        try await backgroundSession.download(
            request,
            resumeData: resumeData,
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

    /// Delete partials (and their saved resume data) for this file written against a different
    /// etag (the repo updated upstream since they were started) — resuming into them would
    /// corrupt the file.
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
            && (item.lastPathComponent.hasSuffix(".partial") || item.lastPathComponent.hasSuffix(".partial.resume"))
            && item.lastPathComponent != keep
            && item.lastPathComponent != keep + ".resume"
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
///
/// Every task is recorded on disk (`transfers.json`) before it starts, so a transfer that
/// outlives the process can still be settled when the session is recreated on the next launch:
/// a task that finished while the app was gone has its bytes appended to the right `.partial`,
/// a task that failed (or was force-quit) leaves its resume data beside the partial for the
/// next attempt, and a task still in flight is re-adopted by the next `download` call for the
/// same file instead of a duplicate being started.
nonisolated final class BackgroundModelDownloadSession: NSObject, URLSessionDownloadDelegate,
    URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BackgroundModelDownloadSession()

    /// What a task is writing and where, as recorded on disk before the task starts —
    /// everything needed to settle the transfer without the in-memory `Transfer`, i.e. after
    /// the process that started it is gone.
    struct TransferSpec: Codable {
        /// The `.partial` path relative to the caches directory (the app container's absolute
        /// path can change between launches).
        let destinationRelativePath: String
        let initialBytes: Int64
        let expectedSize: Int64?
        let filePath: String
        /// Task was created from URLSession resume data. Its response describes the segment
        /// URLSession internally resumed, not our original request, so the strict header
        /// checks don't apply — the final-size check in `append` is the integrity gate.
        let fromResumeData: Bool

        init(destination: URL, initialBytes: Int64, expectedSize: Int64?, filePath: String, fromResumeData: Bool) {
            let root = URL.cachesDirectory.path + "/"
            let path = destination.path
            self.destinationRelativePath = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
            self.initialBytes = initialBytes
            self.expectedSize = expectedSize
            self.filePath = filePath
            self.fromResumeData = fromResumeData
        }

        var destination: URL {
            destinationRelativePath.hasPrefix("/")
                ? URL(fileURLWithPath: destinationRelativePath)
                : URL.cachesDirectory.appendingPathComponent(destinationRelativePath)
        }
    }

    /// Saved when a task fails or is cancelled, so the next attempt hands the segment already
    /// sitting in URLSession's own temp file back instead of re-fetching from `initialBytes`.
    struct ResumeBlob: Codable {
        /// The partial's size when the failed task started — the blob is only valid while the
        /// partial still ends exactly there.
        let initialBytes: Int64
        let data: Data
    }

    private struct Transfer {
        let spec: TransferSpec
        let progress: @Sendable (Int64) async -> Void
        let continuation: CheckedContinuation<Void, Error>
        var temporaryFile: URL?
        var completionError: Error?
    }

    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    /// On-disk mirror of which task writes where, keyed by task identifier; guarded by `lock`.
    private var specs: [String: TransferSpec] = [:]
    private var specsLoaded = false
    private var backgroundCompletionHandler: (() -> Void)?
    private let temporaryDirectory = URL.cachesDirectory
        .appendingPathComponent("huggingface")
        .appendingPathComponent("downloads")
        .appendingPathComponent("background-tasks")

    /// Guards `_session` only — `download()` creates tasks while holding `lock`, so session
    /// creation needs its own lock to stay deadlock-free.
    private let sessionLock = NSLock()
    private var _session: URLSession?
    /// The background session, created on first use (eagerly at `activate()`). Recreating a
    /// session with the same identifier reconnects to tasks a previous process left behind
    /// and replays their undelivered callbacks.
    private var session: URLSession {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let _session { return _session }
        let bundleID = Bundle.main.bundleIdentifier ?? "de.germanflashcards"
        let config = URLSessionConfiguration.background(withIdentifier: "\(bundleID).model-downloads")
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7 * 24 * 60 * 60
        let created = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        _session = created
        return created
    }

    private override init() {
        super.init()
    }

    /// Where a failed task's resume data waits, next to the partial it belongs to.
    static func resumeBlobURL(forPartial partial: URL) -> URL {
        URL(fileURLWithPath: partial.path + ".resume")
    }

    /// Recreate the background session at launch so callbacks from transfers that finished or
    /// failed while the app was gone are delivered — and settled into their partials — right
    /// away, not only once a download screen happens to start something. A beat later, sweep
    /// whatever those callbacks no longer cover: a crash can strand a task's payload with no
    /// callback left to claim it.
    func activate() {
        _ = session
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.session.getAllTasks { tasks in
                self.sweep(liveTaskIDs: Set(tasks.map(\.taskIdentifier)))
            }
        }
    }

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        lock.lock()
        backgroundCompletionHandler = completionHandler
        lock.unlock()
        _ = session
    }

    func download(
        _ request: URLRequest,
        resumeData: Data? = nil,
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
        // Snapshot before taking the lock (the property is async): tasks that survived a
        // relaunch and are still moving bytes.
        let (_, _, existingTasks) = await session.tasks

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                loadSpecsLocked()

                // A task from a previous launch may still be transferring this very segment —
                // adopt it, since a second task on the same partial would double-append. A
                // recorded task on the same file that no longer matches (the etag or offset
                // moved on) gets cancelled instead: its output is useless against the current
                // partial, and left running it would corrupt the resume bookkeeping.
                for task in existingTasks {
                    guard let spec = specs[String(task.taskIdentifier)],
                          spec.filePath == filePath,
                          transfers[task.taskIdentifier] == nil
                    else { continue }
                    if spec.destination.path == destination.path,
                       spec.initialBytes == initialBytes,
                       task.state == .running || task.state == .suspended {
                        var transfer = Transfer(
                            spec: spec, progress: progress, continuation: continuation,
                            temporaryFile: nil, completionError: nil
                        )
                        let temp = temporaryFile(for: task.taskIdentifier)
                        if FileManager.default.fileExists(atPath: temp.path) {
                            transfer.temporaryFile = temp
                        }
                        transfers[task.taskIdentifier] = transfer
                        lock.unlock()
                        box.task = task
                        if task.state == .suspended { task.resume() }
                        return
                    }
                    task.cancel()
                }

                let task = resumeData.flatMap { session.downloadTask(withResumeData: $0) }
                    ?? session.downloadTask(with: request)
                let spec = TransferSpec(
                    destination: destination,
                    initialBytes: initialBytes,
                    expectedSize: expectedSize,
                    filePath: filePath,
                    fromResumeData: resumeData != nil
                )
                transfers[task.taskIdentifier] = Transfer(
                    spec: spec, progress: progress, continuation: continuation,
                    temporaryFile: nil, completionError: nil
                )
                specs[String(task.taskIdentifier)] = spec
                saveSpecsLocked()
                lock.unlock()
                box.task = task
                task.resume()
            }
        } onCancel: {
            // Produce resume data so the segment transferred so far survives the cancel —
            // the delegate's completion callback stores it beside the partial.
            box.task?.cancel(byProducingResumeData: { _ in })
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
            await transfer.progress(transfer.spec.initialBytes + totalBytesWritten)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskTemporaryFile = temporaryFile(for: downloadTask.taskIdentifier)
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
        // With no in-memory transfer (the task finished while the app was gone and this is
        // the replay), the moved file waits at its deterministic path for
        // `didCompleteWithError`, which settles it from the on-disk spec.
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        loadSpecsLocked()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        let spec = transfer?.spec ?? specs[String(task.taskIdentifier)]
        specs.removeValue(forKey: String(task.taskIdentifier))
        saveSpecsLocked()
        lock.unlock()

        // A replayed callback for a task nothing remembers: drop whatever it left behind.
        guard let spec else {
            try? FileManager.default.removeItem(at: temporaryFile(for: task.taskIdentifier))
            return
        }

        if let error {
            // Keep the transferred-but-uncommitted segment reachable: the resume data points
            // into URLSession's own temp file, and the next attempt hands it back to continue
            // mid-segment. Covers network failures, cancels, and force-quits alike.
            storeResumeData(from: error, spec: spec)
            transfer?.continuation.resume(throwing: error)
            return
        }
        if let completionError = transfer?.completionError {
            transfer?.continuation.resume(throwing: completionError)
            return
        }

        // Settle the finished download into its partial. `transfer` is nil when the task
        // finished while the app was away — the spec still knows where the bytes go.
        let temp = transfer?.temporaryFile ?? temporaryFile(for: task.taskIdentifier)
        do {
            guard FileManager.default.fileExists(atPath: temp.path) else {
                throw ModelDownloadError.incompleteTransfer(file: spec.filePath)
            }
            if let http = task.response as? HTTPURLResponse, !spec.fromResumeData {
                try validate(response: http, spec: spec)
            }
            try append(temporaryFile: temp, per: spec)
            transfer?.continuation.resume()
        } catch {
            try? FileManager.default.removeItem(at: temp)
            transfer?.continuation.resume(throwing: error)
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

    /// The strict response checks for a task built from our own ranged request: the status and
    /// headers must describe exactly the segment asked for. Not applicable to resume-data
    /// tasks, whose response describes URLSession's internal continuation instead.
    private func validate(response http: HTTPURLResponse, spec: TransferSpec) throws {
        switch http.statusCode {
        case 200:
            // Full body — either no Range was sent or the server ignored it. The partial's
            // existing bytes would be duplicated by the append, so restart the file.
            if spec.initialBytes > 0 {
                try truncate(spec.destination, to: 0)
            }
        case 206:
            guard http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(spec.initialBytes)-") == true else {
                try truncate(spec.destination, to: 0)
                throw ModelDownloadError.incompleteTransfer(file: spec.filePath)
            }
        case 416:
            try truncate(spec.destination, to: 0)
            throw ModelDownloadError.incompleteTransfer(file: spec.filePath)
        default:
            throw ModelDownloadError.httpStatus(http.statusCode, file: spec.filePath)
        }

        if let expectedSize = spec.expectedSize,
           let contentLength = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
        {
            let expectedRemaining = max(expectedSize - spec.initialBytes, 0)
            guard contentLength == expectedRemaining else {
                try truncate(spec.destination, to: spec.initialBytes)
                throw ModelDownloadError.incompleteTransfer(file: spec.filePath)
            }
        }
    }

    /// Append a finished task's payload to its partial, then verify the partial is exactly the
    /// expected size; anything else rolls it back to where this append started. Doubles as the
    /// whole settle step for orphaned payloads (relaunch replay, sweep), where no live response
    /// is around to header-check — the size check is what guards integrity there.
    private func append(temporaryFile temp: URL, per spec: TransferSpec) throws {
        defer { try? FileManager.default.removeItem(at: temp) }
        let readHandle = try FileHandle(forReadingFrom: temp)
        defer { try? readHandle.close() }
        let writeHandle = try FileHandle(forWritingTo: spec.destination)
        defer { try? writeHandle.close() }
        // Roll back to the size *before* this append on any mismatch — after a 200 reset the
        // partial starts at 0, so rolling back to `initialBytes` would keep garbage.
        let baseOffset = try writeHandle.seekToEnd()

        while true {
            let shouldContinue = try autoreleasepool {
                let data = try readHandle.read(upToCount: ResumableModelDownloader.writeChunkSize)
                guard let data, !data.isEmpty else { return false }
                try writeHandle.write(contentsOf: data)
                return true
            }
            if !shouldContinue { break }
        }

        if let expectedSize = spec.expectedSize {
            let finalSize = Int64(try writeHandle.seekToEnd())
            guard finalSize == expectedSize else {
                try writeHandle.truncate(atOffset: baseOffset)
                throw ModelDownloadError.incompleteTransfer(file: spec.filePath)
            }
        }
    }

    /// Save a failed task's resume data beside its partial for the next attempt to consume.
    private func storeResumeData(from error: Error, spec: TransferSpec) {
        guard let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
              let encoded = try? JSONEncoder().encode(ResumeBlob(initialBytes: spec.initialBytes, data: data))
        else { return }
        try? encoded.write(to: Self.resumeBlobURL(forPartial: spec.destination), options: .atomic)
    }

    /// Settle transfer records nothing will ever call back for — a crash between a task
    /// finishing and its callbacks landing strands the payload on disk. Their bytes are
    /// appended to the right partial, and payload files with no record at all are deleted.
    private func sweep(liveTaskIDs: Set<Int>) {
        lock.lock()
        loadSpecsLocked()
        var orphaned: [(id: Int, spec: TransferSpec)] = []
        for (key, spec) in specs {
            guard let id = Int(key), !liveTaskIDs.contains(id), transfers[id] == nil else { continue }
            orphaned.append((id, spec))
            specs.removeValue(forKey: key)
        }
        if !orphaned.isEmpty { saveSpecsLocked() }
        let claimedIDs = Set(specs.keys.compactMap(Int.init)).union(transfers.keys)
        lock.unlock()

        for (id, spec) in orphaned {
            let temp = temporaryFile(for: id)
            guard FileManager.default.fileExists(atPath: temp.path) else { continue }
            try? append(temporaryFile: temp, per: spec)
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "download" {
            guard let id = Int(file.deletingPathExtension().lastPathComponent),
                  !liveTaskIDs.contains(id), !claimedIDs.contains(id)
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Spec persistence & small helpers

    private var specsFile: URL { temporaryDirectory.appendingPathComponent("transfers.json") }

    /// Callers must hold `lock`. First touch pulls in what a previous process recorded;
    /// in-memory entries always win over the stored copy.
    private func loadSpecsLocked() {
        guard !specsLoaded else { return }
        specsLoaded = true
        guard let data = try? Data(contentsOf: specsFile),
              let stored = try? JSONDecoder().decode([String: TransferSpec].self, from: data)
        else { return }
        specs.merge(stored) { current, _ in current }
    }

    /// Callers must hold `lock`.
    private func saveSpecsLocked() {
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(specs) else { return }
        try? data.write(to: specsFile, options: .atomic)
    }

    private func temporaryFile(for taskIdentifier: Int) -> URL {
        temporaryDirectory.appendingPathComponent("\(taskIdentifier).download")
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
