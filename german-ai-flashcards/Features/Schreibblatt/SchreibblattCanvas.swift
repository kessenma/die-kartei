//
//  SchreibblattCanvas.swift
//  german-ai-flashcards
//
//  The Apple Pencil surface: a `PKCanvasView` holding every page of a sheet in one content space,
//  with the ruled pages drawn behind the ink.
//
//  Runs on the shared Pencil surface (`PencilSurface`, docs/SCHREIBBLATT.md ▸ Pencil surface): this
//  file gives it the sheet's paper and passes its saves on. The paper is one tiled `UIView` below
//  the ink, not a SwiftUI overlay and not a pre-rendered image. It hands `SchreibblattRenderer` a
//  `CGContext` in sheet space, the same as the PDF writer does, which is what keeps the screen and
//  the paper identical. It is tiled (`PencilTiledPaperView`): an endless sheet of twenty tables in
//  a row is twelve thousand points wide, and one bitmap of it at 4× would not fit in memory.
//
//  Fitting (the page's width or a whole page), zoom and the debounced save are the surface's.
//
//  One canvas, all pages, one `PKDrawing`: one blob, one save, one undo stack, and a stroke that
//  crosses a page gutter is harmless rather than lost.
//
//  The tools, undo and the Pencil gestures are the shared `PencilCanvasView`'s, driven by the
//  screen's `PencilBoard` and its rail; there is no system tool picker.
//
//  `PKCanvasView` is iOS-only (`PKDrawing` is not — see `SchreibblattRenderer`), so the Mac gets
//  the stub at the bottom of this file and prints instead.
//
//  See docs/SCHREIBBLATT.md.
//

import SwiftUI

#if canImport(UIKit)
import PencilKit
import UIKit

// MARK: - The paper

/// A sheet's ruled pages as the shared surface's paper (`PencilPaper`): the whole stack of pages
/// is the sheet, one page is what "the whole page" fits, and the ink's appearance follows the
/// paper style.
final class SchreibblattPaper: PencilPaper {
    let layout: SchreibblattLayout
    let lines: Bool
    let style: SchreibblattPaperStyle

    init(layout: SchreibblattLayout, lines: Bool, style: SchreibblattPaperStyle) {
        self.layout = layout
        self.lines = lines
        self.style = style
    }

    var sheetSize: CGSize { layout.canvasSize }
    var pageSize: CGSize { layout.paper.size }
    var fitWidth: CGFloat { layout.paper.fitWidth }
    var appearance: UIUserInterfaceStyle { style.isDark ? .dark : .light }
    var gutterColor: UIColor { SchreibblattCanvas.gutter(for: style) }

    func makeLayers() -> [PencilPaperLayer] {
        [PencilPaperLayer(view: SchreibblattRulesView(layout: layout, lines: lines, palette: style.palette))]
    }
}

/// The sheet's pages, drawn by `SchreibblattRenderer` tile by tile. Immutable: replaced when the
/// layout, the ruling or the paper changes.
final class SchreibblattRulesView: PencilTiledPaperView {
    let layout: SchreibblattLayout
    let lines: Bool
    let palette: SchreibblattRenderer.Palette

    init(layout: SchreibblattLayout, lines: Bool, palette: SchreibblattRenderer.Palette = .paper) {
        self.layout = layout
        self.lines = lines
        self.palette = palette
        super.init(size: layout.canvasSize)
    }

    nonisolated override func drawPaper(_ rect: CGRect, in ctx: CGContext) {
        for page in layout.pages(intersecting: rect) {
            SchreibblattRenderer.draw(layout, page: page, in: ctx, lines: lines, palette: palette)
        }
    }
}

// MARK: - The canvas

struct SchreibblattCanvas: UIViewRepresentable {
    let layout: SchreibblattLayout
    /// The sheet's saved ink, read once when the canvas is made.
    let ink: Data?
    let fit: SchreibblattFit
    /// Exercise-book ruling on the paper around the tables.
    var lines = false
    var paper: SchreibblattPaperStyle = .white
    /// The tool, the pen and undo, shared with the dock beside the canvas.
    let pencil: PencilBoard
    /// Called with debounced bytes and the stroke count. The screen owns the save.
    let onChange: (Data, Int) -> Void

    typealias Container = PencilSurface.Container

    func makeCoordinator() -> Coordinator {
        Coordinator(layout: layout, fit: fit, lines: lines, paper: paper, onChange: onChange)
    }

    func makeUIView(context: Context) -> Container {
        let container = Self.build(coordinator: context.coordinator, ink: ink, layout: layout,
                                   lines: lines, paper: paper)
        context.coordinator.surface?.attach(pencil)
        return container
    }

    /// The surface on this sheet's paper, wired to `coordinator`. Separate from `makeUIView` so
    /// the tests can build one and check the fit and the zoom.
    static func build(coordinator: Coordinator, ink: Data?, layout: SchreibblattLayout,
                      lines: Bool = false, paper: SchreibblattPaperStyle = .white) -> Container {
        let save = coordinator.onChange
        let surface = PencilSurface(
            paper: SchreibblattPaper(layout: layout, lines: lines, style: paper),
            ink: ink.flatMap { try? PKDrawing(data: $0) },
            fit: coordinator.fit,
            onSave: { drawing in save(drawing.dataRepresentation(), drawing.strokes.count) }
        )
        coordinator.surface = surface
        return surface.container
    }

    func updateUIView(_ view: Container, context: Context) {
        // Idempotent: a SwiftUI pass must not round-trip the learner's ink through a copy.
        let coordinator = context.coordinator
        if coordinator.layout != layout { coordinator.relayout(layout) }
        if coordinator.lines != lines || coordinator.paper != paper {
            coordinator.restyle(lines: lines, paper: paper)
        }
        if coordinator.fit != fit {
            coordinator.fit = fit
            coordinator.refit()
        }
    }

    /// Between the pages: the screen's grey, or near black around dark paper.
    static func gutter(for paper: SchreibblattPaperStyle) -> UIColor {
        paper.isDark ? UIColor(white: 0.05, alpha: 1) : .secondarySystemBackground
    }

    static func dismantleUIView(_ view: Container, coordinator: Coordinator) {
        coordinator.surface?.detach()
        coordinator.surface?.flush()
    }

    // MARK: - Coordinator

    /// The sheet's knobs, and the surface they drive.
    final class Coordinator {
        private(set) var layout: SchreibblattLayout
        var fit: SchreibblattFit {
            didSet { surface?.fit = fit }
        }
        private(set) var lines: Bool
        private(set) var paper: SchreibblattPaperStyle
        let onChange: (Data, Int) -> Void
        var surface: PencilSurface?

        init(layout: SchreibblattLayout, fit: SchreibblattFit, lines: Bool = false,
             paper: SchreibblattPaperStyle = .white, onChange: @escaping (Data, Int) -> Void) {
            self.layout = layout
            self.fit = fit
            self.lines = lines
            self.paper = paper
            self.onChange = onChange
        }

        var canvas: PencilCanvasView? { surface?.canvas }
        var rules: SchreibblattRulesView? { surface?.layers.first?.view as? SchreibblattRulesView }

        /// Fit again now, as the fit asks.
        func refit() { surface?.refit() }

        /// A blank sheet turned or rearranged: new paper under the (empty) ink, fitted from the top.
        func relayout(_ layout: SchreibblattLayout) {
            self.layout = layout
            surface?.replace(with: SchreibblattPaper(layout: layout, lines: lines, style: paper), scrollToTop: true)
        }

        /// The ruling or the paper changed: the same sheet, drawn again. Geometry does not move.
        func restyle(lines: Bool, paper: SchreibblattPaperStyle) {
            self.lines = lines
            self.paper = paper
            surface?.restyle(SchreibblattPaper(layout: layout, lines: lines, style: paper))
        }
    }
}

#else

// MARK: - Mac

/// The Mac has no `PKCanvasView` or `PKToolPicker`: they are `TARGET_OS_IPHONE`-only, even though
/// `PKDrawing` is a macOS API. So a sheet cannot be written on here; it can be printed, and the
/// screen that hosts this keeps its Share button for exactly that.
struct SchreibblattCanvas: View {
    let layout: SchreibblattLayout
    let ink: Data?
    let fit: SchreibblattFit
    var lines = false
    var paper: SchreibblattPaperStyle = .white
    let pencil: PencilBoard
    let onChange: (Data, Int) -> Void

    var body: some View {
        ContentUnavailableView(
            "Mit dem iPad schreiben",
            systemImage: "hand.draw",
            description: Text("Writing on the sheet needs an iPad and an Apple Pencil. "
                              + "Share it as a PDF from here and write on paper.")
        )
    }
}

#endif
