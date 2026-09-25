import Foundation
import SwiftData

// MARK: - KasusRound

/// One scored step on the Grammatik path. Append-only, so rounds from both devices simply add up
/// and a unit's progress is exact on both.
/// - Identity is `roundKey` (the round's own id) when it has one, else a content key for rounds
///   recorded before it existed (date, story, unit, step), which never change.
/// - `revealedAnswers` is set after recording (Lösung zeigen) and never unset, so it merges as OR.
/// - Every other field is written once, last-writer-wins.
enum KasusRoundCodec: SyncCodec {
    typealias Model = KasusRound

    static let spec = SyncKindSpec(kind: "KasusRound", rules: ["revealedAnswers": .or])

    static func naturalKey(_ r: KasusRound) -> String {
        r.roundKey.isEmpty
            ? "\(r.date.timeIntervalSinceReferenceDate)|\(r.storyID)|\(r.unitRaw)|\(r.stepRaw)"
            : r.roundKey
    }

    static func recordName(for model: KasusRound) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: naturalKey(model))
    }

    static func known(_ r: KasusRound) -> SyncPayload {
        var f = SyncFields()
        f.set("key", naturalKey(r))
        f.set("date", r.date)
        f.set("storyID", r.storyID)
        f.set("unitRaw", r.unitRaw)
        f.set("stepRaw", r.stepRaw)
        f.set("hintLevelRaw", r.hintLevelRaw)
        f.set("askedCount", r.askedCount)
        f.set("firstTryCount", r.firstTryCount)
        f.set("durationSeconds", r.durationSeconds)
        f.set("perCase", jsonData: r.perCaseData)
        f.set("items", jsonData: r.itemsData)
        f.set("feedbackModeRaw", r.feedbackModeRaw)
        f.set("markCaseRaw", r.markCaseRaw)
        f.set("wrongCount", r.wrongCount)
        f.set("revealedAnswers", r.revealedAnswers)
        f.set("roundKey", r.roundKey)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> KasusRound? {
        if let key = flat.string("roundKey"), !key.isEmpty {
            var d = FetchDescriptor<KasusRound>(predicate: #Predicate { $0.roundKey == key })
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first
        }
        guard let date = flat.date("date"), let story = flat.string("storyID") else { return nil }
        let key = flat.string("key")
        let d = FetchDescriptor<KasusRound>(predicate: #Predicate { $0.date == date && $0.storyID == story })
        return (try? context.fetch(d))?.first { naturalKey($0) == key }
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> KasusRound? {
        let round = KasusRound(storyID: flat.string("storyID") ?? "", unitRaw: flat.string("unitRaw") ?? "",
                               stepRaw: flat.string("stepRaw") ?? "", askedCount: 0, firstTryCount: 0,
                               durationSeconds: 0)
        context.insert(round)
        update(round, from: flat, in: context)
        return round
    }

    static func update(_ r: KasusRound, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { r.date = v }
        if let v = flat.string("storyID") { r.storyID = v }
        if let v = flat.string("unitRaw") { r.unitRaw = v }
        if let v = flat.string("stepRaw") { r.stepRaw = v }
        if let v = flat.string("hintLevelRaw") { r.hintLevelRaw = v }
        if let v = flat.int("askedCount") { r.askedCount = v }
        if let v = flat.int("firstTryCount") { r.firstTryCount = v }
        if let v = flat.int("durationSeconds") { r.durationSeconds = v }
        r.perCaseData = flat.jsonData("perCase")
        r.itemsData = flat.jsonData("items")
        if let v = flat.string("feedbackModeRaw") { r.feedbackModeRaw = v }
        if let v = flat.string("markCaseRaw") { r.markCaseRaw = v }
        if let v = flat.int("wrongCount") { r.wrongCount = v }
        if let v = flat.bool("revealedAnswers") { r.revealedAnswers = v }
        if let v = flat.string("roundKey") { r.roundKey = v }
    }
}

// MARK: - GeneratedKasusStory

/// A tutor-written Kasus story that passed the check. Content, written once; its rounds key on
/// its id, so it has to exist on every device the rounds reach. Everything is last-writer-wins.
enum GeneratedKasusStoryCodec: SyncCodec {
    typealias Model = GeneratedKasusStory

    static let spec = SyncKindSpec(kind: "GeneratedKasusStory")

    static func recordName(for model: GeneratedKasusStory) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: model.id)
    }

    static func known(_ s: GeneratedKasusStory) -> SyncPayload {
        var f = SyncFields()
        f.set("id", s.id)
        f.set("date", s.date)
        f.set("unitRaw", s.unitRaw)
        f.set("level", s.level)
        f.set("modelID", s.modelID)
        f.set("title", s.title)
        f.set("plan", jsonData: s.planData)
        f.set("story", jsonData: s.storyData)
        f.set("validatorSummary", s.validatorSummary)
        f.set("attempts", s.attempts)
        f.set("generationSeconds", s.generationSeconds)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> GeneratedKasusStory? {
        guard let id = flat.string("id") else { return nil }
        var d = FetchDescriptor<GeneratedKasusStory>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> GeneratedKasusStory? {
        guard let id = flat.string("id") else { return nil }
        let story = GeneratedKasusStory(id: id, unitRaw: "", level: "", modelID: "", title: "",
                                        planData: nil, storyData: nil, validatorSummary: "",
                                        attempts: 1, generationSeconds: 0)
        context.insert(story)
        update(story, from: flat, in: context)
        return story
    }

    static func update(_ s: GeneratedKasusStory, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { s.date = v }
        if let v = flat.string("unitRaw") { s.unitRaw = v }
        if let v = flat.string("level") { s.level = v }
        if let v = flat.string("modelID") { s.modelID = v }
        if let v = flat.string("title") { s.title = v }
        s.planData = flat.jsonData("plan")
        s.storyData = flat.jsonData("story")
        if let v = flat.string("validatorSummary") { s.validatorSummary = v }
        if let v = flat.int("attempts") { s.attempts = v }
        if let v = flat.double("generationSeconds") { s.generationSeconds = v }
    }
}

// Field coverage:
// KasusRound: date, storyID, unitRaw, stepRaw, hintLevelRaw, askedCount, firstTryCount,
//   durationSeconds (all lww, written once); perCaseData → "perCase", itemsData → "items" (JSON,
//   lww); feedbackModeRaw, markCaseRaw, wrongCount, roundKey (lww); revealedAnswers (.or).
// GeneratedKasusStory: id (identity), date, unitRaw, level, modelID, title, validatorSummary,
//   attempts, generationSeconds (lww); planData → "plan", storyData → "story" (JSON, lww).
