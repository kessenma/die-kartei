import Foundation

// How a record's fields are written into a flat payload and read back. Shared by the iOS sync
// codecs (SwiftData rows) and the Android record store (`KarteiRecord` values), so both write the
// same JSON for the same field: dates as seconds since 2001, UUIDs as strings, `nil` as `.null`.

/// Where counter changes that existed *before* sync was switched on are credited.
nonisolated enum SyncBootstrap {
    /// Rows whose id both devices derive from the same name (StudyDay, stats, the Wortschatz deck).
    /// Each device's pre-sync history is its own, so they sum. A restored copy of the same store
    /// shares the store identifier, so it lands in the same slot and merges by max.
    case perStore
    /// Rows with a random UUID. Two devices can only share one by copying it (a `.kartei` Replace),
    /// so the copies carry the same history and must max, not sum.
    case shared

    static let sharedSlot = "pre"
}

// MARK: - Payload helpers

/// Builds a flat payload. Every field is written, `nil` as `.null`, so "this field is empty" is
/// explicit and a newer build's unknown fields are the only ones a payload lacks.
nonisolated struct SyncFields {
    private(set) var payload: SyncPayload = [:]

    mutating func set(_ key: String, _ value: String?) { payload[key] = value.map(SyncJSON.string) ?? .null }
    mutating func set(_ key: String, _ value: Int?) { payload[key] = value.map { .int(Int64($0)) } ?? .null }
    mutating func set(_ key: String, _ value: Double?) { payload[key] = value.map(SyncJSON.number) ?? .null }
    mutating func set(_ key: String, _ value: Bool?) { payload[key] = value.map(SyncJSON.bool) ?? .null }
    mutating func set(_ key: String, _ value: Date?) {
        payload[key] = value.map { .number($0.timeIntervalSinceReferenceDate) } ?? .null
    }
    mutating func set(_ key: String, _ value: UUID?) { payload[key] = value.map { .string($0.uuidString) } ?? .null }
    mutating func set(_ key: String, _ value: [String]?) {
        payload[key] = value.map { .array($0.map(SyncJSON.string)) } ?? .null
    }
    mutating func set(_ key: String, _ value: [Int]?) {
        payload[key] = value.map { .array($0.map { .int(Int64($0)) }) } ?? .null
    }
    mutating func set(_ key: String, json value: SyncJSON?) { payload[key] = value ?? .null }
    /// A JSON blob the model stores as `Data` (written by a default `JSONEncoder`), parsed so its
    /// items can merge. Unparseable data travels as base64 and merges as one value.
    mutating func set(_ key: String, jsonData value: Data?) {
        guard let value else { payload[key] = .null; return }
        payload[key] = (try? SyncJSON(data: value)) ?? .string("base64:" + value.base64EncodedString())
    }
}

nonisolated extension Dictionary where Key == String, Value == SyncJSON {
    func has(_ key: String) -> Bool { self[key] != nil }
    func string(_ key: String) -> String? { self[key]?.stringValue }
    func int(_ key: String) -> Int? { self[key]?.int64Value.map { Int($0) } }
    func double(_ key: String) -> Double? { self[key]?.doubleValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
    func date(_ key: String) -> Date? { self[key]?.doubleValue.map(Date.init(timeIntervalSinceReferenceDate:)) }
    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
    func strings(_ key: String) -> [String]? { self[key]?.arrayValue?.compactMap(\.stringValue) }
    func ints(_ key: String) -> [Int]? { self[key]?.arrayValue?.compactMap { $0.int64Value.map { Int($0) } } }
    /// A JSON field as is (the inverse of `SyncFields.set(_:json:)`); nil when absent or `.null`.
    func json(_ key: String) -> SyncJSON? {
        guard let v = self[key], v != .null else { return nil }
        return v
    }
    /// The inverse of `SyncFields.set(_:jsonData:)`.
    func jsonData(_ key: String) -> Data? {
        guard let v = self[key], v != .null else { return nil }
        if let s = v.stringValue, s.hasPrefix("base64:") { return Data(base64Encoded: String(s.dropFirst(7))) }
        return v.canonicalData
    }
}
