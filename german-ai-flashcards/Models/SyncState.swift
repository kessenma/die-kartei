import Foundation
import SwiftData

/// What this device remembers about one record it syncs through iCloud. Local-only: it's never
/// synced itself, and every change to it is saved with the `"sync"` author so the change tracker
/// ignores it.
///
/// It lives in the main store on purpose, so it resets together with the data: if the store is
/// ever moved aside, the fresh store starts with no sync state and refills from iCloud.
@Model
final class SyncRecordState {
    /// `<Kind>:<UUID>` (`SyncRecordName`). Bound once when the row is first seen and never
    /// recomputed, so a key that depends on the time zone can't drift.
    var recordName: String = ""
    var kind: String = ""
    /// The row's `PersistentIdentifier`, encoded with sorted keys. Recorded after a save, when the
    /// id is permanent. It's how a history *delete* (which no longer has the row) finds its record.
    var localKey: String? = nil
    /// CloudKit's system fields (change tag, zone) from the last server copy, or the fake server's tag.
    var serverStamp: Data? = nil
    /// The server copy's change tag, so a fetched copy this device already has (its own upload
    /// echoed back) is skipped.
    var lastSeenTag: String? = nil
    /// `SyncRecordCopies.server`: canonical JSON of the last copy the server is known to hold.
    var serverPayload: Data? = nil
    /// `SyncRecordCopies.pending`: a merged copy waiting to go up.
    var pendingPayload: Data? = nil
    /// Source of truth for "must upload". Cleared only by a successful send.
    var needsUpload: Bool = false
    /// The row was deleted here; the delete still has to reach the server.
    var pendingDelete: Bool = false
    /// A server copy this device can't apply yet: from a newer breaking generation, or a child
    /// whose parent hasn't arrived. `heldReason` says which.
    var heldPayload: Data? = nil
    var heldReason: String? = nil
    /// Consecutive send failures that weren't transient. At five the record counts as stuck.
    var failureCount: Int = 0
    var lastError: String? = nil
    var updatedAt: Date = Date.distantPast

    init(recordName: String, kind: String) {
        self.recordName = recordName
        self.kind = kind
    }

    var copies: SyncRecordCopies {
        get {
            SyncRecordCopies(
                server: serverPayload.flatMap { try? SyncJSON(data: $0).objectValue },
                pending: pendingPayload.flatMap { try? SyncJSON(data: $0).objectValue }
            )
        }
        set {
            serverPayload = newValue.server.map { SyncJSON.object($0).canonicalData }
            pendingPayload = newValue.pending.map { SyncJSON.object($0).canonicalData }
        }
    }

    var isStuck: Bool { failureCount >= 5 }
}

/// Store-scoped sync bookkeeping: one row, only ever touched by sync code.
@Model
final class SyncMeta {
    /// The last processed history token (`DefaultHistoryToken`, JSON). Saved in the same save as the
    /// `needsUpload` flags it produced, so a crash can't lose a change between the two.
    var historyToken: Data? = nil
    /// Set once the first full scan has credited pre-sync data to the bootstrap slot.
    var initialScanDone: Bool = false
    /// The store's identifier at the first scan: the bootstrap slot for pre-sync counters. A restored
    /// backup of the same store carries the same identifier, so its copy merges by max.
    var bootstrapSlot: String? = nil
    /// Set once the singleton rows have their canonical ids.
    var canonicalizedVersion: Int = 0

    init() {}
}
