import CryptoKit
import Foundation

/// Name-based UUIDs (RFC 9562 version 5: SHA-1 over a namespace plus a name).
///
/// Foundation has no v5 initializer, even in the iOS 27 SDK. Two devices that each create "the"
/// Wortschatz deck, "the" learner profile, or the stats row for *der Tisch* derive the same id from
/// the same name. Sync then sees one record instead of two duplicates that `.first` picks between
/// at random.
nonisolated enum SyncNameUUID {
    /// Fixed forever. Changing it re-keys every canonical record.
    static let namespace = UUID(uuidString: "6B2F3C4E-9A1D-4E7B-8C55-4B61E0D7A9F2")!

    /// A v5 UUID for the joined parts. Parts are joined with U+001F (unit separator) so
    /// ("ab", "c") and ("a", "bc") differ.
    static func make(_ parts: String...) -> UUID {
        make(parts: parts)
    }

    static func make(parts: [String]) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: Array(parts.joined(separator: "\u{1F}").utf8))
        var hash = Array(Insecure.SHA1.hash(data: bytes)).prefix(16).map { $0 }
        hash[6] = (hash[6] & 0x0F) | 0x50  // version 5
        hash[8] = (hash[8] & 0x3F) | 0x80  // RFC variant
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]
        ))
    }
}

/// `<Kind>:<UUID>`. CloudKit record names must be ASCII and at most 255 characters, and natural
/// keys like *die Männer* aren't. So every name carries a UUID, and the natural key travels in the
/// payload.
nonisolated struct SyncRecordName: Hashable, Sendable, Comparable, CustomStringConvertible {
    let kind: String
    let id: UUID

    init(kind: String, id: UUID) {
        self.kind = kind
        self.id = id
    }

    /// For rows keyed by a natural key (StudyDay by date, stats by word): the id is derived.
    init(kind: String, naturalKey: String) {
        self.kind = kind
        self.id = SyncNameUUID.make(kind, naturalKey)
    }

    init?(_ string: String) {
        guard let colon = string.firstIndex(of: ":"),
              let id = UUID(uuidString: String(string[string.index(after: colon)...]))
        else { return nil }
        kind = String(string[..<colon])
        self.id = id
    }

    var description: String { "\(kind):\(id.uuidString)" }

    static func < (a: SyncRecordName, b: SyncRecordName) -> Bool { a.description < b.description }
}
