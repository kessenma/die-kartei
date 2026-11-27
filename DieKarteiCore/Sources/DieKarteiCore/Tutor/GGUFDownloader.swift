#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto  // swift-crypto on Android
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads one tutor GGUF (Android): in ranged pieces appended to a `.part` file, so a dropped
/// connection or a closed app costs only the piece in flight, then checks size and SHA-256 before
/// the file gets its real name. A file that fails the check is deleted, never loaded.
///
/// Real file in the core (not linked from the iOS app, which downloads MLX snapshots with its own
/// background-session downloader); here so it runs in `swift test` against a local server.
nonisolated struct GGUFDownloader: Sendable {
    enum Failure: LocalizedError, Equatable {
        case notEnoughSpace(neededGB: Double, freeGB: Double)
        case badResponse(Int)
        case checksumMismatch
        case sizeMismatch(expected: Int64, got: Int64)

        var errorDescription: String? {
            switch self {
            case .notEnoughSpace(let needed, let free):
                String(format: "Not enough space: the model needs %.1f GB, %.1f GB are free.", needed, free)
            case .badResponse(let status):
                "The download server answered \(status). Try again later."
            case .checksumMismatch:
                "The downloaded file didn't match the published one, so it was deleted. Try again."
            case .sizeMismatch(let expected, let got):
                "The download ended at \(got) of \(expected) bytes. Try again."
            }
        }
    }

    var session: URLSession = .shared
    /// Bytes per request. Big enough that per-request overhead doesn't matter, small enough that a
    /// dropped connection loses little.
    var pieceBytes: Int64 = 32 << 20
    var attemptsPerPiece = 6

    static func partURL(for destination: URL) -> URL {
        destination.appendingPathExtension("part")
    }

    /// Bytes already on disk from an earlier attempt.
    static func resumableBytes(for destination: URL) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: partURL(for: destination).path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }

    /// Downloads `release` to `destination`. Safe to call again after any failure or cancellation:
    /// it continues from the `.part` file.
    @concurrent
    func download(
        _ release: GGUFRelease,
        from url: URL? = nil,
        to destination: URL,
        onProgress: @escaping @MainActor @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = Self.partURL(for: destination)
        var offset = Self.resumableBytes(for: destination)
        if offset > release.bytes {
            try? fm.removeItem(at: part)
            offset = 0
        }
        if !fm.fileExists(atPath: part.path) {
            fm.createFile(atPath: part.path, contents: nil)
        }
        try checkSpace(needed: release.bytes - offset, at: destination.deletingLastPathComponent())
        await onProgress(offset)

        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.truncate(atOffset: UInt64(offset))

        let source = url ?? release.downloadURL
        while offset < release.bytes {
            try Task.checkCancellation()
            let end = min(offset + pieceBytes, release.bytes) - 1
            let data = try await fetch(source, range: offset...end, total: release.bytes)
            try handle.write(contentsOf: data)
            offset += Int64(data.count)
            await onProgress(offset)
        }
        try handle.synchronize()
        try handle.close()

        let size = (try fm.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size == release.bytes else {
            throw Failure.sizeMismatch(expected: release.bytes, got: size)
        }
        guard try Self.sha256(of: part) == release.sha256 else {
            try? fm.removeItem(at: part)
            throw Failure.checksumMismatch
        }
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: part, to: destination)
    }

    /// One piece, retried with backoff on network errors and server hiccups.
    private func fetch(_ url: URL, range: ClosedRange<Int64>, total: Int64) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 60
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let expected = Int(range.upperBound - range.lowerBound + 1)
                if status == 206, data.count == expected { return data }
                // A server that ignores Range sends the whole file; fine only from byte 0.
                if status == 200, range.lowerBound == 0, Int64(data.count) == total { return data.prefix(expected) }
                if (500...599).contains(status) || status == 429 || status == 206 {
                    throw URLError(.badServerResponse)   // retried below
                }
                throw Failure.badResponse(status)
            } catch let error as Failure {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                if attempt >= attemptsPerPiece { throw error }
                try await Task.sleep(nanoseconds: UInt64(min(1 << attempt, 20)) * 1_000_000_000)
            }
        }
    }

    private func checkSpace(needed: Int64, at directory: URL) throws {
        guard needed > 0,
              let attributes = try? FileManager.default.attributesOfFileSystem(forPath: directory.path),
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value
        else { return }
        // Keep 500 MB for the rest of the phone.
        if free < needed + 500_000_000 {
            throw Failure.notEnoughSpace(neededGB: Double(needed) / 1e9, freeGB: Double(free) / 1e9)
        }
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: 16 << 20), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
