//
//  SchreibblattLayoutTests.swift
//  german-ai-flashcardsTests
//
//  The writing sheet's geometry (Services/SchreibblattLayout.swift): how many tables and rows a
//  set of knobs produces, that nothing lands in a margin or on top of anything else, that a table
//  is never split across a page break, and the sheet-space <-> page-space round trip that keeps
//  the Pencil canvas and the printed PDF showing the same thing.
//
//  Most assertions run on a round synthetic page, so an expectation is exact arithmetic rather
//  than A4's 841.8 hiding an off-by-one in float noise. The A4 defaults get their own section,
//  which pins the page count on purpose: changing a paper metric should fail a test and make
//  someone look, not silently turn a two-page worksheet into three.
//
//  Not covered here: anything drawn. Text fitting, the ink and the PDF bytes belong to
//  `SchreibblattRenderer` and are checked by -schreibblatt.debugVerifyPDF, which can re-read a
//  real PDF. See docs/SCHREIBBLATT.md.
//

import CoreGraphics
import Foundation
import Testing
@testable import Die_Kartei

@Suite struct SchreibblattLayoutTests {

    // MARK: - Fixtures

    /// A page whose every metric is a round number: content box 800 tall, tables of 5 are
    /// 10 + 5*50 = 260 tall, so 3 fit (260*3 + 20*2 = 820 > 800 -> 2 fit; see `slotsPerPage`).
    static let paper = SchreibblattLayout.Paper(
        size: CGSize(width: 600, height: 1000),
        margin: 50,
        headerHeight: 100,
        rowHeight: 50,
        baselineInset: 10,
        tableGap: 20,
        tableLabelHeight: 10,
        englishColumnFraction: 0.5,
        textSize: 12,
        cellPadding: 5,
        pageGap: 40
    )

    static let words: [SchreibblattWord] = [
        .init(german: "das Haus", english: "the house"),
        .init(german: "der Hund", english: "the dog"),
        .init(german: "das Wasser", english: "the water"),
        .init(german: "das Buch", english: "the book"),
        .init(german: "die Stadt", english: "the city"),
    ]

    private func layout(
        words: [SchreibblattWord] = SchreibblattLayoutTests.words,
        repetitions: Int = 2,
        prefillEnglish: Bool = true,
        englishColumnWidth: CGFloat? = nil,
        paper: SchreibblattLayout.Paper = SchreibblattLayoutTests.paper
    ) -> SchreibblattLayout {
        SchreibblattLayout(words: words, repetitions: repetitions, prefillEnglish: prefillEnglish,
                           englishColumnWidth: englishColumnWidth, paper: paper)
    }

    // MARK: - The synthetic page's own numbers

    @Test func syntheticPaperHasTheMetricsTheRestOfTheSuiteAssumes() {
        let paper = Self.paper
        #expect(paper.contentRect == CGRect(x: 50, y: 150, width: 500, height: 800))
        #expect(paper.tableHeight(rows: 5) == 260)
        // 800 + 20 gap allowance / 280 per slot = 2 whole tables.
        #expect(SchreibblattLayout.tablesPerPage(rows: 5, paper: paper) == 2)
        // One of those is always the reprinted Vorlage.
        #expect(SchreibblattLayout.writingTablesPerPage(rows: 5, paper: paper) == 1)
    }

    // MARK: - Counts

    @Test func everyPageReprintsTheVorlageAndCarriesItsShareOfWritingTables() {
        let sheet = layout(repetitions: 3)
        // One writing table per page here, so three passes means three pages.
        #expect(sheet.pageCount == 3)
        #expect(sheet.tables.count == 6)
        #expect(sheet.tables.filter(\.isVorlage).count == 3)
        for page in 0..<sheet.pageCount {
            let onPage = sheet.tables(onPage: page)
            #expect(onPage.first?.isVorlage == true, "the Vorlage comes first on page \(page)")
            #expect(onPage.filter(\.isVorlage).count == 1)
        }
    }

    @Test func repetitionsAreNumberedOnceThroughInOrder() {
        let sheet = layout(repetitions: 3)
        #expect(sheet.tables.compactMap(\.repetition) == [1, 2, 3])
        #expect(sheet.tables.filter(\.isVorlage).allSatisfy { $0.label == "Vorlage" })
        #expect(sheet.tables.compactMap { $0.isVorlage ? nil : $0.label } == ["1", "2", "3"])
    }

    @Test func everyTableHasOneRowPerWordInTheGivenOrder() {
        let sheet = layout(repetitions: 2)
        for table in sheet.tables {
            #expect(table.rows.count == Self.words.count)
            #expect(table.rows.map(\.german) == Self.words.map(\.german))
            #expect(table.rows.map(\.english) == Self.words.map(\.english))
            #expect(table.rows.map(\.id) == Array(0..<Self.words.count))
        }
    }

    @Test func aVorlageIsNotARepetition() {
        // Five passes must mean five writing tables, however they paginate.
        let sheet = layout(repetitions: 5)
        #expect(sheet.tables.filter { !$0.isVorlage }.count == 5)
        #expect(sheet.repetitions == 5)
    }

    // MARK: - Containment

    @Test func everyRowSitsInsideItsTableAndEveryTableInsideItsPageContent() {
        let sheet = layout(repetitions: 4)
        for table in sheet.tables {
            let pageContent = Self.paper.contentRect
                .offsetBy(dx: 0, dy: sheet.pageOrigin(table.page).y)
            #expect(pageContent.contains(table.frame), "table \(table.id) escaped the content box")
            #expect(pageContent.contains(table.labelFrame))
            for row in table.rows {
                #expect(table.frame.contains(row.frame))
                #expect(row.page == table.page)
            }
        }
    }

    @Test func rowsWithinATableNeverOverlapAndTileItExactly() {
        let sheet = layout(repetitions: 1)
        for table in sheet.tables {
            for (above, below) in zip(table.rows, table.rows.dropFirst()) {
                #expect(above.frame.maxY == below.frame.minY, "a gap or an overlap between rows")
            }
            #expect(table.rows.first?.frame.minY == table.frame.minY)
            #expect(table.rows.last?.frame.maxY == table.frame.maxY)
        }
    }

    @Test func tablesOnAPageNeverOverlap() {
        let sheet = layout(repetitions: 4)
        for page in 0..<sheet.pageCount {
            let frames = sheet.tables(onPage: page).map { $0.labelFrame.union($0.frame) }
            for (first, second) in zip(frames, frames.dropFirst()) {
                #expect(first.maxY <= second.minY, "tables collided on page \(page)")
            }
        }
    }

    @Test func theTwoColumnsMeetAtTheDividerAndHonourTheFraction() {
        let sheet = layout(repetitions: 1)
        for table in sheet.tables {
            // Half of the 500pt content box.
            #expect(table.columnDividerX == 300)
            for row in table.rows {
                #expect(row.englishCell.maxX == table.columnDividerX)
                #expect(row.germanCell.minX == table.columnDividerX)
                #expect(row.englishCell.minX == row.frame.minX)
                #expect(row.germanCell.maxX == row.frame.maxX)
                #expect(row.englishCell.height == row.frame.height)
            }
        }
    }

    @Test func baselinesDescendThroughAPageAndSitInsideTheirOwnRow() {
        let sheet = layout(repetitions: 2)
        for table in sheet.tables {
            for row in table.rows {
                #expect(row.baselineY > row.frame.minY)
                #expect(row.baselineY < row.frame.maxY)
                #expect(row.baselineY == row.frame.maxY - Self.paper.baselineInset)
            }
        }
        let baselines = sheet.tables.flatMap { $0.rows.map(\.baselineY) }
        #expect(baselines == baselines.sorted(), "baselines must run down the sheet")
    }

    // MARK: - Pagination

    @Test func aTableIsNeverSplitAcrossAPageBreak() {
        for repetitions in 1...9 {
            let sheet = layout(repetitions: repetitions)
            for table in sheet.tables {
                let page = sheet.pageRect(table.page)
                #expect(page.contains(table.labelFrame.union(table.frame)),
                        "table \(table.id) straddles a page break at \(repetitions) repetitions")
                #expect(table.rows.allSatisfy { $0.page == table.page })
            }
        }
    }

    @Test func pageCountMatchesTheHighestPageUsed() {
        for repetitions in 1...9 {
            let sheet = layout(repetitions: repetitions)
            #expect(sheet.pageCount == (sheet.tables.map(\.page).max() ?? -1) + 1)
            #expect(Set(sheet.tables.map(\.page)) == Set(0..<sheet.pageCount),
                    "no page may be empty")
        }
    }

    @Test func headerIsPageLocalAndSitsAboveTheContentBox() {
        let sheet = layout(repetitions: 3)
        #expect(sheet.headerFrame.minY == Self.paper.margin)
        #expect(sheet.headerFrame.maxY == Self.paper.contentRect.minY)
        #expect(sheet.headerFrame.maxX == Self.paper.size.width - Self.paper.margin)
    }

    // MARK: - Sheet space <-> page space, the anti-drift invariant

    @Test func everyRowRoundTripsFromSheetSpaceIntoItsOwnPage() {
        let sheet = layout(repetitions: 5)
        let page = CGRect(origin: .zero, size: Self.paper.size)
        for table in sheet.tables {
            for row in table.rows {
                #expect(sheet.page(containing: row.frame.midY) == row.page)
                // This is the transform the PDF writer applies; the rect must land on the page.
                let local = row.frame.offsetBy(dx: 0, dy: -sheet.pageOrigin(row.page).y)
                #expect(page.contains(local), "row \(row.id) of table \(table.id) left the page")
            }
        }
    }

    @Test func pageOriginsAreStackedWithTheGutterAndTheCanvasIsAsTallAsThem() {
        let sheet = layout(repetitions: 5)
        let stride = Self.paper.size.height + Self.paper.pageGap
        for page in 0..<sheet.pageCount {
            #expect(sheet.pageOrigin(page).y == CGFloat(page) * stride)
        }
        #expect(sheet.canvasSize.width == Self.paper.size.width)
        #expect(sheet.canvasSize.height
            == CGFloat(sheet.pageCount) * Self.paper.size.height
                + CGFloat(sheet.pageCount - 1) * Self.paper.pageGap)
        // The last page ends exactly at the bottom of the canvas: no trailing gutter.
        #expect(sheet.pageRect(sheet.pageCount - 1).maxY == sheet.canvasSize.height)
    }

    @Test func pageLookupIsTotalAndClampsOffEitherEnd() {
        let sheet = layout(repetitions: 3)
        #expect(sheet.page(containing: -5_000) == 0)
        #expect(sheet.page(containing: 5_000_000) == sheet.pageCount - 1)
        // A y in the gutter belongs to the page above it rather than nowhere.
        let gutter = sheet.pageRect(0).maxY + Self.paper.pageGap / 2
        #expect(sheet.page(containing: gutter) == 0)
    }

    @Test func pagesIntersectingCoversTheDirtyRectAndNothingMore() {
        let sheet = layout(repetitions: 5)
        #expect(sheet.pages(intersecting: sheet.pageRect(0)) == 0..<1)
        #expect(sheet.pages(intersecting: CGRect(origin: .zero, size: sheet.canvasSize))
            == 0..<sheet.pageCount)
        #expect(sheet.pages(intersecting: .null).isEmpty)
        #expect(sheet.pages(intersecting: .zero).isEmpty)
        let spanning = sheet.pageRect(1).insetBy(dx: 0, dy: -Self.paper.pageGap)
        #expect(sheet.pages(intersecting: spanning) == 0..<3)
    }

    // MARK: - prefillEnglish changes what prints, never where it sits

    @Test func prefillEnglishFlipsOnlyTheEnglishFlagOnWritingRows() {
        let on = layout(repetitions: 2, prefillEnglish: true)
        let off = layout(repetitions: 2, prefillEnglish: false)

        for table in on.tables where !table.isVorlage {
            #expect(table.rows.allSatisfy { $0.showsEnglish })
        }
        for table in off.tables where !table.isVorlage {
            #expect(table.rows.allSatisfy { !$0.showsEnglish })
        }
        // The Vorlage is the model either way, so it prints both columns regardless.
        for sheet in [on, off] {
            for table in sheet.tables where table.isVorlage {
                #expect(table.rows.allSatisfy { $0.showsEnglish && $0.showsGerman })
            }
        }
    }

    @Test func theGermanColumnIsNeverPrintedOnAWritingTable() {
        for prefill in [true, false] {
            let sheet = layout(repetitions: 3, prefillEnglish: prefill)
            for table in sheet.tables where !table.isVorlage {
                #expect(table.rows.allSatisfy { !$0.showsGerman },
                        "a writing table would give the answer away")
                // The word is still carried, so nothing has to re-join it later.
                #expect(table.rows.map(\.german) == Self.words.map(\.german))
            }
        }
    }

    @Test func prefillEnglishChangesNoGeometryAtAll() {
        let on = layout(repetitions: 4, prefillEnglish: true)
        let off = layout(repetitions: 4, prefillEnglish: false)
        #expect(on.pageCount == off.pageCount)
        #expect(on.canvasSize == off.canvasSize)
        #expect(on.tables.map(\.frame) == off.tables.map(\.frame))
        #expect(on.tables.map(\.labelFrame) == off.tables.map(\.labelFrame))
        #expect(on.tables.flatMap { $0.rows.map(\.frame) }
            == off.tables.flatMap { $0.rows.map(\.frame) })
        #expect(on.tables.flatMap { $0.rows.map(\.baselineY) }
            == off.tables.flatMap { $0.rows.map(\.baselineY) })
    }

    // MARK: - Limits are tight

    @Test func maxWordCountFitsTwoTablesOnAPageAndOneMoreRowDoesNot() {
        let paper = Self.paper
        let limit = SchreibblattLayout.maxWordCount(paper: paper)
        #expect(limit >= 1)
        // Two tables, because every page reprints the Vorlage: a page holding only one table
        // would hold nothing to write on.
        let fits = 2 * paper.tableHeight(rows: limit) + paper.tableGap
        let overflows = 2 * paper.tableHeight(rows: limit + 1) + paper.tableGap
        #expect(fits <= paper.contentRect.height)
        #expect(overflows > paper.contentRect.height, "maxWordCount is not tight")
        #expect(SchreibblattLayout.tablesPerPage(rows: limit, paper: paper) >= 2)
    }

    @Test func aSelectionLongerThanAPageIsClampedRatherThanSplit() {
        let limit = SchreibblattLayout.maxWordCount(paper: Self.paper)
        let tooMany = (0..<(limit + 4)).map {
            SchreibblattWord(german: "Wort \($0)", english: "word \($0)")
        }
        let sheet = layout(words: tooMany, repetitions: 1)
        #expect(sheet.wordCount == limit)
        #expect(sheet.tables.allSatisfy { $0.rows.count == limit })
        // Clamped from the front, so the learner gets the words they picked first.
        #expect(sheet.words.map(\.german) == tooMany.prefix(limit).map(\.german))
    }

    @Test func maxRepetitionsStaysInsideItsPageBudget() {
        for budget in 1...4 {
            let limit = SchreibblattLayout.maxRepetitions(
                wordCount: Self.words.count, paper: Self.paper, pageBudget: budget)
            #expect(layout(repetitions: limit).pageCount <= budget)
            #expect(layout(repetitions: limit + 1).pageCount > budget, "the budget is not tight")
        }
    }

    // MARK: - Degenerate input

    @Test func noWordsOrNoRepetitionsMakesAnEmptySheetRatherThanABadOne() {
        let noWords = layout(words: [], repetitions: 5)
        #expect(noWords.pageCount == 0)
        #expect(noWords.tables.isEmpty)
        #expect(noWords.canvasSize.height == 0)

        let noPasses = layout(repetitions: 0)
        #expect(noPasses.pageCount == 0)
        #expect(noPasses.tables.isEmpty)

        // Still total: a renderer that asks anyway gets a drawable answer.
        #expect(noWords.page(containing: 123) == 0)
        #expect(noWords.pages(intersecting: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }

    @Test func negativeRepetitionsAreTreatedAsNone() {
        let sheet = layout(repetitions: -3)
        #expect(sheet.repetitions == 0)
        #expect(sheet.tables.isEmpty)
    }

    @Test func oneWordOnePassIsASinglePageWithTwoTables() {
        let sheet = layout(words: [Self.words[0]], repetitions: 1)
        #expect(sheet.pageCount == 1)
        #expect(sheet.tables.count == 2)
        #expect(sheet.tables.map(\.isVorlage) == [true, false])
        #expect(sheet.tables.allSatisfy { $0.rows.count == 1 })
    }

    // MARK: - A4, the paper that actually prints

    @Test func a4DefaultsPaginateTheTeachersFiveOfFiveToTwoPages() {
        let sheet = SchreibblattLayout(words: Self.words, repetitions: 5, prefillEnglish: true)
        // Pinned on purpose: a later tweak to a paper metric should fail here and make someone
        // look, rather than quietly turning a two-page worksheet into three.
        #expect(sheet.pageCount == 2)
        #expect(sheet.tables.filter { !$0.isVorlage }.count == 5)
        #expect(sheet.tables.filter(\.isVorlage).count == 2)
        #expect(SchreibblattLayout.writingTablesPerPage(rows: 5) == 3)
    }

    @Test func a4HasRoomForMoreWordsThanTheTeacherAsksFor() {
        #expect(SchreibblattLayout.maxWordCount() == 11)
        #expect(SchreibblattLayout.maxRepetitions(wordCount: 5) == 18)
    }

    @Test func a4MediaBoxIsTheSizeThePDFWriterWillDeclare() {
        let paper = SchreibblattLayout.Paper.a4
        #expect(paper.size.width == 595.2)
        #expect(paper.size.height == 841.8)
    }

    @Test func a4RowsStayInsideThePageForEveryKnobCombination() {
        for words in 1...SchreibblattLayout.maxWordCount() {
            let picked = (0..<words).map {
                SchreibblattWord(german: "Wort \($0)", english: "word \($0)")
            }
            for repetitions in [1, 3, 5, 12] {
                let sheet = SchreibblattLayout(
                    words: picked, repetitions: repetitions, prefillEnglish: true)
                for table in sheet.tables {
                    #expect(sheet.pageRect(table.page)
                        .contains(table.labelFrame.union(table.frame)),
                        "\(words) words x \(repetitions) overflowed a page")
                }
            }
        }
    }

    // MARK: - On its side: two tables across

    @Test func a4LandscapePutsTheTeachersFiveOfFiveTwoByTwo() {
        let sheet = SchreibblattLayout(words: Self.words, repetitions: 5, prefillEnglish: true,
                                       paper: .a4Landscape)
        #expect(sheet.pageCount == 2)
        let first = sheet.tables(onPage: 0)
        // Row by row: the Vorlage and 1 across the top, 2 and 3 across the bottom.
        #expect(first.map(\.label) == ["Vorlage", "1", "2", "3"])
        #expect(first[0].frame.minY == first[1].frame.minY)
        #expect(first[2].frame.minY == first[3].frame.minY)
        #expect(first[0].frame.minX == first[2].frame.minX)
        #expect(first[1].frame.minX > first[0].frame.maxX)
        #expect(first[2].labelFrame.minY > first[0].frame.maxY)
        #expect(SchreibblattLayout.writingTablesPerPage(rows: 5, paper: .a4Landscape) == 3)
    }

    @Test func landscapeTablesStayOnTheirPageAndNeverOverlap() {
        let paper = SchreibblattLayout.Paper.a4Landscape
        for words in 1...SchreibblattLayout.maxWordCount(paper: paper) {
            let picked = (0..<words).map { SchreibblattWord(german: "Wort \($0)", english: "word \($0)") }
            for repetitions in [1, 3, 5, 12] {
                let sheet = SchreibblattLayout(words: picked, repetitions: repetitions,
                                               prefillEnglish: true, paper: paper)
                for table in sheet.tables {
                    let box = table.labelFrame.union(table.frame)
                    #expect(sheet.pageRect(table.page).contains(box),
                            "\(words) words x \(repetitions) overflowed a page")
                    for other in sheet.tables where other.id > table.id && other.page == table.page {
                        #expect(!box.intersects(other.labelFrame.union(other.frame)),
                                "\(words) words x \(repetitions): tables \(table.id) and \(other.id) overlap")
                    }
                }
            }
        }
    }

    @Test func aSelectionThatFitsUprightAlwaysFitsOnItsSide() {
        // The picker caps at the upright limit, so a blank sheet can turn without losing a word.
        #expect(SchreibblattLayout.maxWordCount(paper: .a4Landscape) >= SchreibblattLayout.maxWordCount())
        #expect(SchreibblattLayout.maxWordCount(paper: .a4Landscape) == 16)
    }

    @Test func sideBySideTheWordLimitIsOneTableTall() {
        var paper = Self.paper
        paper.columns = 2
        let limit = SchreibblattLayout.maxWordCount(paper: paper)
        #expect(paper.tableHeight(rows: limit) <= paper.contentRect.height)
        #expect(paper.tableHeight(rows: limit + 1) > paper.contentRect.height, "maxWordCount is not tight")
        #expect(SchreibblattLayout.tablesPerPage(rows: limit, paper: paper) >= 2)
    }

    @Test func oneColumnSpansTheContentBoxExactly() {
        let sheet = layout(repetitions: 3)
        let content = Self.paper.contentRect
        #expect(Self.paper.tableWidth == content.width)
        #expect(sheet.tables.allSatisfy { $0.frame.minX == content.minX && $0.frame.width == content.width })
    }

    // MARK: - Endless: one sheet, tables in a grid

    @Test func anEndlessSheetIsOnePageWithTheVorlageOnce() {
        for arrangement in SchreibblattArrangement.endless {
            let format = SchreibblattFormat(arrangement: arrangement)
            let sheet = SchreibblattLayout(words: Self.words, repetitions: 7, prefillEnglish: true,
                                           paper: format.paper(wordCount: 5, repetitions: 7))
            #expect(sheet.pageCount == 1, "\(arrangement)")
            #expect(sheet.tables.count == 8, "\(arrangement)")
            #expect(sheet.tables.filter(\.isVorlage).count == 1, "\(arrangement)")
            #expect(sheet.tables.allSatisfy { $0.rows.count == 5 }, "\(arrangement)")
            for table in sheet.tables {
                let box = table.labelFrame.union(table.frame)
                #expect(sheet.pageRect(0).contains(box), "\(arrangement): table \(table.id) is off the sheet")
                for other in sheet.tables where other.id > table.id {
                    #expect(!box.intersects(other.labelFrame.union(other.frame)), "\(arrangement) overlaps")
                }
            }
        }
    }

    @Test func endlessArrangementsSetHowManyTablesSitAcross() {
        func across(_ arrangement: SchreibblattArrangement) -> Int {
            let sheet = SchreibblattLayout(words: Self.words, repetitions: 7, prefillEnglish: true,
                                           paper: SchreibblattFormat(arrangement: arrangement).paper(wordCount: 5, repetitions: 7))
            return Set(sheet.tables.map(\.frame.minX)).count
        }
        #expect(across(.list) == 1)
        #expect(across(.two) == 2)
        #expect(across(.three) == 3)
        #expect(across(.four) == 4)
        #expect(across(.row) == 8)
    }

    @Test func anEndlessSheetLeavesFreePaperBelowItsTables() {
        let paper = SchreibblattFormat(arrangement: .two).paper(wordCount: 5, repetitions: 5)
        let sheet = SchreibblattLayout(words: Self.words, repetitions: 5, prefillEnglish: true, paper: paper)
        let lowest = sheet.tables.map(\.frame.maxY).max() ?? 0
        #expect(paper.size.height - lowest >= paper.tableHeight(rows: 5))
    }

    @Test func endlessTablesAreAsWideAsAnUprightPagesTables() {
        let paper = SchreibblattFormat(arrangement: .four).paper(wordCount: 5, repetitions: 5)
        #expect(abs(paper.tableWidth - SchreibblattLayout.Paper.a4.tableWidth) < 0.01)
        #expect(SchreibblattFormat(arrangement: .four).maxRepetitions(wordCount: 5)
            == SchreibblattFormat.endlessMaxRepetitions)
    }

    // MARK: - The English column, measured

    @Test func aMeasuredEnglishColumnGivesTheGermanTheRestOfTheRow() {
        // The synthetic table is 500 wide: the English may take 110 to 250 of it.
        let left = Self.paper.contentRect.minX
        #expect(layout(englishColumnWidth: 120).tables[0].columnDividerX == left + 120)
        #expect(layout(englishColumnWidth: 40).tables[0].columnDividerX == left + 110)
        #expect(layout(englishColumnWidth: 400).tables[0].columnDividerX == left + 250)
        // Unmeasured (a sheet from before): the paper's fixed split, here half.
        #expect(layout().tables[0].columnDividerX == left + 250)
    }

    @Test func theEnglishColumnIsMeasuredFromTheLongestEnglish() {
        let short = [SchreibblattWord(german: "der Hund", english: "the dog")]
        let long = short + [SchreibblattWord(german: "jemandem (Dat.) beistehen", english: "to stand by someone")]
        let printed = SchreibblattRenderer.englishColumnWidth(for: short, prefillEnglish: true)
        let longer = SchreibblattRenderer.englishColumnWidth(for: long, prefillEnglish: true)
        let handwritten = SchreibblattRenderer.englishColumnWidth(for: long, prefillEnglish: false)
        #expect(printed > SchreibblattLayout.Paper.a4.cellPadding * 2)
        #expect(longer > printed)
        // Written by hand, the English needs room to write in, not just to print.
        #expect(handwritten > longer)
        // Upright, a long phrase's German gets more than the old fixed 58% of the row.
        let sheet = SchreibblattLayout(words: long, repetitions: 3, prefillEnglish: true,
                                       englishColumnWidth: longer)
        let row = sheet.tables[1].rows[1]
        #expect(row.germanCell.width > row.frame.width * (1 - SchreibblattLayout.Paper.a4.englishColumnFraction))
    }

    // MARK: - The word snapshot

    @Test func wordsRoundTripThroughCodableSoASheetCanFreezeThem() throws {
        let data = try JSONEncoder().encode(Self.words)
        let back = try JSONDecoder().decode([SchreibblattWord].self, from: data)
        #expect(back == Self.words)
        #expect(back.map(\.id) == Self.words.map(\.id), "a sheet must keep pointing at its cards")
    }

    // MARK: - Where the pen is (the crib sheet's marker)

    @Test func aPointInATableFindsItsRow() {
        // Page 0: the Vorlage's rows start at 160, table 1's at 440 (150 + 280 + the 10pt label).
        let sheet = layout(repetitions: 2)
        #expect(sheet.cell(at: CGPoint(x: 300, y: 170)) == .init(table: 0, row: 0))
        #expect(sheet.cell(at: CGPoint(x: 300, y: 465)) == .init(table: 1, row: 0))
        #expect(sheet.cell(at: CGPoint(x: 300, y: 640)) == .init(table: 1, row: 4))
        // Page 1 starts at 1040; its writing table's rows at 1480, so row 2 spans 1580..<1630.
        #expect(sheet.cell(at: CGPoint(x: 300, y: 1590)) == .init(table: 3, row: 2))
    }

    @Test func aWordWrittenPastTheRuleStillBelongsToItsRow() {
        let sheet = layout(repetitions: 1)
        // Half a column gap (12) past the table's right edge at 550.
        #expect(sheet.cell(at: CGPoint(x: 560, y: 465)) == .init(table: 1, row: 0))
        #expect(sheet.cell(at: CGPoint(x: 570, y: 465)) == nil)
    }

    @Test func offEveryTableThereIsNoRow() {
        let sheet = layout(repetitions: 1)
        #expect(sheet.cell(at: CGPoint(x: 300, y: 435)) == nil, "a table's label strip")
        #expect(sheet.cell(at: CGPoint(x: 20, y: 465)) == nil, "the margin")
        #expect(sheet.cell(at: CGPoint(x: 300, y: 100)) == nil, "the header")
        #expect(sheet.cell(at: CGPoint(x: 300, y: 900)) == nil, "the paper below the tables")
    }
}
