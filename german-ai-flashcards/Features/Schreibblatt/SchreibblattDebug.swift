//
//  SchreibblattDebug.swift
//  german-ai-flashcards
//
//  The launch arguments and the two self-verifiers for the writing sheet. DEBUG only.
//
//  The verifiers exist because what matters most here cannot be unit-tested. A PDF that opens but
//  is blank, or upside down, passes every assertion about the layout; and the ink store is
//  FileManager, which the test target does not touch. Both follow
//  `DeckImporter.runDebugVerification`: pass/FAIL strings, and a refusal to pass vacuously — an
//  empty sheet renders perfectly while proving nothing.
//
//  `-schreibblatt.debugVerifyPDF` is the one to run **on the Mac**: Core Graphics is why this
//  feature has a PDF there at all, and the test target is iOS-only.
//

#if DEBUG
import Foundation
import PDFKit
import SwiftData

#if canImport(PencilKit)
import PencilKit
#endif

// MARK: - Which screen to open

/// `-schreibblatt.debugOpen hub|wahl|blatt|fertig`
enum SchreibblattDebugOpen: String, Identifiable, CaseIterable {
    case hub
    case wahl
    /// The newest sheet, canvas and all. Needs one to exist — pair it with
    /// `-schreibblatt.debugSeed 1`, since a sheet cannot be made without tapping.
    case blatt
    /// The finish screen (die Figur cheering, the writing numbers), which otherwise sits at the
    /// end of a whole set.
    case fertig

    var id: String { rawValue }

    init?(argument: String) {
        self.init(rawValue: argument.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

// MARK: - Seeding

enum SchreibblattDebugSeeder {

    /// The finish screen's numbers: the store's, or a made-up week of writing when this device
    /// has none yet, so `-schreibblatt.debugOpen fertig` always shows the card.
    @MainActor
    static func finishStats(in context: ModelContext) -> SchreibblattStats {
        let real = SchreibblattStats.load(in: context)
        guard real.stats.isEmpty else { return real }
        let now = Date()
        let words = ["das Haus", "der Hund", "die Stadt", "das Buch", "der Löffel"]
            .map { SchreibblattStats.Sheet.Word(id: UUID(), german: $0) }
        let day = Calendar.current.startOfDay(for: now)
        return SchreibblattStats(
            sheets: [
                .init(loggedAt: now.addingTimeInterval(-900), words: words, repetitions: 5, strokes: 212),
                .init(loggedAt: now.addingTimeInterval(-86_400), words: Array(words.prefix(3)), repetitions: 5, strokes: 140),
            ],
            days: (0..<4).map { .init(start: day.addingTimeInterval(Double(-$0) * 86_400), words: 5 + $0) },
            now: now)
    }

    /// `-schreibblatt.debugSeed 1` — a sheet with a few strokes already on it, so the canvas, the
    /// "begonnen" badge and the ink-in-PDF path can be seen without an Apple Pencil.
    @MainActor
    static func seed(in context: ModelContext) -> SchreibblattSheet {
        let words = [
            SchreibblattWord(german: "das Haus", english: "the house"),
            SchreibblattWord(german: "der Hund", english: "the dog"),
            SchreibblattWord(german: "die Stadt", english: "the city"),
            SchreibblattWord(german: "das Buch", english: "the book"),
            SchreibblattWord(german: "der Löffel", english: "the spoon"),
        ]
        // `-schreibblatt.debugLandscape 1` seeds it on its side, the tables two by two.
        let orientation: SchreibblattOrientation =
            UserDefaults.standard.bool(forKey: "schreibblatt.debugLandscape") ? .landscape : .portrait
        let sheet = SchreibblattSheet(title: "Probeblatt", words: words,
                                      repetitions: 5, prefillEnglish: true, orientation: orientation)
        context.insert(sheet)

        #if canImport(PencilKit)
        // One scrawl per row of the first writing table, roughly where a hand would put it.
        let layout = sheet.layout
        if let table = layout.tables.first(where: { !$0.isVorlage }) {
            let strokes = table.rows.map { row -> PKStroke in
                let start = CGPoint(x: row.germanCell.minX + 12, y: row.baselineY)
                let points = stride(from: 0.0, through: 120.0, by: 8.0).map { dx in
                    PKStrokePoint(
                        location: CGPoint(x: start.x + dx,
                                          y: start.y - (dx.truncatingRemainder(dividingBy: 24) - 12) * 0.4),
                        timeOffset: dx / 400, size: CGSize(width: 3, height: 3),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                return PKStroke(ink: PKInk(.pen, color: .blue),
                                path: PKStrokePath(controlPoints: points, creationDate: Date()))
            }
            let drawing = PKDrawing(strokes: strokes)
            sheet.saveInk(drawing.dataRepresentation(), strokeCount: strokes.count)
        }
        #endif

        try? context.save()
        return sheet
    }

    /// The newest sheet, for `-schreibblatt.debugOpen blatt`.
    @MainActor
    static func newest(in context: ModelContext) -> SchreibblattSheet? {
        var descriptor = FetchDescriptor<SchreibblattSheet>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

// MARK: - The PDF round trip

extension SchreibblattPDF {

    /// `-schreibblatt.debugVerifyPDF 1` — write a sheet, read the bytes back with PDFKit, and
    /// check the things only a real PDF can answer: the page count and box, that the Vorlage's
    /// German is on the paper and a writing table's is not, and that the words come out in
    /// reading order. That last one is the only check that catches an upside-down page, because
    /// mirrored text extracts perfectly well.
    static func runDebugVerification() -> String {
        let words = [
            SchreibblattWord(german: "das Haus", english: "the house"),
            SchreibblattWord(german: "der Hund", english: "the dog"),
            SchreibblattWord(german: "die Stadt", english: "the city"),
            SchreibblattWord(german: "das Buch", english: "the book"),
            SchreibblattWord(german: "der Löffel", english: "the spoon"),
        ]
        let title = "Schreibblatt Probe"
        let layout = SchreibblattLayout(words: words, repetitions: 5, prefillEnglish: true)

        // Refuse a vacuous pass: an empty sheet would sail through everything below.
        guard layout.pageCount > 1, layout.wordCount == words.count else {
            return "[schreibblatt] FAIL: the probe sheet is \(layout.pageCount) page(s) of "
                + "\(layout.wordCount) word(s); it must paginate to prove anything"
        }

        guard let data = data(layout: layout, title: title) else {
            return "[schreibblatt] FAIL: the writer produced no bytes"
        }
        guard let pdf = PDFDocument(data: data) else {
            return "[schreibblatt] FAIL: \(data.count) bytes that PDFKit will not open"
        }
        guard pdf.pageCount == layout.pageCount else {
            return "[schreibblatt] FAIL: \(pdf.pageCount) PDF pages for \(layout.pageCount) sheet pages"
        }

        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else {
                return "[schreibblatt] FAIL: no page \(index)"
            }
            let box = page.bounds(for: .mediaBox)
            guard abs(box.width - layout.paper.size.width) < 0.5,
                  abs(box.height - layout.paper.size.height) < 0.5 else {
                return "[schreibblatt] FAIL: page \(index) is \(box.size), expected \(layout.paper.size)"
            }

            let text = page.string ?? ""
            guard text.contains(title) else {
                return "[schreibblatt] FAIL: page \(index) has no header"
            }

            let vorlagen = layout.tables(onPage: index).filter(\.isVorlage).count
            for word in words {
                guard text.contains(word.english) else {
                    return "[schreibblatt] FAIL: page \(index) is missing \"\(word.english)\""
                }
                let germans = text.components(separatedBy: word.german).count - 1
                guard germans == vorlagen else {
                    return "[schreibblatt] FAIL: \"\(word.german)\" appears \(germans)x on page "
                        + "\(index), expected \(vorlagen) — a writing table is giving the answer away"
                }
            }

            // Reading order. This is the flip check.
            let positions = words.compactMap { text.range(of: $0.english)?.lowerBound }
            guard positions.count == words.count, positions == positions.sorted() else {
                return "[schreibblatt] FAIL: page \(index) extracts out of order — the page is flipped"
            }
        }

        return "[schreibblatt] PDF ok: \(pdf.pageCount) pages, \(data.count) bytes, "
            + "\(layout.tables.count) tables, reading order intact"
    }
}

// MARK: - The ink round trip

extension SchreibblattInkStore {

    /// `-schreibblatt.debugVerifyInk 1` — save, read back, overwrite in place, delete. FileManager,
    /// so this cannot be a unit test; and the overwrite check is the one that matters, because a
    /// fresh UUID per autosave would quietly fill Application Support with dead ink.
    static func runDebugVerification() -> String {
        let first = Data("first".utf8)
        let second = Data("second, and longer".utf8)

        guard let name = save(first) else {
            return "[schreibblatt] FAIL: the first write did not land"
        }
        guard exists(name) else {
            return "[schreibblatt] FAIL: saved as \(name), but nothing is there"
        }
        guard read(name) == first else {
            delete(name)
            return "[schreibblatt] FAIL: what came back is not what went in"
        }

        guard overwrite(second, as: name) else {
            delete(name)
            return "[schreibblatt] FAIL: the overwrite did not land"
        }
        guard read(name) == second else {
            delete(name)
            return "[schreibblatt] FAIL: the overwrite did not replace the bytes"
        }

        // The orphan sweep must see a file nothing names, and not one that is named.
        guard orphans(keeping: []).contains(name) else {
            delete(name)
            return "[schreibblatt] FAIL: the orphan sweep missed \(name)"
        }
        guard !orphans(keeping: [name]).contains(name) else {
            delete(name)
            return "[schreibblatt] FAIL: the orphan sweep would delete a file still in use"
        }

        delete(name)
        guard !exists(name) else {
            return "[schreibblatt] FAIL: \(name) survived its delete"
        }

        return "[schreibblatt] ink ok: save, read, overwrite in place, orphan sweep, delete"
    }
}
#endif
