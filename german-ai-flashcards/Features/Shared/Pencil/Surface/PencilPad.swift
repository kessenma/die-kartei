//
//  PencilPad.swift
//  german-ai-flashcards
//
//  A ready-made Pencil page on plain or exercise-book paper: the shared surface, the dock with its
//  settings and tips, and drawing mode (the tab bar steps aside), in one view. What a new drawing
//  exercise starts from:
//
//      PencilPad(ink: word.drawing, accent: tint) { data in word.saveDrawing(data) }
//
//  The screen owns where the ink lives (the pad hands over `PKDrawing` bytes, nil for an empty
//  page) and may add rows to the gear's "Blatt" group and to the tips. For the whole screen, wrap
//  the screen in `.pencilFullScreen` (`PencilFullScreen.swift`).
//
//  See docs/SCHREIBBLATT.md ▸ Pencil surface.
//

import SwiftUI

/// Plain or ruled paper's colours are the Schreibblatt's (`SchreibblattRenderer.Palette`).
typealias PencilPaperStyle = SchreibblattPaperStyle

struct PencilPad<Settings: View, Tips: View>: View {
    /// The saved ink, read once when the pad is made.
    let ink: Data?
    var size: CGSize = PencilPad.defaultSize
    var style: PencilPaperStyle = .white
    var lines = true
    var fit: PencilFit = .width
    var accent: Color = .accentColor
    /// Debounced; nil when the page has been wiped.
    let onSave: (Data?) -> Void
    @ViewBuilder var settings: Settings
    @ViewBuilder var tips: Tips

    @State private var board = PencilBoard()

    var body: some View {
        PencilPadCanvas(ink: ink, size: size, style: style, lines: lines, fit: fit, board: board, onSave: onSave)
            .pencilRail(board, accent: accent, canvasSettings: { settings }, tips: { tips })
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: style, initial: true) { board.darkPaper = style.isDark }
    }
}

extension PencilPad where Settings == EmptyView, Tips == EmptyView {
    init(ink: Data?, size: CGSize = PencilPad.defaultSize, style: PencilPaperStyle = .white,
         lines: Bool = true, fit: PencilFit = .width, accent: Color = .accentColor,
         onSave: @escaping (Data?) -> Void) {
        self.init(ink: ink, size: size, style: style, lines: lines, fit: fit, accent: accent,
                  onSave: onSave, settings: { EmptyView() }, tips: { EmptyView() })
    }
}

extension PencilPad {
    /// A page about the shape of an iPad held upright.
    static var defaultSize: CGSize { CGSize(width: 768, height: 1024) }
}

#if canImport(UIKit)
import PencilKit
import UIKit

// MARK: - Blank paper

/// Plain or exercise-book paper in one of the paper styles, `size` points.
final class PencilBlankPaper: PencilPaper {
    let size: CGSize
    let style: PencilPaperStyle
    let lines: Bool
    let lineSpacing: CGFloat

    init(size: CGSize, style: PencilPaperStyle = .white, lines: Bool = true, lineSpacing: CGFloat = 28) {
        self.size = size
        self.style = style
        self.lines = lines
        self.lineSpacing = lineSpacing
    }

    var sheetSize: CGSize { size }
    var appearance: UIUserInterfaceStyle { style.isDark ? .dark : .light }
    var gutterColor: UIColor { style.isDark ? UIColor(white: 0.05, alpha: 1) : .secondarySystemBackground }

    func makeLayers() -> [PencilPaperLayer] {
        [PencilPaperLayer(view: BlankPaperView(size: size, palette: style.palette,
                                               lines: lines, spacing: lineSpacing))]
    }
}

/// The paper's colour, and pale rules from one spacing below the top to one above the bottom.
final class BlankPaperView: PencilTiledPaperView {
    let palette: SchreibblattRenderer.Palette
    let lines: Bool
    let spacing: CGFloat
    let size: CGSize

    init(size: CGSize, palette: SchreibblattRenderer.Palette, lines: Bool, spacing: CGFloat) {
        self.palette = palette
        self.lines = lines
        self.spacing = max(8, spacing)
        self.size = size
        super.init(size: size, opaque: true)
    }

    nonisolated override func drawPaper(_ rect: CGRect, in ctx: CGContext) {
        ctx.setFillColor(palette.page)
        ctx.fill(rect)
        guard lines else { return }
        ctx.setStrokeColor(palette.notebookLine)
        ctx.setLineWidth(0.5)
        ctx.beginPath()
        var y = max(spacing, (rect.minY / spacing).rounded(.down) * spacing)
        while y <= min(rect.maxY, size.height - spacing) {
            if y >= rect.minY {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            y += spacing
        }
        ctx.strokePath()
    }
}

// MARK: - The canvas

/// The pad's canvas: `PencilSurface` on `PencilBlankPaper`.
struct PencilPadCanvas: UIViewRepresentable {
    let ink: Data?
    let size: CGSize
    let style: PencilPaperStyle
    let lines: Bool
    let fit: PencilFit
    let board: PencilBoard
    let onSave: (Data?) -> Void

    final class Coordinator {
        var surface: PencilSurface?
        var key: String = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var paperKey: String { "\(size.width)x\(size.height)-\(style.rawValue)-\(lines)" }

    func makeUIView(context: Context) -> PencilSurface.Container {
        let save = onSave
        let surface = PencilSurface(
            paper: PencilBlankPaper(size: size, style: style, lines: lines),
            ink: ink.flatMap { try? PKDrawing(data: $0) },
            fit: fit,
            onSave: { drawing in save(drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()) }
        )
        surface.attach(board)
        context.coordinator.surface = surface
        context.coordinator.key = paperKey
        return surface.container
    }

    func updateUIView(_ view: PencilSurface.Container, context: Context) {
        guard let surface = context.coordinator.surface else { return }
        if context.coordinator.key != paperKey {
            let resized = surface.paper.sheetSize != size
            context.coordinator.key = paperKey
            let paper = PencilBlankPaper(size: size, style: style, lines: lines)
            if resized { surface.replace(with: paper) } else { surface.restyle(paper) }
        }
        if surface.fit != fit {
            surface.fit = fit
            surface.refit()
        }
    }

    static func dismantleUIView(_ view: PencilSurface.Container, coordinator: Coordinator) {
        coordinator.surface?.detach()
        coordinator.surface?.flush()
    }
}

#else

// MARK: - Mac

/// The Mac has no `PKCanvasView`: drawing is for the iPad.
struct PencilPadCanvas: View {
    let ink: Data?
    let size: CGSize
    let style: PencilPaperStyle
    let lines: Bool
    let fit: PencilFit
    let board: PencilBoard
    let onSave: (Data?) -> Void

    var body: some View {
        ContentUnavailableView("Mit dem iPad zeichnen", systemImage: "hand.draw",
                               description: Text("Drawing needs an iPad and an Apple Pencil."))
    }
}

#endif
