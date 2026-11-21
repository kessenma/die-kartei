//
//  WorksheetExportTests.swift
//  german-ai-flashcardsTests
//
//  The homework PDF (Services/Worksheet/WorksheetExport.swift + WorksheetRenderer.swift), read
//  back with PDFKit: only the worked pages, each at its own size, and every answer's text found
//  inside the gap it was written into — the check that catches a flipped or shifted context, since
//  a mirrored or misplaced answer still extracts perfectly well as text.
//

import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import Die_Kartei

@Suite struct WorksheetExportTests {

    private let source = WorksheetSamplePDF.data()

    private func plan(_ page: Int) -> WorksheetPagePlan {
        WorksheetPagePlan(page: page, mode: .answer, title: "Seite \(page)")
    }

    /// The source page parsed the way the export parses it.
    private func exercise(_ number: Int, in document: PDFDocument) throws -> (WorksheetExercise, WorksheetGeometry) {
        let page = try #require(document.page(at: number - 1))
        let exercise = WorksheetPDFReader.parse(page: page, number: number,
                                                chrome: WorksheetPDFReader.chrome(of: document))
        return (exercise, WorksheetPDFReader.geometry(of: exercise, on: page))
    }

    @Test func onlyTheWorkedPagesInTheirOrder() throws {
        let snapshot = WorksheetExport.Snapshot(pdfData: source, materialID: UUID(), title: "Beispiel",
                                                pages: [plan(5), plan(2)], answers: [:])
        let data = try #require(WorksheetExport.pdf(snapshot))
        let exported = try #require(PDFDocument(data: data))
        #expect(exported.pageCount == 2)
        for index in 0..<exported.pageCount {
            #expect(exported.page(at: index)?.bounds(for: .mediaBox).size == CGSize(width: 960, height: 540))
        }
        #expect(exported.page(at: 0)?.string?.contains("DATIV D1") == true)
        #expect(exported.page(at: 1)?.string?.contains("SÄTZE VERBINDEN") == true)
    }

    @Test func answersLandInTheirGaps() throws {
        let document = try #require(PDFDocument(data: source))
        let (d1, d1Geometry) = try exercise(2, in: document)
        let gaps = d1.items.flatMap(\.gaps)
        #expect(gaps.count == 4)
        // Words that occur nowhere on the slide, so finding them finds the answer.
        let words = ["Quax", "Wolm", "Zirp", "Fexo"]
        var answers: [String: WorksheetAnswer] = [:]
        for (gap, word) in zip(gaps, words) { answers[gap.key] = WorksheetAnswer(text: word) }

        let snapshot = WorksheetExport.Snapshot(pdfData: source, materialID: UUID(), title: "Beispiel",
                                                pages: [plan(2)], answers: answers)
        let data = try #require(WorksheetExport.pdf(snapshot))
        let exported = try #require(PDFDocument(data: data))
        let page = try #require(exported.page(at: 0))
        for (gap, word) in zip(gaps, words) {
            let found = try #require(exported.findString(word, withOptions: []).first, "\(word) not in the export")
            let box = found.bounds(for: page)
            let gapRect = try #require(d1Geometry.gaps[gap.key])
            #expect(abs(box.midY - gapRect.midY) < gapRect.height, "\(word) at \(box), gap at \(gapRect)")
            #expect(abs(box.midX - gapRect.midX) < gapRect.width, "\(word) at \(box), gap at \(gapRect)")
        }
    }

    @Test func choicesAndSentencesReachTheirPages() throws {
        let document = try #require(PDFDocument(data: source))
        let (ak1, _) = try exercise(4, in: document)
        let (g2, g2Geometry) = try exercise(5, in: document)
        let choice = try #require(ak1.items.first?.choices.first)
        let sentenceItem = try #require(g2.items.first)
        let answers: [String: WorksheetAnswer] = [
            choice.key: WorksheetAnswer(choice: 1),
            sentenceItem.writeKey: WorksheetAnswer(text: "Wegen des Regens bleiben wir Plimbo."),
        ]
        let snapshot = WorksheetExport.Snapshot(pdfData: source, materialID: UUID(), title: "Beispiel",
                                                pages: [plan(4), plan(5)], answers: answers)
        let data = try #require(WorksheetExport.pdf(snapshot))
        let exported = try #require(PDFDocument(data: data))
        let sentencePage = try #require(exported.page(at: 1))
        let found = try #require(exported.findString("Plimbo", withOptions: []).first)
        // Under the item it answers, not on top of it.
        let itemBox = try #require(g2Geometry.items[sentenceItem.key])
        #expect(found.bounds(for: sentencePage).maxY < itemBox.minY + 2)
    }

    // MARK: - Sync

    /// Answers merge blank by blank (`ClassMaterialCodec`: `.keyed(item: .lwwBy("at"))`): a gap
    /// filled on the iPad and another on the Mac both survive, and when both edited the same gap
    /// the later edit wins whichever device saved last.
    @MainActor
    @Test func answersMergeBlankByBlank() throws {
        func payload(_ answers: [String: WorksheetAnswer], savedAt: Double) -> SyncPayload {
            var fields = SyncFields()
            fields.set("worksheetAnswers", jsonData: WorksheetCoding.encode(answers))
            var out = fields.payload
            out[SyncPayloadKey.modifiedAt] = .number(savedAt)
            return out
        }
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        let ancestor = payload(["a": WorksheetAnswer(text: "der", at: t0)], savedAt: 1)
        // The iPad answers a again (later) and fills b; the Mac fills c and saves last.
        let pad = payload(["a": WorksheetAnswer(text: "dem", at: t0 + 90),
                           "b": WorksheetAnswer(text: "die", at: t0 + 60)], savedAt: 2)
        let mac = payload(["a": WorksheetAnswer(text: "den", at: t0 + 30),
                           "c": WorksheetAnswer(choice: 1, at: t0 + 40)], savedAt: 3)
        let merged = SyncMerge.merge(ancestor: ancestor, local: pad, remote: mac, spec: ClassMaterialCodec.spec)
        #expect(merged == SyncMerge.merge(ancestor: ancestor, local: mac, remote: pad, spec: ClassMaterialCodec.spec))
        let answers = try #require(WorksheetCoding.decode([String: WorksheetAnswer].self,
                                                          from: merged.jsonData("worksheetAnswers")))
        #expect(answers["a"]?.text == "dem")
        #expect(answers["b"]?.text == "die")
        #expect(answers["c"]?.choice == 1)
    }

    @Test func handwritingReadingsArentTypedOverTheInk() throws {
        // An answer read from the Pencil ink and confirmed is graded, but the ink is what goes on
        // the page: the reading must not be typed in on top of it.
        let document = try #require(PDFDocument(data: source))
        let (d1, _) = try exercise(2, in: document)
        let gaps = d1.items.flatMap(\.gaps)
        let answers: [String: WorksheetAnswer] = [
            gaps[0].key: WorksheetAnswer(text: "Quax", source: .ink),
            gaps[1].key: WorksheetAnswer(text: "Wolm", source: .typed),
        ]
        let snapshot = WorksheetExport.Snapshot(pdfData: source, materialID: UUID(), title: "Beispiel",
                                                pages: [plan(2)], answers: answers)
        let data = try #require(WorksheetExport.pdf(snapshot))
        let exported = try #require(PDFDocument(data: data))
        #expect(exported.findString("Quax", withOptions: []).isEmpty)
        #expect(!exported.findString("Wolm", withOptions: []).isEmpty)
    }

    @Test func checkMarksOnlyWhenAskedFor() throws {
        let document = try #require(PDFDocument(data: source))
        let (d1, _) = try exercise(2, in: document)
        let gap = try #require(d1.items.first?.gaps.first)
        var answer = WorksheetAnswer(text: "der")
        answer.check = WorksheetCheck(outcome: .wrong, correction: "Zorbem", reason: nil, by: .rules, answer: "der")
        var snapshot = WorksheetExport.Snapshot(pdfData: source, materialID: UUID(), title: "Beispiel",
                                                pages: [plan(2)], answers: [gap.key: answer])
        let plainData = try #require(WorksheetExport.pdf(snapshot))
        let plain = try #require(PDFDocument(data: plainData))
        #expect(plain.findString("Zorbem", withOptions: []).isEmpty)
        snapshot.showsChecks = true
        let markedData = try #require(WorksheetExport.pdf(snapshot))
        let marked = try #require(PDFDocument(data: markedData))
        #expect(!marked.findString("Zorbem", withOptions: []).isEmpty)
        #expect(WorksheetExport.fileName(for: "Beispiel", checked: true).hasSuffix("-geprueft.pdf"))
    }

    @Test func fileNamesSurviveAnyTitle() {
        #expect(WorksheetExport.fileName(for: "Präpositionen & Artikel").hasSuffix("-bearbeitet.pdf"))
        #expect(!WorksheetExport.fileName(for: "a/b:c").contains("/"))
    }
}
