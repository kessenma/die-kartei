//
//  KasusServiceTests.swift
//  german-ai-flashcardsTests
//
//  Sessions, blanks, answer buttons and grading on „Der verlorene Schlüssel“, the examples the
//  `-kasus.debugVerify 1` service block prints (and the block itself), plus the old Finden's
//  marks, the round results and the hub's "Weiter" pick (`KasusPath.next`) over synthetic history.
//  Markieren and Endungen have their own suites (KasusMarkingTests, KasusEndingsTests).
//

import Foundation
import Testing
@testable import Die_Kartei

/// A first pick on one blank of the Phase 1 story, at Ohne Hilfe, gemischt.
nonisolated struct GradeExample: Sendable, CustomTestStringConvertible {
    let surface: String
    let pick: String
    let expected: String

    var testDescription: String { "„\(pick)“ on „\(surface)“ → \(expected)" }

    static let all: [GradeExample] = [
        GradeExample(surface: "dem Boden", pick: "dem", expected: "right"),
        GradeExample(surface: "dem Boden", pick: "Dem", expected: "right"),
        // The Nominativ left unchanged is a case miss, even though „der“ is also feminine Dativ.
        GradeExample(surface: "dem Boden", pick: "der", expected: "case miss"),
        GradeExample(surface: "dem Boden", pick: "den", expected: "case miss"),
        GradeExample(surface: "der Tasche", pick: "dem", expected: "gender slip (m)"),
        GradeExample(surface: "der Tasche", pick: "die", expected: "case miss"),
        GradeExample(surface: "den Schlüssel", pick: "die", expected: "number slip"),
        GradeExample(surface: "den Schlüssel", pick: "der", expected: "case miss"),
        GradeExample(surface: "den Schlüssel", pick: "das", expected: "gender slip (n)"),
        GradeExample(surface: "Der Schlüssel", pick: "der", expected: "right"),
        GradeExample(surface: "Der Schlüssel", pick: "Den", expected: "case miss"),
    ]
}

@Suite("Kasus service")
struct KasusServiceTests {
    let story: KasusStory
    let playable: KasusPlayableStory

    init() throws {
        story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
    }

    private func tally(_ blanks: [KasusBlank]) -> [GrammarCase: Int] {
        blanks.reduce(into: [:]) { $0[$1.kasus, default: 0] += 1 }
    }

    private var ohneBlanks: [KasusBlank] {
        KasusService.blanks(in: playable, unit: .dativ, mixed: true, hint: .ohne)
    }

    private func describe(_ outcome: KasusPickOutcome) -> String {
        switch outcome {
        case .right:                 "right"
        case .genderSlip(let other): "gender slip (\(other?.columnLabel ?? "?"))"
        case .numberSlip:            "number slip"
        case .caseMiss:              "case miss"
        }
    }

    // MARK: Blanks

    @Test("Einsetzen blanks the unit's case, or every case in play when gemischt")
    func blanksPerHintLevel() {
        for hint in KasusHintLevel.allCases {
            #expect(tally(KasusService.blanks(in: playable, unit: .dativ, mixed: false, hint: hint)) == [.dativ: 9],
                    "\(hint.germanLabel)")
        }
        #expect(tally(KasusService.blanks(in: playable, unit: .dativ, mixed: true, hint: .genus))
                == [.akkusativ: 11, .dativ: 9], "the Nominativ only at Ohne Hilfe")
        #expect(tally(ohneBlanks) == [.nominativ: 6, .akkusativ: 11, .dativ: 9])
    }

    @Test("The Nominativ unit only runs at Ohne Hilfe")
    func hintLevelsPerUnit() {
        #expect(KasusService.availableHintLevels(unit: .nominativ, mixed: false) == [.ohne])
        #expect(KasusService.effectiveHintLevel(.genus, unit: .nominativ, mixed: false) == .ohne)
        #expect(KasusService.effectiveHintLevel(.viel, unit: .dativ, mixed: false) == .viel)
        #expect(KasusService.availableHintLevels(unit: .akkusativ, mixed: true) == KasusHintLevel.allCases)
        #expect(KasusService.blankCases(unit: .alleFaelle, mixed: false, hint: .genus) == [.akkusativ, .dativ, .genitiv])
        #expect(KasusService.blankCases(unit: .alleFaelle, mixed: false, hint: .ohne) == Set(GrammarCase.allCases))
    }

    @Test("The default hint level follows the learner's level")
    func hintDefaults() {
        #expect(KasusHintLevel.defaultLevel(for: .a1) == .genus)
        #expect(KasusHintLevel.defaultLevel(for: .a2) == .genus)
        #expect(KasusHintLevel.defaultLevel(for: .b1) == .ohne)
        #expect(KasusHintLevel.resolve(stored: "", level: .a1) == .genus)
        #expect(KasusHintLevel.resolve(stored: "viel", level: .b1) == .viel)
        #expect(KasusHintLevel.resolve(stored: "unknown", level: .b2) == .ohne)
        #expect(KasusHintLevel.allCases.first == .lern, "Lernhilfe comes first")
        #expect(KasusHintLevel.lern.harder == .viel)
        #expect(KasusHintLevel.resolve(stored: "lern", level: .b1) == .lern)
        #expect(KasusHintLevel.viel.harder == .genus)
        #expect(KasusHintLevel.genus.harder == .ohne)
        #expect(KasusHintLevel.ohne.harder == nil)
    }

    @Test("Every blank offers its answer, in table order and the text's capitalisation")
    func options() throws {
        for mixed in [false, true] {
            for hint in KasusHintLevel.allCases {
                for blank in KasusService.blanks(in: playable, unit: .dativ, mixed: mixed, hint: hint) {
                    let label = "\(blank.target.surface) at \(hint.germanLabel)"
                    #expect(blank.options.contains(blank.answer), "\(label): \(blank.options)")
                    #expect(Set(blank.options).count == blank.options.count, "\(label) repeats a button")
                    #expect(blank.options.count >= 3, "\(label) is a coin flip")
                }
            }
        }
        let boden = try #require(ohneBlanks.first { $0.target.noun == "Boden" })
        #expect(KasusService.options(for: boden.target, hint: .viel, includeGenitive: false) == ["der", "den", "dem"])
        #expect(KasusService.options(for: boden.target, hint: .genus, includeGenitive: false) == ["der", "die", "das", "den", "dem"])
        #expect(KasusService.options(for: boden.target, hint: .ohne, includeGenitive: true) == ["der", "die", "das", "den", "dem", "des"])
        let capital = try #require(ohneBlanks.first { $0.target.surface == "Der Schlüssel" })
        #expect(capital.options == ["Der", "Die", "Das", "Den", "Dem"])
    }

    @Test("Contractions and pronouns are never blanked", arguments: BundledStories.ids)
    func spotOnlyNeverBlanked(_ id: String) throws {
        let story = try #require(KasusTestData.story(id))
        let playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
        let unit = try #require(story.unit)
        for hint in KasusHintLevel.allCases {
            for blank in KasusService.blanks(in: playable, unit: unit, mixed: true, hint: hint) {
                #expect(blank.target.kind == .article, "\(blank.target.surface) at \(hint.germanLabel)")
                #expect(blank.options.contains(blank.answer), "\(blank.target.surface) at \(hint.germanLabel)")
            }
        }
        for target in playable.targets where target.kind.isSpotOnly {
            #expect(KasusService.options(for: target, hint: .ohne, includeGenitive: true).isEmpty, "\(target.surface)")
            #expect(KasusService.grade(target.determiner, for: target) == .right, "\(target.surface)")
        }
    }

    // MARK: Grading

    @Test("First picks are graded right, case miss, gender slip or number slip", arguments: GradeExample.all)
    func grade(_ example: GradeExample) throws {
        let blank = try #require(ohneBlanks.first { $0.target.surface == example.surface })
        #expect(describe(KasusService.grade(example.pick, for: blank)) == example.expected)
    }

    @Test("The number tag only where the plural reads the same")
    func numberTags() throws {
        let key = try #require(ohneBlanks.first { $0.target.surface == "den Schlüssel" })
        #expect(key.showsNumberTag)
        #expect(key.numberTag == "sg")
        let dative = try #require(ohneBlanks.first { $0.target.surface == "dem Schlüssel" })
        #expect(!dative.showsNumberTag, "the Dativ plural adds -n")
        let boden = try #require(ohneBlanks.first { $0.target.noun == "Boden" })
        #expect(!boden.showsNumberTag, "Böden")
        let genusKey = try #require(KasusService.blanks(in: playable, unit: .dativ, mixed: true, hint: .genus)
            .first { $0.target.surface == "den Schlüssel" })
        #expect(!genusKey.showsNumberTag, "only at Ohne Hilfe")
        #expect(genusKey.showsGenderTag)
    }

    @Test("An n-noun reads the same in both numbers outside the Nominativ")
    func nNounNumber() throws {
        let story = try #require(KasusTestData.story("ks-gen-b1-grossmutter"))
        let playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
        let blanks = KasusService.blanks(in: playable, unit: .genitiv, mixed: true, hint: .ohne)
        // „für die Nachbarn“, „der Nachbarn“ and „die Namen“ are all good German, so the plural of
        // the right case is a number slip, never „Falscher Fall“.
        for (surface, pick) in [("den Nachbarn", "die"), ("des Nachbarn", "der"), ("den Namen", "die")] {
            let blank = try #require(blanks.first { $0.target.surface == surface }, "\(surface)")
            #expect(blank.showsNumberTag, "\(surface)")
            #expect(describe(KasusService.grade(pick, for: blank)) == "number slip", "„\(pick)“ on „\(surface)“")
        }
        let neighbour = try #require(playable.targets.first { $0.surface == "ein Nachbar" })
        #expect(!neighbour.numberAmbiguous, "the Nominativ singular has no -n")
        #expect(!KasusForms.nNounReadsAsPlural(noun: "Herrn", lemma: "Herr", kasus: .dativ), "Herrn · Herren")
        #expect(!KasusForms.nNounReadsAsPlural(noun: "Namens", lemma: "Name", kasus: .genitiv), "des Namens · der Namen")
        // A plural answer: the singular of the right case is the slip, another case is not.
        #expect(KasusForms.isRightCaseWrongNumber(pick: "den", answerCase: .akkusativ, genus: .plural,
                                                  singularGenus: .der, family: .definite, stem: ""))
        #expect(!KasusForms.isRightCaseWrongNumber(pick: "dem", answerCase: .akkusativ, genus: .plural,
                                                   singularGenus: .der, family: .definite, stem: ""))
    }

    @Test("A bare time phrase points at no deciding word")
    func bareTimePhrase() throws {
        let story = try #require(KasusTestData.story("ks-gen-b1-grossmutter"))
        let playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
        let viel = KasusService.blanks(in: playable, unit: .genitiv, mixed: true, hint: .viel)
        let tag = try #require(viel.first { $0.target.surface == "jeden Tag" })
        #expect(tag.isBareTimePhrase)
        #expect(!tag.underlinesTrigger, "„weckte“ isn't what makes it Akkusativ")
        let wald = try #require(viel.first { $0.target.surface == "dem Wald" })
        #expect(!wald.isBareTimePhrase)
        #expect(wald.underlinesTrigger)
    }

    @Test("Feedback after a wrong pick: the slip note for a slip, the explanation for a case miss")
    func feedback() throws {
        let tasche = try #require(ohneBlanks.first { $0.target.surface == "der Tasche" })
        let slip = KasusService.grade("dem", for: tasche)
        #expect(KasusService.feedback(for: slip, pick: "dem", target: tasche.target, in: story)
                == KasusExplanation.genderSlipNote(pick: "dem", answer: "der", genus: .die, kasus: .dativ))
        let miss = KasusService.grade("die", for: tasche)
        #expect(KasusService.feedback(for: miss, pick: "die", target: tasche.target, in: story)
                == KasusService.explanation(for: tasche.target, in: story))
        #expect(KasusService.feedback(for: .right, pick: "der", target: tasche.target, in: story) == nil)
        let key = try #require(ohneBlanks.first { $0.target.surface == "den Schlüssel" })
        #expect(KasusService.feedback(for: .numberSlip, pick: "die", target: key.target, in: story)?
            .hasPrefix("Right case, **wrong number**") == true)
    }

    // MARK: Round results

    @Test("Einsetzen's result keeps every answer in its sentence")
    func fillResult() throws {
        let blanks = ohneBlanks
        let boden = try #require(blanks.first { $0.target.noun == "Boden" })
        let tasche = try #require(blanks.first { $0.target.surface == "der Tasche" })
        let key = try #require(blanks.first { $0.target.surface == "den Schlüssel" })
        var picks = Dictionary(uniqueKeysWithValues: blanks.map { ($0.id, $0.answer) })
        picks[boden.id] = "der"
        picks[tasche.id] = "dem"
        picks[key.id] = "die"
        let unanswered = try #require(blanks.last)
        picks[unanswered.id] = nil

        let result = KasusService.fillResult(storyID: story.id, unit: .dativ, hint: .ohne, blanks: blanks, picks: picks,
                                             tipps: [boden.id: .gender], durationSeconds: 90, story: story)
        #expect(result.step == .fill)
        #expect(result.askedCount == blanks.count - 1, "a blank with no pick is left out")
        #expect(result.firstTryCount == blanks.count - 4)
        let byTarget = Dictionary(uniqueKeysWithValues: result.items.compactMap { item in item.targetIndex.map { ($0, item) } })
        #expect(byTarget[boden.id]?.slip == false)
        #expect(byTarget[boden.id]?.tipp == .gender)
        #expect(byTarget[tasche.id]?.slip == true)
        #expect(byTarget[key.id]?.slip == true)
        #expect(byTarget[boden.id]?.record?.outcome == .caseMiss)
        #expect(byTarget[tasche.id]?.record?.outcome == .genderSlip)
        #expect(byTarget[key.id]?.record?.outcome == .numberSlip)
        #expect(byTarget[tasche.id]?.record?.explanation.hasPrefix("Right case, **wrong gender**") == true)

        for item in result.items {
            let record = try #require(item.record, "every answer has its history row")
            let start = try #require(record.phraseStart)
            let sentence = record.sentence as NSString
            #expect(sentence.substring(with: NSRange(location: start, length: (record.phrase as NSString).length))
                    == record.phrase, "\(record.phrase) sits at its phraseStart in „\(record.sentence)“")
            #expect(RichMarkup.problems(record.explanation).isEmpty, "\(record.phrase)")
        }
        #expect(result.perCase[.nominativ]?.asked == 6)
    }

    @Test("Finden: right brush, wrong brush, missed, and painting a case with no brush")
    func findMarks() throws {
        let gradable = playable.gradable
        let nom = try #require(gradable.first { $0.kasus == .nominativ })
        let dat = try #require(gradable.first { $0.kasus == .dativ })
        var paint = Dictionary(uniqueKeysWithValues: gradable.map { ($0.index, $0.kasus) })
        paint[nom.index] = nil
        paint[dat.index] = .akkusativ

        let marks = KasusService.gradeFind(paint: paint, in: playable, unit: .dativ)
        #expect(marks.count == gradable.count, "the Dativ unit has a brush for every case in the story")
        #expect(marks[nom.index] == .missed)
        #expect(marks[dat.index] == .wrongPick(painted: .akkusativ))
        #expect(marks.values.filter { $0 == .right }.count == gradable.count - 2)

        let result = KasusService.findResult(storyID: story.id, unit: .dativ, marks: marks, in: playable, durationSeconds: 60)
        #expect(result.askedCount == gradable.count)
        #expect(result.answeredCount == gradable.count - 1, "the unpainted phrase wasn't answered")
        #expect(result.items.first { $0.targetIndex == nom.index }?.record?.outcome == .missed)
        #expect(result.items.first { $0.targetIndex == dat.index }?.record?.pickedCase == .akkusativ)

        // The Akkusativ unit hands out one brush: painting everything with it never scores 100%.
        let allAkk = Dictionary(uniqueKeysWithValues: gradable.map { ($0.index, GrammarCase.akkusativ) })
        let akkMarks = KasusService.gradeFind(paint: allAkk, in: playable, unit: .akkusativ)
        #expect(akkMarks.values.filter { $0 == .right }.count == 11)
        #expect(akkMarks.values.filter { $0 != .right }.count == gradable.count - 11)
        #expect(KasusService.gradeFind(paint: [:], in: playable, unit: .akkusativ).count == 11,
                "unpainted phrases without a brush get no mark")
    }

    @Test("Ergebnis offers a harder round at 80% or more")
    func offersHarder() {
        func fill(_ hint: KasusHintLevel, right: Int, of total: Int) -> KasusRoundResult {
            let items = (0..<total).map { KasusItemResult(kasus: .dativ, genus: .der, firstTry: $0 < right) }
            return KasusRoundResult(storyID: "test", unit: .dativ, step: .fill, hintLevel: hint, items: items, durationSeconds: 0)
        }
        #expect(KasusService.offersHarder(fill(.genus, right: 8, of: 10)))
        #expect(!KasusService.offersHarder(fill(.genus, right: 7, of: 10)))
        #expect(!KasusService.offersHarder(fill(.ohne, right: 10, of: 10)), "nothing above Ohne Hilfe")
        #expect(KasusService.offersHarder(fill(.lern, right: 9, of: 10)), "Lernhilfe → Viel Hilfe")
        let quick = KasusService.quickResult(unit: .dativ, items: fill(.genus, right: 10, of: 10).items, durationSeconds: 0)
        #expect(!KasusService.offersHarder(quick))
        #expect(quick.storyID == "quick-dativ")
    }

    @Test("The -kasus.debugVerify service block reads ALL OK")
    func debugServiceReport() {
        let lines = KasusService.debugServiceReport()
        #expect(lines.last == "Service ALL OK", "\(lines.filter { $0.contains("FAIL") }.joined(separator: "\n"))")
    }

    // MARK: The path

    @Test("The hub's Weiter row over synthetic history")
    func kasusPath() throws {
        let url = try #require(Bundle.main.url(forResource: "kasus_stories", withExtension: "json"))
        let bundled = try KasusStoryBank(data: Data(contentsOf: url))
        // The expectations were written for the Phase 1 story alone.
        let bank = bundled.only([story.id])
        func played(_ steps: [(String, KasusUnit, KasusRoundStep)]) -> [KasusRound] {
            steps.map { KasusRound(storyID: $0.0, unitRaw: $0.1.rawValue, stepRaw: $0.2.rawValue,
                                   askedCount: 1, firstTryCount: 1, durationSeconds: 0,
                                   date: Date().addingTimeInterval(-86_400)) }
        }
        func next(_ level: CEFRLevel, _ rounds: [KasusRound], profile: LearnerProfile? = nil) -> String {
            let hero = KasusPath.next(profile: profile, level: level, rounds: rounds, bank: bank)
            return "\(hero.unit.rawValue) · \(hero.subtitle)"
        }
        let title = "„\(story.title)“"
        let findOnly = played([(story.id, .dativ, .find)])
        let storyDone = played([(story.id, .dativ, .find), (story.id, .dativ, .fill)])
        let everything = storyDone + played(KasusUnit.allCases.map { (KasusService.quickRoundID(for: $0), $0, .quick) })

        #expect(next(.a1, []) == "dativ · \(title) · Lesen")
        #expect(next(.b1, findOnly) == "dativ · \(title) · Endungen")
        #expect(next(.a2, findOnly) == "akkusativ · Schnellrunde · Nom + Akk")
        #expect(next(.a2, storyDone) == "akkusativ · Schnellrunde · Nom + Akk")
        #expect(next(.b1, storyDone) == "dativ · Schnellrunde · Nom + Akk + Dat")
        #expect(next(.b1, everything) == "dativ · Wiederholen · \(title)")
        let shaky = LearnerProfile()
        shaky.grammar = [GrammarFocus.dativ.rawValue: GrammarSkill(struggle: 0.6, lastSeen: Date(), samples: [])]
        #expect(next(.b1, everything, profile: shaky) == "dativ · \(title) · Endungen")

        // With every bundled story, each level starts on its own unit's first story.
        let a1 = KasusPath.next(profile: nil, level: .a1, rounds: [], bank: bundled)
        #expect(a1.unit == .nominativ && a1.step == .lesen && a1.reason == .newStory)
        #expect(a1.storyID == bundled.stories(for: .nominativ).first?.id)
        let a2 = KasusPath.next(profile: nil, level: .a2, rounds: [], bank: bundled)
        #expect(a2.unit == .akkusativ && a2.storyID == bundled.stories(for: .akkusativ).first?.id)
    }
}
