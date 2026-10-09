//
//  KasusFormPartsTests.swift
//  german-ai-flashcardsTests
//
//  The stem | ending split the 3D ending blocks build from, checked against the hand-written
//  tables in KasusFormsTests: the two pieces always make the table's word, the stem never moves
//  down a column (except euer's dropped e), and the empty endings sit exactly where a teacher's
//  table has them.
//

import Foundation
import Testing
@testable import Die_Kartei

struct KasusFormPartsTests {

    @Test("stem + ending is the table's word, in every cell", arguments: FormTable.all)
    func partsMakeTheWord(table: FormTable) {
        for kasus in GrammarCase.allCases {
            for (column, genus) in Gender.allCases.enumerated() {
                let parts = KasusForms.parts(family: table.family, stem: table.stem, case: kasus, genus: genus)
                #expect(parts?.word == table.cell(kasus, column), "\(kasus.short) \(genus.columnLabel)")
            }
        }
    }

    @Test("The definite article's stem is always d")
    func definiteStem() {
        for kasus in GrammarCase.allCases {
            for genus in Gender.allCases {
                #expect(KasusForms.parts(family: .definite, stem: "", case: kasus, genus: genus)?.stem == "d")
            }
        }
        #expect(KasusForms.parts(family: .definite, stem: "", case: .nominativ, genus: .die)?.ending == "ie")
        #expect(KasusForms.parts(family: .definite, stem: "", case: .dativ, genus: .der)?.ending == "em")
    }

    @Test("euer keeps its e only when no ending follows")
    func euer() {
        let bare = KasusForms.parts(family: .possessive, stem: "euer", case: .nominativ, genus: .der)
        #expect(bare == KasusFormParts(stem: "euer", ending: ""))
        let akk = KasusForms.parts(family: .possessive, stem: "euer", case: .akkusativ, genus: .der)
        #expect(akk == KasusFormParts(stem: "eur", ending: "en"))
    }

    @Test("ein-words have no ending in exactly m. Nom, n. Nom and n. Akk")
    func emptyEndings() {
        let empty = GrammarCase.allCases.flatMap { kasus in
            Gender.allCases.compactMap { genus -> String? in
                guard let parts = KasusForms.parts(family: .kein, stem: "kein", case: kasus, genus: genus),
                      !parts.hasEnding else { return nil }
                return "\(kasus.short) \(genus.columnLabel)"
            }
        }
        #expect(empty == ["Nom m", "Nom n", "Akk n"])
    }

    @Test("No plural for ein and jeder")
    func noPlural() {
        #expect(KasusForms.parts(family: .ein, stem: "ein", case: .dativ, genus: .plural) == nil)
        #expect(KasusForms.parts(family: .derWord, stem: "jed", case: .akkusativ, genus: .plural) == nil)
        #expect(KasusStemChoice.named("ein")?.hasPlural == false)
        #expect(KasusStemChoice.named("jeder")?.hasPlural == false)
        #expect(KasusStemChoice.named("kein")?.hasPlural == true)
    }

    @Test("Ending options come in table order, Genitiv's -es only with the Genitiv")
    func endingOptions() {
        #expect(KasusForms.endingOptions(family: .definite, stem: "", includeGenitive: false)
                == ["er", "ie", "as", "en", "em"])
        #expect(KasusForms.endingOptions(family: .definite, stem: "", includeGenitive: true)
                == ["er", "ie", "as", "en", "em", "es"])
        #expect(KasusForms.endingOptions(family: .possessive, stem: "mein", includeGenitive: false)
                == ["", "e", "en", "em", "er"])
        #expect(KasusForms.endingOptions(family: .possessive, stem: "mein", includeGenitive: true)
                == ["", "e", "en", "em", "er", "es"])
    }

    @Test("Every stem choice parses back to its family")
    func stemChoices() {
        #expect(KasusStemChoice.all.map(\.label)
                == ["der", "ein", "kein", "mein", "dein", "sein", "ihr", "unser", "euer", "dieser", "jeder", "welcher"])
        for choice in KasusStemChoice.all {
            let word = choice.parts(.dativ, .der)?.word ?? ""
            #expect(KasusForms.parseDeterminer(word)?.family == choice.family, "\(choice.label)")
        }
    }
}

// MARK: - The blocks' moves

struct EndingBlocksStateTests {
    private let dem = KasusFormParts(stem: "d", ending: "em")
    private let den = KasusFormParts(stem: "d", ending: "en")

    @Test("Which move each change makes")
    func transitions() {
        let open = EndingBlocksState.open(stem: "d", genus: .der)
        let built = EndingBlocksState.built(dem, kasus: .dativ, genus: .der)
        #expect(EndingBlocksTransition(from: nil, to: built) == .rise)
        #expect(EndingBlocksTransition(from: open, to: built) == .snap)
        #expect(EndingBlocksTransition(from: open, to: .built(dem, kasus: .dativ, genus: .der, rejected: "en"))
                == .bounceThenSnap(wrong: "en"))
        #expect(EndingBlocksTransition(from: built, to: .built(den, kasus: .akkusativ, genus: .der))
                == .swap(from: "em", wasOpen: false))
        #expect(EndingBlocksTransition(from: built, to: open) == .swap(from: "em", wasOpen: false))
        // dem is m. and n. Dativ alike: only the plate changes.
        #expect(EndingBlocksTransition(from: built, to: .built(dem, kasus: .dativ, genus: .das)) == .hold)
        // die is Nom and Akk alike: the ending hops into its new color.
        let die = KasusFormParts(stem: "d", ending: "ie")
        #expect(EndingBlocksTransition(from: .built(die, kasus: .nominativ, genus: .die),
                                       to: .built(die, kasus: .akkusativ, genus: .die)) == .recolor)
        #expect(EndingBlocksTransition(from: built, to: .built(KasusFormParts(stem: "mein", ending: "em"),
                                                               kasus: .dativ, genus: .der)) == .rise)
    }

    @Test("Every move ends settled, and a dropped ending starts grey and high",
          arguments: [EndingBlocksTransition.rise, .snap, .swap(from: "em", wasOpen: false),
                      .bounceThenSnap(wrong: "en"), .recolor])
    func settles(transition: EndingBlocksTransition) {
        #expect(EndingBlocksPose.at(transition, time: Float(transition.duration) + 0.01) == .settled)
        if transition == .snap {
            let start = EndingBlocksPose.at(transition, time: 0)
            #expect(start.endingTint == 0)
            #expect(start.endingDrop > 1)
        }
    }

    @Test("A wider canvas never needs the camera further back")
    func framing() {
        let narrow = EndingBlocksFraming.distance(width: 3, height: 1.3, depth: 0.9, aspect: 1)
        let wide = EndingBlocksFraming.distance(width: 3, height: 1.3, depth: 0.9, aspect: 3)
        #expect(wide <= narrow)
        #expect(EndingBlocksFraming.distance(width: 5, height: 1.3, depth: 0.9, aspect: 2)
                > EndingBlocksFraming.distance(width: 2, height: 1.3, depth: 0.9, aspect: 2))
    }
}

// MARK: - Bau das Wort

struct BauDasWortTests {
    @Test("An ending pick grades exactly like the whole-word pick")
    func endingPicksGradeLikeWords() {
        for _ in 0..<50 {
            for q in EndingsQuestion.round(cases: GrammarCase.allCases) {
                #expect(q.answerParts.word == q.answer)
                #expect(q.endingLabels.count == q.options.count)
                for (label, option) in zip(q.endingLabels, q.options) {
                    #expect(q.form(endingLabel: label) == option)
                }
                #expect(q.form(endingLabel: KasusEndingGap.label(q.answerParts.ending)) == q.answer)
            }
        }
    }

    @Test("Bau das Wort rounds file apart from the Schnellrunde and count the same")
    func recording() {
        let item = KasusItemResult(kasus: .dativ, genus: .der, firstTry: true, slip: false,
                                   record: nil)
        let build = KasusService.quickResult(unit: .dativ, items: [item], durationSeconds: 30, step: .build)
        #expect(build.storyID == "build-dativ")
        #expect(build.step == .build)
        #expect(KasusService.quickResult(unit: .dativ, items: [item], durationSeconds: 30).storyID == "quick-dativ")
        #expect(KasusService.countsTowardSkill(item, step: .build, hint: nil)
                == KasusService.countsTowardSkill(item, step: .quick, hint: nil))
        #expect(KasusRoundStep(rawValue: "build") == .build)
        #expect(GrammarDrillSession(kind: .build, topic: .kasus(.dativ)).title == "Bau das Wort · Dativ")
    }
}
