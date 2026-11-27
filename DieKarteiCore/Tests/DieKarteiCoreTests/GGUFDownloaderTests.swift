#if canImport(CryptoKit)
import CryptoKit
import Foundation
import Testing
@testable import DieKarteiCore

/// Serves byte ranges of `body`, failing the first `failuresLeft` requests with a 503.
final class RangeServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var failuresLeft = 0
    nonisolated(unsafe) static var requestedStarts: [Int] = []

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "gguf.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        if Self.failuresLeft > 0 {
            Self.failuresLeft -= 1
            respond(503, Data(), [:])
            return
        }
        let header = request.value(forHTTPHeaderField: "Range") ?? ""
        let bounds = header.dropFirst("bytes=".count).split(separator: "-").compactMap { Int($0) }
        guard bounds.count == 2 else { respond(200, Self.body, [:]); return }
        Self.requestedStarts.append(bounds[0])
        let slice = Self.body.subdata(in: bounds[0]..<min(bounds[1] + 1, Self.body.count))
        respond(206, slice, ["Content-Range": "bytes \(bounds[0])-\(bounds[1])/\(Self.body.count)"])
        _ = url
    }

    private func respond(_ status: Int, _ data: Data, _ headers: [String: String]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct GGUFDownloaderTests {
    let body = Data((0..<100_000).map { UInt8($0 % 251) })
    let url = URL(string: "https://gguf.test/model.gguf")!

    func release(sha: String? = nil) -> GGUFRelease {
        let real = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return GGUFRelease(repoID: "x/y", fileName: "model.gguf", quant: "Q4_0", bytes: Int64(body.count), sha256: sha ?? real)
    }

    func downloader() -> GGUFDownloader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeServer.self]
        RangeServer.body = body
        RangeServer.requestedStarts = []
        RangeServer.failuresLeft = 0
        return GGUFDownloader(session: URLSession(configuration: config), pieceBytes: 30_000, attemptsPerPiece: 3)
    }

    func destination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gguf-test-\(UUID().uuidString)")
            .appendingPathComponent("model.gguf")
    }

    @Test func downloadsInPiecesAndChecksTheHash() async throws {
        let d = downloader()
        let dest = destination()
        try await d.download(release(), from: url, to: dest) { _ in }
        #expect(try Data(contentsOf: dest) == body)
        #expect(!FileManager.default.fileExists(atPath: GGUFDownloader.partURL(for: dest).path))
        #expect(RangeServer.requestedStarts == [0, 30_000, 60_000, 90_000])
    }

    @Test func resumesFromThePartFile() async throws {
        let d = downloader()
        let dest = destination()
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.prefix(45_000).write(to: GGUFDownloader.partURL(for: dest))
        #expect(GGUFDownloader.resumableBytes(for: dest) == 45_000)
        try await d.download(release(), from: url, to: dest) { _ in }
        #expect(try Data(contentsOf: dest) == body)
        #expect(RangeServer.requestedStarts == [45_000, 75_000])
    }

    @Test func retriesServerHiccups() async throws {
        let d = downloader()
        RangeServer.failuresLeft = 2
        let dest = destination()
        try await d.download(release(), from: url, to: dest) { _ in }
        #expect(try Data(contentsOf: dest) == body)
    }

    /// The real thing: the smallest published tutor from Hugging Face (1.5 GB), through its
    /// redirect to the CDN, in ranged pieces, hash-checked. `GGUF_LIVE=1 swift test --filter live`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GGUF_LIVE"] == "1"))
    func liveDownloadFromHuggingFace() async throws {
        let release = try #require(MLXModel.granite2B_german.gguf)
        let dest = destination()
        try await GGUFDownloader().download(release, to: dest) { _ in }
        let size = try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber
        #expect(size?.int64Value == release.bytes)
        try? FileManager.default.removeItem(at: dest.deletingLastPathComponent())
    }

    @Test func deletesAFileThatFailsTheChecksum() async throws {
        let d = downloader()
        let dest = destination()
        await #expect(throws: GGUFDownloader.Failure.checksumMismatch) {
            try await d.download(release(sha: String(repeating: "0", count: 64)), from: url, to: dest) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: GGUFDownloader.partURL(for: dest).path))
    }
}
#endif
