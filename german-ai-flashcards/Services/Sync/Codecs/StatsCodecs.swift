import Foundation
import SwiftData

/// What the three game-stat kinds share. The matching game (pairs), the der/die/das game (nouns)
/// and the Kasus drill (prepositions) each keep one lifetime row per word and one log row per
/// finished round, with the same fields and the same merge.
private enum GameStatSync {
    /// A per-word stat row. Seen and missed are per-device counters and the wrong-pick tally is one
    /// counter per wrong answer, so play on two devices adds up. The first-try streak and
    /// `lastSeenAt` are taken together from the device that saw the word last: a streak is an
    /// unbroken run of rounds, and two devices' runs can't be added. `lastSeenAt` sits in the group,
    /// as `lastReviewedAt` does in a card's schedule: a miss that leaves the streak at 0 doesn't
    /// change it, and a streak-only group would then take the other device's older streak.
    /// `lastSeenAt` still comes out as the later time. `lastMissedAt` takes the later time.
    static func statSpec(kind: String, tally: String) -> SyncKindSpec {
        SyncKindSpec(
            kind: kind,
            rules: [
                "timesSeen": .counter,
                "timesMissed": .counter,
                tally: .counterMap,
                "lastMissedAt": .max,
            ],
            groups: [SyncFieldGroup(fields: ["firstTryStreak", "lastSeenAt"], orderBy: ["lastSeenAt"])]
        )
    }

    /// A `[String: Int]` tally blob as an object of plain integers, which `.counterMap` turns into
    /// one counter per answer. Nil when there is no tally yet.
    static func tallyJSON(_ data: Data?) -> SyncJSON? {
        guard let data, let tally = try? JSONDecoder().decode([String: Int].self, from: data),
              !tally.isEmpty
        else { return nil }
        return SyncJSON.object(tally.mapValues { SyncJSON.int(Int64($0)) })
    }

    /// The inverse of `tallyJSON`: the flattened counters, encoded the way the model's accessor
    /// writes them. Answers whose counter merged down to 0 or below are dropped: the word sheet
    /// shows the top wrong pick with no count check, so a stale zero would read as "you reach for
    /// der". Nil when nothing is left.
    static func tallyData(_ flat: SyncPayload, _ key: String) -> Data? {
        guard let counters = flat[key]?.objectValue else { return nil }
        let tally = counters.compactMapValues { $0.int64Value.map { Int($0) } }.filter { $0.value > 0 }
        guard !tally.isEmpty else { return nil }
        return try? JSONEncoder().encode(tally)
    }

    /// A round row has no id, so its record is named after its content. Rounds are never edited,
    /// and two rounds can't finish at the same instant on the same topic.
    static func roundKey(date: Date, topic: String, counts: [Int]) -> String {
        (["\(date.timeIntervalSinceReferenceDate)", topic] + counts.map { String($0) }).joined(separator: "|")
    }
}

// MARK: - MatchingPairStat

/// Lifetime matching-game stats for one German ↔ English pair, one record per pair key.
/// - `timesSeen` and `timesMissed` are per-device counters, and each wrong English meaning in the
///   confusions tally is its own counter, so rounds played on two devices add up.
/// - `firstTryStreak` and `lastSeenAt` travel together, taken from the device that saw the pair
///   last, so a miss there still resets the streak when the streak was already 0.
/// - `lastMissedAt` takes the later time. The display forms take the last edit.
/// - The key names the record and is never rewritten from a payload. Every stored field travels.
enum MatchingPairStatCodec: SyncCodec {
    typealias Model = MatchingPairStat

    static let spec = GameStatSync.statSpec(kind: "MatchingPairStat", tally: "confusions")

    static func recordName(for model: MatchingPairStat) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: model.key)
    }

    static func bootstrap(for model: MatchingPairStat) -> SyncBootstrap { .perStore }

    static func known(_ s: MatchingPairStat) -> SyncPayload {
        var f = SyncFields()
        f.set("key", s.key)
        f.set("german", s.german)
        f.set("article", s.article)
        f.set("english", s.english)
        f.set("timesSeen", s.timesSeen)
        f.set("timesMissed", s.timesMissed)
        f.set("firstTryStreak", s.firstTryStreak)
        f.set("lastSeenAt", s.lastSeenAt)
        f.set("lastMissedAt", s.lastMissedAt)
        f.set("confusions", json: GameStatSync.tallyJSON(s.confusionsData))
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> MatchingPairStat? {
        guard let key = flat.string("key") else { return nil }
        var d = FetchDescriptor<MatchingPairStat>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> MatchingPairStat? {
        guard let key = flat.string("key") else { return nil }
        let stat = MatchingPairStat(key: key, german: flat.string("german") ?? "",
                                    article: flat.string("article"), english: flat.string("english") ?? "")
        context.insert(stat)
        update(stat, from: flat, in: context)
        return stat
    }

    static func update(_ s: MatchingPairStat, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("german") { s.german = v }
        s.article = flat.string("article")
        if let v = flat.string("english") { s.english = v }
        s.timesSeen = flat.int("timesSeen") ?? 0
        s.timesMissed = flat.int("timesMissed") ?? 0
        if let v = flat.int("firstTryStreak") { s.firstTryStreak = v }
        if let v = flat.date("lastSeenAt") { s.lastSeenAt = v }
        s.lastMissedAt = flat.date("lastMissedAt")
        s.confusionsData = GameStatSync.tallyData(flat, "confusions")
    }
}

// MARK: - MatchingRound

/// One finished matching round. Append-only and never edited, so rounds from both devices simply
/// add up. The row has no id: its record is named after its content and found again by its exact
/// date and topic (a date survives the payload as the same number of seconds).
enum MatchingRoundCodec: SyncCodec {
    typealias Model = MatchingRound

    static let spec = SyncKindSpec(kind: "MatchingRound")

    static func recordName(for model: MatchingRound) -> SyncRecordName {
        let key = GameStatSync.roundKey(date: model.date, topic: model.topic,
                                        counts: [model.pairCount, model.firstTryCount, model.durationSeconds])
        return SyncRecordName(kind: spec.kind, naturalKey: key)
    }

    static func known(_ r: MatchingRound) -> SyncPayload {
        var f = SyncFields()
        f.set("date", r.date)
        f.set("topic", r.topic)
        f.set("pairCount", r.pairCount)
        f.set("firstTryCount", r.firstTryCount)
        f.set("durationSeconds", r.durationSeconds)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> MatchingRound? {
        guard let date = flat.date("date"), let topic = flat.string("topic") else { return nil }
        var d = FetchDescriptor<MatchingRound>(predicate: #Predicate { $0.date == date && $0.topic == topic })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> MatchingRound? {
        guard let date = flat.date("date") else { return nil }
        let round = MatchingRound(topic: flat.string("topic") ?? "", pairCount: flat.int("pairCount") ?? 0,
                                  firstTryCount: flat.int("firstTryCount") ?? 0,
                                  durationSeconds: flat.int("durationSeconds") ?? 0)
        round.date = date
        context.insert(round)
        update(round, from: flat, in: context)
        return round
    }

    static func update(_ r: MatchingRound, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { r.date = v }
        if let v = flat.string("topic") { r.topic = v }
        if let v = flat.int("pairCount") { r.pairCount = v }
        if let v = flat.int("firstTryCount") { r.firstTryCount = v }
        if let v = flat.int("durationSeconds") { r.durationSeconds = v }
    }
}

// MARK: - ArticleWordStat

/// Lifetime der/die/das stats for one noun, one record per lowercased noun. Merges like
/// `MatchingPairStatCodec`: seen and missed are per-device counters, each wrong article in the
/// wrong-picks tally is its own counter, the first-try streak and `lastSeenAt` come together from
/// the device that saw the noun last, and `lastMissedAt` takes the later time. The key is never
/// rewritten from a payload. Every stored field travels.
enum ArticleWordStatCodec: SyncCodec {
    typealias Model = ArticleWordStat

    static let spec = GameStatSync.statSpec(kind: "ArticleWordStat", tally: "wrongPicks")

    static func recordName(for model: ArticleWordStat) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: model.key)
    }

    static func bootstrap(for model: ArticleWordStat) -> SyncBootstrap { .perStore }

    static func known(_ s: ArticleWordStat) -> SyncPayload {
        var f = SyncFields()
        f.set("key", s.key)
        f.set("noun", s.noun)
        f.set("articleRaw", s.articleRaw)
        f.set("english", s.english)
        f.set("timesSeen", s.timesSeen)
        f.set("timesMissed", s.timesMissed)
        f.set("firstTryStreak", s.firstTryStreak)
        f.set("lastSeenAt", s.lastSeenAt)
        f.set("lastMissedAt", s.lastMissedAt)
        f.set("wrongPicks", json: GameStatSync.tallyJSON(s.wrongPicksData))
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ArticleWordStat? {
        guard let key = flat.string("key") else { return nil }
        var d = FetchDescriptor<ArticleWordStat>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ArticleWordStat? {
        guard let key = flat.string("key") else { return nil }
        let stat = ArticleWordStat(key: key, noun: flat.string("noun") ?? "",
                                   articleRaw: flat.string("articleRaw") ?? "", english: flat.string("english") ?? "")
        context.insert(stat)
        update(stat, from: flat, in: context)
        return stat
    }

    static func update(_ s: ArticleWordStat, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("noun") { s.noun = v }
        if let v = flat.string("articleRaw") { s.articleRaw = v }
        if let v = flat.string("english") { s.english = v }
        s.timesSeen = flat.int("timesSeen") ?? 0
        s.timesMissed = flat.int("timesMissed") ?? 0
        if let v = flat.int("firstTryStreak") { s.firstTryStreak = v }
        if let v = flat.date("lastSeenAt") { s.lastSeenAt = v }
        s.lastMissedAt = flat.date("lastMissedAt")
        s.wrongPicksData = GameStatSync.tallyData(flat, "wrongPicks")
    }
}

// MARK: - ArticleRound

/// One finished der/die/das round. Append-only like `MatchingRoundCodec`: named after its content,
/// found again by its exact date and topic.
enum ArticleRoundCodec: SyncCodec {
    typealias Model = ArticleRound

    static let spec = SyncKindSpec(kind: "ArticleRound")

    static func recordName(for model: ArticleRound) -> SyncRecordName {
        let key = GameStatSync.roundKey(date: model.date, topic: model.topic,
                                        counts: [model.questionCount, model.firstTryCount, model.durationSeconds])
        return SyncRecordName(kind: spec.kind, naturalKey: key)
    }

    static func known(_ r: ArticleRound) -> SyncPayload {
        var f = SyncFields()
        f.set("date", r.date)
        f.set("topic", r.topic)
        f.set("questionCount", r.questionCount)
        f.set("firstTryCount", r.firstTryCount)
        f.set("durationSeconds", r.durationSeconds)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ArticleRound? {
        guard let date = flat.date("date"), let topic = flat.string("topic") else { return nil }
        var d = FetchDescriptor<ArticleRound>(predicate: #Predicate { $0.date == date && $0.topic == topic })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ArticleRound? {
        guard let date = flat.date("date") else { return nil }
        let round = ArticleRound(topic: flat.string("topic") ?? "", questionCount: flat.int("questionCount") ?? 0,
                                 firstTryCount: flat.int("firstTryCount") ?? 0,
                                 durationSeconds: flat.int("durationSeconds") ?? 0)
        round.date = date
        context.insert(round)
        update(round, from: flat, in: context)
        return round
    }

    static func update(_ r: ArticleRound, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { r.date = v }
        if let v = flat.string("topic") { r.topic = v }
        if let v = flat.int("questionCount") { r.questionCount = v }
        if let v = flat.int("firstTryCount") { r.firstTryCount = v }
        if let v = flat.int("durationSeconds") { r.durationSeconds = v }
    }
}

// MARK: - PrepositionStat

/// Lifetime Kasus-drill stats for one preposition, one record per lowercased word. Merges like
/// `MatchingPairStatCodec`: seen and missed are per-device counters, each wrong case in the
/// wrong-picks tally is its own counter, the first-try streak and `lastSeenAt` come together from
/// the device that saw the word last, and `lastMissedAt` takes the later time. The key is never
/// rewritten from a payload. Every stored field travels.
enum PrepositionStatCodec: SyncCodec {
    typealias Model = PrepositionStat

    static let spec = GameStatSync.statSpec(kind: "PrepositionStat", tally: "wrongPicks")

    static func recordName(for model: PrepositionStat) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, naturalKey: model.key)
    }

    static func bootstrap(for model: PrepositionStat) -> SyncBootstrap { .perStore }

    static func known(_ s: PrepositionStat) -> SyncPayload {
        var f = SyncFields()
        f.set("key", s.key)
        f.set("word", s.word)
        f.set("caseRaw", s.caseRaw)
        f.set("meaning", s.meaning)
        f.set("timesSeen", s.timesSeen)
        f.set("timesMissed", s.timesMissed)
        f.set("firstTryStreak", s.firstTryStreak)
        f.set("lastSeenAt", s.lastSeenAt)
        f.set("lastMissedAt", s.lastMissedAt)
        f.set("wrongPicks", json: GameStatSync.tallyJSON(s.wrongPicksData))
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> PrepositionStat? {
        guard let key = flat.string("key") else { return nil }
        var d = FetchDescriptor<PrepositionStat>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> PrepositionStat? {
        guard let key = flat.string("key") else { return nil }
        let stat = PrepositionStat(key: key, word: flat.string("word") ?? "",
                                   caseRaw: flat.string("caseRaw") ?? "", meaning: flat.string("meaning") ?? "")
        context.insert(stat)
        update(stat, from: flat, in: context)
        return stat
    }

    static func update(_ s: PrepositionStat, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("word") { s.word = v }
        if let v = flat.string("caseRaw") { s.caseRaw = v }
        if let v = flat.string("meaning") { s.meaning = v }
        s.timesSeen = flat.int("timesSeen") ?? 0
        s.timesMissed = flat.int("timesMissed") ?? 0
        if let v = flat.int("firstTryStreak") { s.firstTryStreak = v }
        if let v = flat.date("lastSeenAt") { s.lastSeenAt = v }
        s.lastMissedAt = flat.date("lastMissedAt")
        s.wrongPicksData = GameStatSync.tallyData(flat, "wrongPicks")
    }
}

// MARK: - PrepositionRound

/// One finished Kasus round. Append-only like `MatchingRoundCodec`: named after its content, found
/// again by its exact date and topic.
enum PrepositionRoundCodec: SyncCodec {
    typealias Model = PrepositionRound

    static let spec = SyncKindSpec(kind: "PrepositionRound")

    static func recordName(for model: PrepositionRound) -> SyncRecordName {
        let key = GameStatSync.roundKey(date: model.date, topic: model.topic,
                                        counts: [model.questionCount, model.firstTryCount, model.durationSeconds])
        return SyncRecordName(kind: spec.kind, naturalKey: key)
    }

    static func known(_ r: PrepositionRound) -> SyncPayload {
        var f = SyncFields()
        f.set("date", r.date)
        f.set("topic", r.topic)
        f.set("questionCount", r.questionCount)
        f.set("firstTryCount", r.firstTryCount)
        f.set("durationSeconds", r.durationSeconds)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> PrepositionRound? {
        guard let date = flat.date("date"), let topic = flat.string("topic") else { return nil }
        var d = FetchDescriptor<PrepositionRound>(predicate: #Predicate { $0.date == date && $0.topic == topic })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> PrepositionRound? {
        guard let date = flat.date("date") else { return nil }
        let round = PrepositionRound(topic: flat.string("topic") ?? "", questionCount: flat.int("questionCount") ?? 0,
                                     firstTryCount: flat.int("firstTryCount") ?? 0,
                                     durationSeconds: flat.int("durationSeconds") ?? 0)
        round.date = date
        context.insert(round)
        update(round, from: flat, in: context)
        return round
    }

    static func update(_ r: PrepositionRound, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { r.date = v }
        if let v = flat.string("topic") { r.topic = v }
        if let v = flat.int("questionCount") { r.questionCount = v }
        if let v = flat.int("firstTryCount") { r.firstTryCount = v }
        if let v = flat.int("durationSeconds") { r.durationSeconds = v }
    }
}

// Field coverage:
//
// MatchingPairStat
//   key             -> "key", .lww (identity: names the record, used by find; set on insert only)
//   german          -> "german", .lww
//   article         -> "article", .lww
//   english         -> "english", .lww
//   timesSeen       -> "timesSeen", .counter
//   timesMissed     -> "timesMissed", .counter
//   firstTryStreak  -> "firstTryStreak", SyncFieldGroup [firstTryStreak, lastSeenAt] ordered by lastSeenAt
//   lastSeenAt      -> "lastSeenAt", same SyncFieldGroup (whole from the later side, so in effect the later time)
//   lastMissedAt    -> "lastMissedAt", .max
//   confusionsData  -> "confusions", .counterMap ([String: Int] tally as an object of counters; entries <= 0 dropped on read)
//
// MatchingRound (no id; record name from date|topic|pairCount|firstTryCount|durationSeconds)
//   date            -> "date", .lww (find key)
//   topic           -> "topic", .lww (find key)
//   pairCount       -> "pairCount", .lww
//   firstTryCount   -> "firstTryCount", .lww
//   durationSeconds -> "durationSeconds", .lww
//
// ArticleWordStat
//   key             -> "key", .lww (identity: names the record, used by find; set on insert only)
//   noun            -> "noun", .lww
//   articleRaw      -> "articleRaw", .lww
//   english         -> "english", .lww
//   timesSeen       -> "timesSeen", .counter
//   timesMissed     -> "timesMissed", .counter
//   firstTryStreak  -> "firstTryStreak", SyncFieldGroup [firstTryStreak, lastSeenAt] ordered by lastSeenAt
//   lastSeenAt      -> "lastSeenAt", same SyncFieldGroup (whole from the later side, so in effect the later time)
//   lastMissedAt    -> "lastMissedAt", .max
//   wrongPicksData  -> "wrongPicks", .counterMap ([String: Int] tally as an object of counters; entries <= 0 dropped on read)
//
// ArticleRound (no id; record name from date|topic|questionCount|firstTryCount|durationSeconds)
//   date            -> "date", .lww (find key)
//   topic           -> "topic", .lww (find key)
//   questionCount   -> "questionCount", .lww
//   firstTryCount   -> "firstTryCount", .lww
//   durationSeconds -> "durationSeconds", .lww
//
// PrepositionStat
//   key             -> "key", .lww (identity: names the record, used by find; set on insert only)
//   word            -> "word", .lww
//   caseRaw         -> "caseRaw", .lww
//   meaning         -> "meaning", .lww
//   timesSeen       -> "timesSeen", .counter
//   timesMissed     -> "timesMissed", .counter
//   firstTryStreak  -> "firstTryStreak", SyncFieldGroup [firstTryStreak, lastSeenAt] ordered by lastSeenAt
//   lastSeenAt      -> "lastSeenAt", same SyncFieldGroup (whole from the later side, so in effect the later time)
//   lastMissedAt    -> "lastMissedAt", .max
//   wrongPicksData  -> "wrongPicks", .counterMap ([String: Int] tally as an object of counters; entries <= 0 dropped on read)
//
// PrepositionRound (no id; record name from date|topic|questionCount|firstTryCount|durationSeconds)
//   date            -> "date", .lww (find key)
//   topic           -> "topic", .lww (find key)
//   questionCount   -> "questionCount", .lww
//   firstTryCount   -> "firstTryCount", .lww
//   durationSeconds -> "durationSeconds", .lww
