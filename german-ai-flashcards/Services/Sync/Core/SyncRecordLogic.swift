import Foundation

/// What a device remembers about one synced record, apart from CloudKit's system fields.
///
/// - `server`: the last copy this device knows the server holds. It is the three-way ancestor for
///   ordinary fields and the echo check: nothing is uploaded when the model already matches it.
/// - `pending`: a merged copy waiting to go up, or nil when the device is in step with `server`.
///
/// Local changes are always composed on `pending ?? server`, never on `server` alone. Counter slots
/// credited locally (including the bootstrap slot for pre-sync data) therefore stay put until the
/// server has them, and are never re-attributed to another slot.
nonisolated struct SyncRecordCopies: Hashable, Sendable {
    var server: SyncPayload?
    var pending: SyncPayload?

    init(server: SyncPayload? = nil, pending: SyncPayload? = nil) {
        self.server = server
        self.pending = pending
    }

    var base: SyncPayload? { pending ?? server }
}

/// The per-record state machine shared by the app's sync engine and the test simulator.
nonisolated enum SyncRecordLogic {

    /// The model changed locally. Recompute what should be on the server.
    /// Returns true when there is something to upload.
    @discardableResult
    static func noteLocal(
        _ copies: inout SyncRecordCopies,
        known: SyncPayload,
        spec: SyncKindSpec,
        slot: String,
        now: Double
    ) -> Bool {
        let composed = SyncMerge.compose(base: copies.base, known: known, spec: spec, slot: slot, now: now)
        if let server = copies.server, sameContent(composed, server) {
            copies.pending = nil
            return false
        }
        copies.pending = composed
        return true
    }

    /// The server accepted exactly `sent`.
    static func didSave(_ copies: inout SyncRecordCopies, sent: SyncPayload) {
        copies.server = sent
        if copies.pending == sent { copies.pending = nil }
    }

    /// The outcome of receiving a server copy.
    struct Received: Sendable {
        /// Write this into the model (flatten first). Nil when the model already matches.
        var apply: SyncPayload?
        /// The merged copy differs from the server's, so it must be uploaded.
        var upload: Bool
    }

    /// A server copy arrived, either fetched or handed back by a save conflict.
    /// `known` is the local model as it is right now, or nil if there is no local row.
    static func receive(
        _ copies: inout SyncRecordCopies,
        remote: SyncPayload,
        known: SyncPayload?,
        spec: SyncKindSpec,
        slot: String,
        now: Double
    ) -> Received {
        guard let known else {
            copies.server = remote
            copies.pending = nil
            return Received(apply: remote, upload: false)
        }
        let local = SyncMerge.compose(base: copies.base, known: known, spec: spec, slot: slot, now: now)
        let merged = SyncMerge.merge(ancestor: copies.server, local: local, remote: remote, spec: spec)
        copies.server = remote
        copies.pending = sameContent(merged, remote) ? nil : merged
        let modelNow = SyncMerge.flatten(local, spec: spec)
        let modelAfter = SyncMerge.flatten(merged, spec: spec)
        return Received(apply: modelNow == modelAfter ? nil : merged, upload: copies.pending != nil)
    }

    /// The server deleted the record. Returns true if the local row should survive and be
    /// re-uploaded: local edits since the last server copy beat a concurrent delete.
    static func receiveDeletion(_ copies: inout SyncRecordCopies) -> Bool {
        let keep = copies.pending != nil
        copies.server = nil
        return keep
    }

    /// The server copy is gone or belongs to another database: zone deleted, account or
    /// environment switched. Forget the server, but keep every counter slot in `pending` so a
    /// later re-upload merges by max instead of summing the same history twice.
    static func forgetServer(_ copies: inout SyncRecordCopies) {
        if copies.pending == nil { copies.pending = copies.server }
        copies.server = nil
    }

    /// Equal apart from `_t`, which only matters when a real conflict needs a tiebreak.
    static func sameContent(_ a: SyncPayload, _ b: SyncPayload) -> Bool {
        var a = a, b = b
        a[SyncPayloadKey.modifiedAt] = nil
        b[SyncPayloadKey.modifiedAt] = nil
        return a == b
    }
}
