//
//  WorksheetParserTests.swift
//  german-ai-flashcardsTests
//
//  The worksheet parser (Services/Worksheet/WorksheetParser.swift) over lines written here, in the
//  shapes teachers' slide exports have, and over `WorksheetSamplePDF` as iOS PDFKit reads it —
//  the half `scripts/worksheet_probe.sh` can't cover, since the probe runs on the Mac.
//
//  A real lesson PDF never lives in the repo. Point WORKSHEET_FIXTURE_DIR at a folder holding one
//  plus a `<name>.signature.txt` written by `scripts/worksheet_probe.sh <pdf> --signature`, and the
//  last test compares iOS's reading against the Mac's. From the command line the variable needs
//  xcodebuild's prefix: `TEST_RUNNER_WORKSHEET_FIXTURE_DIR=<folder> xcodebuild test …`. That test
//  is what found iOS gluing a column of item numbers onto the first item (see
//  `WorksheetPDFReader.lines(on:)`).
//

import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import Die_Kartei

@Suite struct WorksheetParserTests {

    // MARK: - Fixtures

    /// Lines laid out top to bottom, one per row, 30 points apart, so "close below" means
    /// something. `x` lets a test put two columns side by side.
    private func page(_ rows: [(String, CGFloat, CGFloat)]) -> WorksheetPageText {
        page(1, rows)
    }

    private func page(_ number: Int, _ rows: [(String, CGFloat, CGFloat)]) -> WorksheetPageText {
        var location = 0
        let lines = rows.map { text, x, top -> WorksheetLine in
            let length = (text as NSString).length
            defer { location += length + 1 }
            return WorksheetLine(text: text, range: NSRange(location: location, length: length),
                                 box: CGRect(x: x, y: 540 - top - 24, width: CGFloat(length) * 10, height: 24))
        }
        return WorksheetPageText(number: number, lines: lines)
    }

    private func lines(_ texts: [String], spacing: CGFloat = 40) -> [(String, CGFloat, CGFloat)] {
        texts.enumerated().map { ($0.element, 60, 60 + CGFloat($0.offset) * spacing) }
    }

    private func parse(_ page: WorksheetPageText) -> WorksheetExercise {
        WorksheetParser.parsePage(page, chrome: [])
    }

    // MARK: - Gaps and options

    @Test func closedSetGapsAreKeyedByItemNumber() throws {
        let exercise = parse(page(4, lines([
            "DATIV D1: ARTIKEL ERGÄNZEN",
            "ÜBUNG · BESTIMMTE ARTIKEL",
            "Ergänze dem, der oder den. Sprich die Sätze laut.",
            "1. Wir fahren mit ___ Zug.",
            "2. Sie wohnt bei ___ Tante.",
            "3. Er kommt aus ___ Büro.",
        ]) + [("Nomen: der Zug, die Tante, das Büro. Lösungen: Folie 9.", 60, 400)]))

        #expect(exercise.verdict == .interactive)
        #expect(exercise.displayTitle == "Dativ D1: Artikel ergänzen")
        #expect(exercise.subtitle == "ÜBUNG · BESTIMMTE ARTIKEL")
        #expect(exercise.sections.first?.options == .closedSet(["dem", "der", "den"]))
        #expect(exercise.items.map(\.label) == ["1", "2", "3"])
        #expect(exercise.items.flatMap(\.gaps).map(\.key) == ["p4.s0.i1.g0", "p4.s0.i2.g0", "p4.s0.i3.g0"])
        #expect(exercise.nouns == ["der Zug", "die Tante", "das Büro"])
        #expect(exercise.answerKeyRef == "Folie 9")
        #expect(exercise.notes.count == 1)
    }

    @Test func gapRangesPointAtTheUnderscores() throws {
        let text = "1. Wir fahren mit ___ Zug."
        let exercise = parse(page(lines(["TITEL", "Ergänze dem, der oder den.", text])))
        let gap = try #require(exercise.items.first?.gaps.first)
        // The item line is the third line: its range starts after the two before it.
        let lineStart = ("TITEL" as NSString).length + 1 + ("Ergänze dem, der oder den." as NSString).length + 1
        #expect(gap.range.location - lineStart == (text as NSString).range(of: "___").location)
        #expect(gap.range.length == 3)
        #expect(!gap.isLong)
    }

    @Test func articleSetFollowsTheInstruction() throws {
        #expect(WorksheetText.articleSet(directions: "Ergänze den bestimmten Artikel.", subtitle: nil)
                == .articles(WorksheetText.definiteArticles))
        #expect(WorksheetText.articleSet(directions: "Ergänze den Artikel.", subtitle: "UNBESTIMMTE ARTIKEL")
                == .articles(WorksheetText.indefiniteArticles))
        #expect(WorksheetText.articleSet(directions: "Schreibe die Wörter.", subtitle: nil) == nil)
        #expect(WorksheetText.closedSet("Setze ein, eine oder einen ein.") == ["ein", "eine", "einen"])
        #expect(WorksheetText.closedSet("Wähle die passende Form.") == nil)
    }

    @Test func wordBankAndUsedOnce() throws {
        let exercise = parse(page(lines([
            "Übung 02 · Was passt?",
            "Wähle aus der Wortliste. Jedes Wort passt einmal.",
            "Zug · Bus · Fahrrad · Auto",
            "1 Ich fahre mit dem ________.",
            "2 Der ________ ist pünktlich.",
        ])))
        #expect(exercise.sections.first?.options == .wordBank(["Zug", "Bus", "Fahrrad", "Auto"], usedOnce: true))
        #expect(exercise.items.allSatisfy { $0.gaps.first?.isLong == false })
    }

    @Test func letteredOptionsMakeAMatchingExercise() throws {
        let exercise = parse(page([
            ("Übung 01 · Zuordnen", 60, 40),
            ("Ordne zu. Schreibe den Buchstaben.", 60, 90),
            ("1 der Zug ____", 60, 140), ("A bus", 500, 140),
            ("2 der Bus ____", 60, 180), ("B train", 500, 180),
            ("3 das Rad ____", 60, 220), ("C bike", 500, 220),
        ]))
        guard case .letters(let options)? = exercise.sections.first?.options else {
            Issue.record("expected lettered options"); return
        }
        #expect(options.map(\.letter) == ["A", "B", "C"])
        #expect(options.map(\.text) == ["bus", "train", "bike"])
        #expect(exercise.items.count == 3)
    }

    // MARK: - Choices, chunks, writing

    @Test func inlineChoicesAndMarks() throws {
        let exercise = parse(page(lines([
            "AKKUSATIV AK1: ERKENNEN",
            "Wähle die passende Form. Markiere die Präposition.",
            "1. durch der / den Park",
            "2. für die / der / das Kind",
        ])))
        let first = try #require(exercise.items.first)
        #expect(first.choices.first?.options.map(\.text) == ["der", "den"])
        #expect(exercise.items[1].choices.first?.options.map(\.text) == ["die", "der", "das"])
        #expect(first.marks == .highlight)
        #expect(first.words.map(\.text) == ["durch", "Park"])
        #expect(first.choices.first?.key == "p1.s0.i1.c0")
    }

    @Test func slashesBetweenWordsAreChunksNotChoices() throws {
        let exercise = parse(page(lines([
            "AK2: SÄTZE BILDEN",
            "Bilde ganze Sätze. Setze ein, eine oder einen ein.",
            "1. Ich / kaufe / Brot / für / ___ Kuchen.",
        ])))
        let item = try #require(exercise.items.first)
        #expect(item.choices.isEmpty)
        #expect(item.gaps.count == 1)
        #expect(item.writeBelow)
        #expect(item.chunks == ["Ich", "kaufe", "Brot", "für", "___ Kuchen."])
    }

    @Test func aGlossWithABlankIsNotAChoice() throws {
        // "faulty / broken" glosses the word to write in the blank under it.
        let exercise = parse(page([
            ("Übung 16 · Mini-Check", 60, 40),
            ("Wie heißt das auf Deutsch? Schreibe Nomen mit Artikel.", 60, 90),
            ("9 faulty / broken", 60, 140),
            ("____________________", 60, 172),
        ]))
        let item = try #require(exercise.items.first)
        #expect(item.choices.isEmpty)
        #expect(item.gaps.count == 1)
        #expect(item.gaps.first?.isLong == true)
    }

    @Test func choiceLineUnderAnItemReplacesItsEllipsis() throws {
        let exercise = parse(page([
            ("Übung 09 · Die passende Aktion", 60, 40),
            ("Wähle das Wort mit der passenden Bedeutung.", 60, 90),
            ("1 Ich brauche die Datei später. Ich möchte sie …", 60, 140),
            ("A speichern B löschen", 80, 168),
        ]))
        let item = try #require(exercise.items.first)
        #expect(item.gaps.isEmpty)
        #expect(item.choices.first?.options.map(\.text) == ["speichern", "löschen"])
    }

    @Test func writeBelowForSentenceTasksWithoutABlank() throws {
        let exercise = parse(page(lines([
            "G2: SÄTZE VERBINDEN",
            "Verbinde die Sätze mit der angegebenen Präposition.",
            "1. Es regnet. Wir bleiben zu Hause. (wegen des Regens)",
        ], spacing: 60)))
        let item = try #require(exercise.items.first)
        #expect(item.writeBelow)
        #expect(item.hint == "wegen des Regens")
        #expect(exercise.answerKeys == [item.writeKey])
    }

    // MARK: - Layout

    @Test func twoColumnsReadInPrintedOrder() throws {
        let exercise = parse(page([
            ("GEMISCHTE ÜBUNG M1", 60, 40),
            ("Ergänze den bestimmten Artikel. Notiere den Fall der Lücke.", 60, 90),
            ("1. ___ Zug ist pünktlich.", 60, 140), ("3. Sie fährt ohne ___ Rad.", 500, 140),
            ("2. Ich warte auf ___ Bus.", 60, 200), ("4. Er hilft ___ Frau.", 500, 200),
        ]))
        #expect(exercise.items.map(\.label) == ["1", "2", "3", "4"])
        let allTagged = exercise.items.allSatisfy { $0.caseTag }
        #expect(allTagged)
    }

    @Test func aLineRunAcrossTwoColumnsIsSplit() throws {
        let exercise = parse(page(lines([
            "M1",
            "Ergänze den bestimmten Artikel.",
            "1. ___ Zug ist pünktlich. 3. Sie fährt ohne ___ Rad.",
            "2. Ich warte auf ___ Bus. 4. Er hilft ___ Frau.",
        ])))
        #expect(exercise.items.map(\.label) == ["1", "2", "3", "4"])
        #expect(exercise.items.allSatisfy { $0.gaps.count == 1 })
    }

    @Test func answerLinesStayWithTheirColumn() throws {
        let exercise = parse(page([
            ("Übung 15 · Meine Sätze", 60, 40),
            ("Schreibe vier Sätze. Die Satzanfänge helfen dir.", 60, 90),
            ("1 Nenne ein Gerät.", 60, 140), ("2 Sage, was du willst.", 500, 140),
            ("Das ist …", 80, 164), ("Ich möchte …", 520, 164),
            ("____________________", 60, 212), ("____________________", 500, 212),
        ]))
        #expect(exercise.items.count == 2)
        #expect(exercise.items.allSatisfy { $0.gaps.count == 1 && !$0.writeBelow })
        #expect(exercise.items[0].anchor.contains("Das ist"))
        #expect(exercise.items[1].anchor.contains("Ich möchte"))
    }

    @Test func sectionsRestartTheirNumbering() throws {
        let exercise = parse(page(lines([
            "DATIV D2: FORMEN VERÄNDERN",
            "A: Setze die Gruppen in den Dativ mit „mit“.",
            "1. ein Zug: ______________________",
            "2. eine Tante: ___________________",
            "B: Schreibe im Plural. Behalte „mit“ bei.",
            "1. mit dem Zug: __________________",
        ])))
        #expect(exercise.sections.map(\.key) == ["sA", "sB"])
        #expect(exercise.items.flatMap(\.gaps).map(\.key) == ["p1.sA.i1.g0", "p1.sA.i2.g0", "p1.sB.i1.g0"])
        #expect(exercise.items.allSatisfy { $0.gaps.first?.isLong == true })
        #expect(exercise.instruction == "Setze die Gruppen in den Dativ mit „mit“.")
    }

    @Test func dialogGapsAreKeyedByTheirPrintedNumber() throws {
        let exercise = parse(page(lines([
            "M2: IM CAFÉ",
            "Ergänze die bestimmten Artikel. Lies den Dialog laut.",
            "A (1) ___ Kaffee ist heiß!",
            "B Ich sitze an (2) ___ Fenster und warte auf (3) ___ Bus.",
        ])))
        #expect(exercise.items.map(\.label) == ["A", "B"])
        #expect(exercise.items.flatMap(\.gaps).map(\.key) == ["p1.s0.n1", "p1.s0.n2", "p1.s0.n3"])
        #expect(exercise.items.flatMap(\.gaps).map(\.number) == [1, 2, 3])
        #expect(exercise.items.allSatisfy { $0.hint == nil })
    }

    // MARK: - Pages that aren't exercises

    @Test func explanationAndOverviewPagesAreNotExercises() throws {
        let table = parse(page(lines([
            "DATIV VERSTEHEN",
            "Diese Präpositionen verlangen den Dativ.",
            "mit dem Zug nach der Schule zu dem Bus",
        ])))
        #expect(table.verdict == .notExercise)
        #expect(table.sections.isEmpty)

        let overview = parse(page(lines([
            "DEIN LERNWEG",
            "01 Überblick",
            "Vier Fälle und Artikel",
            "02 Akkusativ",
            "für, ohne, durch …",
        ])))
        #expect(overview.verdict == .notExercise)

        let howTo = parse(page(lines([
            "SO ARBEITEST DU",
            "1 Regel lesen",
            "Lies die Erklärung und sprich die Beispiele laut.",
            "2 Selbst üben",
        ], spacing: 24)))
        #expect(howTo.verdict == .notExercise)
    }

    @Test func typedInClassAnswersAreNoticed() throws {
        let exercise = parse(page(lines([
            "AK2: SÄTZE BILDEN",
            "Bilde ganze Sätze. Setze ein, eine oder einen ein.",
            "1. Ich / kaufe / Brot / für / ___ Kuchen. Ich kaufe Brot für einen Kuchen.",
            "2. Wir / essen / ohne / ___ Suppe. Wir essen ohne eine Suppe.",
        ])))
        #expect(exercise.hasTypedAnswers)

        let clean = parse(page(lines([
            "D1",
            "Ergänze dem, der oder den.",
            "1. Wir fahren mit ___ Zug.",
        ])))
        #expect(!clean.hasTypedAnswers)
    }

    @Test func chromeRepeatsAcrossPages() throws {
        let pages = (1...4).map { number in
            page(number, lines(["KURS · SEITE \(number)", "Übung \(number)", "Die Kartei · Beispiel"]))
        }
        let chrome = WorksheetParser.chrome(in: pages)
        #expect(chrome.contains(WorksheetParser.chromeKey("KURS · SEITE 1")))
        #expect(chrome.contains(WorksheetParser.chromeKey("Die Kartei · Beispiel")))
        // Digits fold, so a bare "Übung 1" … "Übung 4" would count as chrome too; real titles carry
        // words that differ ("Übung 01 · Geräte zuordnen"), which is what keeps them.
        #expect(chrome.contains(WorksheetParser.chromeKey("Übung 9")))
    }

    @Test func softenedTitlesKeepCodesAndNouns() throws {
        #expect(WorksheetText.softenCaps("WECHSELPRÄPOSITIONEN W1") == "Wechselpräpositionen W1")
        #expect(WorksheetText.softenCaps("Übung 01 · Geräte zuordnen") == "Übung 01 · Geräte zuordnen")
        #expect(WorksheetText.softenCaps("NOMINATIV N1: DAS SUBJEKT") == "Nominativ N1: das Subjekt")
    }

    // MARK: - A real PDF, read by iOS PDFKit

    @Test func samplePDFReadsTheSameOnIOS() throws {
        let document = try #require(PDFDocument(data: WorksheetSamplePDF.data()))
        let exercises = WorksheetPDFReader.parse(document)
        #expect(exercises.map(\.verdict) == [.notExercise, .interactive, .interactive, .interactive, .interactive, .interactive])
        #expect(Self.signature(exercises) == Self.sampleSignature)

        // Every blank and choice can be placed on the page, inside it.
        for exercise in exercises where exercise.isExercise {
            let page = try #require(document.page(at: exercise.page - 1))
            let geometry = WorksheetPDFReader.geometry(of: exercise, on: page)
            #expect(geometry.unplaced.isEmpty, "page \(exercise.page): \(geometry.unplaced)")
            for rect in geometry.gaps.values {
                #expect(geometry.pageBounds.contains(rect))
            }
        }
    }

    /// What `scripts/worksheet_probe.sh <sample> --signature` prints on the Mac.
    static let sampleSignature = """
    p2 interactive | s0:closed[dem,der,den]:1/g1 2/g1 3/g1 4/g1
    p3 interactive | s0:articles[der,die,das,den,dem,des]:1/g1k 2/g1k 3/g1k 4/g1k 5/g1k 6/g1k
    p4 interactive | s0:articles[der,die,das,den,dem,des]:1/c1m 2/c1m 3/c1m
    p5 interactive | s0:–:1/w 2/w
    p6 interactive | s0:articles[der,die,das,den,dem,des]:A/g1 B/g1 A/g1
    """

    @Test func realLessonMatchesTheMacProbe() throws {
        guard let folder = ProcessInfo.processInfo.environment["WORKSHEET_FIXTURE_DIR"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".pdf") }
        for file in files {
            let base = (folder as NSString).appendingPathComponent(file)
            let signatureFile = (base as NSString).deletingPathExtension + ".signature.txt"
            guard let expected = try? String(contentsOfFile: signatureFile, encoding: .utf8),
                  let document = PDFDocument(url: URL(fileURLWithPath: base)) else { continue }
            let actual = Self.signature(WorksheetPDFReader.parse(document))
            let matches = actual == expected.trimmingCharacters(in: .whitespacesAndNewlines)
            // The iOS reading beside the Mac's, to diff when they differ.
            if !matches {
                try? actual.write(toFile: (base as NSString).deletingPathExtension + ".ios.signature.txt",
                                  atomically: true, encoding: .utf8)
            }
            #expect(matches, "\(file)")
        }
    }

    /// The probe's `--signature` format, so the two can be compared line for line.
    static func signature(_ exercises: [WorksheetExercise]) -> String {
        exercises.filter(\.isExercise).map { exercise in
            let parts = exercise.sections.map { section in
                "\(section.key):\(describe(section.options)):" + section.items.map { item in
                    var flags = ""
                    if !item.gaps.isEmpty { flags += "g\(item.gaps.count)" }
                    if !item.choices.isEmpty { flags += "c\(item.choices.count)" }
                    if item.writeBelow { flags += "w" }
                    if item.marks != nil { flags += "m" }
                    if item.caseTag { flags += "k" }
                    return "\(item.label ?? "·")\(flags.isEmpty ? "" : "/" + flags)"
                }.joined(separator: " ")
            }
            return "p\(exercise.page) \(exercise.verdict.rawValue)\(exercise.hasTypedAnswers ? " typed" : "") | "
                + parts.joined(separator: " || ")
        }.joined(separator: "\n")
    }

    private static func describe(_ options: WorksheetOptions?) -> String {
        switch options {
        case .none: "–"
        case .closedSet(let words)?: "closed[\(words.joined(separator: ","))]"
        case .articles(let words)?: "articles[\(words.joined(separator: ","))]"
        case .wordBank(let words, let once)?: "bank\(once ? "·once" : "")[\(words.joined(separator: ","))]"
        case .letters(let options)?: "letters[\(options.map { "\($0.letter)=\($0.text)" }.joined(separator: ","))]"
        }
    }
}
