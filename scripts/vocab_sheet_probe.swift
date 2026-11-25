// Reads a vocabulary PDF the way the app does — PDFKit's line boxes → `OCRTableLayout` → the
// `VocabListParser` — and prints what each page came out as, so a new sheet from a teacher can be
// checked before it ever reaches a device.
//
//   scripts/vocab_sheet_probe.sh ~/Downloads/M01_L01_Vokabeltraining.pdf
//   scripts/vocab_sheet_probe.sh <pdf> --page 8          # one page, cells and rows in full
//   scripts/vocab_sheet_probe.sh <pdf> --touch-gap 0     # as it read before the touch-merge
//   scripts/vocab_sheet_probe.sh <pdf> --reading-order   # PDFKit's own order, no table rebuild
//   scripts/vocab_sheet_probe.sh <pdf> --rows            # every row of the pages that start on,
//                                                        # one per line: the diffable form
//
// macOS and iOS PDFKit order a bordered table's lines differently (macOS row by row, iOS column by
// column), so a green run here is necessary and not sufficient — check the simulator too.
// See docs/DOCUMENT_DECKS.md.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

typealias UIImage = NSImage

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}
func value(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let found = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return found
}

let readingOrderOnly = flag("--reading-order")
let rowsOnly = flag("--rows")
let onlyPage = value("--page").flatMap(Int.init)
let touchGap: CGFloat = value("--touch-gap").flatMap(Double.init).map { CGFloat($0) } ?? PDFTextExtractor.pdfTouchGap

guard let path = arguments.first else {
    FileHandle.standardError.write(Data("usage: vocab_sheet_probe.swift <pdf> [--page N] [--touch-gap G] [--reading-order]\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
guard let document = PDFDocument(url: url) else {
    FileHandle.standardError.write(Data("could not open \(url.path)\n".utf8))
    exit(1)
}

// MARK: - Per page

func percent(_ value: Double) -> String { String(format: "%.2f", value) }
func show(_ text: String) -> String { text.replacingOccurrences(of: "\t", with: "⇥") }

/// What `OCRTableLayout` saw on this page, for the gate internals the summary can't show.
struct Gate {
    var columns: Int
    var medianGap: CGFloat
    var padded: Bool
    var rebuilt: String?
    var rebuiltConfidence: Double
    var readingConfidence: Double
}

func gate(on page: PDFPage, readingOrder: String) -> Gate {
    guard let lines = PDFTextExtractor.placedLines(on: page), lines.count >= 6 else {
        return Gate(columns: 0, medianGap: 0, padded: false, rebuilt: nil,
                    rebuiltConfidence: 0, readingConfidence: VocabListParser.parse(readingOrder).listConfidence)
    }
    let kept = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.box.height > 0 }
    let heights = kept.map(\.box.height).sorted()
    let lineHeight = heights.isEmpty ? 0 : heights[heights.count / 2]

    let byLeft = kept.indices.sorted { kept[$0].box.minX < kept[$1].box.minX }
    var columnOf = [Int](repeating: 0, count: kept.count)
    var column = 0
    for (position, index) in byLeft.enumerated() where position > 0 {
        if kept[index].box.minX - kept[byLeft[position - 1]].box.minX > 0.04 { column += 1 }
        columnOf[index] = column
    }
    let sizes = Dictionary(grouping: columnOf, by: { $0 }).mapValues(\.count)

    var gaps: [CGFloat] = []
    for columnIndex in Set(columnOf) {
        let sorted = kept.indices.filter { columnOf[$0] == columnIndex }.map { kept[$0] }
            .sorted { $0.box.maxY > $1.box.maxY }
        for position in sorted.indices where position > 0 {
            gaps.append((sorted[position - 1].box.minY - sorted[position].box.maxY) / max(lineHeight, 0.0001))
        }
    }
    let sortedGaps = gaps.sorted()
    let median = sortedGaps.isEmpty ? 0 : sortedGaps[sortedGaps.count / 2]

    let rebuilt = OCRTableLayout.rowText(from: kept, wrapGap: 0.25, touchGap: touchGap)
    return Gate(
        columns: sizes.filter { $0.value >= 3 }.count,
        medianGap: median,
        padded: median >= 1.0,
        rebuilt: rebuilt,
        rebuiltConfidence: rebuilt.map { VocabListParser.parse($0).listConfidence } ?? 0,
        readingConfidence: VocabListParser.parse(readingOrder).listConfidence
    )
}

var wholeText = ""
var summaries: [(page: Int, result: VocabListParser.Page, gate: Gate)] = []

for index in 0..<document.pageCount {
    let number = index + 1
    guard let page = document.page(at: index), let readingOrder = page.string, !readingOrder.isEmpty else { continue }
    let found = gate(on: page, readingOrder: readingOrder)
    var text = readingOrder
    if !readingOrderOnly, let rebuilt = found.rebuilt {
        let parsed = VocabListParser.parse(rebuilt)
        // The same gate as `OCRTableLayout.tableRows`: an English right column, or a gloss table.
        if parsed.looksLikeList,
           VocabListParser.englishShare(of: parsed.rows) >= 0.5 || VocabListParser.isGlossTable(rebuilt),
           parsed.listConfidence >= found.readingConfidence {
            text = rebuilt
        }
    }
    wholeText += "\n\n[Seite \(number)]\n" + text + "\n"
    let parsedPage = VocabListParser.pages("[Seite \(number)]\n" + text).first
        ?? VocabListParser.Page(number: number, rows: [], title: nil, contentLines: 0, pairedLines: 0)
    summaries.append((number, parsedPage, found))

    guard onlyPage == number else { continue }
    print("── page \(number) ───────────────────────────────")
    print("columns \(found.columns) · median gap \(percent(Double(found.medianGap))) · padded \(found.padded)")
    print("rebuilt conf \(percent(found.rebuiltConfidence)) vs reading order \(percent(found.readingConfidence)) · used \(text == readingOrder ? "reading order" : "rebuilt rows")")
    if let rebuilt = found.rebuilt {
        let parsed = VocabListParser.parse(rebuilt)
        print("rebuilt: \(parsed.rows.count) rows · looksLikeList \(parsed.looksLikeList) · englishShare \(percent(VocabListParser.englishShare(of: parsed.rows)))")
        print("\n--- rebuilt rows ---")
        print(show(rebuilt))
    } else {
        print("rebuilt: nil (no two columns of three lines)")
    }
    print("\n--- text ---")
    print(show(text))
    print("\n--- rows ---")
    for row in parsedPage.rows {
        print("  \(row.german) | \(row.english) | \(row.example ?? "-") | \(row.forms ?? "-") | \(row.confident ? "ok" : "GUESS")")
    }
    print("")
}

// MARK: - Summary

if rowsOnly {
    let parsed = VocabListParser.pages(wholeText)
    for page in parsed where page.looksLikeVocab {
        for row in page.rows {
            print("p\(page.number) | \(row.german) | \(row.english) | \(row.example ?? "-") | \(row.forms ?? "-")\(row.confident ? "" : " | GUESS")")
        }
    }
    exit(0)
}

if onlyPage == nil {
    print("page  rows  content  conf   english  vocab  title")
    for entry in summaries {
        let english = VocabListParser.englishShare(of: entry.result.rows)
        print(String(format: "%4d  %4d  %7d  %@   %@   %@   %@",
                     entry.page, entry.result.rows.count, entry.result.contentLines,
                     percent(entry.result.listConfidence), percent(english),
                     entry.result.looksLikeVocab ? " ✓ " : " · ",
                     entry.result.title ?? ""))
    }
}

let parsedPages = VocabListParser.pages(wholeText)
let selected = parsedPages.filter(\.looksLikeVocab).map(\.number)
let rows = parsedPages.filter { selected.contains($0.number) }.flatMap(\.rows)

// The deck's merge-dedup, so the probe reports the cards that would actually be made.
var cards: [VocabListRow] = []
var index: [String: Int] = [:]
for row in rows where row.isComplete {
    let key = row.german.lowercased()
        .replacingOccurrences(of: #"^(der|die|das)\s+"#, with: "", options: .regularExpression)
    if let existing = index[key] {
        if cards[existing].example == nil { cards[existing].example = row.example }
        if cards[existing].forms == nil { cards[existing].forms = row.forms }
    } else {
        index[key] = cards.count
        cards.append(row)
    }
}

print("""

\(document.pageCount) pages · \(parsedPages.count) with text · selected \(selected.map(String.init).joined(separator: ","))
\(cards.count) cards · \(cards.filter { $0.example != nil }.count) with an example · \
\(cards.filter { $0.forms != nil }.count) with a plural · \(cards.filter { !$0.confident }.count) guessed
whole-document listConfidence \(percent(VocabListParser.parse(wholeText).listConfidence)) · touchGap \(percent(Double(touchGap)))
""")
