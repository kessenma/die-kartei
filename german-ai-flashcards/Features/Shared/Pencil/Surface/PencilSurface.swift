//
//  PencilSurface.swift
//  german-ai-flashcards
//
//  The engine every Pencil drawing screen runs on: a transparent `PencilCanvasView` in a container,
//  the screen's paper (`PencilPaper`) behind the ink, and everything around them that used to be
//  copied from screen to screen:
//   • fitting: the paper's width or a whole page, centred, again whenever the space changes
//     (rotation, full screen, the dock moving, the tab bar stepping aside) until the learner pinches;
//     a refit keeps whatever was at the top of the screen there;
//   • zoom: PencilKit zooms only its own ink, so each paper layer is scaled by hand and
//     `contentSize` is held at sheet × zoom (the canvas grows it to keep stray ink reachable);
//   • saving: debounced (PencilKit reports each stroke and again when late pressure lands), the
//     ink moved back to its stored space (`PencilPaper.toStore`), flushed on the way out;
//   • the dock's board: attached, told the stroke count, detached.
//
//  A screen's `UIViewRepresentable` makes one in `makeUIView`, hands its `container` to SwiftUI,
//  and calls `flush()` and `detach()` in `dismantleUIView`. `PencilPadCanvas` is the plainest one.
//
//  Traps kept here so no screen meets them again (docs/SCHREIBBLATT.md ▸ Traps):
//   • the canvas is transparent, or its ink view hides everything inserted under it;
//   • `drawing` is set before `contentSize`, which assigning `drawing` resets;
//   • `drawingPolicy` is the board's, never `.default`, which is Pencil-only with no tool picker.
//

#if canImport(UIKit)
import PencilKit
import UIKit

@MainActor
final class PencilSurface: NSObject, PKCanvasViewDelegate {
    let container: Container
    let canvas: PencilCanvasView
    private(set) var paper: PencilPaper
    /// The paper's views behind the ink, bottom first.
    private(set) var layers: [PencilPaperLayer] = []

    var fit: PencilFit
    /// The learner pinched: stop refitting on layout until a fit is asked for again.
    var zoomedByHand = false
    private var fittedFor: CGSize = .zero

    private let saveDelay: Duration
    /// Receives the ink in its stored space, debounced and on the way out.
    private let onSave: (PKDrawing) -> Void
    private var pending: PKDrawing?
    private var saveTask: Task<Void, Never>?

    private(set) weak var board: PencilBoard?
    /// Strokes on the canvas at the last change, so a new one (appended last) can be told apart
    /// from the second report PencilKit sends when late pressure data lands.
    private var knownStrokes = 0

    init(paper: PencilPaper, ink: PKDrawing?, fit: PencilFit = .width,
         saveDelay: Duration = .seconds(1.5), onSave: @escaping (PKDrawing) -> Void) {
        self.paper = paper
        self.fit = fit
        self.saveDelay = saveDelay
        self.onSave = onSave
        self.container = Container()
        self.canvas = PencilCanvasView()
        super.init()

        container.surface = self
        container.backgroundColor = paper.gutterColor

        canvas.delegate = self
        // Order matters: assigning `drawing` resets `contentSize` from the drawing's own bounds.
        if let ink { canvas.drawing = paper.toSheet(ink) }
        knownStrokes = canvas.drawing.strokes.count
        canvas.contentSize = paper.sheetSize
        // Until a board attaches and sets the learner's own (the wrist guard).
        canvas.drawingPolicy = .anyInput
        canvas.bouncesZoom = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        // Transparent, so the paper under the ink is not painted over.
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.overrideUserInterfaceStyle = paper.appearance

        installLayers()

        canvas.frame = container.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(canvas)
    }

    // MARK: The board

    func attach(_ board: PencilBoard) {
        self.board = board
        board.attach(canvas)
    }

    func detach() {
        board?.detach(canvas)
    }

    // MARK: The paper

    /// The same geometry drawn again (ruling, paper colour, answers under a slide): new layers,
    /// the ink and the zoom untouched.
    func restyle(_ paper: PencilPaper) {
        self.paper = paper
        container.backgroundColor = paper.gutterColor
        canvas.overrideUserInterfaceStyle = paper.appearance
        installLayers()
        zoomChanged()
    }

    /// New geometry (a blank sheet turned, notes paper added): the ink keeps its place in its
    /// stored space and is laid on the new sheet, which is fitted again. Undo starts over when the
    /// ink had to move, since its steps remember where it was.
    func replace(with paper: PencilPaper, scrollToTop: Bool = false) {
        let stored = self.paper.toStore(canvas.drawing)
        let before = canvas.drawing.dataRepresentation()
        self.paper = paper
        let placed = paper.toSheet(stored)
        if placed.dataRepresentation() != before {
            canvas.drawing = placed
            canvas.undoManager?.removeAllActions()
            canvas.refreshUndoState()
        }
        container.backgroundColor = paper.gutterColor
        canvas.overrideUserInterfaceStyle = paper.appearance
        installLayers()
        zoomedByHand = false
        fitToView(force: true)
        if scrollToTop { scroll(toSheetY: 0) }
    }

    private func installLayers() {
        layers.forEach { $0.view.removeFromSuperview() }
        layers = paper.makeLayers()
        var below: UIView?
        for layer in layers {
            layer.view.layer.anchorPoint = .zero
            if let below {
                canvas.insertSubview(layer.view, aboveSubview: below)
            } else {
                canvas.insertSubview(layer.view, at: 0)
            }
            below = layer.view
        }
        placeLayers()
    }

    private func placeLayers() {
        let zoom = canvas.zoomScale
        for layer in layers {
            layer.view.transform = CGAffineTransform(scaleX: zoom, y: zoom)
            layer.view.layer.position = CGPoint(x: layer.origin.x * zoom, y: layer.origin.y * zoom)
        }
    }

    // MARK: Fitting

    /// Fit the sheet to the canvas: on a new size unless the learner has zoomed by hand, or always
    /// when `force`d. Whatever was at the top of the screen stays there.
    func fitToView(force: Bool = false) {
        let size = canvas.bounds.size
        let page = paper.pageSize
        let across = paper.fitWidth
        guard size.width > 0, size.height > 0, page.width > 0, page.height > 0, across > 0 else { return }
        let width = size.width / across
        let whole = min(size.width / page.width, size.height / page.height)
        canvas.minimumZoomScale = min(width, whole) * 0.8
        canvas.maximumZoomScale = max(width * 3, whole * 4, 3)

        guard force || (size != fittedFor && !zoomedByHand) else {
            center()
            return
        }
        fittedFor = size
        let top = topSheetY()
        canvas.setZoomScale(fit == .width ? width : whole, animated: false)
        zoomChanged()
        center()
        scroll(toSheetY: top)
    }

    /// Fit again now, as the fit asks: the learner chose it, or the paper changed.
    func refit() {
        zoomedByHand = false
        fitToView(force: true)
    }

    /// The paper follows the zoom as a transform: cheap during a pinch; a tiled layer redraws at
    /// the new detail by itself, others are told when the pinch settles.
    func zoomChanged() {
        let zoom = canvas.zoomScale
        placeLayers()
        let sheet = paper.sheetSize
        let zoomed = CGSize(width: sheet.width * zoom, height: sheet.height * zoom)
        if canvas.contentSize != zoomed { canvas.contentSize = zoomed }
        if !canvas.isZooming { settle() }
    }

    /// A sheet narrower or shorter than the view sits in the middle, not the top-left corner.
    func center() {
        let zoom = canvas.zoomScale
        let sheet = paper.sheetSize
        let x = max(0, (canvas.bounds.width - sheet.width * zoom) / 2)
        let y = max(0, (canvas.bounds.height - sheet.height * zoom) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if canvas.contentInset != inset { canvas.contentInset = inset }
    }

    private func settle() {
        let display = canvas.traitCollection.displayScale
        paper.zoomDidSettle(canvas.zoomScale, displayScale: display > 0 ? display : 2)
    }

    private func topSheetY() -> CGFloat {
        guard canvas.zoomScale > 0 else { return 0 }
        return max(0, (canvas.contentOffset.y + canvas.contentInset.top) / canvas.zoomScale)
    }

    private func scroll(toSheetY y: CGFloat) {
        let inset = canvas.contentInset
        let lowest = max(-inset.top, canvas.contentSize.height + inset.bottom - canvas.bounds.height)
        let offsetY = min(max(-inset.top, y * canvas.zoomScale - inset.top), lowest)
        let offsetX = canvas.contentSize.width <= canvas.bounds.width
            ? -inset.left
            : min(max(-inset.left, canvas.contentOffset.x), canvas.contentSize.width - canvas.bounds.width)
        canvas.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    // MARK: Zoom and scroll

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        zoomedByHand = true
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        zoomChanged()
        center()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        settle()
    }

    // MARK: Ink

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // Held to sheet × zoom: the canvas grows it to keep stray ink reachable, which would add a
        // blank page the first time someone writes past the edge.
        let zoom = canvasView.zoomScale
        let sheet = paper.sheetSize
        let zoomed = CGSize(width: sheet.width * zoom, height: sheet.height * zoom)
        if canvasView.contentSize != zoomed { canvasView.contentSize = zoomed }
        let strokes = canvasView.drawing.strokes
        board?.inkChanged(strokeCount: strokes.count)
        // A new stroke is appended last. (Undo bringing one back counts too, which is harmless.)
        if strokes.count > knownStrokes, let newest = strokes.last {
            board?.strokeLanded(newest.renderBounds)
        }
        knownStrokes = strokes.count

        pending = canvasView.drawing
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Hand over whatever is pending now: on the debounce, and on the way out.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let drawing = pending else { return }
        pending = nil
        onSave(paper.toStore(drawing))
    }

    // MARK: - Container

    /// Fits the sheet into the space it is given whenever that space changes.
    final class Container: UIView {
        weak var surface: PencilSurface?

        override func layoutSubviews() {
            super.layoutSubviews()
            surface?.fitToView()
        }
    }
}
#endif
