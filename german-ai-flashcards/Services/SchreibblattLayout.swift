//
//  SchreibblattLayout.swift
//  german-ai-flashcards
//
//  Where everything on a writing sheet sits. One Vorlage table with both columns printed, then a
//  blank writing table per repetition: the teacher's "five tables of five", with the German given
//  because the drill is copying, not recall.
//
//  This is the one set of numbers behind both the Apple Pencil canvas and the printed PDF.
//  `SchreibblattRenderer` is handed a `CGContext` by each of them and draws from these rects, so
//  the screen and the paper cannot drift apart. Keeping that promise is why this type is pure:
//  CoreGraphics + Foundation, no ambient scale, no `UIFont`, no `@Environment`, no `ThisDevice`.
//  Like `OCRTableLayout`, it therefore also runs on a Mac and under test.
//
//  Two conventions worth knowing before reading on:
//
//  * **Sheet space.** Every rect here is measured from the top-left of a single continuous space
//    holding all the pages stacked with `pageGap` between them, +y down. That is the canvas's
//    content space directly; the PDF writer subtracts `pageOrigin(_:)` per page and the gap
//    vanishes on paper. The gap is nonzero for *both*, so there is only ever one set of numbers.
//  * **Nothing is measured.** A cell is a rect; fitting text into it is the renderer's job. That
//    is what keeps Core Text out of here.
//
//  See docs/SCHREIBBLATT.md.
//

import CoreGraphics
import Foundation

/// One word pair on a sheet. A snapshot, not a card: a sheet freezes its words so that editing or
/// deleting the deck underneath cannot leave handwriting beside a word that changed.
nonisolated struct SchreibblattWord: Hashable, Identifiable, Codable, Sendable {
    /// The `SavedCard` this came from, so a sheet can point back. Not a relationship.
    var id: UUID
    /// The display form, article included — `String.withArticle(_:)` has already run.
    var german: String
    var english: String

    init(id: UUID = UUID(), german: String, english: String) {
        self.id = id
        self.german = german
        self.english = english
    }
}

nonisolated struct SchreibblattLayout: Equatable, Sendable {

    // MARK: - Paper

    /// The page and its furniture, in points. Injected rather than read from the environment: a
    /// test uses a round synthetic page so its expectations are exact, and A4's 841.8 cannot hide
    /// an off-by-one in float noise.
    struct Paper: Equatable, Sendable {
        var size: CGSize
        var margin: CGFloat
        /// The title strip above the Vorlage, on every page.
        var headerHeight: CGFloat
        /// One writing line. School ruling is 8–9 mm (23–26pt); the default leaves room above it.
        var rowHeight: CGFloat
        /// How far above a row's bottom edge its rule sits, so a descender has somewhere to go.
        var baselineInset: CGFloat
        var tableGap: CGFloat
        /// The label strip above each table ("Vorlage", "1", "2", …).
        var tableLabelHeight: CGFloat
        var englishColumnFraction: CGFloat
        /// The largest size printed text is set at; the renderer shrinks to fit from here.
        var textSize: CGFloat
        var cellPadding: CGFloat
        /// The gutter between stacked pages in sheet space. Never zero — see the header.
        var pageGap: CGFloat
        /// Tables side by side. A4 upright holds one across; turned on its side it holds two, which
        /// puts the teacher's five-of-five on a 2×2 grid. Filled row by row.
        var columns: Int = 1
        var columnGap: CGFloat = 24

        /// Chosen so the teacher's five-of-five lands on two pages with a 28pt (9.9mm) rule —
        /// generous for an adult hand, and above the 7-9mm of school ruling. Changing any of these
        /// moves the page count, which `SchreibblattLayoutTests` asserts on purpose.
        static let a4 = Paper(
            size: CGSize(width: 595.2, height: 841.8),
            margin: 40,
            headerHeight: 44,
            rowHeight: 28,
            baselineInset: 6,
            tableGap: 20,
            tableLabelHeight: 16,
            englishColumnFraction: 0.42,
            textSize: 13,
            cellPadding: 8,
            pageGap: 16
        )

        /// A4 on its side: the same metrics, two tables across.
        static let a4Landscape: Paper = {
            var paper = a4
            paper.size = CGSize(width: a4.size.height, height: a4.size.width)
            paper.columns = 2
            return paper
        }()

        /// The box a page's tables live in, page-local.
        var contentRect: CGRect {
            CGRect(x: margin, y: margin + headerHeight,
                   width: size.width - margin * 2,
                   height: size.height - margin * 2 - headerHeight)
        }

        /// How tall a table of `rows` rows is, label included.
        func tableHeight(rows: Int) -> CGFloat {
            tableLabelHeight + CGFloat(rows) * rowHeight
        }

        /// One table's width: the content box shared out between the columns. With one column it
        /// is the content width exactly, so an upright sheet lays out as it always did.
        var tableWidth: CGFloat {
            let across = CGFloat(max(1, columns))
            return (contentRect.width - columnGap * (across - 1)) / across
        }

        /// The width the screen's "fit the width" fits: the whole page, or on an endless sheet
        /// three or more tables across, two of them (the rest are a scroll sideways).
        var fitWidth: CGFloat {
            columns <= 2 ? size.width : margin * 2 + tableWidth * 2 + columnGap
        }

        /// One endless sheet as big as its tables: `columns` across, as many rows as it takes,
        /// the Vorlage once, no header (it is never printed), and a table's height of free paper
        /// below to scribble on. Tables are A4-upright wide, so a row writes the same either way.
        static func endless(columns: Int, tables: Int, words: Int, base: Paper = .a4) -> Paper {
            var paper = base
            let across = max(1, min(columns, tables))
            let down = max(1, Int((Double(tables) / Double(across)).rounded(.up)))
            let unit = base.tableHeight(rows: max(1, words))
            paper.headerHeight = 0
            paper.tableGap = 32
            paper.columns = across
            paper.columnGap = 32
            paper.size = CGSize(
                width: base.margin * 2 + base.tableWidth * CGFloat(across) + paper.columnGap * CGFloat(across - 1),
                // +0.5 so float noise can never round the last row of tables off the sheet.
                height: base.margin * 2 + unit * CGFloat(down + 1) + paper.tableGap * CGFloat(down) + 0.5)
            return paper
        }
    }

    // MARK: - Output

    struct Row: Equatable, Identifiable, Sendable {
        /// Position within the table, 0-based.
        var id: Int
        var page: Int
        var frame: CGRect
        var englishCell: CGRect
        var germanCell: CGRect
        /// Where a written line should sit, in sheet space.
        var baselineY: CGFloat
        var english: String
        /// Carried even when it is not printed, so a renderer or an answer key never re-joins.
        var german: String
        var showsEnglish: Bool
        var showsGerman: Bool
    }

    struct Table: Equatable, Identifiable, Sendable {
        /// Index into `tables`. Not the repetition number — a Vorlage has none.
        var id: Int
        var page: Int
        /// Which pass this is, 1-based. Nil for a Vorlage.
        var repetition: Int?
        /// The ruled box, excluding the label strip above it.
        var frame: CGRect
        var labelFrame: CGRect
        var label: String
        var columnDividerX: CGFloat
        var rows: [Row]

        var isVorlage: Bool { repetition == nil }
    }

    // MARK: - Inputs, kept so a view can re-derive without the caller

    let paper: Paper
    let words: [SchreibblattWord]
    let repetitions: Int
    let prefillEnglish: Bool
    /// The English column's width in points, measured from the words when the sheet was made
    /// (`SchreibblattRenderer.englishColumnWidth`), so the German, the part written by hand, gets
    /// the rest of the row. Kept within `englishColumnShare` of the table. Nil for sheets made
    /// before it was measured: those keep `paper.englishColumnFraction`, so their ink stays put.
    let englishColumnWidth: CGFloat?

    // MARK: - Geometry

    let pageCount: Int
    /// Every table on the sheet, in reading order, each carrying its page. One Vorlage per page,
    /// first on that page, then that page's writing tables.
    let tables: [Table]
    /// The title strip, page-local, repeated on every page.
    let headerFrame: CGRect

    var wordCount: Int { words.count }

    /// The whole stack, which is the canvas's content size.
    var canvasSize: CGSize {
        CGSize(width: paper.size.width,
               height: CGFloat(pageCount) * paper.size.height
                   + CGFloat(max(0, pageCount - 1)) * paper.pageGap)
    }

    /// Page `page`'s top-left corner in sheet space.
    func pageOrigin(_ page: Int) -> CGPoint {
        CGPoint(x: 0, y: CGFloat(page) * (paper.size.height + paper.pageGap))
    }

    /// Page `page`'s whole rect in sheet space.
    func pageRect(_ page: Int) -> CGRect {
        CGRect(origin: pageOrigin(page), size: paper.size)
    }

    /// Which page a sheet-space y falls on. A y in a gutter belongs to the page above it, and one
    /// off either end clamps, so this is total and every caller gets a drawable page.
    func page(containing y: CGFloat) -> Int {
        guard pageCount > 0 else { return 0 }
        let stride = paper.size.height + paper.pageGap
        let index = Int((max(0, y) / stride).rounded(.down))
        return min(max(0, index), pageCount - 1)
    }

    func tables(onPage page: Int) -> [Table] {
        tables.filter { $0.page == page }
    }

    /// The pages a sheet-space rect touches — what the canvas's `draw(_:)` needs for its dirty rect.
    func pages(intersecting rect: CGRect) -> Range<Int> {
        guard pageCount > 0, !rect.isNull, !rect.isEmpty else { return 0..<0 }
        return page(containing: rect.minY)..<(page(containing: rect.maxY) + 1)
    }

    /// A row of a table: where on the sheet a point is being written.
    struct Cell: Equatable, Sendable {
        /// Index into `tables`.
        var table: Int
        /// The row, 0-based, which is also the word's index in `words`.
        var row: Int
    }

    /// The table row a sheet-space point falls in, or nil when it is off every table (a margin,
    /// a label strip, the free paper). A row is its whole height; sideways, a table reaches half a
    /// gap past its rules, since a word written on past the edge is still that row's.
    func cell(at point: CGPoint) -> Cell? {
        let reach = max(paper.columnGap, paper.cellPadding) / 2
        for table in tables {
            let frame = table.frame.insetBy(dx: -reach, dy: 0)
            guard frame.contains(point), paper.rowHeight > 0 else { continue }
            let row = Int(((point.y - table.frame.minY) / paper.rowHeight).rounded(.down))
            if table.rows.indices.contains(row) { return Cell(table: table.id, row: row) }
        }
        return nil
    }

    /// The least and most of a table the English column may take, whatever the words measure:
    /// never so narrow the printed English shrinks to nothing, never more than half the row.
    static let englishColumnShare: ClosedRange<CGFloat> = 0.22...0.5

    // MARK: - Limits

    /// How many tables of `rows` rows fit on one page, Vorlage included: the rows of tables that
    /// stack top to bottom, times the columns across. At least 1, so pagination can never divide
    /// by zero.
    static func tablesPerPage(rows: Int, paper: Paper = .a4) -> Int {
        tableRowsPerPage(rows: rows, paper: paper) * max(1, paper.columns)
    }

    /// How many tables of `rows` rows stack top to bottom on one page. At least 1.
    static func tableRowsPerPage(rows: Int, paper: Paper = .a4) -> Int {
        let unit = paper.tableHeight(rows: rows)
        guard unit > 0 else { return 1 }
        // n tables need n units plus (n - 1) gaps.
        let n = Int(((paper.contentRect.height + paper.tableGap) / (unit + paper.tableGap)).rounded(.down))
        return max(1, n)
    }

    /// Writing tables per page: every page reprints the Vorlage, so one slot is always spent on it.
    static func writingTablesPerPage(rows: Int, paper: Paper = .a4) -> Int {
        max(1, tablesPerPage(rows: rows, paper: paper) - 1)
    }

    /// The most rows a table can have. Bounded by **two** tables fitting a page, not one: the
    /// Vorlage is reprinted on every page, so a page that holds only one table would hold nothing
    /// to write on. Upright, the two stack, and on A4 at the default metrics this is 11,
    /// comfortably above the teacher's 5. With columns they sit side by side, so one table only
    /// has to fit the page's height (16 on A4 landscape).
    ///
    /// The word picker caps a selection at the upright limit (the default), the smaller of the
    /// two, so a blank sheet can be turned either way without losing a word.
    static func maxWordCount(paper: Paper = .a4) -> Int {
        let stacked: CGFloat = paper.columns >= 2 ? 1 : 2
        let available = paper.contentRect.height - paper.tableGap * (stacked - 1)
            - paper.tableLabelHeight * stacked
        return max(1, Int((available / (paper.rowHeight * stacked)).rounded(.down)))
    }

    /// The most repetitions that stay within `pageBudget` pages. A soft cap: the layout paginates
    /// to any depth, but a worksheet nobody will finish is not a kindness. At least 1.
    static func maxRepetitions(wordCount: Int, paper: Paper = .a4, pageBudget: Int = 6) -> Int {
        let rows = max(1, min(wordCount, maxWordCount(paper: paper)))
        return max(1, writingTablesPerPage(rows: rows, paper: paper) * max(1, pageBudget))
    }

    // MARK: - Building

    /// Lay out a sheet. `repetitions` is the number of *writing* tables; the Vorlage is the model
    /// to copy from and is never one of them. Both it and `words` are clamped, so there is no
    /// unrenderable sheet — the setup screen clamps to the same limits so the learner sees why.
    init(words: [SchreibblattWord], repetitions: Int, prefillEnglish: Bool,
         englishColumnWidth: CGFloat? = nil, paper: Paper = .a4) {
        let rows = min(words.count, Self.maxWordCount(paper: paper))
        let kept = Array(words.prefix(max(0, rows)))
        let passes = max(0, repetitions)

        self.paper = paper
        self.words = kept
        self.repetitions = passes
        self.prefillEnglish = prefillEnglish
        self.englishColumnWidth = englishColumnWidth
        self.headerFrame = CGRect(x: paper.margin, y: paper.margin,
                                  width: paper.size.width - paper.margin * 2,
                                  height: paper.headerHeight)

        guard !kept.isEmpty, passes > 0 else {
            self.pageCount = 0
            self.tables = []
            return
        }

        let content = paper.contentRect
        let unit = paper.tableHeight(rows: kept.count)
        let perPage = Self.writingTablesPerPage(rows: kept.count, paper: paper)
        let pages = Int((Double(passes) / Double(perPage)).rounded(.up))
        let columns = max(1, paper.columns)
        let tableWidth = paper.tableWidth
        let share = Self.englishColumnShare
        let dividerOffset = englishColumnWidth.map {
            min(max($0, tableWidth * share.lowerBound), tableWidth * share.upperBound)
        }.map { $0.rounded() } ?? (tableWidth * paper.englishColumnFraction).rounded()
        // `pageOrigin(_:)` is an instance method and `tables` is not assigned yet, so the same
        // arithmetic is spelled out here. Keep the two in step.
        let pageTop = { (page: Int) in CGFloat(page) * (paper.size.height + paper.pageGap) }

        // A table is never split across a page break, so a page is just a run of whole slots:
        // slot 0 is that page's Vorlage, then its share of the writing tables, filled row by row
        // across the columns.
        var built: [Table] = []
        for page in 0..<pages {
            let written = page * perPage
            let remaining = passes - written
            let slots = 1 + min(perPage, remaining)

            for slot in 0..<slots {
                let repetition = slot == 0 ? nil : written + slot
                let top = pageTop(page) + content.minY
                    + CGFloat(slot / columns) * (unit + paper.tableGap)
                let left = content.minX + CGFloat(slot % columns) * (tableWidth + paper.columnGap)
                let labelFrame = CGRect(x: left, y: top,
                                        width: tableWidth, height: paper.tableLabelHeight)
                let frame = CGRect(x: left, y: top + paper.tableLabelHeight,
                                   width: tableWidth,
                                   height: CGFloat(kept.count) * paper.rowHeight)
                let dividerX = frame.minX + dividerOffset
                let isVorlage = repetition == nil

                let builtRows = kept.enumerated().map { position, word -> Row in
                    let rowFrame = CGRect(x: frame.minX,
                                          y: frame.minY + CGFloat(position) * paper.rowHeight,
                                          width: frame.width, height: paper.rowHeight)
                    return Row(
                        id: position,
                        page: page,
                        frame: rowFrame,
                        englishCell: CGRect(x: rowFrame.minX, y: rowFrame.minY,
                                            width: dividerX - rowFrame.minX,
                                            height: rowFrame.height),
                        germanCell: CGRect(x: dividerX, y: rowFrame.minY,
                                           width: rowFrame.maxX - dividerX,
                                           height: rowFrame.height),
                        baselineY: rowFrame.maxY - paper.baselineInset,
                        english: word.english,
                        german: word.german,
                        // The Vorlage is the model and always prints both. A writing table prints
                        // the English only when asked, and never the German — that is the point.
                        showsEnglish: isVorlage || prefillEnglish,
                        showsGerman: isVorlage
                    )
                }

                built.append(Table(
                    id: built.count,
                    page: page,
                    repetition: repetition,
                    frame: frame,
                    labelFrame: labelFrame,
                    label: isVorlage ? "Vorlage" : "\(repetition ?? 0)",
                    columnDividerX: dividerX,
                    rows: builtRows
                ))
            }
        }

        self.tables = built
        self.pageCount = pages
    }
}

// MARK: - Orientation

/// Which way up the paper is. A knob like the others: frozen once something is written, because
/// turning the page moves every table out from under the ink.
nonisolated enum SchreibblattOrientation: String, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape

    var id: String { rawValue }

    var paper: SchreibblattLayout.Paper {
        switch self {
        case .portrait: .a4
        case .landscape: .a4Landscape
        }
    }

    var title: String {
        switch self {
        case .portrait: "Hochformat"
        case .landscape: "Querformat"
        }
    }

    var systemImage: String {
        switch self {
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }
}

// MARK: - Arrangement

/// How the tables sit: on A4 pages (which way up is `SchreibblattOrientation`), or on one endless
/// sheet in a grid of the learner's choosing. Endless sheets are written on the iPad only; they are
/// not exported or printed.
nonisolated enum SchreibblattArrangement: String, CaseIterable, Identifiable, Sendable {
    case pages
    /// One under another.
    case list
    case two, three, four
    /// Every table in one row, scrolled sideways.
    case row

    var id: String { rawValue }

    var isEndless: Bool { self != .pages }

    static let endless: [SchreibblattArrangement] = [.list, .two, .three, .four, .row]

    /// Tables across, for a sheet of `tables` tables.
    func columns(tables: Int) -> Int {
        switch self {
        case .pages, .list: 1
        case .two: 2
        case .three: 3
        case .four: 4
        case .row: max(1, tables)
        }
    }

    var title: String {
        switch self {
        case .pages: "Seiten"
        case .list: "Liste"
        case .two: "2 nebeneinander"
        case .three: "3 nebeneinander"
        case .four: "4 nebeneinander"
        case .row: "Eine Reihe"
        }
    }
}

/// Which way up the paper is and how the tables sit on it: everything about a sheet's shape that
/// the learner chooses. Frozen with the words once something is written.
nonisolated struct SchreibblattFormat: Hashable, Sendable {
    var orientation: SchreibblattOrientation = .portrait
    var arrangement: SchreibblattArrangement = .pages

    /// Endless sheets have no page budget; this keeps one within reason.
    static let endlessMaxRepetitions = 20

    func paper(wordCount: Int, repetitions: Int) -> SchreibblattLayout.Paper {
        guard arrangement.isEndless else { return orientation.paper }
        let tables = max(1, repetitions) + 1
        // The picker caps a selection at the upright limit; an endless sheet keeps to it too.
        let rows = min(max(1, wordCount), SchreibblattLayout.maxWordCount())
        return .endless(columns: arrangement.columns(tables: tables), tables: tables, words: rows)
    }

    func maxRepetitions(wordCount: Int) -> Int {
        arrangement.isEndless
            ? Self.endlessMaxRepetitions
            : SchreibblattLayout.maxRepetitions(wordCount: wordCount, paper: orientation.paper)
    }

    var title: String {
        arrangement.isEndless ? "Endlos · \(arrangement.title)" : orientation.title
    }
}
