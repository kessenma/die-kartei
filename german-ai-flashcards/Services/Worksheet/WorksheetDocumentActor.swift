//
//  WorksheetDocumentActor.swift
//  german-ai-flashcards
//
//  The handout's PDF while a worksheet is open: parsed pages and rendered previews, both off the
//  main thread. The `PDFDocument` is built inside the actor and never handed out — the same
//  arrangement as `PDFPageThumbnailRenderer`, and for the same reason: an actor serializing every
//  PDFKit call is the only thread-safety claim about PDFKit worth relying on.
//
//  Parses are cached per page (cheap, but the work screen asks on every page turn); renders are
//  not (a slide preview is a few megabytes and only one is on screen; docs/MEMORY.md).
//

import CoreGraphics
import Foundation
import PDFKit

actor WorksheetDocumentActor {
    private let data: Data
    private var document: PDFDocument?
    private var chrome: Set<String>?
    private var parsed: [Int: WorksheetPagePart] = [:]

    init(data: Data) {
        self.data = data
    }

    private func opened() -> PDFDocument? {
        if let document { return document }
        document = PDFDocument(data: data)
        return document
    }

    var pageCount: Int { opened()?.pageCount ?? 0 }

    /// Every page parsed, for the setup screen. Fills the per-page cache on the way.
    func allPages() -> [WorksheetExercise] {
        guard let document = opened() else { return [] }
        let exercises = WorksheetPDFReader.parse(document)
        chrome = chrome ?? WorksheetPDFReader.chrome(of: document)
        for exercise in exercises where parsed[exercise.page] == nil {
            if let page = document.page(at: exercise.page - 1) {
                parsed[exercise.page] = part(exercise, on: page)
            }
        }
        return exercises
    }

    /// The teacher's answer key from the document's "Lösungen" pages, matched to its exercises.
    func answerKey() -> WorksheetKeyReading {
        guard let document = opened() else { return WorksheetKeyReading() }
        return WorksheetKeyReader.read(pages: WorksheetPDFReader.pageTexts(of: document),
                                       exercises: WorksheetPDFReader.parse(document))
    }

    /// One page parsed with the document's chrome known, and placed. Nil past the last page.
    func page(_ number: Int) -> WorksheetPagePart? {
        if let hit = parsed[number] { return hit }
        guard let document = opened(), let page = document.page(at: number - 1) else { return nil }
        let chrome = chrome ?? WorksheetPDFReader.chrome(of: document)
        self.chrome = chrome
        let exercise = WorksheetPDFReader.parse(page: page, number: number, chrome: chrome)
        let made = part(exercise, on: page)
        parsed[number] = made
        return made
    }

    private func part(_ exercise: WorksheetExercise, on page: PDFPage) -> WorksheetPagePart {
        WorksheetPagePart(
            exercise: exercise,
            geometry: exercise.isExercise ? WorksheetPDFReader.geometry(of: exercise, on: page) : nil,
            bounds: page.bounds(for: .mediaBox)
        )
    }

    /// The page as she'll get it back: answers in, ink on top.
    func render(page number: Int, answers: [String: WorksheetAnswer], ink: Data?,
                width: CGFloat, scale: CGFloat, outlinesGaps: Bool = false) -> CGImage? {
        guard let part = page(number), let page = opened()?.page(at: number - 1) else { return nil }
        let input = WorksheetRenderer.Input(
            exercise: part.exercise.isExercise ? part.exercise : nil,
            geometry: part.geometry,
            answers: answers,
            ink: ink,
            outlinesGaps: outlinesGaps
        )
        return WorksheetRenderer.pageImage(page: page, input: input, width: width, scale: scale)
    }
}

/// One page's parse and where its parts sit, as the views and the Pencil's background use it.
nonisolated struct WorksheetPagePart: Sendable {
    var exercise: WorksheetExercise
    var geometry: WorksheetGeometry?
    var bounds: CGRect
}
