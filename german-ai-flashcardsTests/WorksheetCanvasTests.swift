//
//  WorksheetCanvasTests.swift
//  german-ai-flashcardsTests
//
//  The Pencil canvas's geometry (Features/ClassNotes/Worksheet/WorksheetCanvas.swift). PencilKit
//  zooms its own ink and nothing else, so the slide behind it has to be scaled by hand; these
//  tests hold that, and that the page fits and centres in the space it gets instead of sitting in
//  the top-left corner at its own size — both seen on a device before this existed.
//

#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit
@testable import Die_Kartei

@MainActor
@Suite struct WorksheetCanvasTests {

    private let pageSize = CGSize(width: 960, height: 540)

    /// The coordinator is returned so the caller holds it: the canvas's delegate is weak, and in
    /// the app SwiftUI is what keeps it alive.
    private func make(size: CGSize, notes: WorksheetNotesMargins = WorksheetNotesMargins(), ink: Data? = nil)
        -> (WorksheetCanvas.FittingContainer, PKCanvasView, WorksheetSlideView, WorksheetCanvas.Coordinator) {
        let exercise = WorksheetExercise(page: 1, verdict: .notExercise, title: "", subtitle: nil, instruction: nil,
                                         sections: [], nouns: [], notes: [], answerKeyRef: nil, hasTypedAnswers: false)
        let part = WorksheetPagePart(exercise: exercise, geometry: nil, bounds: CGRect(origin: .zero, size: pageSize))
        let coordinator = WorksheetCanvas.Coordinator(materialID: UUID(), page: 1, pageSize: pageSize, notes: notes,
                                                      onSaved: {})
        let container = WorksheetCanvas.build(coordinator: coordinator, ink: ink, pdfData: WorksheetSamplePDF.data(),
                                              page: 1, part: part, answers: [:])
        container.frame = CGRect(origin: .zero, size: size)
        container.layoutIfNeeded()
        return (container, coordinator.canvas!, coordinator.slide!, coordinator)
    }

    @Test func aWideScreenFitsTheWholePageAndCentresIt() throws {
        let (_, canvas, slide, coordinator) = make(size: CGSize(width: 1366, height: 900))
        defer { withExtendedLifetime(coordinator) {} }
        let fit = min(1366 / pageSize.width, 900 / pageSize.height)
        #expect(abs(canvas.zoomScale - fit) < 0.001)
        // The slide is scaled with the ink, not left at the page's own size.
        #expect(abs(slide.frame.width - pageSize.width * fit) < 1)
        #expect(abs(canvas.contentSize.width - pageSize.width * fit) < 1)
        // Narrower than the screen's height allows: centred top to bottom.
        let free = 900 - pageSize.height * fit
        #expect(abs(canvas.contentInset.top - free / 2) < 1)
    }

    @Test func zoomingKeepsTheSlideUnderTheInk() throws {
        let (container, canvas, slide, coordinator) = make(size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(coordinator) {} }
        canvas.setZoomScale(2.5, animated: false)
        container.layoutIfNeeded()
        #expect(abs(slide.frame.width - pageSize.width * 2.5) < 1)
        #expect(abs(slide.frame.height - pageSize.height * 2.5) < 1)
        #expect(slide.frame.origin == .zero)
        #expect(abs(canvas.contentSize.width - pageSize.width * 2.5) < 1)
        // Crisper after the zoom, but never past the memory cap.
        #expect(slide.contentScaleFactor <= 4)
    }

    // MARK: Notes paper

    private func stroke(at point: CGPoint) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: point.x + 40, y: point.y + 10), timeOffset: 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ], creationDate: Date()))
    }

    @Test func notesPaperGrowsTheSheetAndTheSlideSitsAtItsOffset() throws {
        let notes = WorksheetNotesMargins(left: true, top: true)
        let (container, canvas, slide, coordinator) = make(size: CGSize(width: 1000, height: 700), notes: notes)
        defer { withExtendedLifetime(coordinator) {} }
        container.layoutIfNeeded()
        let sheet = coordinator.sheetSize
        #expect(abs(sheet.width - pageSize.width * 1.6) < 0.5)
        #expect(abs(sheet.height - pageSize.height * 1.6) < 0.5)
        // The whole sheet fits, and the slide sits right and below the paper on its left and top.
        let zoom = canvas.zoomScale
        #expect(abs(zoom - min(1000 / sheet.width, 700 / sheet.height)) < 0.001)
        #expect(abs(slide.frame.minX - pageSize.width * 0.6 * zoom) < 1)
        #expect(abs(slide.frame.minY - pageSize.height * 0.6 * zoom) < 1)
        #expect(abs(canvas.contentSize.width - sheet.width * zoom) < 1)
    }

    @Test func theFileAlwaysHoldsInkInTheSlidesOwnPoints() throws {
        let ink = PKDrawing(strokes: [stroke(at: CGPoint(x: 100, y: 100))]).dataRepresentation()
        let (container, canvas, _, coordinator) = make(size: CGSize(width: 1000, height: 700),
                                                       notes: WorksheetNotesMargins(left: true), ink: ink)
        defer { withExtendedLifetime(container) {} }
        // On the sheet the ink moves right by the paper on the left...
        let shown = canvas.drawing.bounds
        #expect(abs(shown.minX - (100 + pageSize.width * 0.6)) < 4)
        // ...and goes back to the slide's points for the file, the export and the check.
        #expect(abs(coordinator.onSlide(canvas.drawing).bounds.minX - 100) < 4)
        // Taking the paper away (or adding more) keeps it on the same spot of the slide.
        coordinator.setNotes(WorksheetNotesMargins(top: true, bottom: true))
        #expect(abs(canvas.drawing.bounds.minX - 100) < 4)
        #expect(abs(canvas.drawing.bounds.minY - (100 + pageSize.height * 0.6)) < 4)
        #expect(abs(coordinator.onSlide(canvas.drawing).bounds.minY - 100) < 4)
        #expect(canvas.undoManager?.canUndo == false)
    }

    // MARK: The Pencil controls (Features/Shared/Pencil)

    @Test func theHighlighterIsAToolOfItsOwnAndTheEraserGoesBackToIt() throws {
        let (_, canvas, _, coordinator) = make(size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(coordinator) {} }
        let pencil = try #require(canvas as? PencilCanvasView)
        let board = PencilBoard()
        board.attach(pencil)
        board.tool = .highlighter
        let marker = try #require(pencil.tool as? PKInkingTool)
        #expect(marker.inkType == .marker)
        board.toggleEraser()
        #expect(pencil.tool is PKEraserTool)
        board.toggleEraser()
        #expect(board.tool == .highlighter)
        // A colour cycle changes the highlighter's colour while it is in hand, not the pen's.
        let pen = board.pen
        let saved = PencilHighlighter.stored
        defer { saved.store() }
        board.perform(.nextColour)
        #expect(board.pen == pen)
        #expect(board.highlighter.shade != saved.shade || PencilHighlighter.Shade.allCases.count == 1)
    }

    @Test func theCanvasUndoesOnItsOwnStack() throws {
        let (_, canvas, _, coordinator) = make(size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(coordinator) {} }
        let pencil = try #require(canvas as? PencilCanvasView)
        let undo = try #require(pencil.undoManager)
        #expect(pencil.undoManager === undo)

        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: CGPoint(x: 10, y: 10), timeOffset: 0, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 90, y: 40), timeOffset: 0.1, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ], creationDate: Date()))
        pencil.drawing = PKDrawing(strokes: [stroke])
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        pencil.replaceDrawing(PKDrawing())
        undo.endUndoGrouping()
        #expect(pencil.drawing.strokes.isEmpty)
        pencil.undo()
        #expect(pencil.drawing.strokes.count == 1)
        pencil.redo()
        #expect(pencil.drawing.strokes.isEmpty)
    }

    @Test func theBoardSetsTheCanvasTool() throws {
        let (_, canvas, _, coordinator) = make(size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(coordinator) {} }
        let pencil = try #require(canvas as? PencilCanvasView)
        let board = PencilBoard()
        board.attach(pencil)
        #expect(pencil.tool is PKInkingTool)
        board.tool = .eraser
        #expect(pencil.tool is PKEraserTool)
        #expect(pencil.drawingPolicy == (board.wristGuard ? .pencilOnly : .anyInput))
        board.toggleEraser()
        #expect(pencil.tool is PKInkingTool)
        board.detach(pencil)
        board.tool = .eraser
        #expect(pencil.tool is PKInkingTool)  // a detached canvas no longer follows the board
    }
}
#endif
