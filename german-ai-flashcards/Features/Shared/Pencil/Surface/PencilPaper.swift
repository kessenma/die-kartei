//
//  PencilPaper.swift
//  german-ai-flashcards
//
//  What a drawing screen gives the shared Pencil surface: the paper behind the ink. A Schreibblatt
//  hands over its ruled pages, a Deutschkurs worksheet its slide and notes paper, a blank pad plain
//  or lined paper. The surface (`PencilSurface`) does the rest: fitting, zoom, saving, the dock.
//
//  Everything here is in sheet space: points, origin top-left, the space the ink is drawn in.
//  `PKCanvasView` zooms its own ink and nothing else, so the surface scales each layer by hand
//  (one transform each, from its top-left corner) and keeps `contentSize` at sheet × zoom.
//
//  See docs/SCHREIBBLATT.md ▸ Pencil surface.
//

#if canImport(UIKit)
import PencilKit
import UIKit

/// One view behind the ink: drawn in sheet points at its own size, placed at `origin`.
struct PencilPaperLayer {
    let view: UIView
    var origin: CGPoint = .zero
}

@MainActor
protocol PencilPaper: AnyObject {
    /// The whole sheet the ink lives on, in points.
    var sheetSize: CGSize { get }
    /// What "the whole page" fits (`PencilFit.page`): one page of a paged sheet, or all of it.
    var pageSize: CGSize { get }
    /// What "the page's width" fits (`PencilFit.width`).
    var fitWidth: CGFloat { get }
    /// The ink's appearance. Light on light paper (in Dark Mode PencilKit would turn a black pen
    /// white, on white), dark on dark paper (where that same pen shows white).
    var appearance: UIUserInterfaceStyle { get }
    /// What shows around the sheet.
    var gutterColor: UIColor { get }

    /// The views behind the ink, bottom first. Made fresh each time: the surface replaces them
    /// whenever the paper changes, never mutates them.
    func makeLayers() -> [PencilPaperLayer]

    /// Stored ink → the sheet, and back. A screen whose stored ink lives in another space (a
    /// worksheet keeps it in the slide's own points while the slide sits inside notes paper)
    /// moves it here; everything else keeps the default, no move at all.
    func toSheet(_ ink: PKDrawing) -> PKDrawing
    func toStore(_ ink: PKDrawing) -> PKDrawing

    /// A pinch has settled at `zoom`: a layer that is not tiled can re-render sharper.
    func zoomDidSettle(_ zoom: CGFloat, displayScale: CGFloat)
}

extension PencilPaper {
    var pageSize: CGSize { sheetSize }
    var fitWidth: CGFloat { sheetSize.width }
    var appearance: UIUserInterfaceStyle { .light }
    var gutterColor: UIColor { .secondarySystemBackground }
    func toSheet(_ ink: PKDrawing) -> PKDrawing { ink }
    func toStore(_ ink: PKDrawing) -> PKDrawing { ink }
    func zoomDidSettle(_ zoom: CGFloat, displayScale: CGFloat) {}
}

// MARK: - Tiled paper

/// Paper that may be far bigger than the screen: a `CATiledLayer` draws only the tiles in view, at
/// the detail the zoom needs, off the main thread. An endless row of tables is twelve thousand
/// points wide; one bitmap of it at 4× would not fit in memory (docs/MEMORY.md).
///
/// **`drawPaper` runs on the tiled layer's own threads.** A subclass reads only `let`s of `Sendable`
/// values and is replaced, never mutated, when what it draws changes.
class PencilTiledPaperView: UIView {
    override class var layerClass: AnyClass { PencilTiledLayer.self }

    init(size: CGSize, opaque: Bool = false) {
        super.init(frame: .zero)
        isOpaque = opaque
        backgroundColor = opaque ? .white : .clear
        isUserInteractionEnabled = false
        bounds = CGRect(origin: .zero, size: size)
        if let tiled = layer as? CATiledLayer {
            tiled.tileSize = CGSize(width: 512, height: 512)
            // Detail from about a tenth of the points (an endless row seen whole) up to 8× (a page
            // zoomed in to write small).
            tiled.levelsOfDetail = 8
            tiled.levelsOfDetailBias = 3
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PencilTiledPaperView is created in code, never from a nib")
    }

    /// A `UIView` context is already y-down and in this view's (sheet) coordinates.
    nonisolated override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        drawPaper(rect, in: ctx)
    }

    /// Draw the part of the paper inside `rect`. Off the main thread; see the type's note.
    nonisolated func drawPaper(_ rect: CGRect, in ctx: CGContext) {}
}

/// Tiles appear at once rather than fading in, so scrolling reads as paper, not as loading.
final class PencilTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }
}
#endif
