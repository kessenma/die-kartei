//
//  SchreibblattRenderer.swift
//  german-ai-flashcards
//
//  Draws a writing sheet. This is the only code that does, and that is the point: the Apple
//  Pencil canvas hands it `UIGraphicsGetCurrentContext()` from the ruled view behind the ink, and
//  the PDF writer hands it a page of a `CGPDFContext`. One function, so the screen and the paper
//  cannot drift apart. `SchreibblattLayout` already decided where everything goes.
//
//  Core Graphics and Core Text only — no `UIColor`, no `UIFont`, no `NSAttributedString.draw`.
//  Those would each need a platform fork (`UIGraphicsPushContext` vs. `NSGraphicsContext`) in the
//  one function that must not have one, and the Mac is the platform that needs this most: it has
//  no `PKCanvasView`, so paper is the only writing sheet a Mac gets.
//
//  **Both contexts are y-down when the renderer gets them.** A `UIView.draw(_:)` context already
//  is; `SchreibblattPDF` flips its page to match. So every rect below is sheet space exactly as
//  the layout states it, and the text matrix compensates for the flip in both.
//
//  The sheet is white paper with dark ink in either appearance, deliberately: it is a thing to be
//  printed, and a dark-mode worksheet would print as a black page.
//
//  See docs/SCHREIBBLATT.md.
//

import CoreGraphics
import CoreText
import Foundation

#if canImport(PencilKit)
import PencilKit
#endif
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum SchreibblattRenderer {

    // MARK: - Ink and paper

    struct Palette: Sendable {
        var page: CGColor
        var rule: CGColor
        var tableBorder: CGColor
        var printedText: CGColor
        var label: CGColor
        var headerTitle: CGColor
        /// A school exercise book's pale blue ruling.
        var notebookLine: CGColor

        static let paper = Palette(
            page: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            // Light enough to write over, dark enough to aim at.
            rule: CGColor(srgbRed: 0.76, green: 0.78, blue: 0.82, alpha: 1),
            tableBorder: CGColor(srgbRed: 0.55, green: 0.58, blue: 0.63, alpha: 1),
            printedText: CGColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1),
            label: CGColor(srgbRed: 0.45, green: 0.48, blue: 0.53, alpha: 1),
            headerTitle: CGColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1),
            notebookLine: CGColor(srgbRed: 0.71, green: 0.80, blue: 0.93, alpha: 1)
        )

        /// Cream paper and brown ink, easier on the eyes for a long sheet. On screen only.
        static let sepia = Palette(
            page: CGColor(srgbRed: 0.96, green: 0.92, blue: 0.84, alpha: 1),
            rule: CGColor(srgbRed: 0.79, green: 0.72, blue: 0.62, alpha: 1),
            tableBorder: CGColor(srgbRed: 0.56, green: 0.48, blue: 0.38, alpha: 1),
            printedText: CGColor(srgbRed: 0.24, green: 0.19, blue: 0.13, alpha: 1),
            label: CGColor(srgbRed: 0.50, green: 0.43, blue: 0.34, alpha: 1),
            headerTitle: CGColor(srgbRed: 0.24, green: 0.19, blue: 0.13, alpha: 1),
            notebookLine: CGColor(srgbRed: 0.80, green: 0.70, blue: 0.57, alpha: 1)
        )

        /// Dark paper with light print. The canvas draws its ink in the dark appearance over it, so
        /// a black pen shows white. On screen only: paper is printed white.
        static let dark = Palette(
            page: CGColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1),
            rule: CGColor(srgbRed: 0.29, green: 0.30, blue: 0.33, alpha: 1),
            tableBorder: CGColor(srgbRed: 0.45, green: 0.47, blue: 0.51, alpha: 1),
            printedText: CGColor(srgbRed: 0.88, green: 0.89, blue: 0.91, alpha: 1),
            label: CGColor(srgbRed: 0.60, green: 0.62, blue: 0.66, alpha: 1),
            headerTitle: CGColor(srgbRed: 0.88, green: 0.89, blue: 0.91, alpha: 1),
            notebookLine: CGColor(srgbRed: 0.22, green: 0.30, blue: 0.42, alpha: 1)
        )
    }

    static let ruleWidth: CGFloat = 0.5
    static let borderWidth: CGFloat = 1

    // MARK: - Drawing

    /// Draw one page of `layout` into a y-down context whose coordinates are sheet space.
    ///
    /// `title` is the header strip's text; nil leaves the strip empty, which is what the canvas
    /// wants when the screen's own navigation bar already names the sheet. `lines` rules the paper
    /// around the tables like an exercise book; the tables keep a white ground over it.
    ///
    /// Tables outside the context's clip are skipped, so a canvas tile on a long endless sheet only
    /// sets the text it shows. Safe off the main thread: values and Core Text only.
    static func draw(
        _ layout: SchreibblattLayout,
        page: Int,
        in ctx: CGContext,
        title: String? = nil,
        lines: Bool = false,
        palette: Palette = .paper
    ) {
        guard page >= 0, page < layout.pageCount else { return }
        let origin = layout.pageOrigin(page)

        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Under a y-down CTM, text draws mirrored unless the text matrix undoes the flip.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        ctx.setFillColor(palette.page)
        ctx.fill(layout.pageRect(page))
        if lines {
            drawNotebookLines(layout, page: page, palette: palette, in: ctx)
        }

        if let title, !title.isEmpty {
            let strip = layout.headerFrame.offsetBy(dx: 0, dy: origin.y)
            drawText(title, in: strip.insetBy(dx: 0, dy: 4), baselineY: strip.maxY - 10,
                     size: layout.paper.textSize + 4, color: palette.headerTitle, in: ctx)
            let pageLabel = "\(page + 1) / \(layout.pageCount)"
            drawText(pageLabel, in: strip, baselineY: strip.maxY - 10,
                     size: layout.paper.textSize - 1, color: palette.label,
                     alignedRight: true, in: ctx)
        }

        let clip = ctx.boundingBoxOfClipPath
        for table in layout.tables(onPage: page) where table.labelFrame.union(table.frame).intersects(clip) {
            drawTable(table, layout: layout, lines: lines, palette: palette, in: ctx)
        }
    }

    /// Exercise-book ruling that carries the tables' own rows out to the paper's edges, so every
    /// line beside a table is one of its row lines: across the margins and between tables side by
    /// side, and on down the free paper below the last tables. None in the narrow strip between
    /// one row of tables and the next (it holds the next table's label), so nothing sits off the
    /// grid. Inset half a margin from the paper's edges.
    private static func drawNotebookLines(
        _ layout: SchreibblattLayout, page: Int, palette: Palette, in ctx: CGContext
    ) {
        let paper = layout.paper
        let pageRect = layout.pageRect(page)
        let tables = layout.tables(onPage: page)
        guard !tables.isEmpty else { return }
        let left = pageRect.minX + paper.margin / 2
        let right = pageRect.maxX - paper.margin / 2
        let bottom = pageRect.maxY - paper.margin / 2

        var lines: [CGFloat] = []
        // Tables side by side share a top and their rows: one band of lines each.
        for top in Set(tables.map(\.frame.minY)).sorted() {
            let rows = tables.first { $0.frame.minY == top }?.rows.count ?? 0
            lines += (0...rows).map { top + CGFloat($0) * paper.rowHeight }
        }
        var y = (tables.map(\.frame.maxY).max() ?? bottom) + paper.rowHeight
        while y <= bottom {
            lines.append(y)
            y += paper.rowHeight
        }

        ctx.setStrokeColor(palette.notebookLine)
        ctx.setLineWidth(ruleWidth)
        ctx.beginPath()
        for y in lines {
            ctx.move(to: CGPoint(x: left, y: y))
            ctx.addLine(to: CGPoint(x: right, y: y))
        }
        ctx.strokePath()
    }

    private static func drawTable(
        _ table: SchreibblattLayout.Table,
        layout: SchreibblattLayout,
        lines: Bool,
        palette: Palette,
        in ctx: CGContext
    ) {
        let paper = layout.paper
        if lines {
            ctx.setFillColor(palette.page)
            ctx.fill(table.frame)
        }

        drawText(table.label, in: table.labelFrame,
                 baselineY: table.labelFrame.maxY - 4,
                 size: paper.textSize - 1,
                 color: table.isVorlage ? palette.headerTitle : palette.label, in: ctx)

        // Rules first, then the border, so the border's corners stay clean.
        ctx.setStrokeColor(palette.rule)
        ctx.setLineWidth(ruleWidth)
        ctx.beginPath()
        for row in table.rows.dropLast() {
            ctx.move(to: CGPoint(x: table.frame.minX, y: row.frame.maxY))
            ctx.addLine(to: CGPoint(x: table.frame.maxX, y: row.frame.maxY))
        }
        ctx.strokePath()

        ctx.setStrokeColor(palette.tableBorder)
        ctx.setLineWidth(borderWidth)
        ctx.stroke(table.frame)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: table.columnDividerX, y: table.frame.minY))
        ctx.addLine(to: CGPoint(x: table.columnDividerX, y: table.frame.maxY))
        ctx.strokePath()

        for row in table.rows {
            if row.showsEnglish {
                drawText(row.english, in: row.englishCell.insetBy(dx: paper.cellPadding, dy: 0),
                         baselineY: row.baselineY, size: paper.textSize,
                         color: palette.printedText, in: ctx)
            }
            if row.showsGerman {
                drawText(row.german, in: row.germanCell.insetBy(dx: paper.cellPadding, dy: 0),
                         baselineY: row.baselineY, size: paper.textSize,
                         color: palette.printedText, in: ctx)
            }
        }
    }

    // MARK: - Column width

    /// How wide the English column wants to be for `words`: the longest English as printed, and
    /// half as wide again when the learner writes it by hand too, plus the cell padding. Measured
    /// once, when a sheet is made, and frozen on it (`SchreibblattLayout.englishColumnWidth`), so
    /// a long German phrase gets the rest of the row rather than a fixed 58% of it.
    static func englishColumnWidth(
        for words: [SchreibblattWord],
        prefillEnglish: Bool,
        paper: SchreibblattLayout.Paper = .a4
    ) -> CGFloat {
        let longest = words.map { word -> CGFloat in
            let line = makeLine(word.english, size: paper.textSize, color: Palette.paper.printedText)
            return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }.max() ?? 0
        let handwriting: CGFloat = prefillEnglish ? 1 : 1.5
        return (longest * handwriting + paper.cellPadding * 2).rounded(.up)
    }

    // MARK: - Text

    /// One line, shrunk to fit `cell`'s width and ellipsized only if it still will not go.
    /// `baselineY` is in sheet space; `cell` only bounds it horizontally.
    private static func drawText(
        _ string: String,
        in cell: CGRect,
        baselineY: CGFloat,
        size: CGFloat,
        color: CGColor,
        alignedRight: Bool = false,
        in ctx: CGContext
    ) {
        guard !string.isEmpty, cell.width > 0 else { return }

        var line = makeLine(string, size: size, color: color)
        var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if width > cell.width {
            let fitted = fittedSize(measuredWidth: width, available: cell.width, base: size)
            line = makeLine(string, size: fitted, color: color)
            width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            if width > cell.width,
               let truncated = ellipsized(line, string: string, size: fitted,
                                          color: color, width: cell.width) {
                line = truncated
                width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            }
        }

        ctx.textPosition = CGPoint(x: alignedRight ? cell.maxX - width : cell.minX, y: baselineY)
        CTLineDraw(line, ctx)
    }

    private static func makeLine(_ string: String, size: CGFloat, color: CGColor) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes))
    }

    private static func ellipsized(
        _ line: CTLine, string: String, size: CGFloat, color: CGColor, width: CGFloat
    ) -> CTLine? {
        let token = makeLine("…", size: size, color: color)
        return CTLineCreateTruncatedLine(line, Double(width), .end, token)
    }

    /// The point size at which text that measured `measuredWidth` fits `available`, never below
    /// `floor`. Pure arithmetic, split out so it can be tested without a font on hand.
    static func fittedSize(
        measuredWidth: CGFloat,
        available: CGFloat,
        base: CGFloat,
        floor minimum: CGFloat = 7
    ) -> CGFloat {
        guard measuredWidth > 0, available > 0, base > 0 else { return max(minimum, base) }
        guard measuredWidth > available else { return base }
        let scaled = base * (available / measuredWidth)
        // Round down to a tenth: a size that rounds up can measure wide again on the next pass.
        let stepped = (scaled * 10).rounded(.down) / 10
        return Swift.max(minimum, Swift.min(base, stepped))
    }

    // MARK: - Ink

    #if canImport(PencilKit)
    /// A sheet's handwriting, drawn above the rules. `PKDrawing` is a macOS API too — only the
    /// canvas and the tool picker are iOS-only — so an iPad's sheet exports with its ink from
    /// either platform.
    ///
    /// Rendered at `scale` and composited rather than replayed as vectors: `PKDrawing` exposes no
    /// way to stroke itself into an arbitrary context, and 2x of an A4 page is a reasonable
    /// bitmap. Returns false when there is nothing to draw, so a caller can tell blank from failed.
    @discardableResult
    static func drawInk(
        _ data: Data,
        page: Int,
        in ctx: CGContext,
        layout: SchreibblattLayout,
        scale: CGFloat = 2
    ) -> Bool {
        guard page >= 0, page < layout.pageCount,
              let drawing = try? PKDrawing(data: data),
              !drawing.bounds.isNull, !drawing.bounds.isEmpty else { return false }

        let pageRect = layout.pageRect(page)
        // Only this page's ink, and only if any of it lands here.
        guard drawing.bounds.intersects(pageRect) else { return false }
        // In the light appearance: PencilKit renders with the current trait collection, and in
        // Dark Mode a black pen would come out white on the white page (as the worksheet export).
        var rendered: CGImage?
        #if canImport(UIKit)
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = drawing.image(from: pageRect, scale: scale).cgImage
        }
        #else
        rendered = drawing.image(from: pageRect, scale: scale).cgImage
        #endif
        guard let image = rendered else { return false }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        // `imageFromRect` returns a bottom-up image; the context is y-down, so flip it back over
        // its own rect rather than letting the handwriting come out upside down.
        ctx.translateBy(x: 0, y: pageRect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -pageRect.midY)
        ctx.draw(image, in: pageRect)
        return true
    }
    #endif
}

/// The paper the sheet is written on, on screen. A preference of the learner's, not part of a
/// sheet: the PDF and the printer always get white paper and dark ink.
nonisolated enum SchreibblattPaperStyle: String, CaseIterable, Identifiable, Sendable {
    case white, sepia, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: "Weiß"
        case .sepia: "Sepia"
        case .dark: "Dunkel"
        }
    }

    var palette: SchreibblattRenderer.Palette {
        switch self {
        case .white: .paper
        case .sepia: .sepia
        case .dark: .dark
        }
    }

    /// The ink's appearance: PencilKit turns a dark pen light in the dark one.
    var isDark: Bool { self == .dark }
}
