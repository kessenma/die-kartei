//
//  SchreibblattVerifierTests.swift
//  german-ai-flashcardsTests
//
//  Runs the writing sheet's two DEBUG self-verifiers (Features/Schreibblatt/SchreibblattDebug.swift)
//  and asserts they pass. They exist for the launch arguments — `-schreibblatt.debugVerifyPDF` is
//  the only way to check the PDF on the **Mac**, where this target does not build, and on a
//  device — but the test host is the app, so iOS can also just call them, and a verifier nobody
//  ever runs is a verifier that quietly rots.
//
//  This is the suite that covers `SchreibblattInkStore` at all: it is FileManager, so the other
//  suites stay away from it.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct SchreibblattVerifierTests {

    @Test func thePDFRoundTripPasses() {
        let result = SchreibblattPDF.runDebugVerification()
        #expect(result.contains("PDF ok"), "\(result)")
    }

    @Test func theInkStoreRoundTripPasses() {
        let result = SchreibblattInkStore.runDebugVerification()
        #expect(result.contains("ink ok"), "\(result)")
    }

    @Test func theInkStoreLeavesNothingBehind() {
        // The verifier deletes its own file; anything else in the folder is a leak from a crash
        // mid-write, which the orphan sweep is there to catch.
        let before = SchreibblattInkStore.orphans(keeping: []).count
        _ = SchreibblattInkStore.runDebugVerification()
        #expect(SchreibblattInkStore.orphans(keeping: []).count == before)
    }

    @Test func aMissingInkFileReadsAsNothingRatherThanThrowing() {
        #expect(SchreibblattInkStore.read("nope.drawing") == nil)
        #expect(SchreibblattInkStore.read(nil) == nil)
        #expect(!SchreibblattInkStore.exists(""))
        #expect(!SchreibblattInkStore.exists(nil))
        // Deleting what is not there is a no-op, not a crash.
        SchreibblattInkStore.delete("nope.drawing")
        SchreibblattInkStore.delete(nil)
    }

    @Test func theDebugOpenArgumentParsesTheScreensItDocuments() {
        #expect(SchreibblattDebugOpen(argument: "hub") == .hub)
        #expect(SchreibblattDebugOpen(argument: "wahl") == .wahl)
        // Forgiving about shape, strict about spelling — a typo must say so, not open the hub.
        #expect(SchreibblattDebugOpen(argument: " HUB ") == .hub)
        #expect(SchreibblattDebugOpen(argument: "sheet") == nil)
        #expect(SchreibblattDebugOpen(argument: "") == nil)
    }
}

// MARK: - The model rebuilds its own geometry

@Suite struct SchreibblattSheetModelTests {

    private func sheet() -> SchreibblattSheet {
        SchreibblattSheet(
            title: "Probe",
            words: [
                .init(german: "das Haus", english: "the house"),
                .init(german: "der Hund", english: "the dog"),
                .init(german: "die Stadt", english: "the city"),
                .init(german: "das Buch", english: "the book"),
                .init(german: "der Löffel", english: "the spoon"),
            ],
            repetitions: 5,
            prefillEnglish: true)
    }

    @Test func aSheetRebuildsANonEmptyLayoutFromItsFrozenWords() {
        // If this ever returns an empty layout the canvas draws nothing and the bug looks like a
        // blank screen rather than a decoding failure.
        let layout = sheet().layout
        #expect(layout.wordCount == 5)
        #expect(layout.pageCount == 2)
        #expect(layout.canvasSize.height > 0)
        #expect(!layout.tables.isEmpty)
    }

    @Test func theFrozenWordsSurviveTheRoundTripThroughTheModel() {
        #expect(sheet().words.map(\.german)
            == ["das Haus", "der Hund", "die Stadt", "das Buch", "der Löffel"])
    }

    @Test func aSheetWithUnreadableWordsIsEmptyRatherThanWrong() {
        let made = sheet()
        made.wordsData = Data("not json".utf8)
        #expect(made.words.isEmpty)
        #expect(made.layout.pageCount == 0)
    }

    @Test func summaryReadsTheWayTheSetupScreenSaysIt() {
        #expect(sheet().summary == "5 Wörter · 5×")
    }
}
