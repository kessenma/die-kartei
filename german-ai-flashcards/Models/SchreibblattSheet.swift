//
//  SchreibblattSheet.swift
//  german-ai-flashcards
//
//  One writing sheet: the words the learner picked, the knobs they set, and whatever they have
//  written on it so far. The drill the teacher recommends — a page of tables, the German given,
//  copied out again and again — kept so a half-finished page can be put down and picked up.
//
//  **The knobs and the words are frozen here.** The layout has to rebuild byte for byte or the
//  ink ends up sitting on the wrong rules, and a deck can be edited or deleted underneath a sheet.
//  That is also why `sourceDeckIDs` are ids rather than a relationship: deleting a deck must not
//  cascade into someone's handwriting.
//
//  **Local-only.** Not registered in `SyncRegistry`, so `SyncChangeTracker` skips it and the ink
//  never leaves the device that made it. A sheet is a device artifact — an iPad's pencil page
//  means nothing on a phone — and the bytes are megabytes. Registering it in `AppSchema` is the
//  whole cost. See docs/ICLOUD_SYNC.md and docs/SCHREIBBLATT.md.
//
//  Every property is defaulted or set in `init` so the entity is an additive migration (the app's
//  container deletes the store when a migration fails).
//

import Foundation
import SwiftData

@Model
final class SchreibblattSheet {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// Bumped on every save of the ink or the knobs, so the hub lists what is being worked on first.
    var updatedAt: Date = Date()
    /// What the learner called it, or the date it was made. Also the PDF's title and file name.
    var title: String = ""

    // MARK: - The knobs, frozen

    /// Writing tables. The Vorlage is the model to copy from and is never one of these.
    var repetitions: Int = 5
    /// Whether the English column is printed on the writing tables, or left blank to write too.
    var prefillEnglish: Bool = true
    /// Raw paper name, so Letter can arrive later without a migration: "a4" upright,
    /// "a4-landscape" on its side (see `orientation`).
    var paperRaw: String = "a4"
    /// `SchreibblattArrangement` raw value: "pages", or an endless sheet's grid.
    var arrangementRaw: String = "pages"
    /// Notebook ruling on the paper around the tables. Looks only, so it can change at any time.
    var notebookLines: Bool = false

    /// The English column's width in points, measured from the words at creation and frozen with
    /// them. 0 for sheets made before it was measured, which keep the fixed split.
    var englishColumnWidth: Double = 0

    /// `[SchreibblattWord]` as JSON. Frozen at creation — see the note above.
    var wordsData: Data? = nil
    /// `[UUID]` of the decks the words came from, for an "open the deck" link only.
    var sourceDeckIDsData: Data? = nil

    // MARK: - The ink

    /// Bare file name in `SchreibblattInkStore`; nil for a sheet never written on.
    var inkFileName: String? = nil
    /// How many strokes the ink holds. On the row so a list can say "worked on" without opening
    /// a file, which is what keeps `@Query` off the megabytes (docs/MEMORY.md).
    var strokeCount: Int = 0
    /// When the learner said Fertig. A finished sheet is locked (it scrolls and zooms, nothing
    /// writes) until it is opened again; nil while it is being worked on.
    var finishedAt: Date? = nil
    /// When its words went into the day's study log (`StudyDay.sheetWordsWritten`): the first
    /// Fertig only, so reopening and finishing again never counts the sheet twice.
    var loggedAt: Date? = nil

    // MARK: - One part of several

    /// Shared by every part of a big selection split into sheets (`SchreibblattParts`), all made
    /// at once; nil for a sheet on its own. The hub lists the parts as one row.
    var seriesID: UUID? = nil
    /// This sheet's place among the parts, from 0.
    var partIndex: Int = 0
    /// How many parts were made. A part deleted since is not subtracted; count the parts.
    var partCount: Int = 0
    /// The parts' shared name, without "Teil k von n": the deck's name, or the first word's.
    var seriesTitle: String = ""

    init(
        title: String,
        words: [SchreibblattWord],
        repetitions: Int,
        prefillEnglish: Bool,
        orientation: SchreibblattOrientation = .portrait,
        arrangement: SchreibblattArrangement = .pages,
        notebookLines: Bool = false,
        sourceDeckIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.title = title
        self.repetitions = repetitions
        self.prefillEnglish = prefillEnglish
        self.paperRaw = Self.paperRaw(for: orientation)
        self.arrangementRaw = arrangement.rawValue
        self.notebookLines = notebookLines
        self.englishColumnWidth = Double(SchreibblattRenderer.englishColumnWidth(
            for: words, prefillEnglish: prefillEnglish))
        self.wordsData = try? JSONEncoder().encode(words)
        self.sourceDeckIDsData = try? JSONEncoder().encode(sourceDeckIDs)
    }
}

// MARK: - Derived

extension SchreibblattSheet {
    /// The frozen words. Empty when the blob is missing or from a version that cannot be read,
    /// which `layout` then turns into an empty sheet rather than a broken one.
    var words: [SchreibblattWord] {
        guard let wordsData,
              let decoded = try? JSONDecoder().decode([SchreibblattWord].self, from: wordsData)
        else { return [] }
        return decoded
    }

    var sourceDeckIDs: [UUID] {
        guard let sourceDeckIDsData,
              let decoded = try? JSONDecoder().decode([UUID].self, from: sourceDeckIDsData)
        else { return [] }
        return decoded
    }

    /// Turning the page re-lays out every table, so a sheet with ink on it is never turned in
    /// place; the screen offers a blank copy the other way up instead.
    var orientation: SchreibblattOrientation {
        get { paperRaw == Self.paperRaw(for: .landscape) ? .landscape : .portrait }
        set { paperRaw = Self.paperRaw(for: newValue) }
    }

    static func paperRaw(for orientation: SchreibblattOrientation) -> String {
        switch orientation {
        case .portrait: "a4"
        case .landscape: "a4-landscape"
        }
    }

    var arrangement: SchreibblattArrangement {
        get { SchreibblattArrangement(rawValue: arrangementRaw) ?? .pages }
        set { arrangementRaw = newValue.rawValue }
    }

    /// Which way up and how the tables sit, together. Like the orientation, never changed in place
    /// once something is written.
    var format: SchreibblattFormat {
        get { SchreibblattFormat(orientation: orientation, arrangement: arrangement) }
        set {
            orientation = newValue.orientation
            arrangement = newValue.arrangement
        }
    }

    var paper: SchreibblattLayout.Paper {
        format.paper(wordCount: words.count, repetitions: repetitions)
    }

    /// Endless sheets are written on the iPad only: there is no paper to print them on.
    var canExport: Bool { !arrangement.isEndless }

    /// The geometry for this sheet. Rebuilt rather than stored, and deterministic from the frozen
    /// knobs — that is what lets the ink keep sitting where it was written.
    var layout: SchreibblattLayout {
        SchreibblattLayout(words: words, repetitions: repetitions, prefillEnglish: prefillEnglish,
                           englishColumnWidth: englishColumnWidth > 0 ? CGFloat(englishColumnWidth) : nil,
                           paper: paper)
    }

    var isFinished: Bool { finishedAt != nil }

    /// The words actually on the sheet: a selection bigger than a page keeps only what fits
    /// (`SchreibblattLayout` clamps the same way), so this is what was written, and what
    /// "practise these words" means.
    var writtenWords: [SchreibblattWord] {
        Array(words.prefix(SchreibblattLayout.maxWordCount(paper: paper)))
    }

    var isPart: Bool { seriesID != nil }

    /// "Teil 3 von 5".
    var partLabel: String { "Teil \(partIndex + 1) von \(max(partCount, partIndex + 1))" }

    /// Every part of this sheet's set, in order; just this sheet when it is on its own.
    func parts(in context: ModelContext) -> [SchreibblattSheet] {
        guard let target = seriesID else { return [self] }
        let id: UUID? = target
        let found = (try? context.fetch(FetchDescriptor<SchreibblattSheet>(
            predicate: #Predicate { $0.seriesID == id }))) ?? []
        return found.sorted { $0.partIndex < $1.partIndex }
    }

    /// Something has been written on this sheet.
    var hasInk: Bool { strokeCount > 0 && SchreibblattInkStore.exists(inkFileName) }

    /// The ink bytes, or nil for a blank sheet.
    var ink: Data? { SchreibblattInkStore.read(inkFileName) }

    /// How many times each word gets written, said the way the setup screen says it.
    var summary: String {
        let words = self.words.count
        let wordLabel = words == 1 ? "1 Wort" : "\(words) Wörter"
        let passLabel = repetitions == 1 ? "1×" : "\(repetitions)×"
        return "\(wordLabel) · \(passLabel)"
    }

    /// Store `data` as this sheet's ink, minting a file name on the first write and reusing it
    /// afterwards. False when the bytes did not land, in which case the sheet is left untouched
    /// rather than pointing at a file that is not there.
    @discardableResult
    func saveInk(_ data: Data, strokeCount: Int, now: Date = Date()) -> Bool {
        if let inkFileName, SchreibblattInkStore.exists(inkFileName) {
            guard SchreibblattInkStore.overwrite(data, as: inkFileName) else { return false }
        } else {
            guard let fileName = SchreibblattInkStore.save(data) else { return false }
            self.inkFileName = fileName
        }
        self.strokeCount = strokeCount
        self.updatedAt = now
        return true
    }

    /// The same words and knobs on a fresh page: to write the drill again, or the other way up.
    /// Not inserted; the caller does that.
    func blankCopy(format: SchreibblattFormat? = nil, now: Date = Date()) -> SchreibblattSheet {
        let format = format ?? self.format
        let copy = SchreibblattSheet(title: title, words: words, repetitions: repetitions,
                                     prefillEnglish: prefillEnglish,
                                     orientation: format.orientation, arrangement: format.arrangement,
                                     notebookLines: notebookLines,
                                     sourceDeckIDs: sourceDeckIDs, createdAt: now)
        // Byte for byte, not re-encoded or re-measured: the copy lays out exactly as this one.
        copy.wordsData = wordsData
        copy.englishColumnWidth = englishColumnWidth
        return copy
    }

    /// Called before the sheet is deleted: SwiftData does not own the ink file.
    func deleteInk() {
        SchreibblattInkStore.delete(inkFileName)
        inkFileName = nil
        strokeCount = 0
    }
}
