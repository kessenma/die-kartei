import Foundation
import OSLog
import SwiftData

/// A server copy of one record, as the transport hands it over.
struct SyncIncoming {
    let name: String
    let payload: SyncPayload
    /// CloudKit's encoded system fields (or the fake server's tag).
    let stamp: Data
    /// The record's change tag, used to skip copies this device already has.
    let tag: String
    /// A downloaded asset (pictures, handouts). Valid only while the fetch is being handled.
    var fileURL: URL? = nil
}

/// Writes server copies into the store.
///
/// All of it runs on the main actor in the main context (`SyncWriter`): the learner's pending edits
/// are flushed first, so a merge always sees them, and nothing can interleave. A sibling context
/// would race the main context's unsaved edits. SwiftData has no merge policy to settle that, and
/// the loser would upload as a negative delta.
@MainActor
final class SyncApplier {
    struct Outcome {
        /// Records whose merged copy differs from the server's and must go back up.
        var uploads: [String] = []
        /// Kinds that changed locally, for post-apply hooks (reminders, the Wortschatz backfill).
        var changedKinds: Set<String> = []
        var inserted = 0
        var updated = 0
        var deleted = 0
        var held = 0
    }

    static let deferredDelete = "delete"
    private let context: ModelContext
    private let identity: SyncIdentity
    /// Returns true while a row must not be deleted from under the learner (a deck being studied).
    var isInUse: (String, SyncPayload?) -> Bool = { name, payload in SyncInUse.blocks(name, lastPayload: payload) }
    /// See `SyncChangeTracker.documents`.
    var documents: [String: any SyncDocumentKind] = SyncDocuments.byKind
    private let log = Logger(subsystem: "kyle-essenmacher.german-ai-flashcards", category: "sync")

    init(context: ModelContext, identity: SyncIdentity) {
        self.context = context
        self.identity = identity
    }

    func apply(_ incoming: [SyncIncoming], deleted: [String]) throws -> Outcome {
        try SyncWriter.write(context) {
            var outcome = Outcome()
            var states = SyncStoreMeta.states(named: incoming.map(\.name) + deleted, in: context)
            var needsKey: [(SyncRecordState, any PersistentModel)] = []
            // Decks whose card set changed here: a paused session indexes cards by position.
            var reshuffled: [SavedDeck] = []

            let ordered = incoming.sorted {
                (SyncRegistry.order[kindOf($0.name)] ?? .max) < (SyncRegistry.order[kindOf($1.name)] ?? .max)
            }
            for record in ordered {
                guard let name = SyncRecordName(record.name) else { continue }
                let state = states[record.name] ?? {
                    let s = SyncRecordState(recordName: record.name, kind: name.kind)
                    context.insert(s)
                    states[record.name] = s
                    return s
                }()
                if state.serverStamp != nil, state.lastSeenTag == record.tag, state.heldPayload == nil { continue }

                if SyncRegistry.byKind[name.kind] == nil, let document = documents[name.kind],
                   document.spec.canRead(record.payload) {
                    applyDocument(document, name: name, record: record, state: state, outcome: &outcome)
                    continue
                }

                // A kind this build doesn't know (added by a newer build), or a newer breaking
                // generation: keep it until an update can read it.
                guard let handler = SyncRegistry.byKind[name.kind], handler.spec.canRead(record.payload) else {
                    hold(state, record, reason: "generation")
                    outcome.held += 1
                    continue
                }
                state.serverStamp = record.stamp
                state.lastSeenTag = record.tag

                let flatRemote = SyncMerge.flatten(record.payload, spec: handler.spec)
                let model = SyncStoreMeta.model(for: state, in: context)
                    ?? handler.find(name, flat: flatRemote, in: context)
                let known = model.flatMap(handler.known)

                var copies = state.copies
                let result = SyncRecordLogic.receive(
                    &copies, remote: record.payload, known: known, spec: handler.spec,
                    slot: identity.replica, now: Date().timeIntervalSinceReferenceDate
                )
                state.copies = copies
                state.heldPayload = nil
                state.heldReason = nil

                if let apply = result.apply {
                    let flat = SyncMerge.flatten(apply, spec: handler.spec)
                    if let model {
                        handler.update(model, from: flat, in: context)
                        outcome.updated += 1
                    } else if let created = handler.insert(flat, name: name, in: context) {
                        needsKey.append((state, created))
                        outcome.inserted += 1
                        if let deck = (created as? SavedCard)?.deck { reshuffled.append(deck) }
                    } else {
                        // The parent (deck, chat, course) hasn't arrived yet.
                        hold(state, record, reason: "parent:" + (handler.parent(of: flat)?.description ?? "?"))
                        outcome.held += 1
                        continue
                    }
                    outcome.changedKinds.insert(name.kind)
                } else if let model, state.localKey == nil {
                    needsKey.append((state, model))
                }
                state.needsUpload = result.upload
                state.updatedAt = .now
                if result.upload { outcome.uploads.append(record.name) }
            }

            for name in deleted {
                guard let state = states[name] else { continue }
                if isInUse(name, state.copies.base) {
                    // Applied when the screen closes (`SyncCoordinator.applyDeferredDeletes`).
                    state.heldReason = Self.deferredDelete
                    continue
                }
                var copies = state.copies
                if SyncRecordLogic.receiveDeletion(&copies) {
                    // Edited here since the server's last copy: the edit wins and re-creates it.
                    state.copies = copies
                    state.serverStamp = nil
                    state.lastSeenTag = nil
                    state.needsUpload = true
                    outcome.uploads.append(name)
                    continue
                }
                if let document = documents[state.kind], let recordName = SyncRecordName(name) {
                    document.delete(recordName, payload: state.copies.base)
                    outcome.changedKinds.insert(state.kind)
                    outcome.deleted += 1
                } else if let model = SyncStoreMeta.model(for: state, in: context),
                   let handler = SyncRegistry.byKind[state.kind] {
                    dropStates(of: handler.cascadeChildren(of: model))
                    if let deck = (model as? SavedCard)?.deck { reshuffled.append(deck) }
                    context.delete(model)
                    outcome.changedKinds.insert(state.kind)
                    outcome.deleted += 1
                }
                context.delete(state)
            }

            releaseHeldChildren(&outcome, needsKey: &needsKey)

            for deck in reshuffled where deck.pausedAt != nil && !deck.isDeleted {
                deck.pausedProgressData = nil
                deck.pausedAt = nil
            }

            // Permanent ids exist only after a save.
            if !needsKey.isEmpty {
                try context.save()
                for (state, model) in needsKey { state.localKey = model.persistentModelID.syncKey }
            }
            return outcome
        }
    }

    /// Children held for a missing parent are inserted once the parent exists.
    private func releaseHeldChildren(_ outcome: inout Outcome, needsKey: inout [(SyncRecordState, any PersistentModel)]) {
        let d = FetchDescriptor<SyncRecordState>(predicate: #Predicate { $0.heldReason != nil })
        guard let held = try? context.fetch(d), !held.isEmpty else { return }
        for state in held where state.heldReason?.hasPrefix("parent:") == true {
            guard let data = state.heldPayload, let payload = try? SyncJSON(data: data).objectValue,
                  let name = SyncRecordName(state.recordName),
                  let handler = SyncRegistry.byKind[name.kind]
            else { continue }
            let base = state.copies.base ?? payload
            let flat = SyncMerge.flatten(base, spec: handler.spec)
            guard let created = handler.insert(flat, name: name, in: context) else { continue }
            state.heldPayload = nil
            state.heldReason = nil
            needsKey.append((state, created))
            outcome.inserted += 1
            outcome.changedKinds.insert(name.kind)
        }
    }

    private func applyDocument(
        _ document: any SyncDocumentKind, name: SyncRecordName, record: SyncIncoming,
        state: SyncRecordState, outcome: inout Outcome
    ) {
        state.serverStamp = record.stamp
        state.lastSeenTag = record.tag
        var copies = state.copies
        let result = SyncRecordLogic.receive(
            &copies, remote: record.payload, known: SyncDocuments.known(for: name), spec: document.spec,
            slot: identity.replica, now: Date().timeIntervalSinceReferenceDate
        )
        state.copies = copies
        state.heldPayload = nil
        state.heldReason = nil
        if let apply = result.apply {
            document.apply(SyncMerge.flatten(apply, spec: document.spec), name: name, file: record.fileURL)
            outcome.changedKinds.insert(name.kind)
            outcome.updated += 1
        }
        state.needsUpload = result.upload
        state.updatedAt = .now
        if result.upload { outcome.uploads.append(record.name) }
    }

    private func hold(_ state: SyncRecordState, _ record: SyncIncoming, reason: String) {
        state.heldPayload = SyncJSON.object(record.payload).canonicalData
        state.heldReason = reason
        state.serverStamp = record.stamp
        state.lastSeenTag = record.tag
        state.updatedAt = .now
    }

    private func dropStates(of children: [any PersistentModel]) {
        for child in children {
            guard let key = child.persistentModelID.syncKey,
                  let state = SyncStoreMeta.state(localKey: key, in: context) else { continue }
            context.delete(state)
        }
    }

    private func kindOf(_ name: String) -> String {
        String(name.prefix { $0 != ":" })
    }
}
