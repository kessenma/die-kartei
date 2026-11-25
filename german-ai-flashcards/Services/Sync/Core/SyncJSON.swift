import CryptoKit
import Foundation

/// A JSON value: the payload currency of iCloud sync.
///
/// Every synced row travels as one JSON object. The merge engine works on these values rather than
/// on typed DTOs, so fields a newer build added (and this build has never heard of) survive a merge
/// untouched instead of being dropped by a decoder that doesn't know them.
///
/// Values are only ever produced by round-tripping through JSON text (`SyncJSON(encoding:)`), so a
/// given value always has one representation: `2.0` arrives as `.int(2)` on every device, and
/// equality means equality of meaning.
///
/// This file lives in `Services/Sync/Core`, which the app compiles directly and the
/// `KarteiSyncCore` package symlinks for `swift test`. Keep it free of SwiftData, CloudKit and UI.
nonisolated enum SyncJSON: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([SyncJSON])
    case object([String: SyncJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([SyncJSON].self) { self = .array(a); return }
        self = .object(try c.decode([String: SyncJSON].self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: Building and reading

    /// Any `Encodable` as a JSON value, via JSON text so the representation is canonical.
    /// Dates encode as seconds since the reference date (lossless; the second-granular ISO dates
    /// are a `.kartei` file rule, not a sync rule).
    init<T: Encodable>(encoding value: T) throws {
        let data = try SyncJSON.encoder.encode(value)
        self = try SyncJSON.decoder.decode(SyncJSON.self, from: data)
    }

    /// Decode this value as `T` (unknown keys are ignored by `Decodable`).
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try SyncJSON.decoder.decode(T.self, from: canonicalData)
    }

    init(data: Data) throws {
        self = try SyncJSON.decoder.decode(SyncJSON.self, from: data)
    }

    /// Sorted keys, no whitespace: the bytes that hashes and tie-breaks are computed over.
    var canonicalData: Data {
        // Encoding a SyncJSON can't fail: every case maps to a JSON primitive.
        (try? SyncJSON.encoder.encode(self)) ?? Data()
    }

    /// SHA-256 of the canonical bytes, hex.
    var hashHex: String {
        SHA256.hash(data: canonicalData).map { String(format: "%02x", $0) }.joined()
    }

    var objectValue: [String: SyncJSON]? { if case .object(let o) = self { o } else { nil } }
    var arrayValue: [SyncJSON]? { if case .array(let a) = self { a } else { nil } }
    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }

    /// Integers and doubles both read as a number; everything else is nil.
    var doubleValue: Double? {
        switch self {
        case .int(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case .int(let i): i
        case .double(let d) where d.rounded() == d && abs(d) < 9.0e15: Int64(d)
        default: nil
        }
    }

    subscript(key: String) -> SyncJSON? { objectValue?[key] }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder = JSONDecoder()
}

/// A payload is one JSON object. The merge engine reserves two keys:
/// - `_t`: when this replica last changed a non-counter field (seconds since reference date).
///   It only breaks true conflicts, where both sides changed the same field.
/// - `_b`: the breaking generation. A build holds back payloads from a newer generation instead of
///   applying them. It stays 1 unless a field's *meaning* ever changes. Adding fields never needs it.
typealias SyncPayload = [String: SyncJSON]

nonisolated enum SyncPayloadKey {
    static let modifiedAt = "_t"
    static let generation = "_b"
    static let reserved: Set<String> = [modifiedAt, generation]
}

extension Dictionary where Key == String, Value == SyncJSON {
    /// The canonical bytes of the whole payload.
    nonisolated var syncCanonicalData: Data { SyncJSON.object(self).canonicalData }
    nonisolated var syncHash: String { SyncJSON.object(self).hashHex }
}

/// Lexicographic byte order: the deterministic tiebreak of last resort.
nonisolated func syncBytesLess(_ a: Data, _ b: Data) -> Bool {
    a.lexicographicallyPrecedes(b)
}
