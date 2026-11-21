//
//  SchreibblattCanvasTests.swift
//  german-ai-flashcardsTests
//
//  The writing sheet on screen (Features/Schreibblatt/SchreibblattCanvas.swift) and the sheet's
//  frozen knobs (Models/SchreibblattSheet.swift). The page fits the space it gets, the width or the
//  whole page, centred, instead of sitting in the top-left corner at its own size; the rules zoom
//  with the ink, which PencilKit does not do for them; a blank sheet turns in place; and a sheet
//  keeps its orientation and measured column through a copy.
//

#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit
@testable import Die_Kartei

@MainActor
@Suite struct SchreibblattCanvasTests {

    static let words: [SchreibblattWord] = [
        .init(german: "das Haus", english: "the house"),
        .init(german: "der Hund", english: "the dog"),
        .init(german: "die Stadt", english: "the city"),
        .init(german: "das Buch", english: "the book"),
        .init(german: "der Löffel", english: "the spoon"),
    ]

    private func sheet(repetitions: Int = 5, paper: SchreibblattLayout.Paper = .a4) -> SchreibblattLayout {
        SchreibblattLayout(words: Self.words, repetitions: repetitions, prefillEnglish: true, paper: paper)
    }

    /// The coordinator is returned so the caller holds it: the canvas's delegate is weak, and in
    /// the app SwiftUI is what keeps it alive.
    private func make(_ layout: SchreibblattLayout, size: CGSize, fit: SchreibblattFit = .width)
        -> (SchreibblattCanvas.Container, PencilCanvasView, SchreibblattCanvas.Coordinator) {
        let coordinator = SchreibblattCanvas.Coordinator(layout: layout, fit: fit, onChange: { _, _ in })
        let container = SchreibblattCanvas.build(coordinator: coordinator, ink: nil, layout: layout)
        container.frame = CGRect(origin: .zero, size: size)
        container.layoutIfNeeded()
        return (container, coordinator.canvas!, coordinator)
    }

    // MARK: Fit

    @Test func thePageFillsTheWidth() throws {
        let layout = sheet()
        let (_, canvas, coordinator) = make(layout, size: CGSize(width: 1000, height: 700))
        let rules = try #require(coordinator.rules)
        let fit = 1000 / layout.paper.size.width
        #expect(abs(canvas.zoomScale - fit) < 0.001)
        #expect(abs(rules.frame.width - 1000) < 1)
        #expect(abs(canvas.contentSize.width - 1000) < 1)
        #expect(abs(canvas.contentSize.height - layout.canvasSize.height * fit) < 1)
        #expect(canvas.contentInset.left == 0)
    }

    @Test func aWholePageIsCentred() throws {
        let layout = sheet()
        let (_, canvas, _) = make(layout, size: CGSize(width: 1000, height: 700), fit: .page)
        let fit = min(1000 / layout.paper.size.width, 700 / layout.paper.size.height)
        #expect(abs(canvas.zoomScale - fit) < 0.001)
        let free = 1000 - layout.paper.size.width * fit
        #expect(abs(canvas.contentInset.left - free / 2) < 1)
    }

    @Test func choosingTheOtherFitRefitsAtOnce() {
        let layout = sheet()
        let (_, canvas, coordinator) = make(layout, size: CGSize(width: 1000, height: 700))
        coordinator.fit = .page
        coordinator.refit()
        let whole = min(1000 / layout.paper.size.width, 700 / layout.paper.size.height)
        #expect(abs(canvas.zoomScale - whole) < 0.001)
    }

    @Test func zoomingKeepsTheRulesUnderTheInk() throws {
        let layout = sheet()
        let (container, canvas, coordinator) = make(layout, size: CGSize(width: 1000, height: 700))
        let rules = try #require(coordinator.rules)
        canvas.setZoomScale(2.5, animated: false)
        container.layoutIfNeeded()
        #expect(abs(rules.frame.width - layout.canvasSize.width * 2.5) < 1)
        #expect(abs(rules.frame.height - layout.canvasSize.height * 2.5) < 1)
        #expect(rules.frame.origin == .zero)
        #expect(abs(canvas.contentSize.width - layout.canvasSize.width * 2.5) < 1)
    }

    @Test func thePaperIsTiledSoAnEndlessSheetIsNeverOneBitmap() throws {
        let endless = SchreibblattFormat(arrangement: .row).paper(wordCount: 5, repetitions: 20)
        let layout = sheet(repetitions: 20, paper: endless)
        #expect(layout.canvasSize.width > 10_000)
        let (container, _, coordinator) = make(layout, size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(container) {} }
        let rules = try #require(coordinator.rules)
        #expect(rules.layer is CATiledLayer)
        #expect(rules.bounds.size == layout.canvasSize)
    }

    @Test func aWideEndlessSheetFitsTwoTablesAcross() {
        let paper = SchreibblattFormat(arrangement: .three).paper(wordCount: 5, repetitions: 5)
        let layout = sheet(repetitions: 5, paper: paper)
        let (_, canvas, _) = make(layout, size: CGSize(width: 1000, height: 700))
        #expect(abs(canvas.zoomScale - 1000 / paper.fitWidth) < 0.001)
        #expect(paper.fitWidth < paper.size.width)
    }

    @Test func theRulingAndThePaperRestyleWithoutMovingAnything() throws {
        let layout = sheet()
        let (container, canvas, coordinator) = make(layout, size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(container) {} }
        let zoom = canvas.zoomScale
        coordinator.restyle(lines: true, paper: .dark)
        let rules = try #require(coordinator.rules)
        #expect(rules.lines)
        #expect(canvas.overrideUserInterfaceStyle == .dark)
        #expect(canvas.zoomScale == zoom)
        #expect(abs(rules.frame.width - layout.canvasSize.width * zoom) < 1)
        coordinator.restyle(lines: false, paper: .sepia)
        #expect(canvas.overrideUserInterfaceStyle == .light)
        #expect(canvas.subviews.filter { $0 is SchreibblattRulesView }.count == 1)
    }

    @Test func aBlankSheetTurnedOnItsSideLaysOutAgain() throws {
        let (_, canvas, coordinator) = make(sheet(), size: CGSize(width: 1000, height: 700))
        let landscape = sheet(paper: .a4Landscape)
        coordinator.relayout(landscape)
        let rules = try #require(coordinator.rules)
        #expect(rules.layout == landscape)
        #expect(abs(canvas.zoomScale - 1000 / landscape.paper.size.width) < 0.001)
        #expect(abs(canvas.contentSize.height - landscape.canvasSize.height * canvas.zoomScale) < 1)
        // The old pages are gone, not left under the new ones.
        #expect(canvas.subviews.filter { $0 is SchreibblattRulesView }.count == 1)
    }

    // MARK: The sheet's knobs

    @Test func aSheetKeepsItsOrientationInThePaperName() {
        let sheet = SchreibblattSheet(title: "Probe", words: Self.words, repetitions: 5,
                                      prefillEnglish: true, orientation: .landscape)
        #expect(sheet.paperRaw == "a4-landscape")
        #expect(sheet.layout.paper == .a4Landscape)
        sheet.orientation = .portrait
        #expect(sheet.paperRaw == "a4")
        #expect(sheet.layout.paper == .a4)
    }

    @Test func aBlankCopyHasTheSameWordsAndColumnsAndNoInk() {
        let sheet = SchreibblattSheet(title: "Probe", words: Self.words, repetitions: 4,
                                      prefillEnglish: false)
        sheet.strokeCount = 12
        sheet.inkFileName = "elsewhere.drawing"
        let copy = sheet.blankCopy(format: SchreibblattFormat(orientation: .landscape))
        #expect(copy.id != sheet.id)
        #expect(copy.words == sheet.words)
        #expect(copy.repetitions == 4)
        #expect(copy.prefillEnglish == false)
        #expect(copy.englishColumnWidth == sheet.englishColumnWidth)
        #expect(copy.orientation == .landscape)
        #expect(copy.inkFileName == nil)
        #expect(copy.strokeCount == 0)
    }

    @Test func aFinishedSheetLocksTheCanvasUntilItIsOpenedAgain() throws {
        let (container, canvas, _) = make(sheet(), size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(container) {} }
        let board = PencilBoard()
        board.attach(canvas)
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(
            controlPoints: [CGPoint(x: 100, y: 200), CGPoint(x: 160, y: 210)].enumerated().map { i, point in
                PKStrokePoint(location: point, timeOffset: Double(i) / 10, size: CGSize(width: 3, height: 3),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date()))])

        board.isLocked = true
        #expect(canvas.isLocked)
        #expect(!canvas.drawingGestureRecognizer.isEnabled)
        board.clear()
        #expect(canvas.drawing.strokes.count == 1, "a finished sheet cannot be cleared")

        board.isLocked = false
        #expect(canvas.drawingGestureRecognizer.isEnabled)
        let undo = try #require(canvas.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        board.clear()
        undo.endUndoGrouping()
        #expect(canvas.drawing.strokes.isEmpty)
        board.isLocked = true
        board.undo()
        #expect(canvas.drawing.strokes.isEmpty, "nor can its last step be undone")
        board.isLocked = false
        board.undo()
        #expect(canvas.drawing.strokes.count == 1)
    }

    @Test func aBlankCopyOfAFinishedSheetStartsUnfinished() {
        let sheet = SchreibblattSheet(title: "Probe", words: Self.words, repetitions: 5, prefillEnglish: true)
        #expect(!sheet.isFinished)
        sheet.finishedAt = Date()
        #expect(sheet.isFinished)
        #expect(!sheet.blankCopy().isFinished)
    }

    @Test func aSheetKeepsItsArrangementAndAnEndlessOneIsNotExported() {
        let sheet = SchreibblattSheet(title: "Probe", words: Self.words, repetitions: 5, prefillEnglish: true,
                                      arrangement: .three, notebookLines: true)
        #expect(sheet.arrangementRaw == "three")
        #expect(sheet.format.arrangement == .three)
        #expect(!sheet.canExport)
        #expect(sheet.layout.pageCount == 1)
        #expect(sheet.layout.paper.columns == 3)
        let copy = sheet.blankCopy()
        #expect(copy.format == sheet.format)
        #expect(copy.notebookLines)
        sheet.format = SchreibblattFormat()
        #expect(sheet.canExport)
        #expect(sheet.layout.paper == .a4)
    }

    // MARK: The pen and the wrist guard

    @Test func thePenBecomesPencilKitsInkInItsColour() {
        let tool = PencilCanvasView.inkingTool(for: PencilPen(ink: .fountainPen, shade: .blue, weight: .bold))
        #expect(tool.inkType == .fountainPen)
        #expect(tool.width > PKInkingTool.InkType.fountainPen.defaultWidth)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        tool.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(blue > red && blue > green)
        #expect(PencilCanvasView.inkingTool(for: PencilPen(ink: .fineliner)).inkType == .monoline)
    }

    @Test func onDarkPaperTheBlackPenIsStoredDarkSoItPrintsDark() {
        // Chosen as white on dark paper, kept as a dark ink: PencilKit shows it light there.
        let tool = PencilCanvasView.inkingTool(for: PencilPen(shade: .black), darkPaper: true)
        var white: CGFloat = 0, alpha: CGFloat = 0
        tool.color.getWhite(&white, alpha: &alpha)
        #expect(white < 0.3)
        #expect(PencilPen.Shade.offered(onDark: true).contains(.yellow))
        #expect(!PencilPen.Shade.offered(onDark: false).contains(.yellow))
        #expect(PencilPen.Shade.black.title(onDark: true) == "Weiß")
    }

    @Test func theWristGuardOnlyActsWhenItIsOn() {
        #expect(!PalmGuard.blocks(guarding: false, pencilDown: true, sincePencil: 0, radius: 80))
        // Writing, or just lifted: the hand on the glass is ignored.
        #expect(PalmGuard.blocks(guarding: true, pencilDown: true, sincePencil: 99, radius: 8))
        #expect(PalmGuard.blocks(guarding: true, pencilDown: false, sincePencil: 0.2, radius: 8))
        // A resting hand is ignored at any time; a fingertip on its own scrolls, even pressed flat
        // (iPads report those up to about 42 points, which a threshold of 30 used to block).
        #expect(PalmGuard.blocks(guarding: true, pencilDown: false, sincePencil: 99, radius: 70))
        #expect(!PalmGuard.blocks(guarding: true, pencilDown: false, sincePencil: 99, radius: 41.7))
        #expect(!PalmGuard.blocks(guarding: true, pencilDown: false, sincePencil: 99, radius: 10))
    }

    @Test func aSqueezeCanCycleTheColourAndThickness() {
        let (container, canvas, _) = make(sheet(), size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(container) {} }
        let saved = PencilPen.stored
        defer { saved.store() }
        let board = PencilBoard()
        board.attach(canvas)
        board.pen = PencilPen(shade: .black, weight: .medium)
        board.perform(.nextColour)
        #expect(board.pen.shade == .blue)
        #expect(board.notice?.text == "Blau · Blue")
        board.perform(.nextWidth)
        #expect(board.pen.weight == .bold)
        board.perform(.nextWidth)
        #expect(board.pen.weight == .fine)
        // On dark paper the cycle includes yellow.
        board.darkPaper = true
        board.pen.shade = .black
        board.perform(.nextColour)
        #expect(board.pen.shade == .yellow)
        board.perform(.eraser)
        #expect(board.tool == .eraser)
        #expect(canvas.tool is PKEraserTool)
        let request = board.penPickerRequest
        board.perform(.penPicker)
        #expect(board.tool == .pen)
        #expect(board.penPickerRequest == request + 1)
        // Nothing on a finished page.
        board.isLocked = true
        board.perform(.nextColour)
        #expect(board.pen.shade == .yellow)
    }

    @Test func theEraserComesInFourSizes() throws {
        let (container, canvas, _) = make(sheet(), size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(container) {} }
        let saved = PencilEraserSize.stored
        defer { UserDefaults.standard.set(saved.rawValue, forKey: PencilEraserSize.key) }
        let board = PencilBoard()
        board.attach(canvas)
        board.eraserSize = .huge
        #expect(board.tool == .eraser)
        let eraser = try #require(canvas.tool as? PKEraserTool)
        #expect(abs(eraser.width - PencilEraserSize.huge.width) < 0.5)
        board.eraserSize = .small
        #expect(abs(try #require(canvas.tool as? PKEraserTool).width - PencilEraserSize.small.width) < 0.5)
    }

    @Test func oneFingerScrollingIsAChoiceOnlyWithTheWristGuardOn() {
        let (container, canvas, _) = make(sheet(), size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(container) {} }
        var prefs = PencilPrefs()
        prefs.twoFingerScroll = false
        canvas.prefs = prefs
        canvas.wristGuard = true
        #expect(canvas.panGestureRecognizer.minimumNumberOfTouches == 1)
        // A finger that writes cannot also scroll.
        canvas.wristGuard = false
        #expect(canvas.panGestureRecognizer.minimumNumberOfTouches == 2)
        #expect(PalmGuard.blocks(guarding: true, pencilDown: false, sincePencil: 0.5, radius: 8, pause: 0.8))
        #expect(!PalmGuard.blocks(guarding: true, pencilDown: false, sincePencil: 0.5, radius: 8, pause: 0.25))
    }

    @Test func theWristGuardMakesTheCanvasPencilOnly() {
        let (container, canvas, _) = make(sheet(), size: CGSize(width: 1000, height: 700))
        defer { withExtendedLifetime(container) {} }
        canvas.wristGuard = true
        #expect(canvas.drawingPolicy == .pencilOnly)
        // One finger does nothing: a resting hand cannot move the page.
        #expect(canvas.panGestureRecognizer.minimumNumberOfTouches == 2)
        // A locked page has nothing to write, so one finger scrolls it.
        canvas.isLocked = true
        #expect(canvas.panGestureRecognizer.minimumNumberOfTouches == 1)
        canvas.isLocked = false
        canvas.wristGuard = false
        #expect(canvas.drawingPolicy == .anyInput)
        #expect(canvas.panGestureRecognizer.minimumNumberOfTouches == 2)
    }

    @Test func aSheetFromBeforeTheMeasuredColumnKeepsItsSplit() {
        let sheet = SchreibblattSheet(title: "Alt", words: Self.words, repetitions: 5, prefillEnglish: true)
        #expect(sheet.englishColumnWidth > 0)
        sheet.englishColumnWidth = 0
        #expect(sheet.layout.englishColumnWidth == nil)
        let table = sheet.layout.tables[0]
        let fixed = (table.frame.width * SchreibblattLayout.Paper.a4.englishColumnFraction).rounded()
        #expect(table.columnDividerX == table.frame.minX + fixed)
    }
}
#endif
