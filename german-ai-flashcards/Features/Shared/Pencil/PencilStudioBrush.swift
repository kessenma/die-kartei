//
//  PencilStudioBrush.swift
//  german-ai-flashcards
//
//  The Atelier's brush: any of PencilKit's inks, any colour, its own opacity and a free width.
//  The plain pens (`PencilPen`) stay a short list of writing tools; this is for drawing.
//
//  Still PencilKit's own inks: no smudge, airbrush or halftone *brush* (PencilKit cannot load a
//  brush of ours). The halftone look is a finish applied to the picture (`ZeichnenHalftone`).
//  A real stamp-brush engine is the Atelier's phase 2 (docs/ZEICHNEN.md).
//

import SwiftUI
#if canImport(UIKit)
import PencilKit
import UIKit
#endif

struct PencilStudioBrush: Equatable {
    enum Ink: String, CaseIterable, Identifiable {
        case pen, pencil, fineliner, fountainPen, marker, watercolor, crayon

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pen: "Stift"
            case .pencil: "Bleistift"
            case .fineliner: "Fineliner"
            case .fountainPen: "Füller"
            case .marker: "Marker"
            case .watercolor: "Aquarell"
            case .crayon: "Wachs"
            }
        }

        var english: String {
            switch self {
            case .pen: "Pen"
            case .pencil: "Pencil"
            case .fineliner: "Fineliner"
            case .fountainPen: "Fountain pen"
            case .marker: "Marker"
            case .watercolor: "Watercolour"
            case .crayon: "Crayon"
            }
        }

        var systemImage: String {
            switch self {
            case .pen: "pencil.tip"
            case .pencil: "pencil"
            case .fineliner: "pencil.line"
            case .fountainPen: "signature"
            case .marker: "highlighter"
            case .watercolor: "paintbrush"
            case .crayon: "scribble.variable"
            }
        }

        /// The width the slider starts at, in points.
        var startWidth: Double {
            switch self {
            case .pen: 3
            case .pencil: 3
            case .fineliner: 2
            case .fountainPen: 4
            case .marker: 16
            case .watercolor: 24
            case .crayon: 12
            }
        }

        #if canImport(UIKit)
        var inkType: PKInkingTool.InkType {
            switch self {
            case .pen: .pen
            case .pencil: .pencil
            case .fineliner: .monoline
            case .fountainPen: .fountainPen
            case .marker: .marker
            case .watercolor: .watercolor
            case .crayon: .crayon
            }
        }

        var widthRange: ClosedRange<Double> {
            let range = inkType.validWidthRange
            return Double(range.lowerBound)...Double(range.upperBound)
        }
        #else
        var widthRange: ClosedRange<Double> { 1...80 }
        #endif
    }

    var ink: Ink = .pen
    /// sRGB as it looks on the paper.
    var red: Double = 0.08
    var green: Double = 0.08
    var blue: Double = 0.10
    /// 0.05…1. PencilKit multiplies it with what the Pencil's pressure gives.
    var opacity: Double = 1
    /// Points, clamped to the ink's own range when the tool is made.
    var width: Double = Ink.pen.startWidth

    var color: Color {
        get { Color(red: red, green: green, blue: blue) }
    }

    static let opacityRange: ClosedRange<Double> = 0.05...1

    #if canImport(UIKit)
    mutating func setColor(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r); green = Double(g); blue = Double(b)
    }

    /// Stored, like the plain pen, as its light-appearance colour, so a piece drawn on black
    /// paper keeps the colour the learner saw.
    func tool(darkPaper: Bool) -> PKInkingTool {
        let alpha = min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        let seen = UIColor(red: red, green: green, blue: blue, alpha: alpha)
        let color = darkPaper ? PKInkingTool.convertColor(seen, from: .dark, to: .light) : seen
        let range = ink.widthRange
        let width = min(max(width, range.lowerBound), range.upperBound)
        return PKInkingTool(ink.inkType, color: color, width: width)
    }
    #endif
}

/// The Atelier's palette: the colours the room's styles came from first (ink black, acid yellow,
/// crimson, salmon, pale lavender-grey), then a few neutrals.
enum PencilStudioPalette {
    struct Swatch: Identifiable, Hashable {
        let id: String
        let red: Double, green: Double, blue: Double
        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    static let swatches: [Swatch] = [
        Swatch(id: "Tinte", red: 0.06, green: 0.06, blue: 0.07),
        Swatch(id: "Säuregelb", red: 0.98, green: 0.95, blue: 0.30),
        Swatch(id: "Karmin", red: 0.76, green: 0.20, blue: 0.29),
        Swatch(id: "Lachs", red: 0.93, green: 0.45, blue: 0.40),
        Swatch(id: "Flieder", red: 0.88, green: 0.88, blue: 0.93),
        Swatch(id: "Weiß", red: 1, green: 1, blue: 1),
        Swatch(id: "Grau", red: 0.55, green: 0.55, blue: 0.58),
        Swatch(id: "Ocker", red: 0.80, green: 0.58, blue: 0.20),
        Swatch(id: "Blau", red: 0.12, green: 0.30, blue: 0.70),
    ]
}
