//
//  EnglishAnchorTests.swift
//  german-ai-flashcardsTests
//
//  „Englisch & Fälle“: the pool the bundled Verstehen items yield, the rules that keep the
//  exercise honest (no Dativ verb in the clean pool, every round carries a „Keine Frage“ span,
//  every English span really stands in its English line), and the rounds each kind composes.
//
//  The numbers here are measured by the shipped predicate, not copied from the research note: the
//  note counted reasons, the app also requires an English span and a preposition on a Keine-Frage
//  phrase. `poolTable` prints them, so a content change says exactly what it moved.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("English anchors")
@MainActor
struct EnglishAnchorTests {

    private var lexicon: AppKasusLexicon { KasusTestData.lexicon }

    private var bank: KasusConceptBank {
        let url = Bundle.main.url(forResource: "kasus_concepts", withExtension: "json")!
        return try! KasusConceptBank(data: Data(contentsOf: url))
    }

    private func pool(_ unit: KasusUnit) -> [EnglishAnchorItem] {
        EnglishAnchors.pool(unit: unit, bank: bank, lexicon: lexicon)
    }

    // MARK: - The pool

    /// Measured by the shipped predicate on 2026-10-18, not copied from the note: the app also
    /// requires an English span, and a preposition on a Keine-Frage phrase.
    @Test("The pool per unit, pinned")
    func poolSizes() {
        let want: [KasusUnit: (clean: Int, trap: Int, keine: Int)] = [
            .nominativ: (50, 0, 1), .akkusativ: (299, 0, 23), .dativ: (195, 123, 10),
            .genitiv: (378, 33, 66), .alleFaelle: (302, 38, 66),
        ]
        let bank = bank
        var line: [String] = []
        for unit in KasusUnit.allCases {
            let spans = EnglishAnchors.pool(unit: unit, bank: bank, lexicon: lexicon)
            let got = (clean: spans.filter { $0.bucket == .clean }.count,
                       trap: spans.filter { $0.bucket == .trap }.count,
                       keine: spans.filter { $0.bucket == .keine }.count)
            line.append("\(unit.rawValue): \(got.clean) clean · \(got.trap) trap · \(got.keine) keine")
            let expected = want[unit] ?? (clean: -1, trap: -1, keine: -1)
            #expect(got == expected, "\(unit.rawValue) moved: \(got) instead of \(expected)")
        }
        // Printed so a content change reports what it moved, not only that something did.
        print("English anchor pool —\n  " + line.joined(separator: "\n  "))
    }

    @Test("A Dativ verb is never in the clean pool, and a Keine-Frage span always has a preposition")
    func bucketsAreHonest() {
        for unit in EnglishAnchors.units {
            for span in pool(unit) {
                guard let target = span.target else {
                    Issue.record("\(span.id) lost its target")
                    continue
                }
                switch span.bucket {
                case .clean:
                    #expect(target.spec.reason != .dativeVerb, "\(span.id) is a Dativ verb in the clean pool")
                    #expect(span.question != .keine, "\(span.id) is clean but answers no question")
                case .trap:
                    #expect(target.spec.reason == .dativeVerb, "\(span.id) is in the trap pool without a Dativ verb")
                    #expect(span.question == .wem, "a trap's answer is always Wem?")
                case .keine:
                    #expect(target.preposition != nil, "\(span.id) answers Keine Frage with no preposition on it")
                    #expect(span.question == .keine)
                }
            }
        }
    }

    @Test("Every English span stands verbatim in its English line")
    func spansAreVerbatim() {
        for unit in EnglishAnchors.units {
            for span in pool(unit) {
                let paragraphs = span.playable.story.paragraphs
                guard paragraphs.indices.contains(span.paragraph) else {
                    Issue.record("\(span.id) points past its paragraphs")
                    continue
                }
                #expect(paragraphs[span.paragraph].en.contains(span.english),
                        "\(span.id): „\(span.english)“ is not in „\(paragraphs[span.paragraph].en)“")
            }
        }
    }

    @Test("The question comes off the role, in the Kasus-Check's own order")
    func questionsFollowRoles() {
        #expect(KasusQuestion(role: .subjekt) == .wer)
        #expect(KasusQuestion(role: .gleichSubjekt) == .wer)
        #expect(KasusQuestion(role: .direktesObjekt) == .wen)
        #expect(KasusQuestion(role: .empfaenger) == .wem)
        #expect(KasusQuestion(role: .gehoertZu) == .wessen)
        #expect(KasusQuestion(role: .praeposition) == .keine)
        // Keine Frage names no case of its own, and the four name one each.
        #expect(KasusQuestion.keine.kasus == nil)
        #expect(KasusQuestion.allCases.compactMap(\.kasus) == GrammarCase.allCases)
    }

    @Test("Keine Frage is always on the board, and only the four narrow with the unit")
    func buttons() {
        #expect(KasusQuestion.buttons().count == 5)
        #expect(KasusQuestion.buttons(cases: KasusUnit.dativ.casesInPlay) == [.wer, .wen, .wem, .keine])
        #expect(KasusQuestion.buttons(cases: KasusUnit.akkusativ.casesInPlay) == [.wer, .wen, .keine])
        #expect(KasusQuestion.buttons(cases: KasusUnit.alleFaelle.casesInPlay).contains(.keine))
    }

    // MARK: - The rounds

    @Test("Welche Frage? composes a round that holds a Keine-Frage span", arguments: EnglishAnchors.units)
    func frageRound(unit: KasusUnit) {
        let spans = pool(unit)
        guard spans.contains(where: { $0.bucket == .keine }) else { return }
        for seed in UInt64(1)...5 {
            var rng = KasusSeededRandom(seed: seed)
            let round = EnglishAnchors.items(unit: unit, kind: .frage, help: .normal,
                                             count: KasusDrillKind.frage.meta.roundSize,
                                             bank: bank, rng: &rng)
            #expect(!round.isEmpty, "\(unit.rawValue) composed nothing")
            #expect(round.allSatisfy { $0.bucket != .trap }, "a trap reached Welche Frage?")
            #expect(round.contains { $0.bucket == .keine },
                    "\(unit.rawValue) seed \(seed): no „Keine Frage“ span in the round")
        }
    }

    @Test("Die englische Falle mixes traps with the spans they are confused with")
    func falleRound() {
        for unit in EnglishAnchors.units where EnglishAnchors.offers(.englischeFalle, for: unit, bank: bank) {
            var rng = KasusSeededRandom(seed: 7)
            let round = EnglishAnchors.items(unit: unit, kind: .englischeFalle, help: .normal,
                                             count: KasusDrillKind.englischeFalle.meta.roundSize,
                                             bank: bank, rng: &rng)
            #expect(round.contains { $0.bucket == .trap }, "\(unit.rawValue): no trap in Die Falle")
            #expect(round.contains { $0.bucket == .clean },
                    "\(unit.rawValue): all traps, so the answer is always Wem?")
            #expect(round.allSatisfy { $0.question == .wem || $0.question == .wen },
                    "\(unit.rawValue): Die Falle is the Wen/Wem confusion, nothing else")
        }
    }

    @Test("The preset is the ramp: Leicht and Frei pin a stage, Normal walks it")
    func stages() {
        var rng = KasusSeededRandom(seed: 3)
        let leicht = EnglishAnchors.items(unit: .dativ, kind: .frage, help: .leicht, count: 10,
                                          bank: bank, rng: &rng)
        #expect(leicht.allSatisfy { $0.stage == .beide })
        var rng2 = KasusSeededRandom(seed: 3)
        let frei = EnglishAnchors.items(unit: .dativ, kind: .frage, help: .frei, count: 10,
                                        bank: bank, rng: &rng2)
        #expect(frei.allSatisfy { $0.stage == .deutsch })
        // Frei asks one phrase per sentence, so nothing is answerable by elimination.
        #expect(Set(frei.map(\.playable.id)).count == frei.count)
        var rng3 = KasusSeededRandom(seed: 3)
        let normal = EnglishAnchors.items(unit: .dativ, kind: .frage, help: .normal, count: 10,
                                          bank: bank, rng: &rng3)
        #expect(Set(normal.map(\.stage)).count > 1, "Normal should walk the stages")
    }

    @Test("Nominativ is never offered, and Die Falle only where a Dativ verb can stand")
    func offered() {
        #expect(!EnglishAnchors.units.contains(.nominativ))
        #expect(!EnglishAnchors.offers(.frage, for: .nominativ, bank: bank))
        #expect(EnglishAnchors.offers(.frage, for: .dativ, bank: bank))
        #expect(!EnglishAnchors.offers(.englischeFalle, for: .akkusativ, bank: bank),
                "there is no English trap before the Dativ")
        #expect(EnglishAnchors.offers(.englischeFalle, for: .dativ, bank: bank))
    }

    // MARK: - The level seed

    @Test("The preset follows the declared level until it is pinned")
    func seeding() {
        #expect(KasusHelp.seeded(level: .a1) == .leicht)
        #expect(KasusHelp.seeded(level: .b1) == .normal)
        #expect(KasusHelp.seeded(level: .c1) == .frei)
        #expect(KasusHelp.resolve(stored: nil, level: .b1) == .normal)
        #expect(KasusHelp.resolve(stored: "frei", level: .a1) == .frei, "a pinned preset ignores the level")
        #expect(KasusHelp.isAutomatic(stored: nil) && !KasusHelp.isAutomatic(stored: "leicht"))
        #expect(KasusHelp.leicht.marksTheRound && !KasusHelp.normal.marksTheRound)
    }
}
