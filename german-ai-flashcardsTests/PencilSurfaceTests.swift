//
//  PencilSurfaceTests.swift
//  german-ai-flashcardsTests
//
//  The shared Pencil surface (Features/Shared/Pencil/Surface/) on its plainest paper, and drawing
//  mode (App/NavBarVisibility.swift). The Schreibblatt and worksheet suites hold their own papers;
//  these hold what every drawing screen gets from the surface: the fit, the paper following the
//  zoom, saves in the stored space, and new paper under ink that keeps its place.
//

#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit
@testable import Die_Kartei

@MainActor
@Suite struct PencilSurfaceTests {

    /// A paper whose stored ink sits `offset` away from the sheet's, like a worksheet's slide.
    final class OffsetPaper: PencilPaper {
        let size: CGSize
        let offset: CGPoint
        init(size: CGSize, offset: CGPoint) {
            self.size = size
            self.offset = offset
        }
        var sheetSize: CGSize { size }
        func makeLayers() -> [PencilPaperLayer] {
            [PencilPaperLayer(view: BlankPaperView(size: size, palette: .paper, lines: true, spacing: 28))]
        }
        func toSheet(_ ink: PKDrawing) -> PKDrawing {
            ink.transformed(using: CGAffineTransform(translationX: offset.x, y: offset.y))
        }
        func toStore(_ ink: PKDrawing) -> PKDrawing {
            ink.transformed(using: CGAffineTransform(translationX: -offset.x, y: -offset.y))
        }
    }

    private func stroke(at point: CGPoint) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: point.x + 40, y: point.y + 10), timeOffset: 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ], creationDate: Date()))
    }

    private func make(_ paper: PencilPaper, ink: PKDrawing? = nil, fit: PencilFit = .width,
                      size: CGSize = CGSize(width: 1000, height: 700),
                      onSave: @escaping (PKDrawing) -> Void = { _ in }) -> PencilSurface {
        let surface = PencilSurface(paper: paper, ink: ink, fit: fit, onSave: onSave)
        surface.container.frame = CGRect(origin: .zero, size: size)
        surface.container.layoutIfNeeded()
        return surface
    }

    @Test func blankPaperFillsTheWidthOrShowsAWholePage() {
        let paper = PencilBlankPaper(size: CGSize(width: 768, height: 1024))
        let wide = make(paper)
        #expect(abs(wide.canvas.zoomScale - 1000 / 768) < 0.001)
        #expect(wide.canvas.contentInset.left == 0)

        let whole = make(PencilBlankPaper(size: CGSize(width: 768, height: 1024)), fit: .page)
        let zoom = min(1000.0 / 768, 700.0 / 1024)
        #expect(abs(whole.canvas.zoomScale - zoom) < 0.001)
        #expect(abs(whole.canvas.contentInset.left - (1000 - 768 * zoom) / 2) < 1)
    }

    @Test func thePaperFollowsTheZoom() throws {
        let surface = make(PencilBlankPaper(size: CGSize(width: 768, height: 1024)))
        surface.canvas.setZoomScale(2.5, animated: false)
        let layer = try #require(surface.layers.first?.view)
        #expect(abs(layer.frame.width - 768 * 2.5) < 1)
        #expect(layer.frame.origin == .zero)
        #expect(abs(surface.canvas.contentSize.height - 1024 * 2.5) < 1)
        #expect(layer.layer is CATiledLayer)
    }

    @Test func aSaveHandsOverTheInkInItsStoredSpace() {
        var saved: PKDrawing?
        let paper = OffsetPaper(size: CGSize(width: 800, height: 600), offset: CGPoint(x: 200, y: 0))
        let surface = make(paper, ink: PKDrawing(strokes: [stroke(at: CGPoint(x: 100, y: 100))]),
                           onSave: { saved = $0 })
        // Shown moved out by the offset...
        #expect(abs(surface.canvas.drawing.bounds.minX - 300) < 4)
        // ...and saved back where it is stored.
        surface.canvasViewDrawingDidChange(surface.canvas)
        surface.flush()
        #expect(abs((saved?.bounds.minX ?? 0) - 100) < 4)
    }

    @Test func newPaperKeepsTheInkInItsStoredPlace() {
        let surface = make(OffsetPaper(size: CGSize(width: 800, height: 600), offset: .zero),
                           ink: PKDrawing(strokes: [stroke(at: CGPoint(x: 100, y: 100))]))
        surface.replace(with: OffsetPaper(size: CGSize(width: 1200, height: 600), offset: CGPoint(x: 400, y: 0)))
        #expect(abs(surface.canvas.drawing.bounds.minX - 500) < 4)
        #expect(surface.canvas.undoManager?.canUndo == false)
        // The new sheet is fitted again.
        #expect(abs(surface.canvas.zoomScale - 1000 / 1200) < 0.001)
    }

    @Test func theBoardIsToldHowMuchInkThereIs() {
        let surface = make(PencilBlankPaper(size: CGSize(width: 768, height: 1024)))
        let board = PencilBoard()
        surface.attach(board)
        #expect(board.strokeCount == 0)
        surface.canvas.drawing = PKDrawing(strokes: [stroke(at: CGPoint(x: 50, y: 50))])
        surface.canvasViewDrawingDidChange(surface.canvas)
        #expect(board.strokeCount == 1)
        surface.detach()
        #expect(board.strokeCount == 0)
    }
}

@MainActor
@Suite struct NavBarVisibilityTests {
    @Test func aHoldHidesTheBarOnlyOnItsOwnTab() {
        let visibility = NavBarVisibility()
        let id = UUID()
        #expect(!visibility.isHidden(on: .home))
        visibility.hold(id, on: .home)
        #expect(visibility.isHidden(on: .home))
        // A deep link to another tab finds the bar there.
        #expect(!visibility.isHidden(on: .settings))
        visibility.release(id)
        #expect(!visibility.isHidden(on: .home))
    }

    @Test func theBarStaysHiddenWhileAnyHoldRemains() {
        let visibility = NavBarVisibility()
        let first = UUID(), second = UUID()
        visibility.hold(first, on: .home)
        visibility.hold(second, on: .home)
        visibility.release(first)
        #expect(visibility.isHidden(on: .home))
        visibility.release(second)
        #expect(!visibility.isHidden(on: .home))
    }
}
#endif
