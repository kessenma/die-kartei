//
//  WorksheetRenderer.swift
//  german-ai-flashcards
//
//  One worksheet page as the teacher will get it back: her slide, untouched and still vector, with
//  the learner's answers written into her blanks in blue, the options they didn't pick struck
//  through (the way a teacher marks "der / den" by hand), marked words highlighted or underlined, a
//  case noted over a gap where the sheet asks for it, whole sentences on the ruled line under an
//  item, and the Pencil ink on top. The one renderer behind the live preview, the slide under the
//  Pencil, and the exported PDF, so what the learner sees is what she receives.
//
//  Everything is drawn in page space: points, origin bottom-left, the coordinates PDFKit's
//  selections report a gap's rectangle in. `draw` expects the context already set up that way
//  (see `pageImage` and `WorksheetExport`). Core Graphics + Core Text only, so the Mac exports the
//  same pages (with the iPad's ink: `PKDrawing` is a macOS API too).
//

import CoreGraphics
import CoreText
import Foundation
import PDFKit
#if canImport(PencilKit)
import PencilKit
#endif
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum WorksheetRenderer {

    /// What to draw over a page. A Pencil-only page has no exercise; its ink is all there is.
    struct Input: Sendable {
        var exercise: WorksheetExercise?
        var geometry: WorksheetGeometry?
        var answers: [String: WorksheetAnswer] = [:]
        var ink: Data?
        /// `-classNotes.debugWorksheetRects 1`: outline every placed gap, to report a misplaced one.
        var outlinesGaps = false
        /// The optional check's marks beside each blank. On the learner's own screen only; the
        /// export and the "what she'll get" preview never set it.
        var showsChecks = false
        /// Her answer key beside each blank ("Lösungen" on the Pencil page). The learner's own
        /// screen only, like the marks; the export and the preview never set it.
        var herAnswers: [String: KeyAnswer] = [:]
    }

    /// One answer from her key, as shown on the slide.
    struct KeyAnswer: Hashable, Sendable {
        var text: String
        /// One of her examples ("Mögliche Übersetzungen"): other answers can be right too.
        var isExample: Bool
    }

    /// Ballpoint blue: reads as the learner's hand on any slide, and clear of the case colors.
    static let inkColor = CGColor(srgbRed: 0.09, green: 0.29, blue: 0.82, alpha: 1)
    static let highlightColor = CGColor(srgbRed: 1, green: 0.90, blue: 0.20, alpha: 0.45)

    /// Smallest share of the line's natural size an answer shrinks to before it moves above the gap.
    static let minimumShrink: CGFloat = 0.6

    // MARK: - A page

    /// Her page, then the answers, then the ink, into a context in page space.
    static func draw(page: PDFPage, input: Input, in ctx: CGContext) {
        draw(cgPage: page.pageRef, bounds: page.bounds(for: .mediaBox), input: input, in: ctx)
    }

    /// The same from Core Graphics' own page: the Pencil's background draws on the main thread
    /// from a `CGPDFDocument` of its own rather than touching the `PDFDocument` an actor owns.
    static func draw(cgPage: CGPDFPage?, bounds: CGRect, input: Input, in ctx: CGContext) {
        ctx.saveGState()
        if let cgPage {
            ctx.drawPDFPage(cgPage)
        }
        ctx.restoreGState()
        if let exercise = input.exercise, let geometry = input.geometry {
            drawAnswers(exercise, geometry: geometry, answers: input.answers, in: ctx)
            if input.outlinesGaps { outline(geometry, in: ctx) }
            if input.showsChecks {
                // With her answers shown, her green tag is the correction: the ✗ doesn't repeat it.
                drawChecks(exercise, geometry: geometry, answers: input.answers,
                           herAnswers: Set(input.herAnswers.keys), in: ctx)
            }
            if !input.herAnswers.isEmpty { drawKey(exercise, geometry: geometry, key: input.herAnswers, in: ctx) }
        }
        if let ink = input.ink {
            drawInk(ink, pageBounds: bounds, in: ctx)
        }
    }

    /// The page as a bitmap `width` points wide at `scale`, for the preview and the Pencil's
    /// background. One page at a time, never a deck's worth (docs/MEMORY.md).
    static func pageImage(page: PDFPage, input: Input, width: CGFloat, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0, width > 0 else { return nil }
        let pixelsWide = Int((width * scale).rounded())
        let pixelsHigh = Int((width * scale * bounds.height / bounds.width).rounded())
        guard let ctx = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        // A bitmap context is y-up already; scale it to page points and slide the box to 0,0.
        let factor = CGFloat(pixelsWide) / bounds.width
        ctx.scaleBy(x: factor, y: factor)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        draw(page: page, input: input, in: ctx)
        return ctx.makeImage()
    }

    // MARK: - Answers

    static func drawAnswers(
        _ exercise: WorksheetExercise,
        geometry: WorksheetGeometry,
        answers: [String: WorksheetAnswer],
        in ctx: CGContext
    ) {
        for item in exercise.items {
            for gap in item.gaps {
                guard let rect = geometry.gaps[gap.key], let answer = answers[gap.key] else { continue }
                // Text read from the ink is already on the page as the ink itself.
                if answer.source != .ink, let text = answer.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    drawGapAnswer(text, in: rect, long: gap.isLong, ctx: ctx)
                }
                if let kasus = answer.kasus {
                    drawCaseTag(kasus, over: rect, ctx: ctx)
                }
            }
            for choice in item.choices {
                guard let rects = geometry.choices[choice.key], let picked = answers[choice.key]?.choice,
                      rects.indices.contains(picked) else { continue }
                for (index, rect) in rects.enumerated() where index != picked {
                    strike(rect, ctx: ctx)
                }
            }
            if item.marks != nil, let marked = answers[item.markKey]?.marks,
               let rects = geometry.words[item.key] {
                for index in marked where rects.indices.contains(index) && rects[index] != .zero {
                    mark(rects[index], style: item.marks ?? .highlight, ctx: ctx)
                }
            }
            if item.writeBelow, answers[item.writeKey]?.source != .ink, let text = answers[item.writeKey]?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                let box = geometry.items[item.key] ?? item.box
                if box != .zero {
                    drawBelow(text, item: item, box: box, geometry: geometry, ctx: ctx)
                }
            }
        }
    }

    /// An answer in its gap: centered on a short gap, from the left on a writing line, sitting on
    /// the underline. Shrinks to `minimumShrink`; beyond that it moves up over the gap at that
    /// size, rather than running over the words after it.
    static func drawGapAnswer(_ text: String, in rect: CGRect, long: Bool, ctx: CGContext) {
        let natural = rect.height * 0.74
        var size = natural
        var width = measure(text, size: size)
        let room = rect.width + (long ? 0 : rect.height * 0.3)
        if width > room {
            size = max(natural * minimumShrink, natural * room / width)
            width = measure(text, size: size)
        }
        let fits = width <= room + 0.5
        let x = long ? rect.minX + rect.height * 0.15 : rect.midX - width / 2
        // The baseline sits a little above the underscores, which hang below the text line.
        let baseline = fits ? rect.minY + rect.height * 0.30 : rect.maxY + 1
        draw(text, at: CGPoint(x: fits ? x : rect.midX - width / 2, y: baseline), size: size,
             color: inkColor, ctx: ctx)
    }

    /// A case noted over its gap, small, in the case's color: "Dat".
    static func drawCaseTag(_ kasus: GrammarCase, over rect: CGRect, ctx: CGContext) {
        let size = rect.height * 0.42
        let text = kasus.short
        let width = measure(text, size: size)
        draw(text, at: CGPoint(x: rect.midX - width / 2, y: rect.maxY + 1), size: size,
             color: caseColor(kasus), ctx: ctx)
    }

    /// A whole sentence on the ruled line under an item: one line height down, starting where the
    /// item's own words start.
    static func drawBelow(_ text: String, item: WorksheetItem, box: CGRect, geometry: WorksheetGeometry, ctx: CGContext) {
        let breaks: Int = item.segments.reduce(0) { count, segment in
            if case .lineBreak = segment { return count + 1 }
            return count
        }
        let lineHeight: CGFloat = box.height / CGFloat(breaks + 1)
        let size = lineHeight * 0.72
        let startX = geometry.words[item.key]?.first(where: { $0 != .zero })?.minX
            ?? box.minX + lineHeight * 1.2
        let available = geometry.pageBounds.maxX - startX - lineHeight
        var fitted = size
        let width = measure(text, size: size)
        if width > available { fitted = max(size * minimumShrink, size * available / width) }
        draw(text, at: CGPoint(x: startX, y: box.minY - lineHeight * 0.95), size: fitted, color: inkColor, ctx: ctx)
    }

    // MARK: - The check's marks (on screen only)

    /// A small mark beside each checked answer: ✓ in teal, ? in grey, ✗ in orange with the
    /// expected form after it. A check made for an answer since edited isn't shown.
    static func drawChecks(
        _ exercise: WorksheetExercise,
        geometry: WorksheetGeometry,
        answers: [String: WorksheetAnswer],
        herAnswers: Set<String> = [],
        in ctx: CGContext
    ) {
        for item in exercise.items {
            for gap in item.gaps {
                guard let rect = geometry.gaps[gap.key], let answer = answers[gap.key],
                      let check = answer.check, answer.text == check.answer || answer.text?
                        .trimmingCharacters(in: .whitespacesAndNewlines) == check.answer else { continue }
                drawMark(check, at: CGPoint(x: rect.maxX + rect.height * 0.15, y: rect.maxY + rect.height * 0.05),
                         size: rect.height * 0.55, limit: geometry.pageBounds.maxX,
                         correction: !herAnswers.contains(gap.key), ctx: ctx)
            }
            for choice in item.choices {
                guard let rects = geometry.choices[choice.key], let last = rects.last,
                      let check = answers[choice.key]?.check else { continue }
                drawMark(check, at: CGPoint(x: last.maxX + last.height * 0.2, y: last.maxY), size: last.height * 0.55,
                         limit: geometry.pageBounds.maxX, ctx: ctx)
            }
            if item.writeBelow, let check = answers[item.writeKey]?.check,
               let box = geometry.items[item.key] ?? (item.box == .zero ? nil : item.box) {
                drawMark(check, at: CGPoint(x: box.minX - box.height * 0.9, y: box.minY - box.height * 0.2),
                         size: box.height * 0.55, limit: geometry.pageBounds.maxX, ctx: ctx)
            }
        }
    }

    /// `corner` is the mark's top-left, in page space (y up).
    private static func drawMark(_ check: WorksheetCheck, at corner: CGPoint, size: CGFloat, limit: CGFloat,
                                 correction showsCorrection: Bool = true, ctx: CGContext) {
        let color: CGColor
        let glyph: String
        switch check.outcome {
        case .right:
            color = CGColor(srgbRed: 0.05, green: 0.55, blue: 0.58, alpha: 1)
            glyph = "✓"
        case .unsure:
            color = CGColor(gray: 0.45, alpha: 1)
            glyph = "?"
        case .wrong:
            color = CGColor(srgbRed: 0.90, green: 0.45, blue: 0.10, alpha: 1)
            glyph = "✗"
        }
        let circle = CGRect(x: corner.x, y: corner.y - size, width: size, height: size)
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.fillEllipse(in: circle)
        ctx.restoreGState()
        let glyphSize = size * 0.72
        let width = measure(glyph, size: glyphSize)
        draw(glyph, at: CGPoint(x: circle.midX - width / 2, y: circle.minY + size * 0.24), size: glyphSize,
             color: CGColor(gray: 1, alpha: 1), ctx: ctx)
        if showsCorrection, check.outcome == .wrong, let correction = check.correction, !correction.isEmpty {
            // The right form after the mark, shrunk to stay on the page.
            let start = circle.maxX + size * 0.2
            var textSize = size * 0.8
            let width = measure(correction, size: textSize)
            let room = limit - start - size * 0.3
            if width > room, room > 0 { textSize = max(textSize * 0.55, textSize * room / width) }
            draw(correction, at: CGPoint(x: start, y: circle.minY + size * 0.24), size: textSize, color: color, ctx: ctx)
        }
    }

    // MARK: - Her answers

    /// Her green: a teacher's pen, apart from the learner's blue and the marks' teal and orange.
    static let keyColor = CGColor(srgbRed: 0.10, green: 0.48, blue: 0.20, alpha: 1)

    /// Her answers on the slide, for the learner to mark their own work: a small green tag after
    /// each blank (past where a check mark sits), or under it when the page has no room to the
    /// right; a choice's right option is ringed. Her examples read "z. B. …".
    static func drawKey(
        _ exercise: WorksheetExercise,
        geometry: WorksheetGeometry,
        key: [String: KeyAnswer],
        in ctx: CGContext
    ) {
        for item in exercise.items {
            for gap in item.gaps {
                guard let rect = geometry.gaps[gap.key], let answer = key[gap.key],
                      !answer.text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                // One blank on a one-line item: after the item's printed words, not over the rest
                // of the sentence ("Ich möchte ___ lernen."). Several blanks keep theirs at each.
                var after = rect.maxX
                if item.gaps.count == 1, let box = geometry.items[item.key], box.height < rect.height * 1.8,
                   box.minY < rect.maxY, box.maxY > rect.minY {
                    after = max(after, box.maxX)
                }
                drawKeyTag(answer, beside: rect, after: after, page: geometry.pageBounds, ctx: ctx)
            }
            for choice in item.choices {
                guard let answer = key[choice.key], let rects = geometry.choices[choice.key],
                      let index = choice.options.firstIndex(where: {
                          WorksheetKeyReader.normalize($0.text) == WorksheetKeyReader.normalize(answer.text)
                      }),
                      rects.indices.contains(index) else { continue }
                let rect = rects[index]
                ctx.saveGState()
                ctx.setStrokeColor(keyColor)
                ctx.setLineWidth(max(1.2, rect.height * 0.08))
                ctx.strokeEllipse(in: rect.insetBy(dx: -rect.height * 0.35, dy: -rect.height * 0.2))
                ctx.restoreGState()
            }
        }
    }

    private static func drawKeyTag(_ answer: KeyAnswer, beside gap: CGRect, after: CGFloat, page: CGRect, ctx: CGContext) {
        let label = answer.isExample ? "z. B. \(answer.text)" : answer.text
        var size = gap.height * 0.6
        var width = measureKey(label, size: size)
        // Past the check mark (0.15 + 0.55 of the gap's height), on the gap's line.
        var x = max(gap.maxX + gap.height * 0.85, after + gap.height * 0.4)
        var below = false
        if x + width + size * 0.8 > page.maxX - gap.height * 0.3 {
            // No room to the right: under the blank, from its left edge, shrunk to stay on the page.
            below = true
            x = gap.minX
            let room = page.maxX - gap.height * 0.3 - x - size * 0.8
            if width > room, room > 0 {
                size = max(size * 0.6, size * room / width)
                width = measureKey(label, size: size)
            }
        }
        let pad = size * 0.4
        let height = size * 1.4
        let y = below ? gap.minY - height - gap.height * 0.08 : gap.midY - height / 2
        let tag = CGRect(x: x, y: y, width: width + pad * 2, height: height)
        let shape = CGPath(roundedRect: tag, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.97, blue: 0.93, alpha: 0.94))
        ctx.fillPath()
        ctx.addPath(shape)
        ctx.setStrokeColor(keyColor.copy(alpha: 0.7) ?? keyColor)
        ctx.setLineWidth(max(0.8, size * 0.07))
        ctx.strokePath()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: tag.minX + pad, y: tag.minY + height * 0.3)
        CTLineDraw(keyLine(label, size: size), ctx)
        ctx.restoreGState()
    }

    /// Her answers in print, not in a hand: they're the key, not anybody's writing.
    private static func keyLine(_ text: String, size: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): keyColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    static func measureKey(_ text: String, size: CGFloat) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(keyLine(text, size: size), nil, nil, nil))
    }

    static func strike(_ rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(inkColor)
        ctx.setLineWidth(max(1.5, rect.height * 0.07))
        ctx.setLineCap(.round)
        let y = rect.midY - rect.height * 0.05
        ctx.move(to: CGPoint(x: rect.minX - 1, y: y))
        ctx.addLine(to: CGPoint(x: rect.maxX + 1, y: y))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func mark(_ rect: CGRect, style: WorksheetMarkStyle, ctx: CGContext) {
        ctx.saveGState()
        switch style {
        case .highlight:
            ctx.setFillColor(highlightColor)
            ctx.fill(rect.insetBy(dx: -1, dy: rect.height * 0.08))
        case .underline:
            ctx.setStrokeColor(inkColor)
            ctx.setLineWidth(max(1.5, rect.height * 0.07))
            let y = rect.minY + rect.height * 0.12
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX + 2, y: y))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func outline(_ geometry: WorksheetGeometry, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.8))
        ctx.setLineWidth(1)
        for rect in geometry.gaps.values { ctx.stroke(rect) }
        for rects in geometry.choices.values { rects.forEach { ctx.stroke($0) } }
        ctx.restoreGState()
    }

    // MARK: - Ink

    /// The page's ink over everything. The canvas works in page points with the origin top-left,
    /// so the drawing's own rect is (0, 0, width, height); rendered at `scale` and laid over the
    /// page box — upright as is, since this context is y-up (Schreibblatt flips because its is
    /// y-down).
    static func drawInk(_ data: Data, pageBounds: CGRect, in ctx: CGContext, scale: CGFloat = 2) {
        #if canImport(PencilKit)
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isNull, !drawing.bounds.isEmpty,
              let image = inkImage(drawing, size: pageBounds.size, scale: scale) else { return }
        ctx.draw(image, in: pageBounds)
        #endif
    }

    #if canImport(PencilKit)
    /// The drawing as an image of the whole page. In light appearance: PencilKit renders with the
    /// current trait collection, and in Dark Mode black ink would come out white on her slide.
    static func inkImage(_ drawing: PKDrawing, size: CGSize, scale: CGFloat) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        #if canImport(UIKit)
        var image: CGImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale).cgImage
        }
        return image
        #else
        guard let image = drawing.image(from: rect, scale: scale).cgImage else { return nil }
        return image
        #endif
    }
    #endif

    // MARK: - Text

    /// The learner's hand, legibly: Noteworthy where the system has it, Helvetica otherwise.
    static func font(size: CGFloat) -> CTFont {
        let preferred = CTFontCreateWithName("Noteworthy-Bold" as CFString, size, nil)
        let name = CTFontCopyPostScriptName(preferred) as String
        return name.hasPrefix("Noteworthy") ? preferred : CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    static func measure(_ text: String, size: CGFloat) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, size: size, color: inkColor), nil, nil, nil))
    }

    private static func line(_ text: String, size: CGFloat, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func draw(_ text: String, at baseline: CGPoint, size: CGFloat, color: CGColor, ctx: CGContext) {
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = baseline
        CTLineDraw(line(text, size: size, color: color), ctx)
        ctx.restoreGState()
    }

    /// `CasePalette`'s light values: the export is a light document whatever the device is set to.
    static func caseColor(_ kasus: GrammarCase) -> CGColor {
        switch kasus {
        case .nominativ: CGColor(srgbRed: 0x4A / 255, green: 0x52 / 255, blue: 0x60 / 255, alpha: 1)
        case .akkusativ: CGColor(srgbRed: 0xE2 / 255, green: 0x70 / 255, blue: 0x1A / 255, alpha: 1)
        case .dativ:     CGColor(srgbRed: 0x0E / 255, green: 0x87 / 255, blue: 0x94 / 255, alpha: 1)
        case .genitiv:   CGColor(srgbRed: 0x8A / 255, green: 0x5A / 255, blue: 0x2B / 255, alpha: 1)
        }
    }
}
