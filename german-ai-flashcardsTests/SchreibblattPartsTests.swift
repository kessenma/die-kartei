//
//  SchreibblattPartsTests.swift
//  german-ai-flashcardsTests
//
//  A big selection written in parts (Services/SchreibblattParts.swift): how the words are shared
//  out, what a checkpoint offers as flashcards, and which part comes next. See docs/SCHREIBBLATT.md.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct SchreibblattPartsTests {

    typealias Parts = SchreibblattParts
    typealias Part = SchreibblattParts.Part

    /// Five parts of ten fresh ids; `finished` are the indices marked done.
    private func parts(_ count: Int = 5, size: Int = 10, finished: Set<Int>) -> [Part] {
        (0..<count).map { Part(index: $0, wordIDs: (0..<size).map { _ in UUID() }, isFinished: finished.contains($0)) }
    }

    // MARK: - Splitting

    @Test func fiftyAtTenIsFiveOfTen() {
        #expect(Parts.sizes(count: 50, partSize: 10) == [10, 10, 10, 10, 10])
    }

    @Test func aRemainderIsSharedOutNotLeftAsAStub() {
        #expect(Parts.sizes(count: 52, partSize: 10) == [9, 9, 9, 9, 8, 8])
        #expect(Parts.sizes(count: 11, partSize: 10) == [6, 5])
    }

    @Test func fewerWordsThanAPartIsOneSheet() {
        #expect(Parts.sizes(count: 7, partSize: 10) == [7])
        #expect(Parts.sizes(count: 0, partSize: 10).isEmpty)
    }

    @Test func splitKeepsEveryWordInOrder() {
        let words = Array(1...23)
        let split = Parts.split(words, partSize: 10)
        #expect(split.map(\.count) == [8, 8, 7])
        #expect(split.flatMap { $0 } == words)
    }

    @Test func sizeLabelSaysARangeOnlyWhenSizesDiffer() {
        #expect(Parts.sizeLabel([10, 10]) == "10")
        #expect(Parts.sizeLabel([9, 9, 8]) == "8–9")
    }

    // MARK: - Checkpoint offers

    @Test func firstPartOffersOnlyItself() {
        let set = parts(finished: [0])
        let options = Parts.practiceOptions(parts: set, current: 0)
        #expect(options.map(\.kind) == [.thisPart])
        #expect(options[0].wordIDs == set[0].wordIDs)
    }

    @Test func secondPartsLastTwoIsEverythingSoFarSoItCollapses() {
        let set = parts(finished: [0, 1])
        let options = Parts.practiceOptions(parts: set, current: 1)
        #expect(options.map(\.kind) == [.thisPart, .lastTwo])
    }

    @Test func thirtyOfFiftyOffersTenTwentyAndThirty() {
        let set = parts(finished: [0, 1, 2])
        let options = Parts.practiceOptions(parts: set, current: 2)
        #expect(options.map(\.kind) == [.thisPart, .lastTwo, .soFar])
        #expect(options.map(\.wordIDs.count) == [10, 20, 30])
        #expect(options[1].wordIDs == set[1].wordIDs + set[2].wordIDs)
        #expect(options[1].detail.hasSuffix("parts 2–3"))
    }

    @Test func theLastPartOffersTheWholeSet() {
        let set = parts(finished: [0, 1, 2, 3, 4])
        let options = Parts.practiceOptions(parts: set, current: 4)
        #expect(options.last?.kind == .whole)
        #expect(options.last?.wordIDs.count == 50)
    }

    /// Only parts written count: a part skipped never joins "so far" or "the last two".
    @Test func anUnfinishedPartIsNotWritten() {
        let set = parts(finished: [0, 2])
        let options = Parts.practiceOptions(parts: set, current: 2)
        #expect(options.map(\.kind) == [.thisPart, .lastTwo])
        #expect(options[1].wordIDs == set[0].wordIDs + set[2].wordIDs)
        #expect(options[1].detail.hasSuffix("parts 1, 3"))
    }

    /// The part just finished counts even before it is saved as finished.
    @Test func theCurrentPartCountsAsWritten() {
        let set = parts(finished: [0])
        let options = Parts.practiceOptions(parts: set, current: 1)
        #expect(options.map(\.kind) == [.thisPart, .lastTwo])
    }

    @Test func partsWithNoCardsLeftOfferNothing() {
        let set = [Part(index: 0, wordIDs: [], isFinished: true)]
        #expect(Parts.practiceOptions(parts: set, current: 0).isEmpty)
    }

    @Test func aSheetOnItsOwnOffersItsWords() {
        let set = parts(1, size: 6, finished: [0])
        let options = Parts.practiceOptions(parts: set, current: 0)
        #expect(options.map(\.kind) == [.thisPart])
        #expect(options[0].title == "Diese Wörter")
    }

    // MARK: - Next part

    @Test func nextIsTheFirstOpenPartAfterThisOne() {
        #expect(Parts.nextPart(parts: parts(finished: [0, 1, 2]), after: 2) == 3)
        #expect(Parts.nextPart(parts: parts(finished: [0, 2, 3]), after: 3) == 4)
    }

    @Test func nextWrapsToAnOpenPartBeforeThisOne() {
        #expect(Parts.nextPart(parts: parts(finished: [0, 2, 3, 4]), after: 4) == 1)
    }

    @Test func noNextOnceEveryPartIsDone() {
        #expect(Parts.nextPart(parts: parts(finished: [0, 1, 2, 3, 4]), after: 4) == nil)
        #expect(Parts.nextPart(parts: parts(finished: [0, 1, 2, 3]), after: 4) == nil)
    }

    // MARK: - The day's log

    @Test func theStudyDayCountsSheetWords() {
        #expect(StudyDayCodec.counterFields.contains("sheetWordsWritten"))
        let day = StudyDay(dayStart: Date())
        #expect(!day.hasActivity)
        day.sheetWordsWritten = 10
        #expect(day.hasActivity)
        #expect(ExperienceService.xp(for: day) == 10)
    }

    @Test func partListNamesARunOrEachPart() {
        let set = parts(finished: [])
        #expect(Parts.partList([set[1], set[2], set[3]]) == "2–4")
        #expect(Parts.partList([set[0], set[2]]) == "1, 3")
        #expect(Parts.partList([set[4]]) == "5")
    }
}
