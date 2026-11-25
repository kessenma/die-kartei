import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

/// The Atelier's finishes: Core Image's screens over the finished picture. PencilKit can't load a
/// halftone *brush*, so phase 1 offers the look as a finish when the piece is saved; a real
/// halftone brush is the stamp engine's job (docs/ZEICHNEN.md ▸ Atelier phase 2).
nonisolated enum ZeichnenHalftone: String, CaseIterable, Identifiable, Sendable {
    case none
    /// Round dots, the newspaper look.
    case dots
    /// Colour halftone: cyan, magenta, yellow and black dots at their own angles.
    case color
    /// Parallel lines that thicken in the dark.
    case lines
    /// Cross-hatching.
    case hatched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Ohne · None"
        case .dots: "Raster · Dots"
        case .color: "Farbraster · Colour dots"
        case .lines: "Linien · Lines"
        case .hatched: "Schraffur · Hatching"
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.slash"
        case .dots: "circle.grid.3x3.fill"
        case .color: "circle.hexagongrid.fill"
        case .lines: "line.3.horizontal"
        case .hatched: "number"
        }
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The picture with this finish, `cell` pixels between dots or lines. Returns the input for
    /// `.none`, or if Core Image fails.
    func apply(to image: CGImage, cell: Double = 9) -> CGImage {
        guard self != .none else { return image }
        let input = CIImage(cgImage: image)
        let center = CGPoint(x: input.extent.midX, y: input.extent.midY)
        let output: CIImage?
        switch self {
        case .none:
            output = input
        case .dots:
            let f = CIFilter.dotScreen()
            f.inputImage = input; f.center = center; f.angle = .pi / 4; f.width = Float(cell); f.sharpness = 0.7
            output = f.outputImage
        case .color:
            let f = CIFilter.cmykHalftone()
            f.inputImage = input; f.center = center; f.width = Float(cell); f.sharpness = 0.7
            f.angle = 0; f.grayComponentReplacement = 1; f.underColorRemoval = 0.5
            output = f.outputImage
        case .lines:
            let f = CIFilter.lineScreen()
            f.inputImage = input; f.center = center; f.angle = .pi / 6; f.width = Float(cell * 0.8); f.sharpness = 0.7
            output = f.outputImage
        case .hatched:
            let f = CIFilter.hatchedScreen()
            f.inputImage = input; f.center = center; f.angle = .pi / 4; f.width = Float(cell); f.sharpness = 0.7
            output = f.outputImage
        }
        guard let output = output?.cropped(to: input.extent),
              let rendered = Self.context.createCGImage(output, from: input.extent)
        else { return image }
        return rendered
    }
}
