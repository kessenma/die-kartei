import Foundation
import SwiftData

/// Rows open on screen right now: the deck being studied, the chat being had. A delete arriving
/// from another device waits until they close, since SwiftData traps when a view reads a row
/// deleted from under it. Cards and quiz results of an open deck, and messages of an open chat,
/// wait with it.
@MainActor
enum SyncInUse {
    private static var open: [UUID: Int] = [:]

    static func begin(_ id: UUID?) {
        guard let id else { return }
        open[id, default: 0] += 1
    }

    static func end(_ id: UUID?) {
        guard let id, let count = open[id] else { return }
        if count <= 1 { open[id] = nil } else { open[id] = count - 1 }
        SyncManager.shared.coordinator?.applyDeferredDeletes()
    }

    /// Whether deleting this record now would pull a row out from under an open screen.
    static func blocks(_ name: String, lastPayload: SyncPayload?) -> Bool {
        guard !open.isEmpty, let record = SyncRecordName(name) else { return false }
        if open[record.id] != nil { return true }
        for parentKey in ["deck", "conversation", "course", "entry"] {
            if let parent = lastPayload?.uuid(parentKey), open[parent] != nil { return true }
        }
        return false
    }
}
