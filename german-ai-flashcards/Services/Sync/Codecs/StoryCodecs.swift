import Foundation
import SwiftData

// MARK: - StudyStory

/// An AI-written story: its text, questions and glossary, plus the learner's marks on it.
/// - The content is written by the device that generated it, so it merges field by field and the
///   later edit wins where both sides changed one. `englishText` is filled in on first reveal, on
///   whichever device that happens.
/// - `bestScore` takes the higher score, so a quiz finished on either device counts.
///   `generationComplete` is true once either side says so.
/// - Looked-up words merge as a set keyed by the German form, ignoring case (the dedup
///   `recordLookup` uses): a word looked up on either device is kept, one swiped away is removed.
///   The model keeps them newest first, but the entries carry no date, so a merged list comes back
///   in alphabetical order. Any copy from another device is merged, even one that left the words
///   alone.
/// - `images` lists the illustrations' file names. The PNGs sync separately under the same names,
///   in the story's image folder, which is named by the story id both devices share.
/// - `deckIDRaw` points at the story's deck by id, the same on every device. If both devices create
///   that deck before either syncs, the later link wins and the other deck keeps its words, unlinked.
/// - A story still being written stays on this device: every list hides it, and a stopped or
///   failed generation deletes it. It syncs from the moment it completes.
/// - The `@Transient` decode caches never travel.
enum StudyStoryCodec: SyncCodec {
    typealias Model = StudyStory

    static let spec = SyncKindSpec(
        kind: "StudyStory",
        rules: [
            "bestScore": .max,
            "generationComplete": .or,
            "lookups": .set(idField: "german", lowercasedID: true),
        ]
    )

    static func recordName(for model: StudyStory) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func includes(_ story: StudyStory) -> Bool { story.generationComplete }

    static func known(_ s: StudyStory) -> SyncPayload {
        var f = SyncFields()
        f.set("id", s.id)
        f.set("createdAt", s.createdAt)
        f.set("title", s.title)
        f.set("topic", s.topic)
        f.set("levelRaw", s.levelRaw)
        f.set("genreRaw", s.genreRaw)
        f.set("storyText", s.storyText)
        f.set("englishText", s.englishText)
        f.set("glossary", jsonData: s.glossaryData)
        f.set("questions", jsonData: s.questionsData)
        f.set("speakers", jsonData: s.speakersData)
        f.set("images", jsonData: s.imagesData)
        f.set("lookups", jsonData: s.lookupsData)
        f.set("modelRaw", s.modelRaw)
        f.set("deckIDRaw", s.deckIDRaw)
        f.set("generationComplete", s.generationComplete)
        f.set("bestScore", s.bestScore)
        f.set("lastStudiedAsListening", s.lastStudiedAsListening)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> StudyStory? {
        let id = name.id
        var d = FetchDescriptor<StudyStory>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> StudyStory? {
        let story = StudyStory(
            topic: flat.string("topic") ?? "",
            level: flat.string("levelRaw").flatMap { CEFRLevel(rawValue: $0) } ?? .a2,
            genre: .alltag
        )
        story.id = name.id
        context.insert(story)
        update(story, from: flat, in: context)
        return story
    }

    static func update(_ s: StudyStory, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("createdAt") { s.createdAt = v }
        if let v = flat.string("title") { s.title = v }
        if let v = flat.string("topic") { s.topic = v }
        if let v = flat.string("levelRaw") { s.levelRaw = v }
        s.genreRaw = flat.string("genreRaw")
        if let v = flat.string("storyText") { s.storyText = v }
        s.englishText = flat.string("englishText")
        s.glossaryData = flat.jsonData("glossary")
        s.questionsData = flat.jsonData("questions")
        s.speakersData = flat.jsonData("speakers")
        s.imagesData = flat.jsonData("images")
        s.lookupsData = flat.jsonData("lookups")
        s.modelRaw = flat.string("modelRaw")
        s.deckIDRaw = flat.string("deckIDRaw")
        if let v = flat.bool("generationComplete") { s.generationComplete = v }
        s.bestScore = flat.int("bestScore")
        if let v = flat.bool("lastStudiedAsListening") { s.lastStudiedAsListening = v }
    }
}

// MARK: - StoryReadingSession

/// One stretch of reading or listening. Append-only, so rows from both devices simply add up.
/// `storyID` is a plain id, not a relationship: the row outlives its story, so it lands whether or
/// not the story is on this device.
enum StoryReadingSessionCodec: SyncCodec {
    typealias Model = StoryReadingSession

    static let spec = SyncKindSpec(kind: "StoryReadingSession")

    static func recordName(for model: StoryReadingSession) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ r: StoryReadingSession) -> SyncPayload {
        var f = SyncFields()
        f.set("id", r.id)
        f.set("date", r.date)
        f.set("storyID", r.storyID)
        f.set("storyTitle", r.storyTitle)
        f.set("levelRaw", r.levelRaw)
        f.set("seconds", r.seconds)
        f.set("wasListening", r.wasListening)
        f.set("lookups", r.lookups)
        f.set("wordsSaved", r.wordsSaved)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> StoryReadingSession? {
        let id = name.id
        var d = FetchDescriptor<StoryReadingSession>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> StoryReadingSession? {
        let session = StoryReadingSession(
            storyID: flat.uuid("storyID") ?? UUID(),
            storyTitle: flat.string("storyTitle") ?? "",
            levelRaw: flat.string("levelRaw") ?? "",
            seconds: flat.int("seconds") ?? 0,
            wasListening: flat.bool("wasListening") ?? false,
            lookups: flat.int("lookups") ?? 0,
            wordsSaved: flat.int("wordsSaved") ?? 0,
            date: flat.date("date") ?? .now
        )
        session.id = name.id
        context.insert(session)
        update(session, from: flat, in: context)
        return session
    }

    static func update(_ r: StoryReadingSession, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { r.date = v }
        if let v = flat.uuid("storyID") { r.storyID = v }
        if let v = flat.string("storyTitle") { r.storyTitle = v }
        if let v = flat.string("levelRaw") { r.levelRaw = v }
        if let v = flat.int("seconds") { r.seconds = v }
        if let v = flat.bool("wasListening") { r.wasListening = v }
        if let v = flat.int("lookups") { r.lookups = v }
        if let v = flat.int("wordsSaved") { r.wordsSaved = v }
    }
}

// MARK: - StoryQuizAttempt

/// One finished comprehension quiz. Append-only, so rows from both devices simply add up.
/// `storyID` is a plain id, not a relationship, as for `StoryReadingSession`.
enum StoryQuizAttemptCodec: SyncCodec {
    typealias Model = StoryQuizAttempt

    static let spec = SyncKindSpec(kind: "StoryQuizAttempt")

    static func recordName(for model: StoryQuizAttempt) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ q: StoryQuizAttempt) -> SyncPayload {
        var f = SyncFields()
        f.set("id", q.id)
        f.set("date", q.date)
        f.set("storyID", q.storyID)
        f.set("storyTitle", q.storyTitle)
        f.set("levelRaw", q.levelRaw)
        f.set("questionCount", q.questionCount)
        f.set("correctCount", q.correctCount)
        f.set("durationSeconds", q.durationSeconds)
        f.set("wasListening", q.wasListening)
        f.set("writtenCount", q.writtenCount)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> StoryQuizAttempt? {
        let id = name.id
        var d = FetchDescriptor<StoryQuizAttempt>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> StoryQuizAttempt? {
        let attempt = StoryQuizAttempt(
            storyID: flat.uuid("storyID") ?? UUID(),
            storyTitle: flat.string("storyTitle") ?? "",
            levelRaw: flat.string("levelRaw") ?? "",
            questionCount: flat.int("questionCount") ?? 0,
            correctCount: flat.int("correctCount") ?? 0,
            durationSeconds: flat.int("durationSeconds") ?? 0,
            wasListening: flat.bool("wasListening") ?? false,
            writtenCount: flat.int("writtenCount") ?? 0
        )
        attempt.id = name.id
        context.insert(attempt)
        update(attempt, from: flat, in: context)
        return attempt
    }

    static func update(_ q: StoryQuizAttempt, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("date") { q.date = v }
        if let v = flat.uuid("storyID") { q.storyID = v }
        if let v = flat.string("storyTitle") { q.storyTitle = v }
        if let v = flat.string("levelRaw") { q.levelRaw = v }
        if let v = flat.int("questionCount") { q.questionCount = v }
        if let v = flat.int("correctCount") { q.correctCount = v }
        if let v = flat.int("durationSeconds") { q.durationSeconds = v }
        if let v = flat.bool("wasListening") { q.wasListening = v }
        if let v = flat.int("writtenCount") { q.writtenCount = v }
    }
}

// MARK: - StudyPaper

/// A paper or photo scan the learner imported to study: its text, summary, key points and
/// questions, merged field by field, the later edit winning where both sides changed one.
/// - `generationComplete` is true once either side says so. An unfinished paper travels too:
///   either device can finish it from the paper's screen.
/// - `fullText` can be long; the transport moves a large payload to an asset.
/// - A scan's `photo://` source is only a marker (it names no file), so it travels as is.
/// Nothing is left out.
enum StudyPaperCodec: SyncCodec {
    typealias Model = StudyPaper

    static let spec = SyncKindSpec(kind: "StudyPaper", rules: ["generationComplete": .or])

    static func recordName(for model: StudyPaper) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ p: StudyPaper) -> SyncPayload {
        var f = SyncFields()
        f.set("id", p.id)
        f.set("title", p.title)
        f.set("createdAt", p.createdAt)
        f.set("fullText", p.fullText)
        f.set("sourceURL", p.sourceURL)
        f.set("germanSummary", p.germanSummary)
        f.set("keyPoints", p.keyPoints)
        f.set("questions", jsonData: p.questionsData)
        f.set("deckIDRaw", p.deckIDRaw)
        f.set("modelRaw", p.modelRaw)
        f.set("generationComplete", p.generationComplete)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> StudyPaper? {
        let id = name.id
        var d = FetchDescriptor<StudyPaper>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> StudyPaper? {
        let paper = StudyPaper(title: flat.string("title") ?? "", fullText: flat.string("fullText") ?? "")
        paper.id = name.id
        context.insert(paper)
        update(paper, from: flat, in: context)
        return paper
    }

    static func update(_ p: StudyPaper, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.string("title") { p.title = v }
        if let v = flat.date("createdAt") { p.createdAt = v }
        if let v = flat.string("fullText") { p.fullText = v }
        p.sourceURL = flat.string("sourceURL")
        p.germanSummary = flat.string("germanSummary")
        if let v = flat.strings("keyPoints") { p.keyPoints = v }
        p.questionsData = flat.jsonData("questions")
        p.deckIDRaw = flat.string("deckIDRaw")
        p.modelRaw = flat.string("modelRaw")
        if let v = flat.bool("generationComplete") { p.generationComplete = v }
    }
}

// Field coverage:
//
// StudyStory (kind "StudyStory", id-based, bootstrap .shared, includes only generationComplete rows)
//   id                      -> "id" (record name; .lww, never changes)
//   createdAt               -> "createdAt" .lww
//   title                   -> "title" .lww
//   topic                   -> "topic" .lww
//   levelRaw                -> "levelRaw" .lww
//   genreRaw                -> "genreRaw" .lww
//   storyText               -> "storyText" .lww
//   englishText             -> "englishText" .lww
//   glossaryData            -> "glossary" (jsonData, [GlossaryEntry]) .lww
//   questionsData           -> "questions" (jsonData, [StoryQuestion]) .lww
//   speakersData            -> "speakers" (jsonData, [StorySpeaker]) .lww
//   imagesData              -> "images" (jsonData, [StoryImageRecord]) .lww; PNGs sync separately
//                              under Application Support/StoryImages/<story id>/<fileName>
//   lookupsData             -> "lookups" (jsonData, [GlossaryEntry]) .set(idField: "german", lowercasedID: true)
//   modelRaw                -> "modelRaw" .lww
//   deckIDRaw               -> "deckIDRaw" .lww (soft link to SavedDeck.id)
//   generationComplete      -> "generationComplete" .or (only ever set true, by StoryStudyService)
//   bestScore               -> "bestScore" .max
//   lastStudiedAsListening  -> "lastStudiedAsListening" .lww
//   questionsCache, glossaryCache, speakersCache, imagesCache, lookupsCache
//                           -> EXCLUDED: @Transient decode caches, rebuilt from the blobs on read
//
// StoryReadingSession (kind "StoryReadingSession", id-based, bootstrap .shared, append-only)
//   id            -> "id" (record name; .lww)
//   date          -> "date" .lww
//   storyID       -> "storyID" .lww (soft link to StudyStory.id, no parent)
//   storyTitle    -> "storyTitle" .lww
//   levelRaw      -> "levelRaw" .lww
//   seconds       -> "seconds" .lww
//   wasListening  -> "wasListening" .lww
//   lookups       -> "lookups" .lww (an Int tally for this one stretch, not a counter)
//   wordsSaved    -> "wordsSaved" .lww
//
// StoryQuizAttempt (kind "StoryQuizAttempt", id-based, bootstrap .shared, append-only)
//   id               -> "id" (record name; .lww)
//   date             -> "date" .lww
//   storyID          -> "storyID" .lww (soft link to StudyStory.id, no parent)
//   storyTitle       -> "storyTitle" .lww
//   levelRaw         -> "levelRaw" .lww
//   questionCount    -> "questionCount" .lww
//   correctCount     -> "correctCount" .lww
//   durationSeconds  -> "durationSeconds" .lww
//   wasListening     -> "wasListening" .lww
//   writtenCount     -> "writtenCount" .lww
//
// StudyPaper (kind "StudyPaper", id-based, bootstrap .shared, unfinished papers included)
//   id                  -> "id" (record name; .lww)
//   title               -> "title" .lww
//   createdAt           -> "createdAt" .lww
//   fullText            -> "fullText" .lww (large; the transport moves big payloads to an asset)
//   sourceURL           -> "sourceURL" .lww
//   germanSummary       -> "germanSummary" .lww
//   keyPoints           -> "keyPoints" ([String]) .lww
//   questionsData       -> "questions" (jsonData, [StudyQuestion]) .lww
//   deckIDRaw           -> "deckIDRaw" .lww (soft link to SavedDeck.id)
//   modelRaw            -> "modelRaw" .lww
//   generationComplete  -> "generationComplete" .or (only ever set true, by PaperStudyService)
