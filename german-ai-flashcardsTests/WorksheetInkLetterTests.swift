//
//  WorksheetInkLetterTests.swift
//  german-ai-flashcardsTests
//
//  Handwriting at a closed-set blank (Services/Worksheet/InkLetterReading.swift,
//  WorksheetInkReader.read): a matching exercise's letter is folded and voted into one of the
//  sheet's letters, ink is never dropped because Vision read nothing, and her answer key is drawn
//  on the slide only when asked (WorksheetRenderer.drawKey).
//

import CoreGraphics
import Foundation
import PDFKit
import PencilKit
import Testing
@testable import Die_Kartei

@Suite struct WorksheetInkLetterTests {

    private let letters = ["A", "B", "C", "D", "E", "F"]

    // MARK: - Letters

    @Test func aReadingVotesForOneOfTheSheetsLetters() {
        #expect(InkLetterReading.vote("C", letters: letters) == "C")
        #expect(InkLetterReading.vote("ccc", letters: letters) == "C")
        // Vision answers in Cyrillic look-alikes: С, В, Е.
        #expect(InkLetterReading.vote("С С С", letters: letters) == "C")
        #expect(InkLetterReading.vote("ВBВ", letters: letters) == "B")
        #expect(InkLetterReading.vote("ЕЕЕ", letters: letters) == "E")
        #expect(InkLetterReading.vote("666", letters: letters) == nil)
        #expect(InkLetterReading.vote("CE", letters: letters) == nil, "a tie is no answer")
        #expect(InkLetterReading.vote("G", letters: letters) == nil, "not one of the sheet's letters")
    }

    @Test func onlyCleanCapitalsArePreAccepted() {
        #expect(InkLetterReading.isClean("CCC"))
        #expect(InkLetterReading.isClean("В В В"))
        // A lowercase run is how Vision misreads a capital (a D read as "aaa"): asked about.
        #expect(!InkLetterReading.isClean("aaa"))
        #expect(!InkLetterReading.isClean("CDC"))
        #expect(!InkLetterReading.isClean("666"))
    }

    @Test func readingsSnapToTheSheetsLetters() {
        #expect(WorksheetInkReader.snapLetters(["c", "6", "C"], to: letters) == ["C"])
        #expect(WorksheetInkReader.snapLetters(["(", "6"], to: letters).isEmpty)
        #expect(WorksheetInkReader.isLetters(letters))
        #expect(!WorksheetInkReader.isLetters(["dem", "der", "den"]))
        #expect(!WorksheetInkReader.isLetters([]))
    }

    @Test func tilingRepeatsTheGlyph() throws {
        let glyph = try #require(CGContext(data: nil, width: 20, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let tiled = try #require(InkLetterReading.tiled(glyph, times: 3))
        #expect(tiled.width > glyph.width * 3)
        #expect(tiled.height == glyph.height * 3)
    }

    @Test func picksAreTheLettersInOrderOrTheReadingsThenTheBank() {
        let letter = WorksheetInkReading(key: "k", page: 1, candidates: ["E"], confidence: 0.2, options: letters)
        #expect(WorksheetCheckView.picks(for: letter) == letters)
        let word = WorksheetInkReading(key: "k", page: 1, candidates: ["dem", "den"], confidence: 0.2,
                                       options: ["dem", "der", "den"])
        #expect(WorksheetCheckView.picks(for: word) == ["dem", "den", "der"])
        let unread = WorksheetInkReading(key: "k", page: 1, candidates: [], confidence: 0)
        #expect(unread.isUnread && !unread.isSure && unread.best.isEmpty)
    }

    // MARK: - Ink at a blank on the sample sheet

    private func part(_ number: Int) throws -> (WorksheetPagePart, PDFPage) {
        let document = try #require(PDFDocument(data: WorksheetSamplePDF.data()))
        let page = try #require(document.page(at: number - 1))
        let exercise = WorksheetPDFReader.parse(page: page, number: number, chrome: WorksheetPDFReader.chrome(of: document))
        let geometry = WorksheetPDFReader.geometry(of: exercise, on: page)
        return (WorksheetPagePart(exercise: exercise, geometry: geometry, bounds: page.bounds(for: .mediaBox)), page)
    }

    @Test func aBlanksOfferedAnswersComeFromItsSection() throws {
        let (part, _) = try part(2)
        let allowed = WorksheetCheckRunner.allowedAnswers(in: part.exercise)
        let gaps = part.exercise.items.flatMap(\.gaps)
        #expect(gaps.count == 4)
        for gap in gaps {
            #expect(Set(allowed[gap.key] ?? []) == ["dem", "der", "den"])
        }
    }

    /// A squiggle no recognizer reads as a word, written where the answer goes.
    private func squiggle(over area: CGRect) -> PKStroke {
        var points: [PKStrokePoint] = []
        for step in 0...12 {
            let x = area.minX + area.width * 0.2 + CGFloat(step) * 3
            let y = area.midY + (step.isMultiple(of: 2) ? -6 : 6)
            points.append(PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: Double(step) * 0.02,
                                        size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }

    /// A straight stroke from `a` to `b`.
    private func line(_ a: CGPoint, _ b: CGPoint) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: a, timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: b, timeOffset: 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ], creationDate: .now))
    }

    @Test func eachStrokeBelongsToTheOneBlankItSitsOnMost() {
        // Two rows of a matching table, regions overlapping where a tall letter rides up.
        let row1 = CGRect(x: 100, y: 100, width: 80, height: 40)
        let row2 = CGRect(x: 100, y: 130, width: 80, height: 40)
        // Row 2's letter reaches up into row 1's region, but mostly sits in its own.
        let tall = line(CGPoint(x: 120, y: 135), CGPoint(x: 120, y: 168))
        let low = line(CGPoint(x: 110, y: 104), CGPoint(x: 150, y: 120))
        let owned = WorksheetInkReader.assign([tall, low], to: [("r1", row1), ("r2", row2)])
        #expect(owned["r1"]?.count == 1)
        #expect(owned["r2"]?.count == 1)
        #expect(owned["r2"]?.first?.renderBounds.minY ?? 0 > 130)
        // Ink near no blank belongs to none.
        #expect(WorksheetInkReader.assign([line(CGPoint(x: 500, y: 500), CGPoint(x: 520, y: 510))],
                                          to: [("r1", row1)]).isEmpty)
    }

    @Test func inkAtABlankIsNeverDroppedEvenWhenNothingIsRead() throws {
        let (part, _) = try part(2)
        let gap = try #require(part.exercise.items.first?.gaps.first)
        let area = try #require(WorksheetInkReader.region(for: gap.key, part: part))
        let ink = PKDrawing(strokes: [squiggle(over: area)]).dataRepresentation()
        let readings = WorksheetInkReader.read(ink: ink, page: 2, part: part, keys: part.exercise.items.flatMap(\.gaps).map(\.key),
                                               allowed: WorksheetCheckRunner.allowedAnswers(in: part.exercise))
        let reading = try #require(readings.first { $0.key == gap.key }, "the inked blank came back")
        #expect(readings.count == 1, "only the inked blank")
        #expect(Set(reading.options) == ["dem", "der", "den"])
        // Read or not, it isn't pre-accepted: a squiggle is no word from the bank.
        #expect(!reading.isSure)
    }

    // MARK: - Her answers on the slide

    /// How many pixels in `rect` (page points) are her green.
    private func greenPixels(in image: CGImage, rect: CGRect, pageBounds: CGRect) throws -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / pageBounds.width
        // Page space is y-up like the bitmap context; rows in memory run top-down.
        let minX = max(0, Int((rect.minX - pageBounds.minX) * scale)), maxX = min(width, Int((rect.maxX - pageBounds.minX) * scale))
        let minY = max(0, Int((rect.minY - pageBounds.minY) * scale)), maxY = min(height, Int((rect.maxY - pageBounds.minY) * scale))
        var count = 0
        for y in minY..<max(minY, maxY) {
            let row = height - 1 - y
            for x in minX..<max(minX, maxX) {
                let i = (row * width + x) * 4
                let (r, g, b) = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
                if g > 90, g > r + 40, g > b + 40 { count += 1 }
            }
        }
        return count
    }

    @Test func herAnswersAreDrawnBesideTheBlankOnlyWhenShown() throws {
        let (part, page) = try part(2)
        let gap = try #require(part.exercise.items.first?.gaps.first)
        let rect = try #require(part.geometry?.gaps[gap.key])
        var input = WorksheetRenderer.Input(exercise: part.exercise, geometry: part.geometry)
        let beside = CGRect(x: rect.maxX, y: rect.minY - rect.height, width: rect.height * 8, height: rect.height * 3)

        let plain = try #require(WorksheetRenderer.pageImage(page: page, input: input, width: 960, scale: 1))
        #expect(try greenPixels(in: plain, rect: beside, pageBounds: part.bounds) == 0)

        input.herAnswers = [gap.key: WorksheetRenderer.KeyAnswer(text: "dem", isExample: false)]
        let shown = try #require(WorksheetRenderer.pageImage(page: page, input: input, width: 960, scale: 1))
        #expect(try greenPixels(in: shown, rect: beside, pageBounds: part.bounds) > 20)
    }

    @Test func theExportHasNoPlaceForHerAnswers() throws {
        // The snapshot the teacher's PDF is made from carries answers and check marks, never her
        // key: what she gets back is the learner's work.
        let snapshot = WorksheetExport.Snapshot(pdfData: WorksheetSamplePDF.data(), materialID: UUID(), title: "Beispiel",
                                                pages: [WorksheetPagePlan(page: 2, mode: .pencil, title: "D1")], answers: [:])
        let mirror = Mirror(reflecting: snapshot)
        #expect(!mirror.children.contains { $0.label?.lowercased().contains("key") == true || $0.label == "herAnswers" })
    }
}
