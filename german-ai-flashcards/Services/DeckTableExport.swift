//
//  DeckTableExport.swift
//  german-ai-flashcards
//
//  A deck's Wortliste as something to send: a PDF table to print or mail a tutor, a CSV for a
//  spreadsheet (or a classmate's own flashcard app), and plain text for a chat message. With
//  "Include my progress" each format also says how every word has gone: missed last time in
//  flashcards, times forgotten, and times written by hand. The PDF tints the rows missed last
//  time, so a tutor sees at a glance what to go over.
//
//  The PDF is drawn with Core Graphics + Core Text into `CGContext(consumer:mediaBox:)`, the same
//  route as `SchreibblattPDF`, so it builds and runs on the Mac too and writes to `Data` for
//  `Transferable`. It draws in the page's own y-up space: a cursor starts at the top margin and
//  walks down, and each cell's text frame is placed with its top at the cursor. Rows are measured
//  first, then paginated, so the footer can say "page 1 of 3".
//
//  The documents hold rows, not bytes: the file is written when someone actually shares.
//

import CoreGraphics
import CoreText
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated enum DeckTableExport {

    // MARK: - PDF

    /// A4 upright, in points.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    private static let margin: CGFloat = 40
    private static let cellPadX: CGFloat = 6
    private static let cellPadY: CGFloat = 5
    private static let footerHeight: CGFloat = 20

    /// Which progress columns an export carries: only those with something in them.
    struct ProgressColumns: Sendable {
        var flashcards: Bool
        var written: Bool

        init(rows: [DeckWordRow], include: Bool) {
            flashcards = include && rows.contains { $0.progress?.hasAnswers == true }
            written = include && rows.contains { $0.written != nil }
        }

        var any: Bool { flashcards || written }
    }

    /// The table as PDF bytes. Nil when there are no rows or Core Graphics refuses a context.
    static func pdf(rows: [DeckWordRow], title: String, includeExamples: Bool, includeProgress: Bool = false,
                    date: Date = .now) -> Data? {
        guard !rows.isEmpty else { return nil }
        let withExamples = includeExamples && rows.contains { !($0.example ?? "").isEmpty }
        let progress = ProgressColumns(rows: rows, include: includeProgress)
        let columns = Columns(width: pageSize.width - margin * 2, withExamples: withExamples, progress: progress)

        // Measure every row once; pagination and drawing both use these.
        let cells = rows.map { RowCells(row: $0, columns: columns) }
        let headerCells = RowCells.header(columns: columns)
        let titleBlock = TitleBlock(title: title, rows: rows, date: date, progress: progress,
                                    width: pageSize.width - margin * 2)

        // Pagination: the title only on page one, the column header on every page.
        let bottom = margin + footerHeight
        var pages: [[Int]] = [[]]
        var cursor = pageSize.height - margin - titleBlock.height - headerCells.height
        for (index, row) in cells.enumerated() {
            if cursor - row.height < bottom, !(pages.last ?? []).isEmpty {
                pages.append([])
                cursor = pageSize.height - margin - headerCells.height
            }
            pages[pages.count - 1].append(index)
            cursor -= row.height
        }

        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: title,
            kCGPDFContextCreator: "Die Kartei",
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else { return nil }

        for (pageIndex, page) in pages.enumerated() {
            ctx.beginPDFPage(nil)
            var top = pageSize.height - margin
            if pageIndex == 0 {
                titleBlock.draw(in: ctx, x: margin, top: top)
                top -= titleBlock.height
            }
            headerCells.draw(in: ctx, columns: columns, x: margin, top: top, fill: Palette.headerFill)
            top -= headerCells.height
            stroke(ctx, from: CGPoint(x: margin, y: top), to: CGPoint(x: pageSize.width - margin, y: top),
                   color: Palette.rule, width: 0.75)

            for (position, index) in page.enumerated() {
                let row = cells[index]
                let fill = row.struggling ? Palette.missedFill : position.isMultiple(of: 2) ? nil : Palette.stripe
                row.draw(in: ctx, columns: columns, x: margin, top: top, fill: fill)
                top -= row.height
                stroke(ctx, from: CGPoint(x: margin, y: top), to: CGPoint(x: pageSize.width - margin, y: top),
                       color: Palette.hairline, width: 0.4)
            }

            drawFooter(in: ctx, title: title, page: pageIndex + 1, of: pages.count)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out.length > 0 ? out as Data : nil
    }

    // MARK: - CSV

    /// Comma-separated, one card per line, with a UTF-8 byte-order mark so Excel reads the
    /// umlauts right (Numbers and Google Sheets ignore it). The article stays on the noun, the
    /// way the card shows it.
    static func csv(rows: [DeckWordRow], includeExamples: Bool, includeProgress: Bool = false) -> Data {
        let withExamples = includeExamples && rows.contains { !($0.example ?? "").isEmpty }
        let progress = ProgressColumns(rows: rows, include: includeProgress)
        var header = ["Deutsch", "English"]
        if withExamples { header.append("Beispiel") }
        // Separate number columns, so a spreadsheet can sort and sum them.
        if progress.flashcards { header += ["Flashcards", "Times forgotten"] }
        if progress.written { header.append("Times written") }
        var lines: [String] = [header.joined(separator: ",")]
        for row in rows {
            var fields = [row.german.withArticle(row.article), row.english]
            if withExamples { fields.append(row.example ?? "") }
            if progress.flashcards {
                fields.append(row.progress?.label ?? "")
                fields.append(row.progress.map { "\($0.lapses)" } ?? "")
            }
            if progress.written { fields.append("\(row.written?.times ?? 0)") }
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        let body = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(body.utf8)
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Text

    /// For a chat message: the deck's name, then one "der Holzhacker = lumberjack" per line, with
    /// "(missed last time, forgotten 2×, written 10×)" after a word when progress is included.
    static func text(rows: [DeckWordRow], title: String, includeExamples: Bool,
                     includeProgress: Bool = false) -> String {
        let progress = ProgressColumns(rows: rows, include: includeProgress)
        var lines = ["\(title) (\(rows.count == 1 ? "1 word" : "\(rows.count) words"))"]
        if progress.any { lines.append(progressSummary(rows, progress)) }
        lines.append("")
        for row in rows {
            var notes: [String] = []
            if progress.flashcards, let p = row.progress {
                if p.state == .missed { notes.append("missed last time") }
                if let forgotten = p.forgotten { notes.append(forgotten) }
            }
            if progress.written, let written = row.written { notes.append("written \(written.label)") }
            let note = notes.isEmpty ? "" : " (\(notes.joined(separator: ", ")))"
            lines.append("\(row.german.withArticle(row.article)) = \(row.english)\(note)")
            if includeExamples, let example = row.example, !example.isEmpty {
                lines.append("   \(example)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "3 missed last time · 12 written by hand", for the top of a PDF or a message.
    static func progressSummary(_ rows: [DeckWordRow], _ progress: ProgressColumns) -> String {
        var parts: [String] = []
        if progress.flashcards {
            let missed = rows.filter { $0.progress?.state == .missed }.count
            let forgotten = rows.filter { ($0.progress?.lapses ?? 0) > 0 }.count
            parts.append("\(missed) missed last time")
            if forgotten > 0 { parts.append("\(forgotten) forgotten at least once") }
        }
        if progress.written {
            parts.append("\(rows.filter { $0.written != nil }.count) written by hand")
        }
        return parts.joined(separator: " · ")
    }

    /// A file name that survives a deck title with slashes, colons or emoji in it.
    static func fileName(for title: String, ext: String) -> String {
        "\(DeckTransfer.fileStem(title, fallback: "wortliste")).\(ext)"
    }

    // MARK: - Drawing pieces

    private enum Palette {
        static let ink = CGColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        static let secondary = CGColor(srgbRed: 0.42, green: 0.42, blue: 0.45, alpha: 1)
        static let tertiary = CGColor(srgbRed: 0.62, green: 0.62, blue: 0.65, alpha: 1)
        static let headerFill = CGColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1)
        static let stripe = CGColor(srgbRed: 0.975, green: 0.975, blue: 0.98, alpha: 1)
        static let rule = CGColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
        static let hairline = CGColor(srgbRed: 0.86, green: 0.86, blue: 0.88, alpha: 1)
        /// A row missed last time: a pale wash of the die-red, light enough to print.
        static let missedFill = CGColor(srgbRed: 1.0, green: 0.93, blue: 0.93, alpha: 1)
        static let missed = CGColor(srgbRed: 0.80, green: 0.17, blue: 0.22, alpha: 1)
        static let knew = CGColor(srgbRed: 0.12, green: 0.55, blue: 0.35, alpha: 1)

        /// The light-mode der/die/das colours from `GenderPalette`, as Core Graphics colours
        /// (paper is always light).
        static func gender(_ gender: Gender) -> CGColor {
            switch gender {
            case .der: hex(0x2F6BFF)
            case .die: hex(0xE23D4C)
            case .das: hex(0x1FA971)
            case .plural: hex(0xD9930E)
            }
        }

        private static func hex(_ value: UInt32) -> CGColor {
            CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }

    private enum Fonts {
        static func regular(_ size: CGFloat) -> CTFont {
            CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }

        static func bold(_ size: CGFloat) -> CTFont {
            CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
                ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        }

        static func italic(_ size: CGFloat) -> CTFont {
            let base = regular(size)
            return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitItalic, .traitItalic) ?? base
        }
    }

    private static func attributed(_ string: String, font: CTFont, color: CGColor) -> NSMutableAttributedString {
        NSMutableAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    }

    /// One block of wrapped text, measured for a width and drawn with its top at a y.
    private struct TextBlock {
        let framesetter: CTFramesetter
        let width: CGFloat
        let height: CGFloat

        init(_ text: NSAttributedString, width: CGFloat) {
            framesetter = CTFramesetterCreateWithAttributedString(text)
            self.width = width
            guard text.length > 0 else { height = 0; return }
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            height = ceil(fit.height)
        }

        func draw(in ctx: CGContext, x: CGFloat, top: CGFloat) {
            guard height > 0 else { return }
            // A point of slack under the measured height, or Core Text may drop the last line.
            let rect = CGRect(x: x, y: top - height - 1, width: width, height: height + 1)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
            ctx.saveGState()
            ctx.textMatrix = .identity
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()
        }
    }

    /// Column widths across the printable width.
    private struct Columns {
        let index: CGFloat = 26
        let german: CGFloat
        let english: CGFloat
        let example: CGFloat
        let flashcards: CGFloat
        let written: CGFloat

        init(width: CGFloat, withExamples: Bool, progress: ProgressColumns) {
            flashcards = progress.flashcards ? 76 : 0
            written = progress.written ? 62 : 0
            let rest = width - index - flashcards - written
            if withExamples {
                german = rest * 0.34
                english = rest * 0.30
                example = rest - german - english
            } else {
                german = rest * 0.5
                english = rest - german
                example = 0
            }
        }

        /// The x of each column's left edge, after `x`: #, Deutsch, English, Beispiel,
        /// Flashcards, Written (a column that is off has no width, so the next one starts there).
        func edges(from x: CGFloat) -> [CGFloat] {
            let widths = [index, german, english, example, flashcards, written]
            var out: [CGFloat] = []
            var at = x
            for width in widths {
                out.append(at)
                at += width
            }
            return out
        }

        var hasExample: Bool { example > 0 }
        var hasFlashcards: Bool { flashcards > 0 }
        var hasWritten: Bool { written > 0 }
    }

    /// A table row's cells, measured.
    private struct RowCells {
        let number: TextBlock
        let german: TextBlock
        let english: TextBlock
        let example: TextBlock?
        let flashcards: TextBlock?
        let written: TextBlock?
        let height: CGFloat
        /// Missed last time: the row gets the red wash.
        var struggling = false

        init(row: DeckWordRow, columns: Columns) {
            let inner = { (width: CGFloat) in max(width - cellPadX * 2, 10) }
            number = TextBlock(attributed("\(row.id)", font: Fonts.regular(8.5), color: Palette.tertiary), width: inner(columns.index))

            let germanText: NSMutableAttributedString
            if let article = row.article, !article.isEmpty {
                let color = Gender(article: article).map(Palette.gender) ?? Palette.ink
                germanText = attributed(article + " ", font: Fonts.bold(11), color: color)
                germanText.append(attributed(row.bareGerman, font: Fonts.bold(11), color: Palette.ink))
            } else {
                germanText = attributed(row.german, font: Fonts.bold(11), color: Palette.ink)
            }
            if let forms = row.forms, !forms.isEmpty {
                germanText.append(attributed("\n" + forms, font: Fonts.regular(8.5), color: Palette.secondary))
            }
            german = TextBlock(germanText, width: inner(columns.german))
            english = TextBlock(attributed(row.english, font: Fonts.regular(11), color: Palette.ink), width: inner(columns.english))
            if columns.hasExample {
                example = TextBlock(attributed(row.example ?? "", font: Fonts.italic(9.5), color: Palette.secondary),
                                    width: inner(columns.example))
            } else {
                example = nil
            }

            if columns.hasFlashcards, let progress = row.progress, progress.hasAnswers {
                let color: CGColor = switch progress.state {
                case .missed: Palette.missed
                case .knew: Palette.knew
                case .new: Palette.tertiary
                }
                let text = attributed(progress.shortLabel, font: Fonts.bold(9), color: color)
                if let forgotten = progress.forgotten {
                    text.append(attributed("\n" + forgotten, font: Fonts.regular(8.5), color: Palette.secondary))
                }
                flashcards = TextBlock(text, width: inner(columns.flashcards))
            } else if columns.hasFlashcards {
                flashcards = TextBlock(attributed("New", font: Fonts.regular(9), color: Palette.tertiary),
                                       width: inner(columns.flashcards))
            } else {
                flashcards = nil
            }
            if columns.hasWritten, let written = row.written {
                let text = attributed(written.label, font: Fonts.bold(9.5), color: Palette.ink)
                text.append(attributed(written.sheets == 1 ? "\n1 sheet" : "\n\(written.sheets) sheets",
                                       font: Fonts.regular(8), color: Palette.tertiary))
                self.written = TextBlock(text, width: inner(columns.written))
            } else {
                self.written = nil
            }
            struggling = columns.hasFlashcards && row.progress?.state == .missed

            height = max(number.height, german.height, english.height, example?.height ?? 0,
                         flashcards?.height ?? 0, self.written?.height ?? 0) + cellPadY * 2
        }

        private init(number: TextBlock, german: TextBlock, english: TextBlock, example: TextBlock?,
                     flashcards: TextBlock?, written: TextBlock?) {
            self.number = number
            self.german = german
            self.english = english
            self.example = example
            self.flashcards = flashcards
            self.written = written
            height = max(german.height, english.height, example?.height ?? 0,
                         flashcards?.height ?? 0, written?.height ?? 0) + cellPadY * 2
        }

        static func header(columns: Columns) -> RowCells {
            let inner = { (width: CGFloat) in max(width - cellPadX * 2, 10) }
            let label = { (text: String, width: CGFloat) in
                TextBlock(attributed(text, font: Fonts.bold(8.5), color: Palette.secondary), width: inner(width))
            }
            return RowCells(
                number: label("#", columns.index),
                german: label("DEUTSCH", columns.german),
                english: label("ENGLISH", columns.english),
                example: columns.hasExample ? label("BEISPIEL", columns.example) : nil,
                flashcards: columns.hasFlashcards ? label("FLASHCARDS", columns.flashcards) : nil,
                written: columns.hasWritten ? label("WRITTEN", columns.written) : nil
            )
        }

        func draw(in ctx: CGContext, columns: Columns, x: CGFloat, top: CGFloat, fill: CGColor?) {
            if let fill {
                ctx.setFillColor(fill)
                ctx.fill(CGRect(x: x, y: top - height, width: pageSize.width - margin * 2, height: height))
            }
            let edges = columns.edges(from: x)
            let textTop = top - cellPadY
            // The smaller number sits on the same line as the 11 pt word.
            number.draw(in: ctx, x: edges[0] + cellPadX, top: textTop - 2)
            german.draw(in: ctx, x: edges[1] + cellPadX, top: textTop)
            english.draw(in: ctx, x: edges[2] + cellPadX, top: textTop)
            example?.draw(in: ctx, x: edges[3] + cellPadX, top: textTop)
            flashcards?.draw(in: ctx, x: edges[4] + cellPadX, top: textTop)
            written?.draw(in: ctx, x: edges[5] + cellPadX, top: textTop)
        }
    }

    /// Page one's heading: the deck name, then its size, gender split and the date.
    private struct TitleBlock {
        let title: TextBlock
        let subtitle: TextBlock
        /// "3 missed last time · 12 written by hand", with the legend for the red rows.
        let progressLine: TextBlock?
        let height: CGFloat

        init(title text: String, rows: [DeckWordRow], date: Date, progress: ProgressColumns, width: CGFloat) {
            title = TextBlock(attributed(text, font: Fonts.bold(18), color: Palette.ink), width: width)
            let line = attributed(rows.count == 1 ? "1 word" : "\(rows.count) words", font: Fonts.regular(10.5), color: Palette.secondary)
            for gender in [Gender.der, .die, .das] {
                let count = rows.filter { $0.gender == gender }.count
                guard count > 0 else { continue }
                line.append(attributed("   ", font: Fonts.regular(10.5), color: Palette.secondary))
                line.append(attributed("\(gender.article) \(count)", font: Fonts.bold(10.5), color: Palette.gender(gender)))
            }
            line.append(attributed("   " + date.formatted(date: .long, time: .omitted), font: Fonts.regular(10.5), color: Palette.secondary))
            subtitle = TextBlock(line, width: width)
            if progress.any {
                let text = attributed(DeckTableExport.progressSummary(rows, progress), font: Fonts.regular(10),
                                      color: Palette.secondary)
                if progress.flashcards {
                    text.append(attributed("   Red rows were missed the last time.", font: Fonts.italic(9.5),
                                           color: Palette.missed))
                }
                progressLine = TextBlock(text, width: width)
            } else {
                progressLine = nil
            }
            height = title.height + 4 + subtitle.height + (progressLine.map { $0.height + 3 } ?? 0) + 14
        }

        func draw(in ctx: CGContext, x: CGFloat, top: CGFloat) {
            title.draw(in: ctx, x: x, top: top)
            subtitle.draw(in: ctx, x: x, top: top - title.height - 4)
            progressLine?.draw(in: ctx, x: x, top: top - title.height - 4 - subtitle.height - 3)
        }
    }

    private static func drawFooter(in ctx: CGContext, title: String, page: Int, of total: Int) {
        let width = pageSize.width - margin * 2
        let left = TextBlock(attributed(title, font: Fonts.regular(8), color: Palette.tertiary), width: width * 0.7)
        let top = margin - 6
        left.draw(in: ctx, x: margin, top: top)

        // The page number as one Core Text line, set flush right by its own width (paragraph
        // styles are a UIKit/AppKit type, and this file stays on Core Text for the Mac).
        let line = CTLineCreateWithAttributedString(
            attributed("\(page) / \(total)", font: Fonts.regular(8), color: Palette.tertiary))
        var ascent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: pageSize.width - margin - lineWidth, y: top - ascent)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func stroke(_ ctx: CGContext, from: CGPoint, to: CGPoint, color: CGColor, width: CGFloat) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - Sharing

/// What the Wortliste shares. `Transferable` rather than a temp file, like `SchreibblattDocument`:
/// the system materializes the attachment itself, and the bytes are only made when someone shares.
struct DeckTableDocument: Transferable {
    enum Format: Sendable { case pdf, csv, text }

    let format: Format
    let rows: [DeckWordRow]
    let title: String
    let includeExamples: Bool
    var includeProgress = false

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            guard let data = DeckTableExport.pdf(rows: document.rows, title: document.title,
                                                 includeExamples: document.includeExamples,
                                                 includeProgress: document.includeProgress) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { DeckTableExport.fileName(for: $0.title, ext: "pdf") }
        .exportingCondition { $0.format == .pdf }

        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            DeckTableExport.csv(rows: document.rows, includeExamples: document.includeExamples,
                                includeProgress: document.includeProgress)
        }
        .suggestedFileName { DeckTableExport.fileName(for: $0.title, ext: "csv") }
        .exportingCondition { $0.format == .csv }

        // As a string, so Messages and WhatsApp paste it inline instead of attaching a file.
        ProxyRepresentation { document in
            DeckTableExport.text(rows: document.rows, title: document.title,
                                 includeExamples: document.includeExamples,
                                 includeProgress: document.includeProgress)
        }
        .exportingCondition { $0.format == .text }
    }
}
