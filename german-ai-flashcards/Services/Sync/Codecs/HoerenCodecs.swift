import Foundation
import SwiftData

// MARK: - HoerenRound

/// A finished Hören round. Written once and never edited, so every field is last-writer-wins and
/// the round key is the natural key (the `KasusRoundCodec` pattern).
enum HoerenRoundCodec: SyncCodec {
    typealias Model = HoerenRound

    static let spec = SyncKinds.hoerenRound

    static func recordName(for model: HoerenRound) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: model.roundKey)
    }

    static func known(_ r: HoerenRound) -> SyncPayload {
        var f = SyncFields()
        f.set("roundKey", r.roundKey)
        f.set("date", r.date)
        f.set("kindRaw", r.kindRaw)
        f.set("modeRaw", r.modeRaw)
        f.set("playbackRaw", r.playbackRaw)
        f.set("levelRaw", r.levelRaw)
        f.set("sourceRaw", r.sourceRaw)
        f.set("askedCount", r.askedCount)
        f.set("correctCount", r.correctCount)
        f.set("firstPassCount", r.firstPassCount)
        f.set("replayCount", r.replayCount)
        f.set("durationSeconds", r.durationSeconds)
        f.set("items", jsonData: r.itemsData)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> HoerenRound? {
        guard let key = flat.string("roundKey"), !key.isEmpty else { return nil }
        var d = FetchDescriptor<HoerenRound>(predicate: #Predicate { $0.roundKey == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> HoerenRound? {
        guard let key = flat.string("roundKey"), !key.isEmpty else { return nil }
        let round = HoerenRound(kind: .zahlen, roundKey: key)
        context.insert(round)
        update(round, from: flat, in: context)
        return round
    }

    static func update(_ r: HoerenRound, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { r.date = v }
        if let v = flat.string("kindRaw") { r.kindRaw = v }
        if let v = flat.string("modeRaw") { r.modeRaw = v }
        if let v = flat.string("playbackRaw") { r.playbackRaw = v }
        if let v = flat.string("levelRaw") { r.levelRaw = v }
        if let v = flat.string("sourceRaw") { r.sourceRaw = v }
        if let v = flat.int("askedCount") { r.askedCount = v }
        if let v = flat.int("correctCount") { r.correctCount = v }
        if let v = flat.int("firstPassCount") { r.firstPassCount = v }
        if let v = flat.int("replayCount") { r.replayCount = v }
        if let v = flat.int("durationSeconds") { r.durationSeconds = v }
        r.itemsData = flat.jsonData("items")
    }
}
