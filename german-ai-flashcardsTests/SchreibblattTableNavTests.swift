//
//  SchreibblattTableNavTests.swift
//  german-ai-flashcardsTests
//
//  "Nächste Tabelle" (Services/SchreibblattTableNav.swift): which writing table the learner is on,
//  and which one the button brings into view. On the A4 five-of-five, two pages: page 1 holds the
//  Vorlage and passes 1–3, page 2 the Vorlage again and passes 4–5.
//

import CoreGraphics
import Testing
@testable import Die_Kartei

@Suite struct SchreibblattTableNavTests {

    static let words: [SchreibblattWord] = [
        .init(german: "das Haus", english: "the house"),
        .init(german: "der Hund", english: "the dog"),
        .init(german: "das Wasser", english: "the water"),
        .init(german: "das Buch", english: "the book"),
        .init(german: "die Stadt", english: "the city"),
    ]

    private let sheet = SchreibblattLayout(words: Self.words, repetitions: 5, prefillEnglish: true)

    private func pass(_ n: Int) -> SchreibblattLayout.Table {
        sheet.writingTables.first { $0.repetition == n }!
    }

    /// A screen-sized window whose top sits a little above `table`'s label.
    private func screen(at table: SchreibblattLayout.Table, height: CGFloat = 300) -> CGRect {
        CGRect(x: 0, y: table.labelFrame.minY - 10, width: sheet.paper.size.width, height: height)
    }

    @Test func writingTablesRunInPassOrder() {
        #expect(sheet.writingTables.map(\.repetition) == [1, 2, 3, 4, 5])
    }

    @Test func theStrokeOnScreenDecidesTheCurrentTable() {
        // Pass 1 and 2 both on screen; the pen just wrote in 2.
        let visible = CGRect(x: 0, y: pass(1).labelFrame.minY, width: sheet.paper.size.width,
                             height: pass(2).frame.maxY - pass(1).labelFrame.minY)
        let row = pass(2).rows[1].germanCell
        let stroke = CGRect(x: row.midX - 20, y: row.midY - 6, width: 40, height: 12)
        #expect(sheet.currentWritingTable(visible: visible, lastStroke: stroke)?.repetition == 2)
        #expect(sheet.tableAfter(visible: visible, lastStroke: stroke)?.repetition == 3)
    }

    @Test func aStrokeScrolledAwayIsIgnored() {
        let row = pass(1).rows[0].germanCell
        let stroke = CGRect(x: row.midX - 20, y: row.midY - 6, width: 40, height: 12)
        // The screen shows pass 3, nothing of pass 1.
        let visible = screen(at: pass(3), height: pass(3).frame.maxY - pass(3).labelFrame.minY + 20)
        #expect(sheet.currentWritingTable(visible: visible, lastStroke: stroke)?.repetition == 3)
        #expect(sheet.tableAfter(visible: visible, lastStroke: stroke)?.repetition == 4)
    }

    @Test func withoutAStrokeTheMostVisibleTableIsCurrent() {
        // All of pass 2 and the top sliver of pass 3.
        let visible = CGRect(x: 0, y: pass(2).labelFrame.minY, width: sheet.paper.size.width,
                             height: pass(3).frame.minY + 10 - pass(2).labelFrame.minY)
        #expect(sheet.currentWritingTable(visible: visible, lastStroke: nil)?.repetition == 2)
    }

    @Test func nextCrossesThePageBreak() {
        let visible = screen(at: pass(3), height: pass(3).frame.maxY - pass(3).labelFrame.minY + 20)
        let next = sheet.tableAfter(visible: visible, lastStroke: nil)
        #expect(next?.repetition == 4)
        #expect(next?.page == 1)
    }

    @Test func onlyTheVorlageOnScreenGoesToTheFirstPassBelow() {
        let vorlage = sheet.tables.first { $0.isVorlage && $0.page == 1 }!
        let visible = CGRect(x: 0, y: vorlage.labelFrame.minY - 10, width: sheet.paper.size.width,
                             height: vorlage.frame.maxY - vorlage.labelFrame.minY + 12)
        #expect(sheet.currentWritingTable(visible: visible, lastStroke: nil) == nil)
        #expect(sheet.tableAfter(visible: visible, lastStroke: nil)?.repetition == 4)
    }

    @Test func theLastPassHasNothingAfterIt() {
        let visible = screen(at: pass(5), height: pass(5).frame.maxY - pass(5).labelFrame.minY + 20)
        #expect(sheet.tableAfter(visible: visible, lastStroke: nil) == nil)
        #expect(sheet.isOnLastTable(visible: visible, lastStroke: nil))
        let earlier = screen(at: pass(4), height: pass(4).frame.maxY - pass(4).labelFrame.minY + 20)
        #expect(!sheet.isOnLastTable(visible: earlier, lastStroke: nil))
    }

    @Test func theRevealRectIncludesTheLabel() {
        let rect = sheet.revealRect(for: pass(2))
        #expect(rect.minY == pass(2).labelFrame.minY)
        #expect(rect.maxY == pass(2).frame.maxY)
    }
}
