import Foundation
import SwiftData

/// Where counter changes that existed *before* sync was switched on are credited.
enum SyncBootstrap {
    /// Rows whose id both devices derive from the same name (StudyDay, stats, the Wortschatz deck).
    /// Each device's pre-sync history is its own, so they sum. A restored copy of the same store
    /// shares the store identifier, so it lands in the same slot and merges by max.
    case perStore
    /// Rows with a random UUID. Two devices can only share one by copying it (a `.kartei` Replace),
    /// so the copies carry the same history and must max, not sum.
    case shared

    static let sharedSlot = "pre"
}

/// Maps one `@Model` type to sync payloads. One conformance per synced type, in `Codecs/`.
///
/// Payloads are flat JSON objects: counters as plain integers (the merge engine turns them into
/// per-replica slots), dates as seconds since the reference date, `nil` as `.null`. Write them
/// with `SyncFields` and read them with the `SyncPayload` accessors below.
@MainActor
protocol SyncCodec {
    associatedtype Model: PersistentModel

    static var spec: SyncKindSpec { get }
    /// The record name for a local row. Called once per row; the result is bound into its
    /// `SyncRecordState` and never recomputed.
    static func recordName(for model: Model) -> SyncRecordName
    /// Rows that stay on this device (e.g. Wortschatz cards never reviewed: the bundle rebuilds them).
    static func includes(_ model: Model) -> Bool
    static func bootstrap(for model: Model) -> SyncBootstrap
    /// The row's fields, flat.
    static func known(_ model: Model) -> SyncPayload
    /// Find the local row a record names when no `SyncRecordState` maps it yet: by id, or by the
    /// natural key in the payload.
    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> Model?
    /// The record this one hangs off (card → deck). Nil when it has none.
    static func parent(of flat: SyncPayload) -> SyncRecordName?
    /// A new row from a server copy. Returns nil if its parent isn't here yet (the payload is then
    /// held until the parent arrives).
    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> Model?
    /// Write a server copy's fields into an existing row.
    static func update(_ model: Model, from flat: SyncPayload, in context: ModelContext)
    /// Rows a delete of this one cascades to, so their sync state can be dropped with it.
    static func cascadeChildren(of model: Model) -> [any PersistentModel]
}

extension SyncCodec {
    static func includes(_ model: Model) -> Bool { true }
    static func bootstrap(for model: Model) -> SyncBootstrap { .shared }
    static func parent(of flat: SyncPayload) -> SyncRecordName? { nil }
    static func cascadeChildren(of model: Model) -> [any PersistentModel] { [] }
}

// MARK: - Type erasure

/// A codec as the tracker and applier see it: `any PersistentModel` in, payloads out.
@MainActor
protocol SyncKindHandling {
    var kind: String { get }
    var entityName: String { get }
    var spec: SyncKindSpec { get }
    func model(for id: PersistentIdentifier, in context: ModelContext) -> (any PersistentModel)?
    func recordName(for model: any PersistentModel) -> SyncRecordName?
    func includes(_ model: any PersistentModel) -> Bool
    func bootstrap(for model: any PersistentModel) -> SyncBootstrap
    func known(_ model: any PersistentModel) -> SyncPayload?
    func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> (any PersistentModel)?
    func parent(of flat: SyncPayload) -> SyncRecordName?
    func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> (any PersistentModel)?
    func update(_ model: any PersistentModel, from flat: SyncPayload, in context: ModelContext)
    func cascadeChildren(of model: any PersistentModel) -> [any PersistentModel]
    func allModels(in context: ModelContext, offset: Int, limit: Int) -> [any PersistentModel]
}

@MainActor
struct SyncHandler<C: SyncCodec>: SyncKindHandling {
    var kind: String { C.spec.kind }
    var entityName: String { String(describing: C.Model.self) }
    var spec: SyncKindSpec { C.spec }

    func model(for id: PersistentIdentifier, in context: ModelContext) -> (any PersistentModel)? {
        var d = FetchDescriptor<C.Model>(predicate: #Predicate { $0.persistentModelID == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func recordName(for model: any PersistentModel) -> SyncRecordName? {
        (model as? C.Model).map(C.recordName(for:))
    }

    func includes(_ model: any PersistentModel) -> Bool {
        (model as? C.Model).map(C.includes) ?? false
    }

    func bootstrap(for model: any PersistentModel) -> SyncBootstrap {
        (model as? C.Model).map(C.bootstrap(for:)) ?? .shared
    }

    func known(_ model: any PersistentModel) -> SyncPayload? {
        (model as? C.Model).map(C.known)
    }

    func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> (any PersistentModel)? {
        C.find(name, flat: flat, in: context)
    }

    func parent(of flat: SyncPayload) -> SyncRecordName? { C.parent(of: flat) }

    func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> (any PersistentModel)? {
        C.insert(flat, name: name, in: context)
    }

    func update(_ model: any PersistentModel, from flat: SyncPayload, in context: ModelContext) {
        if let m = model as? C.Model { C.update(m, from: flat, in: context) }
    }

    func cascadeChildren(of model: any PersistentModel) -> [any PersistentModel] {
        (model as? C.Model).map(C.cascadeChildren(of:)) ?? []
    }

    func allModels(in context: ModelContext, offset: Int, limit: Int) -> [any PersistentModel] {
        var d = FetchDescriptor<C.Model>()
        d.fetchOffset = offset
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }
}

// MARK: - Payload helpers

/// Builds a flat payload. Every field is written, `nil` as `.null`, so "this field is empty" is
/// explicit and a newer build's unknown fields are the only ones a payload lacks.
struct SyncFields {
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

extension Dictionary where Key == String, Value == SyncJSON {
    func has(_ key: String) -> Bool { self[key] != nil }
    func string(_ key: String) -> String? { self[key]?.stringValue }
    func int(_ key: String) -> Int? { self[key]?.int64Value.map { Int($0) } }
    func double(_ key: String) -> Double? { self[key]?.doubleValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
    func date(_ key: String) -> Date? { self[key]?.doubleValue.map(Date.init(timeIntervalSinceReferenceDate:)) }
    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
    func strings(_ key: String) -> [String]? { self[key]?.arrayValue?.compactMap(\.stringValue) }
    func ints(_ key: String) -> [Int]? { self[key]?.arrayValue?.compactMap { $0.int64Value.map { Int($0) } } }
    /// The inverse of `SyncFields.set(_:jsonData:)`.
    func jsonData(_ key: String) -> Data? {
        guard let v = self[key], v != .null else { return nil }
        if let s = v.stringValue, s.hasPrefix("base64:") { return Data(base64Encoded: String(s.dropFirst(7))) }
        return v.canonicalData
    }
}

extension PersistentIdentifier {
    /// A stable string for looking a row up from `SyncRecordState.localKey`.
    var syncKey: String? {
        guard let data = try? SyncJSON.encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
