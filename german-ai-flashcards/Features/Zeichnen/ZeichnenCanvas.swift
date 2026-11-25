//
//  ZeichnenCanvas.swift
//  german-ai-flashcards
//
//  The drawing surface for Quick Draw and the Atelier: the shared `PencilSurface` on a square
//  sheet of plain paper, with an optional reference picture under the ink (the Atelier's tracing
//  layer, its opacity live).
//
//  The screen holds a `ZeichnenCanvasHandle` to read the ink *now* (Quick Draw's Next can't wait
//  for the surface's debounced save) and to render it.
//
//  `PKCanvasView` is iOS-only, so the Mac gets the stub at the bottom (docs/MACOS.md).
//

import SwiftUI

/// What the screen can ask of the canvas it is showing.
@MainActor
final class ZeichnenCanvasHandle {
    #if canImport(UIKit)
    fileprivate weak var surface: PencilSurface?
    #endif

    /// The ink on the page right now, nil when it is blank.
    var inkData: Data? {
        #if canImport(UIKit)
        guard let drawing = surface?.canvas.drawing, !drawing.strokes.isEmpty else { return nil }
        return drawing.dataRepresentation()
        #else
        return nil
        #endif
    }

    var isBlank: Bool { inkData == nil }
}

/// The square page every Zeichnen drawing is made on, in points.
enum ZeichnenSheet {
    static let side: CGFloat = 768
    static var size: CGSize { CGSize(width: side, height: side) }
}

#if canImport(UIKit)
import PencilKit
import UIKit

// MARK: - The paper

/// Plain paper in one colour, and the reference picture on top of it at `referenceOpacity`.
final class ZeichnenPaper: PencilPaper {
    let ground: UIColor
    let dark: Bool
    private let referenceView: UIImageView?

    init(ground: UIColor, dark: Bool, reference: UIImage?, referenceOpacity: Double) {
        self.ground = ground
        self.dark = dark
        if let reference {
            let view = UIImageView(image: reference)
            view.frame = CGRect(origin: .zero, size: ZeichnenSheet.size)
            view.contentMode = .scaleAspectFit
            view.alpha = referenceOpacity
            view.isUserInteractionEnabled = false
            referenceView = view
        } else {
            referenceView = nil
        }
    }

    var sheetSize: CGSize { ZeichnenSheet.size }
    var appearance: UIUserInterfaceStyle { dark ? .dark : .light }
    var gutterColor: UIColor { dark ? UIColor(white: 0.04, alpha: 1) : .secondarySystemBackground }

    func makeLayers() -> [PencilPaperLayer] {
        let groundView = UIView(frame: CGRect(origin: .zero, size: ZeichnenSheet.size))
        groundView.backgroundColor = ground
        groundView.isUserInteractionEnabled = false
        var layers = [PencilPaperLayer(view: groundView)]
        if let referenceView { layers.append(PencilPaperLayer(view: referenceView)) }
        return layers
    }

    /// Live, without rebuilding the paper: the slider moves this on every tick.
    func setReferenceOpacity(_ opacity: Double) {
        referenceView?.alpha = opacity
    }
}

// MARK: - The canvas

struct ZeichnenCanvas: UIViewRepresentable {
    /// Ink to start from (a studio piece reopened), read once.
    var ink: Data?
    var dark = false
    var reference: UIImage?
    var referenceOpacity: Double = 0.35
    let board: PencilBoard
    let handle: ZeichnenCanvasHandle
    /// Debounced, and once more on the way out. Nil when the page was wiped.
    var onSave: (Data?) -> Void = { _ in }

    final class Coordinator {
        var surface: PencilSurface?
        var paper: ZeichnenPaper?
        var key = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var paperKey: String { "\(dark)-\(reference.map { ObjectIdentifier($0).hashValue } ?? 0)" }

    private func makePaper() -> ZeichnenPaper {
        ZeichnenPaper(ground: dark ? UIColor(white: 0.06, alpha: 1) : .white, dark: dark,
                      reference: reference, referenceOpacity: referenceOpacity)
    }

    func makeUIView(context: Context) -> PencilSurface.Container {
        let save = onSave
        let paper = makePaper()
        let surface = PencilSurface(
            paper: paper,
            ink: ink.flatMap { try? PKDrawing(data: $0) },
            fit: .page,
            saveDelay: .seconds(1),
            onSave: { drawing in save(drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()) }
        )
        surface.attach(board)
        context.coordinator.surface = surface
        context.coordinator.paper = paper
        context.coordinator.key = paperKey
        handle.surface = surface
        return surface.container
    }

    func updateUIView(_ view: PencilSurface.Container, context: Context) {
        let coordinator = context.coordinator
        guard let surface = coordinator.surface else { return }
        if coordinator.key != paperKey {
            coordinator.key = paperKey
            let paper = makePaper()
            coordinator.paper = paper
            surface.restyle(paper)
        }
        coordinator.paper?.setReferenceOpacity(referenceOpacity)
        board.darkPaper = dark
    }

    static func dismantleUIView(_ view: PencilSurface.Container, coordinator: Coordinator) {
        coordinator.surface?.detach()
        coordinator.surface?.flush()
    }
}

// MARK: - Rendering

enum ZeichnenRender {
    /// The ink on its paper as a square picture, `pixels` on a side.
    static func image(ink: Data, dark: Bool, pixels: Int) -> CGImage? {
        guard let drawing = try? PKDrawing(data: ink) else { return nil }
        return image(drawing: drawing, dark: dark, pixels: pixels)
    }

    static func image(drawing: PKDrawing, dark: Bool, pixels: Int) -> CGImage? {
        let rect = CGRect(origin: .zero, size: ZeichnenSheet.size)
        let scale = CGFloat(pixels) / ZeichnenSheet.side
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        var inkImage: UIImage?
        traits.performAsCurrent {
            inkImage = drawing.image(from: rect, scale: scale)
        }
        let picture = renderer.image { ctx in
            (dark ? UIColor(white: 0.06, alpha: 1) : UIColor.white).setFill()
            ctx.fill(rect)
            inkImage?.draw(in: rect)
        }
        return picture.cgImage
    }
}

#else

// MARK: - Mac

struct ZeichnenCanvas: View {
    var ink: Data?
    var dark = false
    var reference: UIImage?
    var referenceOpacity: Double = 0.35
    let board: PencilBoard
    let handle: ZeichnenCanvasHandle
    var onSave: (Data?) -> Void = { _ in }

    var body: some View {
        ContentUnavailableView("Mit dem iPad zeichnen", systemImage: "hand.draw",
                               description: Text("Drawing needs an iPad or iPhone. Your pictures and saved drawings are all here."))
    }
}

enum ZeichnenRender {
    static func image(ink: Data, dark: Bool, pixels: Int) -> CGImage? { nil }
}

#endif
