import Foundation
import SwiftData

/// A phrase from the phrase library. Plain content; the rotation bookkeeping takes the later use.
enum LearnedPhraseCodec: SyncCodec {
    typealias Model = LearnedPhrase

    static let spec = SyncKindSpec(
        kind: "LearnedPhrase",
        rules: ["lastSurfacedAt": .max, "surfacedCount": .max]
    )

    static func recordName(for model: LearnedPhrase) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ p: LearnedPhrase) -> SyncPayload {
        var f = SyncFields()
        f.set("id", p.id)
        f.set("german", p.german)
        f.set("english", p.english)
        f.set("scenarioTagsRaw", p.scenarioTagsRaw)
        f.set("focusAreasRaw", p.focusAreasRaw)
        f.set("creatorModelRaw", p.creatorModelRaw)
        f.set("isActive", p.isActive)
        f.set("surfacedCount", p.surfacedCount)
        f.set("lastSurfacedAt", p.lastSurfacedAt)
        f.set("createdAt", p.createdAt)
        f.set("note", p.note)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> LearnedPhrase? {
        let id = name.id
        var d = FetchDescriptor<LearnedPhrase>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> LearnedPhrase? {
        let phrase = LearnedPhrase(german: flat.string("german") ?? "", english: flat.string("english") ?? "")
        phrase.id = name.id
        context.insert(phrase)
        update(phrase, from: flat, in: context)
        return phrase
    }

    static func update(_ p: LearnedPhrase, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("german") { p.german = v }
        if let v = flat.string("english") { p.english = v }
        p.scenarioTagsRaw = flat.strings("scenarioTagsRaw") ?? []
        p.focusAreasRaw = flat.strings("focusAreasRaw") ?? []
        if let v = flat.string("creatorModelRaw") { p.creatorModelRaw = v }
        if let v = flat.bool("isActive") { p.isActive = v }
        if let v = flat.int("surfacedCount") { p.surfacedCount = v }
        p.lastSurfacedAt = flat.date("lastSurfacedAt")
        if let v = flat.date("createdAt") { p.createdAt = v }
        p.note = flat.string("note")
    }
}
