//
//  HoerenCoreTests.swift
//  german-ai-flashcardsTests
//
//  The pure core of the Hören room (docs/HOEREN.md): the number speller, the typed-answer
//  parser, the confusion classes, and the Diktat scorer.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct GermanNumberSpellerTests {

    @Test func cardinals() {
        let S = GermanNumberSpeller.self
        #expect(S.cardinal(0) == "null")
        #expect(S.cardinal(1) == "eins")
        #expect(S.cardinal(1, standalone: false) == "ein")
        #expect(S.cardinal(16) == "sechzehn")
        #expect(S.cardinal(17) == "siebzehn")
        #expect(S.cardinal(21) == "einundzwanzig")
        #expect(S.cardinal(24) == "vierundzwanzig")
        #expect(S.cardinal(30) == "dreißig")
        #expect(S.cardinal(60) == "sechzig")
        #expect(S.cardinal(70) == "siebzig")
        #expect(S.cardinal(100) == "hundert")
        #expect(S.cardinal(101) == "hunderteins")
        #expect(S.cardinal(1001) == "tausendeins")
        #expect(S.cardinal(1100) == "tausendeinhundert")
        #expect(S.cardinal(1250) == "tausendzweihundertfünfzig")
        #expect(S.cardinal(21_000) == "einundzwanzigtausend")
        #expect(S.cardinal(101_000) == "hunderteintausend")
        #expect(S.cardinal(999_999) == "neunhundertneunundneunzigtausendneunhundertneunundneunzig")
    }

    @Test func years() {
        #expect(GermanNumberSpeller.year(1987) == "neunzehnhundertsiebenundachtzig")
        #expect(GermanNumberSpeller.year(1900) == "neunzehnhundert")
        #expect(GermanNumberSpeller.year(2024) == "zweitausendvierundzwanzig")
    }

    @Test func prices() {
        #expect(GermanNumberSpeller.price(cents: 350) == "drei Euro fünfzig")
        #expect(GermanNumberSpeller.price(cents: 100) == "ein Euro")
        #expect(GermanNumberSpeller.price(cents: 99) == "neunundneunzig Cent")
    }

    @Test func clockTimes() {
        let S = GermanNumberSpeller.self
        #expect(S.time(hour: 13, minute: 5) == "dreizehn Uhr fünf")
        #expect(S.time(hour: 1, minute: 0) == "ein Uhr")
        #expect(S.time(hour: 0, minute: 15) == "null Uhr fünfzehn")
        #expect(S.colloquialTime(hour: 2, minute: 30) == "halb drei")
        #expect(S.colloquialTime(hour: 12, minute: 30) == "halb eins")
        #expect(S.colloquialTime(hour: 2, minute: 45) == "Viertel vor drei")
        #expect(S.colloquialTime(hour: 2, minute: 15) == "Viertel nach zwei")
        #expect(S.colloquialTime(hour: 2, minute: 25) == "fünf vor halb drei")
        #expect(S.colloquialTime(hour: 11, minute: 55) == "fünf vor zwölf")
    }

    @Test func dates() {
        #expect(GermanNumberSpeller.date(day: 3, month: 5, form: .dative) == "am dritten Mai")
        #expect(GermanNumberSpeller.date(day: 7, month: 10, form: .dative) == "am siebten Oktober")
        #expect(GermanNumberSpeller.date(day: 1, month: 1, form: .nominative) == "der erste Januar")
        #expect(GermanNumberSpeller.date(day: 20, month: 3, form: .nominative) == "der zwanzigste März")
    }

    @Test func phoneNumbers() {
        #expect(GermanNumberSpeller.phone(["030", "2345"], pairs: false) == "null drei null, zwo drei vier fünf")
        #expect(GermanNumberSpeller.phone(["030", "34051"], pairs: true) == "null drei null, vierunddreißig null fünf eins")
    }

    @Test func neverASoftHyphen() {
        var rng = SeededGenerator(seed: 7)
        for kind in HoerenNumberKind.allCases {
            for mode in HoerenNumberMode.allCases {
                let items = HoerenNumberGenerator.round(kinds: [kind], level: .b1, mode: mode, count: 30, rng: &rng)
                #expect(!items.isEmpty)
                for item in items { #expect(!item.spoken.contains("\u{00AD}")) }
            }
        }
    }
}

@Suite struct HoerenNumberAnswerTests {

    @Test func integers() {
        #expect(HoerenNumberAnswer.parse("1.000", kind: .large) == .integer(1000))
        #expect(HoerenNumberAnswer.parse("1 000", kind: .large) == .integer(1000))
        #expect(HoerenNumberAnswer.parse("042", kind: .small) == .integer(42))
        #expect(HoerenNumberAnswer.parse("12.5", kind: .large) == nil)
        #expect(HoerenNumberAnswer.parse("vier", kind: .small) == nil)
    }

    @Test func prices() {
        #expect(HoerenNumberAnswer.parse("3,5", kind: .price) == .cents(350))
        #expect(HoerenNumberAnswer.parse("3.50 €", kind: .price) == .cents(350))
        #expect(HoerenNumberAnswer.parse("3€", kind: .price) == .cents(300))
        #expect(HoerenNumberAnswer.parse("99 Cent", kind: .price) == .cents(99))
        #expect(HoerenNumberAnswer.parse("0,99", kind: .price) == .cents(99))
    }

    @Test func times() {
        #expect(HoerenNumberAnswer.parse("14.30 Uhr", kind: .time) == .time(hour: 14, minute: 30))
        #expect(HoerenNumberAnswer.parse("08:05", kind: .time) == .time(hour: 8, minute: 5))
        #expect(HoerenNumberAnswer.parse("14 Uhr", kind: .time) == .time(hour: 14, minute: 0))
        // The everyday clock has no a.m./p.m.
        let typed = HoerenNumberAnswer.parse("14:30", kind: .timeColloquial)!
        #expect(HoerenNumberAnswer.matches(typed, expected: .time(hour: 2, minute: 30), kind: .timeColloquial))
        #expect(!HoerenNumberAnswer.matches(typed, expected: .time(hour: 2, minute: 30), kind: .time))
    }

    @Test func dates() {
        #expect(HoerenNumberAnswer.parse("3.5.", kind: .date) == .date(day: 3, month: 5, year: nil))
        #expect(HoerenNumberAnswer.parse("3. Mai", kind: .date) == .date(day: 3, month: 5, year: nil))
        let withYear = HoerenNumberAnswer.parse("3.5.1987", kind: .date)!
        #expect(HoerenNumberAnswer.matches(withYear, expected: .date(day: 3, month: 5, year: nil), kind: .date))
    }

    @Test func phoneKeepsItsLeadingZero() {
        #expect(HoerenNumberAnswer.parse("030 / 45 67-89", kind: .phone) == .digits("030456789"))
    }

    @Test func confusions() {
        #expect(HoerenConfusion.classify(typed: .integer(42), expected: .integer(24), kind: .small) == .tensUnitsSwap)
        #expect(HoerenConfusion.classify(typed: .integer(1978), expected: .integer(1987), kind: .year) == .tensUnitsSwap)
        #expect(HoerenConfusion.classify(typed: .integer(30), expected: .integer(13), kind: .small) == .teenTy)
        #expect(HoerenConfusion.classify(typed: .time(hour: 3, minute: 30), expected: .time(hour: 2, minute: 30),
                                         kind: .timeColloquial) == .halbHour)
        #expect(HoerenConfusion.classify(typed: .digits("0303"), expected: .digits("0302"), kind: .phone) == .zweiDrei)
    }

    @Test func everyGeneratedItemParsesBackToItsValue() {
        var rng = SeededGenerator(seed: 11)
        for kind in HoerenNumberKind.allCases {
            let items = HoerenNumberGenerator.round(kinds: [kind], level: .b1, mode: .bare, count: 40, rng: &rng)
            for item in items {
                let typed = HoerenNumberAnswer.parse(item.value.display, kind: kind)
                #expect(typed.map { HoerenNumberAnswer.matches($0, expected: item.value, kind: kind) } == true,
                        "\(kind) \(item.value.display)")
            }
        }
    }
}

@Suite struct DiktatScorerTests {

    @Test func endingMissTaggedFromTheSentence() {
        let result = DiktatScorer.score(reference: "Ich helfe dem Mann.", typed: "ich helfe den mann",
                                        focusByWord: ["dem": .dativ, "mann": .dativ])
        #expect(result.tokens.map(\.cls) == [.right, .right, .ending, .capital])
        #expect(result.tokens[2].focus == .dativ)
        #expect(result.rightCount == 3)
        #expect(result.referenceCount == 4)
    }

    @Test func determinerAloneIsArtikel() {
        let result = DiktatScorer.score(reference: "Ich sehe den Hund.", typed: "Ich sehe der Hund")
        #expect(result.tokens[2].cls == .ending)
        #expect(result.tokens[2].focus == .artikel)
    }

    @Test func adjectiveBetweenDeterminerAndNoun() {
        let result = DiktatScorer.score(reference: "Er kauft einen neuen Tisch.", typed: "Er kauft einen neue Tisch")
        #expect(result.tokens[3].cls == .ending)
        #expect(result.tokens[3].focus == .adjektivendungen)
    }

    @Test func umlautAndEszettCountWrong() {
        let a = DiktatScorer.score(reference: "Das Mädchen lacht.", typed: "Das Madchen lacht")
        #expect(a.tokens[1].cls == .umlautEszett)
        #expect(a.rightCount == 2)
        let b = DiktatScorer.score(reference: "Die Straße ist lang.", typed: "Die Strasse ist lang.")
        #expect(b.tokens[1].cls == .umlautEszett)
    }

    @Test func punctuationIsNeverScored() {
        let result = DiktatScorer.score(reference: "„Komm her!“, ruft sie.", typed: "Komm her ruft sie")
        #expect(result.isPerfect)
    }

    @Test func missingAndExtraWords() {
        let result = DiktatScorer.score(reference: "Wir fahren morgen nach Berlin.", typed: "Wir fahren nach Berlin heute")
        #expect(result.count(.word) == 1)          // morgen missing
        #expect(result.count(.extra) == 1)         // heute extra
        #expect(result.referenceCount == 5)
        #expect(result.rightCount == 4)
    }

    @Test func aDifferentWordIsAWordMiss() {
        let result = DiktatScorer.score(reference: "Ich habe Hunger.", typed: "Ich habe Hand")
        #expect(result.tokens[2].cls == .word)
    }

    @Test func sentenceFilter() {
        #expect(DiktatSentenceFilter.accepts("Wir lernen Deutsch.", level: .a1))
        #expect(!DiktatSentenceFilter.accepts("Wie bitte?", level: .a1))
        #expect(!DiktatSentenceFilter.accepts("Der Zug ist um 10 Uhr abgefahren.", level: .a1))
        #expect(!DiktatSentenceFilter.accepts("(haben/machen) guten Vorschlag?", level: .a2))
        #expect(DiktatSentenceFilter.sentences(in: "Wie heißt du? Er schreibt wie ein Kind. Wie bitte?", level: .a1).count == 2)
    }

    @Test @MainActor func bankHasSentencesAtEveryLevel() {
        for level in [CEFRLevel.a1, .a2, .b1] {
            let pool = DiktatSentenceBank.pool(for: level, sources: Set(DiktatSourceKind.allCases))
            #expect(pool.count >= 100, "\(level) has \(pool.count)")
        }
    }
}

@Suite struct GistPromptsTests {

    @Test func keyPointsParseAndGate() {
        let raw = """
        <think>let me see</think>
        KERNPUNKTE:
        - A train from Cologne to Bonn was late on Monday.
        - A tree on the tracks caused the delay.
        - The fire brigade removed it quickly.
        """
        #expect(GistPrompts.parseKeyPoints(raw).count == 3)
        // German points fail the gate; one point alone is not enough.
        #expect(GistPrompts.parseKeyPoints("KERNPUNKTE:\n- Der Zug war zu spät und die Leute waren sauer.\n- Ein Baum lag auf den Gleisen.").isEmpty)
        #expect(GistPrompts.parseKeyPoints("KERNPUNKTE:\n- The train was late on Monday morning.").isEmpty)
    }

    @Test func judgeParse() {
        let raw = "1: ja ; mentions the delay\n2: teilweise ; tree not named\n3: nein\n"
        let verdicts = GistPrompts.parseJudge(raw, count: 4)
        #expect(verdicts == [.ja, .teilweise, .nein, nil])
        #expect(GistPrompts.scoreHalves(verdicts) == 3)
        #expect(!GistPrompts.isJudgeable("train late"))
    }

    @Test func predictionHits() {
        let text = "Die Katzen spielen im Garten. Dann ging der Hund nach Hause. Wir machen Hausaufgaben."
        let hits = StoryGlossaryHighlighter.hits(for: ["Katze", "gehen", "Haus", "Auto"], in: text)
        #expect(hits["Katze"] != nil)
        #expect(hits["Auto"] == nil)
        // "Haus" may match "Hause" but never the compound "Hausaufgaben".
        #expect(hits["Haus"]?.contains("hausaufgaben") != true)
    }
}

/// `WritingDiff.diff` now runs on the shared `alignment`; its output must not change.
@Suite struct WritingDiffAlignmentTests {
    @Test func diffUnchanged() {
        let d = WritingDiff.diff("Ich gehe nach Hause", "Ich ging nach Hause")
        #expect(d.map(\.text) == ["Ich", "gehe", "ging", "nach", "Hause"])
        #expect(d.map(\.kind) == [.same, .removed, .inserted, .same, .same])
        #expect(d.map(\.id) == [0, 1, 2, 3, 4])
        #expect(WritingDiff.singleSwap("mit der Freund", "mit dem Freund")! == (wrong: "der", right: "dem"))
        #expect(WritingDiff.changedRatio("a b c d", "a b c d") == 0)
        #expect(WritingDiff.diff("", "").isEmpty)
    }
}

@Suite struct GistJudgeEchoTests {
    @Test func anEchoedFormatIsNotAnAnswer() {
        #expect(GistPrompts.parseJudge("1: ja | teilweise | nein ; <omitted>\n2: nein", count: 2) == [nil, .nein])
    }
}
