import CryptoKit
import Foundation

/// A fingerprint of what one device believes the server holds for one kind of record.
///
/// Each device publishes its digests in its heartbeat. Two devices that have fetched everything and
/// have nothing pending should publish identical digests. If they don't, one of them drifted, and
/// the repair path (reconcile, then refetch the whole zone) runs. Merges are idempotent, so repair is
/// always safe.
nonisolated struct SyncDigest: Hashable, Sendable, Codable {
    var count: Int
    var hash: String

    /// `entries`: (record name, hash of the server payload this device holds). Order doesn't matter.
    init(entries: [(name: String, payloadHash: String)]) {
        count = entries.count
        var hasher = SHA256()
        for entry in entries.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: Data("\(entry.name)=\(entry.payloadHash)\n".utf8))
        }
        hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
