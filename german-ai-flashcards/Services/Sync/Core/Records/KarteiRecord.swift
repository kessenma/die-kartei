import Foundation

// Typed values for synced rows, without SwiftData: what the Android store reads and writes.
//
// A record's `payload` is exactly what the iOS codec's `known(_:)` produces for the same row
// (same field names, same encodings), so a record written on Android is a row iOS can apply,
// and an iOS payload reads straight into a record. The golden tests hold both sides to that:
// `SyncGoldenTests` on iOS (codec ⇄ golden) and `SyncRecordTests` in DieKarteiCore
// (record ⇄ golden), over `DieKarteiCore/Tests/DieKarteiCoreTests/sync_golden.json`.
//
// Adding a field to a synced model: add it to the codec (docs/ICLOUD_SYNC.md), to the record
// here, and regenerate the golden file (see `SyncGoldenTests`).

/// The columns the record store indexes a record by. Each kind fills in what its queries need.
nonisolated struct RecordIndex: Hashable, Sendable {
    /// The record this one hangs off (card → deck). Deleting the parent deletes it too.
    var parent: UUID? = nil
    /// A key to find the record by other than its id (a card's German word, a stat's key).
    var naturalKey: String? = nil
    /// `yyyy-MM-dd` (`SyncDayKey`) for records that belong to a day.
    var day: String? = nil
    /// When it is due (seconds since 2001): a card's `nextReviewDate`. Nil means not scheduled.
    var due: Double? = nil
    /// The kind's list order.
    var sort: Double? = nil
}

nonisolated protocol KarteiRecord: Sendable, Hashable {
    static var spec: SyncKindSpec { get }
    var name: SyncRecordName { get }
    /// A flat payload: a codec's `known`, or a stored copy after `SyncMerge.flatten`. Fields this
    /// build doesn't know are kept in `extra`, so writing the record back never drops what a
    /// newer build of either app added.
    init(payload: SyncPayload)
    /// The fields this record knows, every one written (`nil` as `.null`).
    var fields: SyncPayload { get }
    /// Fields from the payload this record doesn't model, passed through untouched.
    var extra: SyncPayload { get set }
    var index: RecordIndex { get }
}

nonisolated extension KarteiRecord {
    /// The flat payload, iOS `known` shape: the known fields over anything passed through.
    var payload: SyncPayload { extra.merging(fields) { _, known in known } }

    /// Keep only the payload fields `fields` doesn't cover. Call at the end of `init(payload:)`.
    mutating func keepExtra(from payload: SyncPayload) {
        let known = fields
        extra = payload.filter { known[$0.key] == nil && !SyncPayloadKey.reserved.contains($0.key) }
    }
}
