import Foundation
import SwiftData

/// Calendar dates in the Deutschkurs models (an entry's day, homework due, a course's start and
/// end) are stored as local midnight. They travel as `yyyy-MM-dd`, not as instants, so a class
/// held on Monday is on Monday on every device, and "today's entry" (an equality on local
/// midnight) still matches on a device in another time zone.
private enum ClassDayKey {
    static func key(_ date: Date?) -> String? {
        date.map { SyncDayKey.key(for: Calendar.current.startOfDay(for: $0)) }
    }

    static func date(_ key: String?) -> Date? {
        key.flatMap { SyncDayKey.dayStart(for: $0) }
    }
}

// MARK: - ClassCourse

/// A course's own fields. Its entries sync as their own records and hang off it.
/// - Every field is last-writer-wins, three-way, so renaming the course on one device and
///   archiving it on the other both land.
/// - `updatedAt` takes the later time: it only orders the hub, and the course worked on last on
///   either device should list first.
/// - `startDate` and `endDate` travel as calendar dates (`ClassDayKey`).
/// - `deckIDRaw` travels: the course deck syncs as a `SavedDeck` under the same id. If both
///   devices create the deck (first word saved) before either syncs, the later link wins and the
///   other deck keeps its words and its course, as a second deck on it.
/// Nothing is left out.
enum ClassCourseCodec: SyncCodec {
    typealias Model = ClassCourse

    static let spec = SyncKindSpec(kind: "ClassCourse", rules: ["updatedAt": .max])

    static func recordName(for model: ClassCourse) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func known(_ c: ClassCourse) -> SyncPayload {
        var f = SyncFields()
        f.set("id", c.id)
        f.set("createdAt", c.createdAt)
        f.set("updatedAt", c.updatedAt)
        f.set("name", c.name)
        f.set("kindRaw", c.kindRaw)
        f.set("teacher", c.teacher)
        f.set("teacherEmail", c.teacherEmail)
        f.set("courseURL", c.courseURL)
        f.set("goal", c.goal)
        f.set("levelRaw", c.levelRaw)
        f.set("startDay", ClassDayKey.key(c.startDate))
        f.set("endDay", ClassDayKey.key(c.endDate))
        f.set("isArchived", c.isArchived)
        f.set("deckIDRaw", c.deckIDRaw)
        f.set("sortOrder", c.sortOrder)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ClassCourse? {
        fetchCourse(id: name.id, in: context)
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ClassCourse? {
        let course = ClassCourse(name: flat.string("name") ?? "")
        course.id = name.id
        context.insert(course)
        update(course, from: flat, in: context)
        return course
    }

    static func update(_ c: ClassCourse, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("createdAt") { c.createdAt = v }
        if let v = flat.date("updatedAt") { c.updatedAt = v }
        if let v = flat.string("name") { c.name = v }
        if let v = flat.string("kindRaw") { c.kindRaw = v }
        c.teacher = flat.string("teacher")
        c.teacherEmail = flat.string("teacherEmail")
        c.courseURL = flat.string("courseURL")
        c.goal = flat.string("goal")
        c.levelRaw = flat.string("levelRaw")
        c.startDate = ClassDayKey.date(flat.string("startDay"))
        c.endDate = ClassDayKey.date(flat.string("endDay"))
        if let v = flat.bool("isArchived") { c.isArchived = v }
        c.deckIDRaw = flat.string("deckIDRaw")
        if let v = flat.int("sortOrder") { c.sortOrder = v }
    }

    /// Deleting a course cascades to its entries, and theirs to their handouts. The applier
    /// doesn't recurse, so the handouts are listed here too.
    static func cascadeChildren(of course: ClassCourse) -> [any PersistentModel] {
        var children: [any PersistentModel] = []
        for entry in course.entries {
            children.append(entry)
            for material in entry.materials { children.append(material) }
        }
        return children
    }

    static func fetchCourse(id: UUID, in context: ModelContext) -> ClassCourse? {
        var d = FetchDescriptor<ClassCourse>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
}

// MARK: - ClassEntry

/// One logged class. Its handouts sync as their own records and hang off it.
/// - `words` merges word by word (each `ClassWord` carries its own id): words added on either
///   device are all kept, and a word deleted on one device stays deleted unless the other edited
///   it. The words carry no position, so a merged list comes back in id order, not the order
///   they were typed. Any copy from another device is merged, even one that left the words alone.
/// - The title, notes, grammar points, topics and homework are last-writer-wins per field.
/// - `date` and `homeworkDue` travel as calendar dates (`ClassDayKey`).
/// - `updatedAt` takes the later time.
/// An entry without a course stays on this device: no other device could file it. Nothing else
/// is left out.
enum ClassEntryCodec: SyncCodec {
    typealias Model = ClassEntry

    static let spec = SyncKindSpec(
        kind: "ClassEntry",
        rules: [
            "updatedAt": .max,
            "words": .set(idField: "id"),
        ]
    )

    static func recordName(for model: ClassEntry) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func includes(_ entry: ClassEntry) -> Bool { entry.course != nil }

    static func known(_ e: ClassEntry) -> SyncPayload {
        var f = SyncFields()
        f.set("id", e.id)
        f.set("course", e.course?.id)
        f.set("createdAt", e.createdAt)
        f.set("updatedAt", e.updatedAt)
        f.set("day", ClassDayKey.key(e.date))
        f.set("title", e.title)
        f.set("notes", e.notes)
        f.set("grammarFocusRaws", e.grammarFocusRaws)
        f.set("topics", e.topics)
        f.set("words", jsonData: e.wordsData)
        f.set("homework", e.homework)
        f.set("homeworkDueDay", ClassDayKey.key(e.homeworkDue))
        f.set("homeworkDone", e.homeworkDone)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ClassEntry? {
        fetchEntry(id: name.id, in: context)
    }

    static func parent(of flat: SyncPayload) -> SyncRecordName? {
        flat.uuid("course").map { SyncRecordName(kind: ClassCourseCodec.spec.kind, id: $0) }
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ClassEntry? {
        guard let courseID = flat.uuid("course"),
              let course = ClassCourseCodec.fetchCourse(id: courseID, in: context) else {
            return nil
        }
        let entry = ClassEntry(date: ClassDayKey.date(flat.string("day")) ?? .now)
        entry.id = name.id
        context.insert(entry)
        entry.course = course
        update(entry, from: flat, in: context)
        return entry
    }

    static func update(_ e: ClassEntry, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("createdAt") { e.createdAt = v }
        if let v = flat.date("updatedAt") { e.updatedAt = v }
        if let v = ClassDayKey.date(flat.string("day")) { e.date = v }
        if let v = flat.string("title") { e.title = v }
        if let v = flat.string("notes") { e.notes = v }
        if let v = flat.strings("grammarFocusRaws") { e.grammarFocusRaws = v }
        if let v = flat.strings("topics") { e.topics = v }
        e.wordsData = flat.jsonData("words")
        if let v = flat.string("homework") { e.homework = v }
        e.homeworkDue = ClassDayKey.date(flat.string("homeworkDueDay"))
        if let v = flat.bool("homeworkDone") { e.homeworkDone = v }
    }

    static func cascadeChildren(of entry: ClassEntry) -> [any PersistentModel] {
        entry.materials
    }

    static func fetchEntry(id: UUID, in context: ModelContext) -> ClassEntry? {
        var d = FetchDescriptor<ClassEntry>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
}

// MARK: - ClassMaterial

/// A handout from class.
/// - `lookups` merges word by word, keyed on the German form case-insensitively (the dedup
///   `recordLookup` uses): words looked up on either device are all kept, one removed on either
///   is removed. The entries carry no date, so a merged list comes back in alphabetical order,
///   not newest first. Any copy from another device is merged, even one that left the words alone.
/// - The translation and the tutor that wrote it travel as one group, taken whole from one side,
///   so a translation is never credited to the other device's tutor. If both devices translated
///   at once, the later save wins whole; translating again fills in the sentences it lacks.
/// - `snapshotFile` travels as the file name; the PDF or photo itself syncs separately under the
///   same name in `ClassMaterialStore`.
/// - Everything else is last-writer-wins per field.
/// A handout stays on this device when its entry does (no entry, or an entry without a course):
/// no other device could file it. Nothing else is left out.
enum ClassMaterialCodec: SyncCodec {
    typealias Model = ClassMaterial

    static let spec = SyncKindSpec(
        kind: "ClassMaterial",
        rules: ["lookups": .set(idField: "german", lowercasedID: true)],
        groups: [SyncFieldGroup(fields: ["translation", "translationModelRaw"], orderBy: [])]
    )

    static func recordName(for model: ClassMaterial) -> SyncRecordName {
        SyncRecordName(kind: spec.kind, id: model.id)
    }

    static func includes(_ material: ClassMaterial) -> Bool {
        guard let entry = material.entry else { return false }
        return ClassEntryCodec.includes(entry)
    }

    static func known(_ m: ClassMaterial) -> SyncPayload {
        var f = SyncFields()
        f.set("id", m.id)
        f.set("entry", m.entry?.id)
        f.set("createdAt", m.createdAt)
        f.set("title", m.title)
        f.set("sourceKindRaw", m.sourceKindRaw)
        f.set("text", m.text)
        f.set("snapshotFile", m.snapshotFile)
        f.set("lookups", jsonData: m.lookupsData)
        f.set("modelRaw", m.modelRaw)
        f.set("glossaryDeckIDRaw", m.glossaryDeckIDRaw)
        f.set("translation", jsonData: m.translationData)
        f.set("translationModelRaw", m.translationModelRaw)
        return f.payload
    }

    static func find(_ name: SyncRecordName, flat: SyncPayload, in context: ModelContext) -> ClassMaterial? {
        let id = name.id
        var d = FetchDescriptor<ClassMaterial>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func parent(of flat: SyncPayload) -> SyncRecordName? {
        flat.uuid("entry").map { SyncRecordName(kind: ClassEntryCodec.spec.kind, id: $0) }
    }

    static func insert(_ flat: SyncPayload, name: SyncRecordName, in context: ModelContext) -> ClassMaterial? {
        guard let entryID = flat.uuid("entry"),
              let entry = ClassEntryCodec.fetchEntry(id: entryID, in: context) else {
            return nil
        }
        let material = ClassMaterial(title: flat.string("title") ?? "", text: flat.string("text") ?? "")
        material.id = name.id
        context.insert(material)
        material.entry = entry
        update(material, from: flat, in: context)
        return material
    }

    static func update(_ m: ClassMaterial, from flat: SyncPayload, in context: ModelContext) {
        if let v = flat.date("createdAt") { m.createdAt = v }
        if let v = flat.string("title") { m.title = v }
        if let v = flat.string("sourceKindRaw") { m.sourceKindRaw = v }
        if let v = flat.string("text") { m.text = v }
        m.snapshotFile = flat.string("snapshotFile")
        m.lookupsData = flat.jsonData("lookups")
        m.modelRaw = flat.string("modelRaw")
        m.glossaryDeckIDRaw = flat.string("glossaryDeckIDRaw")
        m.translationData = flat.jsonData("translation")
        m.translationModelRaw = flat.string("translationModelRaw")
    }
}

// Field coverage:
//
// ClassCourse
//   id            -> "id" .lww (also the record name)
//   createdAt     -> "createdAt" .lww
//   updatedAt     -> "updatedAt" .max
//   name          -> "name" .lww
//   kindRaw       -> "kindRaw" .lww
//   teacher       -> "teacher" .lww
//   teacherEmail  -> "teacherEmail" .lww
//   courseURL     -> "courseURL" .lww
//   goal          -> "goal" .lww
//   levelRaw      -> "levelRaw" .lww
//   startDate     -> "startDay" (yyyy-MM-dd) .lww
//   endDate       -> "endDay" (yyyy-MM-dd) .lww
//   isArchived    -> "isArchived" .lww
//   deckIDRaw     -> "deckIDRaw" .lww
//   sortOrder     -> "sortOrder" .lww
//   entries       -> relationship: each ClassEntry carries "course"; cascadeChildren (the
//                    entries and their materials)
//
// ClassEntry
//   id                -> "id" .lww (also the record name)
//   createdAt         -> "createdAt" .lww
//   updatedAt         -> "updatedAt" .max
//   date              -> "day" (yyyy-MM-dd) .lww
//   title             -> "title" .lww
//   notes             -> "notes" .lww
//   grammarFocusRaws  -> "grammarFocusRaws" .lww
//   topics            -> "topics" .lww
//   wordsData         -> "words" (JSON [ClassWord]: id, german, english, addedToDeck)
//                        .set(idField: "id")
//   homework          -> "homework" .lww
//   homeworkDue       -> "homeworkDueDay" (yyyy-MM-dd) .lww
//   homeworkDone      -> "homeworkDone" .lww
//   course            -> "course" (ClassCourse id) .lww; parent, linked on insert only (the app
//                        never moves an entry to another course)
//   materials         -> relationship: each ClassMaterial carries "entry"; cascadeChildren
//
// ClassMaterial
//   id                   -> "id" .lww (also the record name)
//   createdAt            -> "createdAt" .lww
//   title                -> "title" .lww
//   sourceKindRaw        -> "sourceKindRaw" .lww
//   text                 -> "text" .lww
//   snapshotFile         -> "snapshotFile" .lww (the file syncs separately)
//   lookupsData          -> "lookups" (JSON [GlossaryEntry]: german, english)
//                           .set(idField: "german", lowercasedID: true)
//   modelRaw             -> "modelRaw" .lww
//   glossaryDeckIDRaw    -> "glossaryDeckIDRaw" .lww
//   translationData      -> "translation" (JSON HandoutTranslation) .lww, group with
//                           translationModelRaw
//   translationModelRaw  -> "translationModelRaw" .lww, group with translation
//   entry                -> "entry" (ClassEntry id) .lww; parent, linked on insert only (the app
//                           never moves a handout to another entry)
