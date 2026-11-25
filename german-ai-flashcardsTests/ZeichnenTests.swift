//
//  ZeichnenTests.swift
//  german-ai-flashcardsTests
//
//  The Zeichnen room's pure parts: the word key, the three sync codecs (round trips, two devices
//  adding pictures, counters adding up), the file root, the gallery prompt, the Quick Draw state
//  machine, and the paint-by-number generator. See docs/ZEICHNEN.md.
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

// MARK: - Word key

@Suite struct WordArtKeyTests {
    @Test func dropsTheArticleAndCase() {
        #expect(WordArtKey.make("der Tisch") == "tisch")
        #expect(WordArtKey.make("Tisch") == "tisch")
        #expect(WordArtKey.make("  das   Haus  am See ") == "haus am see")
    }

    @Test func aLoneArticleIsAWord() {
        #expect(WordArtKey.make("die") == "die")
    }

    @Test func umlautsMakeDifferentWords() {
        #expect(WordArtKey.make("der Bär") != WordArtKey.make("die Bar"))
        #expect(WordArtKey.make("die Straße") == "straße")
    }

    @Test func theFolderIsStableAndASCII() {
        let a = WordArtKey.folderName(for: "straße")
        #expect(a == WordArtKey.folderName(for: "straße"))
        let ascii = a.allSatisfy { $0.isASCII }
        #expect(ascii)
        #expect(a != WordArtKey.folderName(for: "strasse"))
    }
}

// MARK: - Sync

@MainActor
@Suite struct WordArtSyncTests {
    private func container() -> ModelContainer {
        ModelContainer.inMemory([WordArtwork.self, WordDrawingStat.self, QuickDrawSet.self])
    }

    @Test func anArtworkRoundTrips() throws {
        let a = WordArtwork(wordKey: "tisch", germanWord: "der Tisch", english: "the table", kind: .quick,
                            fileName: "x-1.png", styleRaw: nil)
        a.modeRaw = QuickDrawMode.recall.rawValue
        a.recalled = false
        a.starred = true
        a.inkFileName = "x.drawing"
        let payload = WordArtworkCodec.known(a)

        let context = ModelContext(container())
        let name = WordArtworkCodec.recordName(for: a)
        let copy = try #require(WordArtworkCodec.insert(payload, name: name, in: context))
        #expect(WordArtworkCodec.known(copy) == payload)
        #expect(copy.id == a.id)
    }

    @Test func picturesFromTwoDevicesAreTwoRecords() {
        let one = WordArtwork(wordKey: "tisch", germanWord: "der Tisch", english: "the table", kind: .ai, fileName: "a.png")
        let two = WordArtwork(wordKey: "tisch", germanWord: "der Tisch", english: "the table", kind: .ai, fileName: "b.png")
        #expect(WordArtworkCodec.recordName(for: one) != WordArtworkCodec.recordName(for: two))
    }

    @Test func drawingCountsAddUpAcrossDevices() {
        let spec = WordDrawingStatCodec.spec
        let ipad = WordDrawingStat(key: "tisch", germanWord: "der Tisch", english: "the table")
        ipad.quickCount = 3
        ipad.recallRight = 2
        let phone = WordDrawingStat(key: "tisch", germanWord: "der Tisch", english: "the table")
        phone.quickCount = 2
        phone.studioCount = 1
        let l = SyncMerge.compose(base: nil, known: WordDrawingStatCodec.known(ipad), spec: spec, slot: "ipad", now: 10)
        let r = SyncMerge.compose(base: nil, known: WordDrawingStatCodec.known(phone), spec: spec, slot: "phone", now: 20)
        for merged in [SyncMerge.merge(ancestor: nil, local: l, remote: r, spec: spec),
                       SyncMerge.merge(ancestor: nil, local: r, remote: l, spec: spec)] {
            let flat = SyncMerge.flatten(merged, spec: spec)
            #expect(flat.int("quickCount") == 5)
            #expect(flat.int("studioCount") == 1)
            #expect(flat.int("recallRight") == 2)
        }
    }

    @Test func aStatIsNamedByItsWord() {
        let a = WordDrawingStat(key: "tisch", germanWord: "der Tisch", english: "")
        let b = WordDrawingStat(key: "tisch", germanWord: "Tisch", english: "table")
        #expect(WordDrawingStatCodec.recordName(for: a) == WordDrawingStatCodec.recordName(for: b))
    }

    @Test func aSetKeepsItsOrderAndItsDate() throws {
        let ids = [UUID(), UUID(), UUID()]
        let set = QuickDrawSet(name: "Küche", cardIDs: ids, createdAt: Date(timeIntervalSince1970: 1000))
        let payload = QuickDrawSetCodec.known(set)
        let context = ModelContext(container())
        let copy = try #require(QuickDrawSetCodec.insert(payload, name: QuickDrawSetCodec.recordName(for: set), in: context))
        #expect(copy.cardIDs == ids)
        #expect(copy.updatedAt == set.updatedAt)
        #expect(copy.name == "Küche")
    }

    @Test func theWordArtFolderSyncs() {
        #expect(FileSyncDocument.roots.contains(WordArtStore.rootName))
    }

    @Test func theStudyDayCountsDrawing() {
        #expect(StudyDayCodec.counterFields.contains("wordsDrawn"))
        #expect(StudyDayCodec.counterFields.contains("drawingSeconds"))
        let day = StudyDay(dayStart: Date())
        day.wordsDrawn = 3
        #expect(day.hasActivity)
        #expect(ExperienceService.xp(for: day) >= 3)
    }
}

// MARK: - Prompts

@Suite struct WordArtPromptTests {
    @Test func everyStyleIsInItsPromptAndNoTextIsAsked() {
        for style in WordArtStyle.allCases {
            let prompt = CardIllustrationPrompts.artPrompt(englishTranslation: "the table", wordType: "noun", style: style)
            #expect(prompt.contains(style.promptFragment))
            #expect(prompt.contains(CardIllustrationPrompts.noTextClause))
            #expect(!prompt.contains("plain empty background"))
        }
    }

    @Test func galleryPicturesAreReferenceSized() {
        let request = CardIllustrationPrompts.artRequest(englishTranslation: "to run", wordType: "verb", style: .skizze)
        #expect(request.maxPixel == WordArtStore.artMaxPixel)
        #expect(request.cloudPrompt.contains("a person performing the action: run"))
    }
}

// MARK: - Quick Draw

@MainActor
@Suite struct QuickDrawSessionTests {
    private func words(_ n: Int) -> [ZeichnenWord] {
        (0..<n).map { i in
            ZeichnenWord(id: UUID(), word: GameWord(german: "Wort\(i)", english: "word \(i)", article: "das")!,
                         deckID: UUID(), deckTitle: "Deck")
        }
    }

    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    @Test func copyRunsAdvanceOnNext() {
        let clock = Clock()
        let s = QuickDrawSession(words: words(2), mode: .copy, secondsPerWord: 40, keepByDefault: false, now: { clock.now })
        clock.now += 12
        s.endDrawing(ink: Data([1]))
        #expect(s.phase == .drawing)
        #expect(s.index == 1)
        #expect(s.turns[0].seconds == 12)
        #expect(s.turns[0].recalled == nil)
        s.endDrawing(ink: nil)
        #expect(s.phase == .finished)
        #expect(s.drawnTurns.count == 1)
    }

    @Test func recallRunsRevealThenMark() {
        let s = QuickDrawSession(words: words(2), mode: .recall, secondsPerWord: 40, keepByDefault: true)
        s.endDrawing(ink: Data([1]))
        #expect(s.phase == .reveal)
        #expect(s.revealInk == Data([1]))
        #expect(s.index == 0)
        s.mark(knewIt: false)
        #expect(s.phase == .drawing)
        #expect(s.index == 1)
        #expect(s.missed.count == 1)
        // Kept by default, but only what was drawn.
        #expect(s.keep == [s.turns[0].id])
    }

    @Test func theClockIsCappedAtTheWordsTime() {
        let clock = Clock()
        let s = QuickDrawSession(words: words(1), mode: .copy, secondsPerWord: 20, keepByDefault: false, now: { clock.now })
        clock.now += 95
        #expect(s.remaining(at: clock.now) == 0)
        s.endDrawing(ink: Data([1]))
        #expect(s.turns[0].seconds == 20)
    }

    @Test func blankPagesCannotBeKept() {
        let s = QuickDrawSession(words: words(2), mode: .copy, secondsPerWord: 40, keepByDefault: false)
        s.endDrawing(ink: nil)
        s.endDrawing(ink: Data([2]))
        s.toggleKeep(s.turns[0].id)
        #expect(s.keep.isEmpty)
        s.keepAll()
        #expect(s.turnsToKeep.map(\.id) == [s.turns[1].id])
        s.keepNone()
        #expect(s.turnsToKeep.isEmpty)
    }

    @Test func finishingEarlyCountsTheRevealedWordAsMissed() {
        let s = QuickDrawSession(words: words(3), mode: .recall, secondsPerWord: 40, keepByDefault: false)
        s.endDrawing(ink: Data([1]))
        s.finishEarly()
        #expect(s.phase == .finished)
        #expect(s.turns.count == 1)
        #expect(s.turns[0].recalled == false)
    }

    @Test func anEmptyRunIsAlreadyOver() {
        let s = QuickDrawSession(words: [], mode: .copy, secondsPerWord: 40, keepByDefault: false)
        #expect(s.phase == .finished)
    }
}

// MARK: - Paint by number

@Suite struct PaintByNumberTests {
    /// Four flat quadrants (red, blue, yellow, green) with a small white dot in the red one.
    static func quadrants(side: Int = 96) -> [UInt8] {
        var rgba = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let c: (UInt8, UInt8, UInt8)
                switch (x < side / 2, y < side / 2) {
                case (true, true): c = (220, 30, 30)
                case (false, true): c = (30, 60, 220)
                case (true, false): c = (250, 230, 30)
                case (false, false): c = (40, 160, 60)
                }
                let p = (y * side + x) * 4
                rgba[p] = c.0; rgba[p + 1] = c.1; rgba[p + 2] = c.2
            }
        }
        // A 3×3 speck: below the minimum area, so it must merge away.
        for y in 10..<13 { for x in 10..<13 { let p = (y * side + x) * 4; rgba[p] = 255; rgba[p + 1] = 255; rgba[p + 2] = 255 } }
        return rgba
    }

    @Test func fourQuadrantsMakeFourRegionsInFourColours() throws {
        let t = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(), side: 96, difficulty: .leicht))
        #expect(t.facetCount == 4)
        #expect(t.palette.count == 4)
        #expect(Set(t.palette.map(\.number)) == [1, 2, 3, 4])
    }

    @Test func itIsDeterministic() throws {
        let a = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(), side: 96, difficulty: .mittel))
        let b = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(), side: 96, difficulty: .mittel))
        #expect(a == b)
    }

    @Test func noRegionIsBelowTheMinimum() throws {
        let side = 96
        let difficulty = PaintByNumberDifficulty.schwer
        let t = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(side: side), side: side, difficulty: difficulty))
        let map = t.facetMap()
        let sizes = Dictionary(grouping: map, by: { $0 }).mapValues(\.count)
        let minArea = max(4, Int(difficulty.minAreaFraction * Double(side * side)))
        let allBigEnough = sizes.values.allSatisfy { $0 >= minArea }
        #expect(allBigEnough)
        #expect(t.palette.count <= difficulty.colors)
    }

    @Test func everyLabelSitsInsideItsRegion() throws {
        let t = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(), side: 96, difficulty: .leicht))
        let map = t.facetMap()
        for (facet, label) in t.labels.enumerated() {
            let x = Int(label.x), y = Int(label.y)
            #expect(Int(map[y * t.side + x]) == facet)
            #expect(label.room > 5)
        }
    }

    @Test func theTemplateSurvivesItsFile() throws {
        let t = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(), side: 96, difficulty: .leicht))
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(PaintByNumberTemplate.self, from: data)
        #expect(back == t)
        #expect(back.facetMap() == t.facetMap())
    }

    @Test func colourNamesAreGermanAndUnique() throws {
        let t = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(), side: 96, difficulty: .leicht))
        let names = t.palette.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.contains("rot"))
        #expect(names.contains("blau"))
    }

    @Test func twoRedsGetDifferentNames() {
        let names = GermanColorName.uniqueNames(for: [
            ColorLab.lab(red: 0.95, green: 0.15, blue: 0.15),
            ColorLab.lab(red: 0.80, green: 0.10, blue: 0.10),
        ])
        #expect(Set(names).count == 2)
    }

    @Test func labRoundTrips() {
        let lab = ColorLab.lab(red: 0.2, green: 0.5, blue: 0.8)
        let rgb = ColorLab.rgb(lab)
        #expect(abs(rgb.red - 0.2) < 0.01 && abs(rgb.green - 0.5) < 0.01 && abs(rgb.blue - 0.8) < 0.01)
    }

    @Test func renderingPaintsOnlyFilledRegions() throws {
        let t = try #require(PaintByNumberGenerator.make(rgba: Self.quadrants(), side: 96, difficulty: .leicht))
        let map = t.facetMap()
        let image = try #require(PaintByNumberRenderer.fill(t, map: map, filled: [0]))
        #expect(image.width == t.side)
        #expect(PaintByNumberRenderer.outlines(t, map: map) != nil)
    }
}
