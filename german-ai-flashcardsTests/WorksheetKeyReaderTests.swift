//
//  WorksheetKeyReaderTests.swift
//  german-ai-flashcardsTests
//
//  A teacher's "Lösungen" pages read into the worksheet key (Services/Worksheet/WorksheetKeyReader
//  .swift), and how the check uses it (WorksheetKeyCheck). The fixtures copy the shape of a real
//  tutor workbook: two answer columns side by side, "C · error analysis" for a matching exercise,
//  and blocks marked as examples. See docs/WORKSHEETS.md.
//

import Foundation
import PDFKit
import Testing
@testable import Die_Kartei

@Suite struct WorksheetKeyReaderTests {

    // MARK: - Fixtures

    private func page(_ number: Int, _ rows: [(String, CGFloat, CGFloat)], boxes: Bool = true) -> WorksheetPageText {
        var location = 0
        let lines = rows.map { text, x, top -> WorksheetLine in
            let length = (text as NSString).length
            defer { location += length + 1 }
            return WorksheetLine(text: text, range: NSRange(location: location, length: length),
                                 box: boxes ? CGRect(x: x, y: 540 - top - 24, width: CGFloat(length) * 10, height: 24) : .zero)
        }
        return WorksheetPageText(number: number, lines: lines)
    }

    private var matching: WorksheetPageText {
        page(2, [
            ("Übung 01 · Zuordnen", 60, 40),
            ("Ordne zu. Schreibe den Buchstaben.", 60, 90),
            ("1 der Zug ____", 60, 140), ("A bus", 500, 140),
            ("2 der Bus ____", 60, 180), ("B train", 500, 180),
            ("3 das Rad ____", 60, 220), ("C bike", 500, 220),
        ])
    }

    private var bank: WorksheetPageText {
        page(3, [
            ("Übung 02 · Im Support", 60, 40),
            ("Ergänze die Wörter. Jedes Wort passt einmal.", 60, 90),
            ("Ticket · Störung", 60, 130),
            ("1 Im System erfassen wir ein ________.", 60, 180),
            ("2 Eine ________ betrifft das Netzwerk.", 60, 220),
        ])
    }

    private var translate: WorksheetPageText {
        page(4, [
            ("Übung 03 · Übersetzen", 60, 40),
            ("Übersetze die Wortgruppen.", 60, 90),
            ("1 to resolve faults ________________", 60, 140),
            ("2 a user account ________________", 60, 180),
        ])
    }

    /// Two answer columns side by side, as her slides have them, plus the slide footer.
    private func twoColumnKey(boxes: Bool = true) -> WorksheetPageText {
        page(10, [
            ("Shohdy German Way", 30, 500),
            ("Lösungen · Übungen 01 und 02", 60, 40),
            ("Erst lösen, dann vergleichen", 60, 80),
            ("Übung 01", 60, 130), ("Übung 02", 560, 130),
            ("1 B · train", 60, 180), ("1 Ticket", 560, 180),
            ("2 A · bus", 60, 220), ("2 Störung", 560, 220),
            ("3 C · bike", 60, 260),
        ], boxes: boxes)
    }

    private var exampleKey: WorksheetPageText {
        page(11, [
            ("Lösungen · Übung 03", 60, 40),
            ("Mögliche Übersetzungen", 60, 80),
            ("1 Störungen beheben", 60, 130),
            ("2 ein Benutzerkonto", 60, 170),
            ("Sinngleiche Übersetzungen sind ebenfalls möglich.", 60, 220),
        ])
    }

    private func exercises(_ pages: [WorksheetPageText]) -> [WorksheetExercise] {
        pages.map { WorksheetParser.parsePage($0, chrome: []) }
    }

    // MARK: - Reading

    @Test func twoColumnsOfAnswersLandOnTheirExercises() throws {
        let sheets = [matching, bank]
        let reading = WorksheetKeyReader.read(pages: sheets + [twoColumnKey()], exercises: exercises(sheets))
        let first = exercises([matching])[0].items.compactMap { $0.gaps.first?.key }
        let second = exercises([bank])[0].items.compactMap { $0.gaps.first?.key }
        #expect(first.map { reading.key[$0] } == ["B", "A", "C"])
        #expect(second.map { reading.key[$0] } == ["Ticket", "Störung"])
        #expect(reading.samples.isEmpty)
        #expect(reading.unmatched.isEmpty)
        #expect(reading.exercises.map(\.number) == [1, 2])
        #expect(reading.exercises.map(\.page) == [2, 3])
    }

    @Test func withoutBoxesTheBlocksAreReadInOrder() {
        // Stacked rather than side by side, the way a page with no geometry reads.
        let stacked = page(10, [
            ("Lösungen · Übungen 01 und 02", 0, 0), ("Übung 01", 0, 0),
            ("1 B · train", 0, 0), ("2 A · bus", 0, 0), ("3 C · bike", 0, 0),
            ("Übung 02", 0, 0), ("1 Ticket", 0, 0), ("2 Störung", 0, 0),
        ], boxes: false)
        let sheets = [matching, bank]
        let reading = WorksheetKeyReader.read(pages: sheets + [stacked], exercises: exercises(sheets))
        #expect(reading.key.count == 5)
        #expect(reading.unmatched.isEmpty)
    }

    @Test func anExampleBlockGoesToSamplesNotTheKey() {
        let reading = WorksheetKeyReader.read(pages: [translate, exampleKey], exercises: exercises([translate]))
        #expect(reading.key.isEmpty)
        #expect(Set(reading.samples.values) == ["Störungen beheben", "ein Benutzerkonto"])
        #expect(reading.exercises.first?.isSample == true)
    }

    @Test func aBlockThatOnlyPartlyFitsIsKeptAsSamples() {
        // Three answers for a page the parser read as two items: the layout was misread, so none
        // of the block is trusted to grade.
        let short = page(10, [
            ("Lösungen · Übung 02", 60, 40),
            ("1 Ticket", 60, 130), ("2 Störung", 60, 170), ("3 Server", 60, 210),
        ])
        let reading = WorksheetKeyReader.read(pages: [bank, short], exercises: exercises([bank]))
        #expect(reading.key.isEmpty)
        #expect(reading.samples.count == 2)
        #expect(reading.unmatched == ["Übung 2 · 3 Server"])
    }

    @Test func pagesThatAreNotAKeyAreIgnored() {
        let reading = WorksheetKeyReader.read(pages: [matching, bank, translate], exercises: exercises([matching, bank, translate]))
        #expect(reading.isEmpty)
        #expect(reading.exercises.isEmpty)
        // An exercise's own pointer to the key is not a key page.
        let pointer = page(5, [("Lösungen: Folie 36.", 60, 40), ("1 Ticket", 60, 90)])
        #expect(WorksheetKeyReader.blocks(on: pointer).isEmpty)
    }

    @Test func theAnswerAsTheLearnerWritesIt() {
        #expect(WorksheetKeyReader.value("C · error analysis") == "C")
        #expect(WorksheetKeyReader.value("falsch: Git ist erforderlich.") == "falsch")
        #expect(WorksheetKeyReader.value("richtig") == "richtig")
        #expect(WorksheetKeyReader.value("40 Stunden pro Woche") == "40 Stunden pro Woche")
        #expect(WorksheetKeyReader.titleNumbers("Lösungen · Übungen 01 und 02") == [1, 2])
        #expect(WorksheetKeyReader.titleNumbers("Lösungen · Übung 09") == [9])
    }

    // MARK: - The check

    @Test func aClosedSetIsSettledByTheKey() throws {
        let item = try #require(exercises([bank])[0].items.first { !$0.gaps.isEmpty })
        let slot = try #require(item.gaps.first?.key)
        #expect(WorksheetKeyCheck.isClosedSet(slot: slot, item: item, options: .wordBank(["Ticket"], usedOnce: true)))
        #expect(!WorksheetKeyCheck.isClosedSet(slot: slot, item: item, options: nil))
        #expect(WorksheetKeyCheck.check("ticket", key: "Ticket").outcome == .right)
        #expect(WorksheetKeyCheck.check("Störung", key: "Ticket").outcome == .wrong)
    }

    @Test func anOpenBlankInOtherWordsIsOnlyPruefen() {
        let check = WorksheetKeyCheck.mismatch("40 Stunden", key: "40 Stunden pro Woche")
        #expect(check.outcome == .unsure)
        #expect(check.correction == "40 Stunden pro Woche")
    }

    @Test func anExampleIsRightWhenMatchedAndNeverWrong() {
        #expect(WorksheetKeyCheck.example("Störungen beheben", sample: "Störungen beheben").outcome == .right)
        let other = WorksheetKeyCheck.example("Fehler beheben", sample: "Störungen beheben")
        #expect(other.outcome == .unsure)
        #expect(other.correction == "Störungen beheben")
    }

    @Test func theTutorSeesHerAnswerBesideTheLearners() throws {
        let exercise = exercises([translate])[0]
        let slot = try #require(exercise.items.first?.gaps.first?.key)
        let answers = [slot: WorksheetAnswer(text: "Fehler beheben")]
        let questions = WorksheetTutorCheck.questions(for: exercise, answers: answers, open: [slot],
                                                      references: [slot: "Störungen beheben"])
        let question = try #require(questions.first)
        #expect(question.reference == "Störungen beheben")
        #expect(question.context.contains("Störungen beheben"))
        #expect(WorksheetTutorCheck.prompt(instruction: nil, nouns: [], questions: questions)
                    .contains("the teacher's example answer: Störungen beheben"))
    }

    // MARK: - Phrase cards from the key

    private var nounVerb: WorksheetPageText {
        page(6, [
            ("Übung 04 · Nomen und Verb", 60, 40),
            ("Welches Verb passt? Schreibe den Buchstaben.", 60, 90),
            ("1 eine Störung ____", 60, 140), ("A konfigurieren", 500, 140),
            ("2 einen Server ____", 60, 180), ("B beheben", 500, 180),
            ("3 eine Anwendung ____", 60, 220), ("C entwickeln", 500, 220),
        ])
    }

    @Test func aNounAndVerbExerciseGivesPhrases() {
        let pages = [nounVerb]
        let key = page(12, [("Lösungen · Übung 04", 60, 40), ("1 B · beheben", 60, 130), ("2 A · konfigurieren", 60, 170),
                                  ("3 C · entwickeln", 60, 210)])
        let reading = WorksheetKeyReader.read(pages: pages + [key], exercises: exercises(pages))
        let phrases = KeyPhraseExtractor.phrases(from: exercises(pages), key: reading.key, samples: reading.samples)
        #expect(phrases.map(\.german) == ["eine Störung beheben", "einen Server konfigurieren", "eine Anwendung entwickeln"])
        #expect(phrases.allSatisfy { $0.english == nil && !$0.isSentence })
    }

    @Test func anEnglishPromptBecomesTheBack() {
        let reading = WorksheetKeyReader.read(pages: [translate, exampleKey], exercises: exercises([translate]))
        let phrases = KeyPhraseExtractor.phrases(from: exercises([translate]), key: reading.key, samples: reading.samples)
        #expect(phrases.first?.german == "Störungen beheben")
        #expect(phrases.first?.english == "to resolve faults")
    }

    @Test func singleWordsAndAnswerSlotsAreNotPhrases() {
        // German → English matching gives word pairs, which the lesson's vocabulary already has.
        let sheets = [matching, bank]
        let reading = WorksheetKeyReader.read(pages: sheets + [twoColumnKey()], exercises: exercises(sheets))
        let fromMatching = KeyPhraseExtractor.phrases(from: exercises([matching]), key: reading.key, samples: reading.samples)
        #expect(fromMatching.isEmpty)
        // A blank after a finished sentence is an answer slot ("Muss"/"Kann"), never part of it.
        let label = page(7, [
            ("Übung 05 · Muss oder Kann?", 60, 40),
            ("Schreibe „Muss“ oder „Kann“.", 60, 90),
            ("1 Kenntnisse in Linux sind wünschenswert. ____", 60, 140),
        ])
        let labelKey = page(13, [("Lösungen · Übung 05", 60, 40), ("1 Kann", 60, 130)])
        let labelReading = WorksheetKeyReader.read(pages: [label, labelKey], exercises: exercises([label]))
        #expect(KeyPhraseExtractor.phrases(from: exercises([label]), key: labelReading.key, samples: labelReading.samples).isEmpty)
    }

    // MARK: - A real workbook

    /// For each PDF in `WORKSHEET_FIXTURE_DIR` with a `<name>.key.txt` beside it (what
    /// `scripts/worksheet_probe.sh <pdf> --key-signature` prints on the Mac), the iOS reading
    /// must match. Her PDFs never enter the repo.
    @Test func realWorkbookKeyMatchesTheMacProbe() throws {
        guard let folder = ProcessInfo.processInfo.environment["WORKSHEET_FIXTURE_DIR"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".pdf") }
        for file in files {
            let base = (folder as NSString).appendingPathComponent(file)
            let keyFile = (base as NSString).deletingPathExtension + ".key.txt"
            guard let expected = try? String(contentsOfFile: keyFile, encoding: .utf8),
                  let document = PDFDocument(url: URL(fileURLWithPath: base)) else { continue }
            let reading = WorksheetKeyReader.read(pages: WorksheetPDFReader.pageTexts(of: document),
                                                  exercises: WorksheetPDFReader.parse(document))
            let actual = WorksheetKeyReader.signature(reading)
            let matches = actual == expected.trimmingCharacters(in: .whitespacesAndNewlines)
            // The iOS reading beside the Mac's, to diff when they differ.
            if !matches {
                try? actual.write(toFile: (base as NSString).deletingPathExtension + ".ios.key.txt", atomically: true, encoding: .utf8)
            }
            #expect(matches, "\(file)")
        }
    }
}
