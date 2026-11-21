//
//  SchreibblattPDFTests.swift
//  german-ai-flashcardsTests
//
//  The writing sheet's PDF (Services/SchreibblattPDF.swift) and the arithmetic inside its
//  renderer (Services/SchreibblattRenderer.swift): that the bytes are a PDF with one page per
//  layout page at A4's media box, that the Vorlage's German reaches the paper and a writing
//  table's never does, that the text extracts top to bottom — the check that catches a botched
//  coordinate flip, since mirrored text extracts perfectly well — and that shrink-to-fit converges.
//
//  PDFKit is used here only to read back what Core Graphics wrote. The same round trip runs as
//  `-schreibblatt.debugVerifyPDF 1` on a device and on the Mac, where this target does not build;
//  what it adds there is the real platform rather than another assertion. Ink is not covered
//  either way: it needs a `PKDrawing` from a Pencil, which is what -schreibblatt.debugVerifyInk
//  seeds. See docs/SCHREIBBLATT.md.
//

import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import Die_Kartei

@Suite struct SchreibblattPDFTests {

    // MARK: - Fixtures

    /// Five, like the teacher asks for: at the A4 defaults that is genuinely two pages, so the
    /// suite exercises pagination rather than only ever writing one page.
    static let words: [SchreibblattWord] = [
        .init(german: "das Haus", english: "the house"),
        .init(german: "der Hund", english: "the dog"),
        .init(german: "die Stadt", english: "the city"),
        .init(german: "das Buch", english: "the book"),
        .init(german: "der Löffel", english: "the spoon"),
    ]

    private func sheet(
        words: [SchreibblattWord] = SchreibblattPDFTests.words,
        repetitions: Int = 5,
        prefillEnglish: Bool = true
    ) -> SchreibblattLayout {
        SchreibblattLayout(words: words, repetitions: repetitions, prefillEnglish: prefillEnglish)
    }

    private func document(
        _ layout: SchreibblattLayout, title: String = "Schreibblatt"
    ) throws -> PDFDocument {
        let data = try #require(SchreibblattPDF.data(layout: layout, title: title),
                                "the writer produced no bytes")
        return try #require(PDFDocument(data: data), "the bytes are not a PDF")
    }

    // MARK: - The bytes are a real PDF

    @Test func theRulingChangesNoTextOnThePaper() throws {
        let layout = sheet()
        let plain = try document(layout)
        let data = try #require(SchreibblattPDF.data(layout: layout, title: "Schreibblatt", lines: true))
        let ruled = try #require(PDFDocument(data: data))
        #expect(ruled.pageCount == plain.pageCount)
        #expect(ruled.page(at: 0)?.string == plain.page(at: 0)?.string)
    }

    @Test func theSheetWritesOnePDFPagePerLayoutPage() throws {
        let layout = sheet()
        let pdf = try document(layout)
        #expect(layout.pageCount > 1, "the default sheet should exercise pagination")
        #expect(pdf.pageCount == layout.pageCount)
    }

    @Test func everyPageIsA4() throws {
        let pdf = try document(sheet())
        for index in 0..<pdf.pageCount {
            let page = try #require(pdf.page(at: index))
            let box = page.bounds(for: .mediaBox)
            #expect(abs(box.width - 595.2) < 0.5, "page \(index) is \(box.width)pt wide")
            #expect(abs(box.height - 841.8) < 0.5, "page \(index) is \(box.height)pt tall")
        }
    }

    @Test func anEmptySheetProducesNoFileRatherThanABlankOne() {
        // A vacuous PDF would pass every other check in this suite while proving nothing.
        #expect(SchreibblattPDF.data(layout: sheet(words: []), title: "x") == nil)
        #expect(SchreibblattPDF.data(layout: sheet(repetitions: 0), title: "x") == nil)
    }

    // MARK: - What reaches the paper

    @Test func everyEnglishWordIsPrintedOnEveryPage() throws {
        let layout = sheet()
        let pdf = try document(layout)
        for index in 0..<pdf.pageCount {
            let text = try #require(pdf.page(at: index)?.string)
            for word in Self.words {
                #expect(text.contains(word.english),
                        "\"\(word.english)\" is missing from page \(index)")
            }
        }
    }

    @Test func theGermanIsGivenOnceAsTheVorlageAndNeverOnAWritingTable() throws {
        let layout = sheet(repetitions: 3)
        let pdf = try document(layout)
        for index in 0..<pdf.pageCount {
            let text = try #require(pdf.page(at: index)?.string)
            let vorlagen = layout.tables(onPage: index).filter(\.isVorlage).count
            for word in Self.words {
                // Exactly as many copies as there are Vorlagen on the page: the writing tables
                // leave the German column blank, which is the whole point of the drill.
                let found = text.components(separatedBy: word.german).count - 1
                #expect(found == vorlagen,
                        "\"\(word.german)\" appears \(found)x on page \(index), expected \(vorlagen)")
            }
        }
    }

    @Test func turningOffPrefillLeavesOnlyTheVorlagesEnglish() throws {
        let layout = sheet(repetitions: 3, prefillEnglish: false)
        let pdf = try document(layout)
        for index in 0..<pdf.pageCount {
            let text = try #require(pdf.page(at: index)?.string)
            let vorlagen = layout.tables(onPage: index).filter(\.isVorlage).count
            for word in Self.words {
                let found = text.components(separatedBy: word.english).count - 1
                #expect(found == vorlagen,
                        "\"\(word.english)\" appears \(found)x on page \(index), expected \(vorlagen)")
            }
        }
    }

    @Test func theTitleAndPageNumberArePrintedOnEveryPage() throws {
        let layout = sheet()
        let pdf = try document(layout, title: "Lektion 4")
        for index in 0..<pdf.pageCount {
            let text = try #require(pdf.page(at: index)?.string)
            #expect(text.contains("Lektion 4"))
            #expect(text.contains("\(index + 1) / \(layout.pageCount)"))
        }
    }

    @Test func theVorlageIsLabelledAndThePassesAreNumbered() throws {
        let layout = sheet(repetitions: 3)
        let pdf = try document(layout)
        let joined = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        #expect(joined.contains("Vorlage"))
        for pass in 1...3 {
            #expect(joined.contains("\(pass)"), "pass \(pass) is unlabelled")
        }
    }

    // MARK: - The coordinate flip

    @Test func wordsExtractTopToBottomSoTheFlipIsRightSideUp() throws {
        // Mirrored text still extracts fine, so only the *order* catches a botched flip: the
        // Vorlage's own rows must come out in the order they were given.
        let layout = sheet(repetitions: 1)
        let pdf = try document(layout)
        let text = try #require(pdf.page(at: 0)?.string)
        let positions = Self.words.compactMap { text.range(of: $0.english)?.lowerBound }
        #expect(positions.count == Self.words.count)
        #expect(positions == positions.sorted(),
                "the rows came back out of order — the page is flipped or the rows are")
    }

    @Test func theTitleExtractsAboveTheFirstRow() throws {
        let pdf = try document(sheet(repetitions: 1), title: "Kopfzeile")
        let text = try #require(pdf.page(at: 0)?.string)
        let title = try #require(text.range(of: "Kopfzeile"))
        let firstRow = try #require(text.range(of: Self.words[0].english))
        #expect(title.lowerBound < firstRow.lowerBound, "the header is not at the top")
    }

    // MARK: - File naming

    @Test func theFileNameSurvivesATitleFullOfPunctuation() {
        // Umlauts are alphanumeric, so they survive; only the punctuation collapses.
        #expect(SchreibblattPDF.fileName(for: "Lektion 4: Möbel / Küche") == "Lektion-4-Möbel-Küche.pdf")
        #expect(SchreibblattPDF.fileName(for: "") == "schreibblatt.pdf")
        #expect(SchreibblattPDF.fileName(for: "🙂🙂") == "schreibblatt.pdf")
        #expect(SchreibblattPDF.fileName(for: String(repeating: "a", count: 80)).count == 44)
        // The deck exporter's own fallback is untouched.
        #expect(DeckTransfer.fileStem("***") == "deck")
    }

    // MARK: - Shrink to fit

    @Test func textThatAlreadyFitsKeepsItsSize() {
        #expect(SchreibblattRenderer.fittedSize(measuredWidth: 50, available: 100, base: 13) == 13)
        #expect(SchreibblattRenderer.fittedSize(measuredWidth: 100, available: 100, base: 13) == 13)
    }

    @Test func textThatOverflowsShrinksInProportionAndNeverGrows() {
        // Twice as wide as the cell, so half the size. Base 26 rather than the sheet's 13,
        // because half of 13 is 6.5 and the 7pt floor would be what is actually under test.
        let half = SchreibblattRenderer.fittedSize(measuredWidth: 200, available: 100, base: 26)
        #expect(half == 13)
        // At the sheet's own size the floor takes over, which is the point of having one.
        #expect(SchreibblattRenderer.fittedSize(measuredWidth: 200, available: 100, base: 13) == 7)
        for measured in stride(from: 101.0, through: 400.0, by: 7.0) {
            let size = SchreibblattRenderer.fittedSize(
                measuredWidth: measured, available: 100, base: 13)
            #expect(size <= 13, "shrink-to-fit grew the text")
            #expect(size >= 7, "shrink-to-fit went under the floor")
        }
    }

    @Test func shrinkToFitStopsAtTheFloorHoweverLongTheWord() {
        let size = SchreibblattRenderer.fittedSize(
            measuredWidth: 10_000, available: 10, base: 13, floor: 7)
        #expect(size == 7)
    }

    @Test func shrinkToFitConvergesInOneStepRatherThanOscillating() {
        // Rounding down to a tenth is what guarantees this: a size that rounded up could measure
        // wide again and shrink forever.
        let base: CGFloat = 13
        let measured: CGFloat = 183
        let available: CGFloat = 100
        let once = SchreibblattRenderer.fittedSize(
            measuredWidth: measured, available: available, base: base)
        // Width scales with point size, so re-measuring at the new size gives this.
        let remeasured = measured * (once / base)
        #expect(remeasured <= available)
        #expect(SchreibblattRenderer.fittedSize(
            measuredWidth: remeasured, available: available, base: once) == once)
    }

    @Test func degenerateMeasurementsDoNotProduceAZeroOrNegativeSize() {
        for (measured, available) in [(0.0, 100.0), (100.0, 0.0), (0.0, 0.0), (-5.0, 100.0)] {
            let size = SchreibblattRenderer.fittedSize(
                measuredWidth: measured, available: available, base: 13)
            #expect(size >= 7)
        }
    }
}
