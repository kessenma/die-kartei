//
//  WorksheetCanvas.swift
//  german-ai-flashcards
//
//  Writing on the teacher's slide with the Pencil. A `PKCanvasView` whose content space is the
//  page in points, origin top-left, so a stroke's coordinates map one to one onto the exported
//  page (`WorksheetRenderer.drawInk`). Behind the ink, as the canvas's bottom subview, the slide
//  itself with any answers typed in the app already written into it — drawn by the same renderer
//  as the preview and the export, so the three agree.
//
//  Runs on the shared Pencil surface (`PencilSurface`, docs/SCHREIBBLATT.md ▸ Pencil surface): this
//  file gives it the slide as paper (`WorksheetPaper`) and decides what a save writes. Ink is read
//  before `makeUIView`, never in `onAppear`. One page per canvas:
//  the screen gives each page its own (`.id(page)`), and saves are debounced, skipped when
//  nothing changed, and an erased page deletes its file — every write is a sync upload.
//
//  Notes: a page can get extra paper on any side of the slide (`WorksheetNotesMargins`) for the
//  learner's own notes and questions. The slide then sits at an offset inside a bigger sheet, so
//  the ink is moved by that offset on the way in and back on the way out: the file always holds
//  ink in the slide's own points, which is what the export, the preview and the check read. Ink
//  in the margins is outside the slide, so it stays in the app.
//
//  PencilKit zooms its own ink view and nothing else (measured in the simulator: at zoom 2 the
//  content is 1920×1080 and a subview at index 0 is still 960×540), so the slide is scaled to the
//  zoom by hand, and `contentSize` is always page × zoom. The page fits and centres in the space it
//  gets until the learner pinches. The slide re-renders crisp when a zoom ends, capped at 4× the
//  page's points: a slide at 6× is ~75 MB of backing store (docs/MEMORY.md).
//

import SwiftUI

#if canImport(UIKit)
import PencilKit
import UIKit

struct WorksheetCanvas: UIViewRepresentable {
    let materialID: UUID
    let page: Int
    let pdfData: Data
    let part: WorksheetPagePart
    let answers: [String: WorksheetAnswer]
    /// Her answer key on the slide ("Lösungen"); empty when hidden.
    let herAnswers: [String: WorksheetRenderer.KeyAnswer]
    /// Paper around the slide for notes.
    let notes: WorksheetNotesMargins
    /// The tool, the pen and undo, shared with the dock beside the canvas.
    let pencil: PencilBoard
    /// Called after the ink for this page was written to disk.
    let onSaved: () -> Void

    /// Read now, in the struct's init, so it is on the canvas before the first frame.
    private let ink: Data?

    init(materialID: UUID, page: Int, pdfData: Data, part: WorksheetPagePart,
         answers: [String: WorksheetAnswer], herAnswers: [String: WorksheetRenderer.KeyAnswer] = [:],
         notes: WorksheetNotesMargins = WorksheetNotesMargins(),
         pencil: PencilBoard, onSaved: @escaping () -> Void) {
        self.materialID = materialID
        self.page = page
        self.pdfData = pdfData
        self.part = part
        self.answers = answers
        self.herAnswers = herAnswers
        self.notes = notes
        self.pencil = pencil
        self.onSaved = onSaved
        self.ink = WorksheetInkStore.read(materialID, page: page)
    }

    typealias FittingContainer = PencilSurface.Container

    private var pageSize: CGSize { part.bounds.size }

    func makeCoordinator() -> Coordinator {
        Coordinator(materialID: materialID, page: page, pageSize: pageSize, notes: notes, onSaved: onSaved)
    }

    func makeUIView(context: Context) -> FittingContainer {
        let container = Self.build(coordinator: context.coordinator, ink: ink, pdfData: pdfData,
                                   page: page, part: part, answers: answers, herAnswers: herAnswers)
        context.coordinator.surface?.attach(pencil)
        return container
    }

    /// The surface on this page's slide, wired to `coordinator`. Separate from `makeUIView` so the
    /// tests can build one and check the zoom keeps the slide under the ink.
    static func build(coordinator: Coordinator, ink: Data?, pdfData: Data, page: Int,
                      part: WorksheetPagePart, answers: [String: WorksheetAnswer],
                      herAnswers: [String: WorksheetRenderer.KeyAnswer] = [:]) -> FittingContainer {
        let slide = WorksheetSlideView(pdfData: pdfData, pageNumber: page, part: part, answers: answers,
                                       herAnswers: herAnswers)
        slide.bounds = CGRect(origin: .zero, size: part.bounds.size)
        coordinator.slide = slide
        coordinator.saved = ink
        let surface = PencilSurface(
            paper: coordinator.makePaper(),
            ink: ink.flatMap { try? PKDrawing(data: $0) },
            // The whole slide (and its notes paper) at once: a slide is one page, read as a page.
            fit: .page,
            // Every write is a sync upload, so the pause is longer than a Schreibblatt's.
            saveDelay: .seconds(3),
            onSave: { [weak coordinator] drawing in coordinator?.save(drawing) }
        )
        coordinator.surface = surface
        return surface.container
    }

    func updateUIView(_ view: FittingContainer, context: Context) {
        // Typed answers and the check's marks can change under the slide; the ink is the canvas's
        // own and never round-trips through SwiftUI.
        context.coordinator.slide?.update(answers: answers, herAnswers: herAnswers)
        context.coordinator.setNotes(notes)
    }

    static func dismantleUIView(_ view: FittingContainer, coordinator: Coordinator) {
        coordinator.surface?.detach()
        coordinator.surface?.flush()
    }

    // MARK: - Coordinator

    /// The page's notes paper and its saves, and the surface they drive.
    final class Coordinator {
        let materialID: UUID
        let page: Int
        /// The slide's own size, in its points.
        let pageSize: CGSize
        private(set) var notes: WorksheetNotesMargins
        let onSaved: () -> Void
        var surface: PencilSurface?
        var slide: WorksheetSlideView?
        /// What the file holds, so an unchanged drawing isn't written (and re-uploaded) again.
        var saved: Data?

        init(materialID: UUID, page: Int, pageSize: CGSize,
             notes: WorksheetNotesMargins = WorksheetNotesMargins(), onSaved: @escaping () -> Void) {
            self.materialID = materialID
            self.page = page
            self.pageSize = pageSize
            self.notes = notes
            self.onSaved = onSaved
        }

        var canvas: PencilCanvasView? { surface?.canvas }

        func makePaper() -> WorksheetPaper {
            WorksheetPaper(slideSize: pageSize, notes: notes, slide: slide)
        }

        /// The slide and the notes paper around it.
        var sheetSize: CGSize { makePaper().sheetSize }

        /// The sheet's ink back in the slide's points, for the file.
        func onSlide(_ drawing: PKDrawing) -> PKDrawing { makePaper().toStore(drawing) }

        /// Notes paper added or taken away: the ink keeps its place on the slide, the sheet grows or
        /// shrinks around it, and the whole of it is fitted again (`PencilSurface.replace`).
        func setNotes(_ new: WorksheetNotesMargins) {
            guard new != notes else { return }
            notes = new
            surface?.replace(with: makePaper())
        }

        /// The surface's debounced save, the ink already in the slide's points. An empty drawing
        /// removes the page's file.
        func save(_ drawing: PKDrawing) {
            let data: Data? = drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
            guard data != saved else { return }
            if WorksheetInkStore.write(data, for: materialID, page: page) {
                saved = data
                onSaved()
            }
        }
    }
}

// MARK: - The paper

/// The slide on its notes paper, as the shared surface's paper. The stored ink is in the slide's
/// own points, so it moves out by the slide's offset on the way in and back on the way out. Always
/// light: her slide is white, and in Dark Mode PencilKit would turn a black pen white on it.
final class WorksheetPaper: PencilPaper {
    let slideSize: CGSize
    let notes: WorksheetNotesMargins
    private weak var slide: WorksheetSlideView?

    init(slideSize: CGSize, notes: WorksheetNotesMargins, slide: WorksheetSlideView?) {
        self.slideSize = slideSize
        self.notes = notes
        self.slide = slide
    }

    /// Where the slide's top-left corner sits on the sheet.
    var slideOrigin: CGPoint {
        let insets = notes.insets(for: slideSize)
        return CGPoint(x: insets.left, y: insets.top)
    }

    var sheetSize: CGSize {
        let insets = notes.insets(for: slideSize)
        return CGSize(width: insets.left + slideSize.width + insets.right,
                      height: insets.top + slideSize.height + insets.bottom)
    }

    func makeLayers() -> [PencilPaperLayer] {
        var layers: [PencilPaperLayer] = []
        if !notes.isEmpty { layers.append(PencilPaperLayer(view: WorksheetNotesPaperView(size: sheetSize))) }
        if let slide { layers.append(PencilPaperLayer(view: slide, origin: slideOrigin)) }
        return layers
    }

    func toSheet(_ ink: PKDrawing) -> PKDrawing {
        let origin = slideOrigin
        guard origin != .zero else { return ink }
        return ink.transformed(using: CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    func toStore(_ ink: PKDrawing) -> PKDrawing {
        let origin = slideOrigin
        guard origin != .zero else { return ink }
        return ink.transformed(using: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }

    /// Re-render the slide at the new zoom, capped at 4× its points: a slide at 6× is about 75 MB
    /// of backing store (docs/MEMORY.md).
    func zoomDidSettle(_ zoom: CGFloat, displayScale: CGFloat) {
        guard let slide else { return }
        let factor = min(displayScale * zoom, 4)
        if abs(slide.contentScaleFactor - factor) > 0.01 {
            slide.contentScaleFactor = factor
            slide.setNeedsDisplay()
        }
    }
}

// MARK: - The notes paper

/// White paper ruled like an exercise book, the size of the whole sheet, under the slide.
final class WorksheetNotesPaperView: PencilTiledPaperView {
    nonisolated static let lineSpacing: CGFloat = 28

    init(size: CGSize) {
        super.init(size: size, opaque: true)
    }

    nonisolated override func drawPaper(_ rect: CGRect, in ctx: CGContext) {
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.setStrokeColor(SchreibblattRenderer.Palette.paper.notebookLine)
        ctx.setLineWidth(0.5)
        let spacing = Self.lineSpacing
        var y = (rect.minY / spacing).rounded(.down) * spacing + spacing
        ctx.beginPath()
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        ctx.strokePath()
    }
}

// MARK: - The slide behind the ink

/// Her page with the typed answers in it, in the canvas's content space (points, y-down).
final class WorksheetSlideView: UIView {
    private let document: CGPDFDocument?
    private let pageNumber: Int
    private let part: WorksheetPagePart
    private var answers: [String: WorksheetAnswer]
    private var herAnswers: [String: WorksheetRenderer.KeyAnswer]

    init(pdfData: Data, pageNumber: Int, part: WorksheetPagePart, answers: [String: WorksheetAnswer],
         herAnswers: [String: WorksheetRenderer.KeyAnswer] = [:]) {
        self.document = CGDataProvider(data: pdfData as CFData).flatMap(CGPDFDocument.init)
        self.pageNumber = pageNumber
        self.part = part
        self.answers = answers
        self.herAnswers = herAnswers
        super.init(frame: .zero)
        backgroundColor = .white
        isOpaque = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(answers: [String: WorksheetAnswer], herAnswers: [String: WorksheetRenderer.KeyAnswer] = [:]) {
        guard answers != self.answers || herAnswers != self.herAnswers else { return }
        self.answers = answers
        self.herAnswers = herAnswers
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let bounds = part.bounds
        // y-down view → the page's y-up space.
        ctx.translateBy(x: 0, y: self.bounds.height)
        ctx.scaleBy(x: self.bounds.width / bounds.width, y: -self.bounds.height / bounds.height)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        let input = WorksheetRenderer.Input(
            exercise: part.exercise.isExercise ? part.exercise : nil,
            geometry: part.geometry,
            answers: answers,
            ink: nil,
            outlinesGaps: WorksheetDebug.outlinesGaps,
            showsChecks: true,
            herAnswers: herAnswers
        )
        WorksheetRenderer.draw(cgPage: document?.page(at: pageNumber), bounds: bounds, input: input, in: ctx)
    }
}

#else

// MARK: - Mac

/// The Mac has no `PKCanvasView`. A page set to the Pencil is written on the iPad; its ink syncs
/// here and is in the export all the same.
struct WorksheetCanvas: View {
    let materialID: UUID
    let page: Int
    let pdfData: Data
    let part: WorksheetPagePart
    let answers: [String: WorksheetAnswer]
    var herAnswers: [String: WorksheetRenderer.KeyAnswer] = [:]
    var notes = WorksheetNotesMargins()
    let pencil: PencilBoard
    let onSaved: () -> Void

    var body: some View {
        ContentUnavailableView(
            "Mit dem iPad schreiben",
            systemImage: "hand.draw",
            description: Text("Writing on the slide needs an iPad and an Apple Pencil. Ink written there "
                              + "syncs here and goes into the PDF you share.")
        )
    }
}

#endif
