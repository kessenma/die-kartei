import Foundation
import SwiftData

// MARK: - WordArtwork

/// One picture of one word. A record per picture, so pictures added on two devices both survive
/// with no merge to do; a delete is a record delete. The bytes are not here: they are files under
/// `WordArt/` that `FileSyncDocument` carries on their own. Every field is plain last-writer-wins.
enum WordArtworkCodec: SyncCodec {
    typealias Model = WordArtwork

    static let spec = SyncKinds.wordArtwork

    static func recordName(for model: WordArtwork) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ a: WordArtwork) -> SyncPayload {
        var f = SyncFields()
        f.set("id", a.id)
        f.set("wordKey", a.wordKey)
        f.set("germanWord", a.germanWord)
        f.set("english", a.english)
        f.set("kindRaw", a.kindRaw)
        f.set("styleRaw", a.styleRaw)
        f.set("modelID", a.modelID)
        f.set("prompt", a.prompt)
        f.set("fileName", a.fileName)
        f.set("inkFileName", a.inkFileName)
        f.set("createdAt", a.createdAt)
        f.set("starred", a.starred)
        f.set("modeRaw", a.modeRaw)
        f.set("recalled", a.recalled)
        f.set("inProgress", a.inProgress)
        f.set("sourceArtworkID", a.sourceArtworkID)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> WordArtwork? {
        let id = name.id
        var d = FetchDescriptor<WordArtwork>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> WordArtwork? {
        guard let key = flat.string("wordKey"), let fileName = flat.string("fileName") else { return nil }
        let artwork = WordArtwork(
            wordKey: key,
            germanWord: flat.string("germanWord") ?? key,
            english: flat.string("english") ?? "",
            kind: flat.string("kindRaw").flatMap(WordArtworkKind.init(rawValue:)) ?? .ai,
            fileName: fileName
        )
        artwork.id = name.id
        context.insert(artwork)
        update(artwork, from: flat, in: context)
        return artwork
    }

    static func update(_ a: WordArtwork, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("wordKey") { a.wordKey = v }
        if let v = flat.string("germanWord") { a.germanWord = v }
        if let v = flat.string("english") { a.english = v }
        // An unknown kind from a newer build keeps its raw value, so it travels back unchanged.
        if let v = flat.string("kindRaw") { a.kindRaw = v }
        a.styleRaw = flat.string("styleRaw")
        a.modelID = flat.string("modelID")
        a.prompt = flat.string("prompt")
        if let v = flat.string("fileName") { a.fileName = v }
        a.inkFileName = flat.string("inkFileName")
        if let v = flat.date("createdAt") { a.createdAt = v }
        a.starred = flat.bool("starred") ?? false
        a.modeRaw = flat.string("modeRaw")
        a.recalled = flat.bool("recalled")
        a.inProgress = flat.bool("inProgress") ?? false
        a.sourceArtworkID = flat.uuid("sourceArtworkID")
    }

    // Field coverage: id, wordKey, germanWord, english, kindRaw, styleRaw, modelID, prompt,
    // fileName, inkFileName, createdAt, starred, modeRaw, recalled, inProgress, sourceArtworkID.
}

// MARK: - WordDrawingStat

/// Lifetime drawing counts for one word, one record per `WordArtKey`. Every count is a per-device
/// counter, so drawing on two devices adds up; the last-drawn dates take the later time. The key
/// is never rewritten from a payload.
enum WordDrawingStatCodec: SyncCodec {
    typealias Model = WordDrawingStat

    static let counterFields = SyncKinds.wordDrawingCounterFields

    static let spec = SyncKinds.wordDrawingStat

    static func recordName(for model: WordDrawingStat) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: model.key)
    }

    static func bootstrap(for model: WordDrawingStat) -> SyncBootstrap { .perStore }

    static func known(_ s: WordDrawingStat) -> SyncPayload {
        var f = SyncFields()
        f.set("key", s.key)
        f.set("germanWord", s.germanWord)
        f.set("english", s.english)
        f.set("quickCount", s.quickCount)
        f.set("studioCount", s.studioCount)
        f.set("paintedCount", s.paintedCount)
        f.set("recallRight", s.recallRight)
        f.set("recallMissed", s.recallMissed)
        f.set("lastQuickAt", s.lastQuickAt)
        f.set("lastStudioAt", s.lastStudioAt)
        f.set("lastPaintedAt", s.lastPaintedAt)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> WordDrawingStat? {
        guard let key = flat.string("key") else { return nil }
        var d = FetchDescriptor<WordDrawingStat>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> WordDrawingStat? {
        guard let key = flat.string("key") else { return nil }
        let stat = WordDrawingStat(key: key, germanWord: flat.string("germanWord") ?? key,
                                   english: flat.string("english") ?? "")
        context.insert(stat)
        update(stat, from: flat, in: context)
        return stat
    }

    static func update(_ s: WordDrawingStat, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("germanWord") { s.germanWord = v }
        if let v = flat.string("english") { s.english = v }
        s.quickCount = flat.int("quickCount") ?? 0
        s.studioCount = flat.int("studioCount") ?? 0
        s.paintedCount = flat.int("paintedCount") ?? 0
        s.recallRight = flat.int("recallRight") ?? 0
        s.recallMissed = flat.int("recallMissed") ?? 0
        s.lastQuickAt = flat.date("lastQuickAt")
        s.lastStudioAt = flat.date("lastStudioAt")
        s.lastPaintedAt = flat.date("lastPaintedAt")
    }

    // Field coverage: key, germanWord, english, quickCount, studioCount, paintedCount,
    // recallRight, recallMissed, lastQuickAt, lastStudioAt, lastPaintedAt.
}

// MARK: - QuickDrawSet

/// A saved Quick Draw word list. Plain last-writer-wins: a set is edited by one learner at a time,
/// and merging two edited lists word by word would resurrect words they removed.
enum QuickDrawSetCodec: SyncCodec {
    typealias Model = QuickDrawSet

    static let spec = SyncKinds.quickDrawSet

    static func recordName(for model: QuickDrawSet) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ s: QuickDrawSet) -> SyncPayload {
        var f = SyncFields()
        f.set("id", s.id)
        f.set("name", s.name)
        f.set("createdAt", s.createdAt)
        f.set("updatedAt", s.updatedAt)
        f.set("cardIDs", s.cardIDs.map(\.uuidString))
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> QuickDrawSet? {
        let id = name.id
        var d = FetchDescriptor<QuickDrawSet>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> QuickDrawSet? {
        let set = QuickDrawSet(name: flat.string("name") ?? "")
        set.id = name.id
        context.insert(set)
        update(set, from: flat, in: context)
        return set
    }

    static func update(_ s: QuickDrawSet, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("name") { s.name = v }
        if let v = flat.date("createdAt") { s.createdAt = v }
        let ids = (flat.strings("cardIDs") ?? []).compactMap(UUID.init(uuidString:))
        s.cardIDsData = try? JSONEncoder().encode(ids)
        // After the list: setting `cardIDs` through the accessor would stamp `updatedAt` now.
        if let v = flat.date("updatedAt") { s.updatedAt = v }
    }

    // Field coverage: id, name, createdAt, updatedAt, cardIDsData (as cardIDs).
}
