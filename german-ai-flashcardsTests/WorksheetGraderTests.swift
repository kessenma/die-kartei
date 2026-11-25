//
//  WorksheetGraderTests.swift
//  german-ai-flashcardsTests
//
//  The optional check (Services/Worksheet/WorksheetGrader.swift): the article rules on the shapes
//  a teacher's sheet uses, with a stub lexicon so the dictionary and the preposition table are out
//  of the picture; the rule that they stay silent rather than guess; the tutor's reply parser,
//  malformed replies included; and the noun extraction behind "words to the deck".
//

import CoreGraphics
import Foundation
import Testing
@testable import Die_Kartei

@Suite struct WorksheetGraderTests {

    private let lexicon = WorksheetArticleRules.Lexicon(
        prepositions: ["mit": .dativ, "zu": .dativ, "von": .dativ, "ohne": .akkusativ, "für": .akkusativ,
                       "auf": .wechsel, "in": .wechsel, "wegen": .genitiv, "während": .genitiv],
        genders: ["Brot": .das, "Suppe": .die, "Salat": .der, "Tisch": .der, "Sonne": .die,
                  "Regen": .der, "Essen": .das]
    )

    /// One item parsed from a line, on a page whose nouns are `nouns`.
    private func parsed(_ line: String, instruction: String = "Ergänze den bestimmten Artikel.",
                        nouns: [String] = []) throws -> (WorksheetExercise, WorksheetItem) {
        var rows = [("TITEL", CGFloat(60), CGFloat(40)), (instruction, 60, 80), (line, 60, 120)]
        if !nouns.isEmpty { rows.append(("Nomen: " + nouns.joined(separator: ", ") + ".", 60, 400)) }
        var location = 0
        let lines = rows.map { text, x, top -> WorksheetLine in
            let length = (text as NSString).length
            defer { location += length + 1 }
            return WorksheetLine(text: text, range: NSRange(location: location, length: length),
                                 box: CGRect(x: x, y: 540 - top - 24, width: CGFloat(length) * 10, height: 24))
        }
        let exercise = WorksheetParser.parsePage(WorksheetPageText(number: 1, lines: lines), chrome: [])
        let item = try #require(exercise.items.first)
        return (exercise, item)
    }

    private func expected(_ line: String, nouns: [String] = [], candidates: [String] = WorksheetText.definiteArticles)
        throws -> WorksheetArticleRules.Expectation? {
        let (exercise, item) = try parsed(line, nouns: nouns)
        let slot = try #require(item.gaps.first?.key ?? item.choices.first?.key)
        return WorksheetArticleRules.expected(slot: slot, in: item, exercise: exercise,
                                              candidates: candidates, lexicon: lexicon)
    }

    // MARK: - Rules

    @Test func prepositionSetsTheCase() throws {
        #expect(try expected("1. Ich esse die Suppe mit ___ Brot.")?.article == "dem")
        #expect(try expected("2. Zu ___ Suppe passt Brot.")?.article == "der")
        #expect(try expected("3. Ich esse die Suppe ohne ___ Brot.")?.article == "das")
        #expect(try expected("4. Wegen ___ Regens essen wir drinnen.")?.article == "des")
    }

    @Test func twoWayPrepositionsFollowTheHint() throws {
        #expect(try expected("1. Das Brot liegt auf ___ Tisch. (Ort)")?.article == "dem")
        #expect(try expected("2. Ich lege das Brot auf ___ Tisch. (Ziel)")?.article == "den")
        // No hint: the rules don't know, so they don't say.
        #expect(try expected("3. Ich lege das Brot auf ___ Tisch.") == nil)
    }

    @Test func aSentenceStartIsTheSubject() throws {
        let sonne = try expected("7. ___ Sonne scheint.")
        #expect(sonne?.article == "die")
        #expect(sonne?.kasus == .nominativ)
        // A dialog line: "(1)" before the blank isn't a word.
        let (exercise, item) = try parsed("A (1) ___ Essen ist heute gut!")
        let slot = try #require(item.gaps.first?.key)
        #expect(WorksheetArticleRules.expected(slot: slot, in: item, exercise: exercise,
                                               candidates: WorksheetText.definiteArticles, lexicon: lexicon)?.article == "das")
    }

    @Test func aVerbBeforeTheBlankIsLeftToTheTutor() throws {
        #expect(try expected("8. Am Abend wird ___ Suppe kalt.") == nil)
    }

    @Test func theSheetsNounListDecidesPluralsAndEndings() throws {
        // "die Salate" on the sheet + "Salat" masculine in the dictionary → plural → dative "den".
        let plural = try expected("6. Ich nehme etwas von ___ Salaten.", nouns: ["das Brot", "die Salate"])
        #expect(plural?.article == "den")
        // "Essens" matches "das Essen" on the sheet.
        #expect(try expected("8. Während ___ Essens sprechen wir.", nouns: ["das Essen"])?.article == "des")
    }

    @Test func indefiniteArticlesAndChoices() throws {
        #expect(try expected("1. Ich kaufe Brot für ___ Salat.",
                             candidates: ["ein", "eine", "einen"])?.article == "einen")
        // An inline choice is checked the same way.
        let (exercise, item) = try parsed("1. für der / den Salat", instruction: "Wähle die passende Form.")
        let choice = try #require(item.choices.first)
        let check = WorksheetArticleRules.check(answer: "der", caseTag: nil, slot: choice.key, in: item,
                                                exercise: exercise, candidates: ["der", "den"], lexicon: lexicon)
        #expect(check?.outcome == .wrong)
        #expect(check?.correction == "den")
    }

    @Test func theCaseTagIsCheckedToo() throws {
        let (exercise, item) = try parsed("1. Ich esse die Suppe mit ___ Brot.",
                                          instruction: "Ergänze den bestimmten Artikel. Notiere den Fall der Lücke.")
        let slot = try #require(item.gaps.first?.key)
        let right = WorksheetArticleRules.check(answer: "dem", caseTag: .dativ, slot: slot, in: item, exercise: exercise,
                                                candidates: WorksheetText.definiteArticles, lexicon: lexicon)
        #expect(right?.outcome == .right)
        let wrongCase = WorksheetArticleRules.check(answer: "dem", caseTag: .akkusativ, slot: slot, in: item,
                                                    exercise: exercise, candidates: WorksheetText.definiteArticles,
                                                    lexicon: lexicon)
        #expect(wrongCase?.outcome == .wrong)
    }

    @Test func unknownNounsAndNonArticleSetsStaySilent() throws {
        #expect(try expected("1. Ich spiele mit ___ Quokka.") == nil)
        #expect(try expected("1. Ich esse mit ___ Brot.", candidates: ["Drucker", "Kabel"]) == nil)
    }

    // MARK: - A group into a case

    private func groupTask(_ line: String, heading: String) throws -> WorksheetGroupRules.Task? {
        let (exercise, item) = try parsed(line, instruction: heading)
        let slot = try #require(item.gaps.first?.key)
        let directions = [exercise.instruction, exercise.sections.first?.heading].compactMap { $0 }.joined(separator: " ")
        return WorksheetGroupRules.task(slot: slot, in: item, directions: directions, lexicon: lexicon)
    }

    @Test func aGroupPutIntoTheDativ() throws {
        let heading = "A: Setze die Gruppen in den Dativ mit „mit“."
        let maybeBrot = try groupTask("3. ein Brot: ______________________", heading: heading)
        let brot = try #require(maybeBrot)
        #expect(brot.expected == "mit einem Brot")
        #expect(try groupTask("2. eine Suppe: ______________________", heading: heading)?.expected == "mit einer Suppe")

        #expect(WorksheetGroupRules.check(answer: "Mit einem Brot.", task: brot).outcome == .right)
        // A real article in the wrong case is wrong, with the right form.
        let einen = WorksheetGroupRules.check(answer: "mit einen Brot", task: brot)
        #expect(einen.outcome == .wrong)
        #expect(einen.correction == "mit einem Brot")
        // A misread ("eipen", "Brst") is a reading to fix, never a wrong answer.
        #expect(WorksheetGroupRules.check(answer: "mit eipen Brst", task: brot).outcome == .unsure)
        #expect(WorksheetGroupRules.check(answer: "mit eipen Brot", task: brot).outcome == .unsure)
        #expect(WorksheetGroupRules.check(answer: "mit einem", task: brot).outcome == .unsure)
    }

    @Test func pluralAndGenitivGroupsAreLeftToTheTutor() throws {
        #expect(try groupTask("1. mit dem Brot: ____________________", heading: "B: Schreibe im Plural. Behalte „mit“ bei.") == nil)
        #expect(try groupTask("1. der Regen: ____________________", heading: "Setze die Gruppen in den Genitiv.") == nil)
    }

    @Test func aTutorCorrectionFromNowhereIsUnsure() {
        let question = WorksheetTutorCheck.Question(key: "x", line: "ein Brot: [mit eipen Brst]", answer: "mit eipen Brst",
                                                    context: ["3 ein Brot: ___", "Setze die Gruppen in den Dativ mit „mit“."])
        let checks = WorksheetTutorCheck.parse("1: falsch ; mit Eiern ; Dativ", questions: [question])
        #expect(checks["x"]?.outcome == .unsure)
        // A correction about the item's own noun stands, endings and all.
        let sentence = WorksheetTutorCheck.Question(key: "w", line: "Task: Es gibt Wind. → [Wegen dem Wind essen wir drinnen.]",
                                                    answer: "Wegen dem Wind essen wir drinnen.",
                                                    context: ["1 Es gibt Wind. Wir essen drinnen. (wegen des Windes)"])
        let kept = WorksheetTutorCheck.parse("1: falsch ; Wegen des Windes essen wir drinnen. ; Genitiv", questions: [sentence])
        #expect(kept["w"]?.outcome == .wrong)
    }

    // MARK: - The teacher's key

    @Test func keyCheckNormalizesButKeepsUmlauts() {
        #expect(WorksheetKeyCheck.check("Des Regens.", key: "des Regens").outcome == .right)
        #expect(WorksheetKeyCheck.check("Mause", key: "Mäuse").outcome == .wrong)
    }

    // MARK: - The tutor's reply

    private let questions = [
        WorksheetTutorCheck.Question(key: "a", line: "Ich esse mit [dem] Brot.", answer: "dem"),
        WorksheetTutorCheck.Question(key: "b", line: "Zu [die] Suppe passt Brot.", answer: "die"),
        WorksheetTutorCheck.Question(key: "c", line: "Während [des] Essens …", answer: "des"),
    ]

    @Test func parsesOneLinePerAnswer() {
        let reply = """
        1: richtig ; dem ; mit + Dativ
        2: falsch ; der ; zu takes the dative
        3. Unsicher
        """
        let checks = WorksheetTutorCheck.parse(reply, questions: questions)
        #expect(checks["a"]?.outcome == .right)
        #expect(checks["b"]?.outcome == .wrong)
        #expect(checks["b"]?.correction == "der")
        #expect(checks["c"]?.outcome == .unsure)
    }

    @Test func missingOrSelfContradictingLinesAreUnsure() {
        let reply = """
        Here is my check:
        **2: falsch ; die ; hmm**
        """
        let checks = WorksheetTutorCheck.parse(reply, questions: questions)
        #expect(checks["a"]?.outcome == .unsure)
        // "Wrong, the right form is what you wrote" isn't a verdict.
        #expect(checks["b"]?.outcome == .unsure)
        #expect(checks["c"]?.outcome == .unsure)
    }

    @Test func promptBracketsTheAnswers() throws {
        let (exercise, item) = try parsed("1. Ich esse die Suppe mit ___ Brot.")
        let gap = try #require(item.gaps.first)
        let answers = [gap.key: WorksheetAnswer(text: "dem")]
        let asked = WorksheetTutorCheck.questions(for: exercise, answers: answers, open: [gap.key])
        #expect(asked.first?.line == "Ich esse die Suppe mit [dem] Brot.")
        #expect(WorksheetTutorCheck.prompt(instruction: exercise.instruction, nouns: [], questions: asked)
                .contains("1. Ich esse die Suppe mit [dem] Brot."))
    }

    // MARK: - Words to the deck

    @Test func lessonWordsFromNounListsAndVocabularySlides() {
        let vocabulary = WorksheetExercise(
            page: 11, verdict: .notExercise, title: "WORTSCHATZ", subtitle: nil, instruction: nil, sections: [],
            nouns: [], notes: [
                "der Regen der Wind der Schnee",
                "das Brot (bread) die Pizza",
                "Das Café == Location",
                "Zusätzlich (Additionally) für die Sätze: der Tisch, die Küche und der Geschmack.",
            ], answerKeyRef: nil, hasTypedAnswers: false)
        let exercise = WorksheetExercise(
            page: 21, verdict: .interactive, title: "D1", subtitle: nil, instruction: nil, sections: [],
            nouns: ["das Brot", "die Salate", "der Salat", "die Wolken", "die Wolke"], notes: [],
            answerKeyRef: nil, hasTypedAnswers: false)
        let words = LessonWordExtractor.words(from: [vocabulary, exercise])
        let german = words.map(\.german)
        #expect(german.contains("der Regen"))
        #expect(german.contains("die Pizza"))
        #expect(words.first { $0.german == "das Brot" }?.english == "bread")
        #expect(words.first { $0.german == "das Brot" }?.pages == [11, 21])
        // A passing mention isn't a vocabulary line, a note isn't a pair, a plural goes.
        #expect(!german.contains("der Tisch"))
        #expect(!german.contains { $0.contains("Café") })
        #expect(!german.contains("die Salate"))
        #expect(!german.contains("die Wolken"))
        #expect(german.contains("der Salat"))
    }
}
