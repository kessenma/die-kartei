//
//  VocabListParserTests.swift
//  german-ai-flashcardsTests
//
//  The vocabulary-sheet reader (Services/VocabListParser.swift): the tab-delimited table shapes a
//  rebuilt page arrives in, the plural a noun cell wrapped onto its second line, what is furniture
//  and what is a row, and the per-page reading that keeps one page's loose ends off the next.
//
//  Also the deck builder's pure helpers (Features/DocumentDeck/DocumentDeckBuilderView.swift) and
//  the merge they have to agree with (Services/DocumentDeckService.swift): `fold` must equal
//  `parse`, or the builder reads a document twice to answer one question about it, and a repeat
//  badge must mean exactly what the merge is about to do.
//
//  The fixtures are written here rather than taken from a teacher's file — same structure, our own
//  words. A real sheet is checked end to end with scripts/vocab_sheet_probe.sh; see
//  docs/DOCUMENT_DECKS.md for the numbers that run records.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct VocabListParserTests {

    // MARK: - Fixtures

    /// A lesson slide as `OCRTableLayout` rebuilds it: three columns, the noun cell carrying its
    /// plural, and the slide's own furniture above and below the table.
    private static let nounSlide = """
    Geräte und Zubehör I
    Lektion 01 · Wortfeld 01
    Wort und Plural\tMeaning\tBeispiel
    der Computer die Computer\tcomputer\tDer Computer ist neu.
    die Maus die Mäuse\tmouse\tDie Maus ist klein.
    das Netzteil die Netzteile\tpower adapter\tDas Netzteil ist für den Laptop.
    Lerne das Nomen zusammen mit dem Artikel.
    Musterschule Deutsch\tLearn. Practice. Succeed.\tITKursStudentM01L01V01Q4/2026
    kurs@example.com\t© Musterschule – All rights reserved
    """

    private static let verbSlide = """
    Aktionen am Computer I
    Wort\tMeaning\tBeispiel
    öffnen\tto open\tIch öffne die Datei.
    schließen\tto close\tIch schließe das Programm.
    speichern\tto save\tIch speichere die Datei.
    """

    /// A Wortliste's double block: two German | English pairs printed side by side on one line.
    private static let doubleBlock = """
    Deutsch\tEnglish\tDeutsch\tEnglish
    der Computer\tcomputer\tdie Datei\tfile
    der Laptop\tlaptop\tder Ordner\tfolder
    der Drucker\tprinter\tdas Programm\tprogram
    """

    private func rows(_ text: String) -> [VocabListRow] { VocabListParser.parse(text).rows }

    // MARK: - Three columns

    @Test func nounRowKeepsItsExampleAndPlural() throws {
        let parsed = rows(Self.nounSlide)
        #expect(parsed.count == 3)
        let computer = try #require(parsed.first)
        #expect(computer.german == "der Computer")
        #expect(computer.english == "computer")
        #expect(computer.example == "Der Computer ist neu.")
        #expect(computer.forms == "Plural: die Computer")
        #expect(computer.confident)
    }

    @Test func umlautedPluralIsStillReadAsAPlural() throws {
        let maus = try #require(rows(Self.nounSlide).first { $0.german == "die Maus" })
        #expect(maus.forms == "Plural: die Mäuse")
    }

    @Test func verbRowHasAnExampleAndNoPlural() throws {
        let parsed = rows(Self.verbSlide)
        #expect(parsed.count == 3)
        let open = try #require(parsed.first)
        #expect(open.german == "öffnen")
        #expect(open.english == "to open")
        #expect(open.example == "Ich öffne die Datei.")
        #expect(open.forms == nil)
    }

    // MARK: - Four columns

    @Test func doubleBlockGivesTwoRowsPerLine() {
        let parsed = rows(Self.doubleBlock)
        #expect(parsed.count == 6)
        #expect(parsed.allSatisfy { $0.isComplete })
        #expect(parsed.allSatisfy { $0.example == nil })
        #expect(parsed.map(\.german).contains("die Datei"))
        #expect(parsed.map(\.english).contains("folder"))
    }

    // MARK: - What a page keeps out

    @Test func slideFurnitureNeverBecomesARow() {
        let germans = rows(Self.nounSlide).map(\.german).joined(separator: " ")
        #expect(!germans.contains("Musterschule"))
        #expect(!germans.contains("kurs@example.com"))
        #expect(!germans.contains("ITKurs"))
        #expect(!germans.contains("Geräte und Zubehör"))
    }

    /// The footnote under the table is a German sentence on a line of its own. Before pages were
    /// read one at a time it became a pending German column and glued onto the next row.
    @Test func footnoteDoesNotGlueOntoTheNextRow() {
        let parsed = rows(Self.nounSlide)
        #expect(parsed.allSatisfy { !$0.german.contains("Lerne das Nomen") })
        #expect(parsed.allSatisfy { !$0.english.contains("Lerne das Nomen") })
    }

    @Test func aPageEndsWhereItsMarkerSays() throws {
        let text = """
        [Seite 1]
        der Tisch\ttable
        die Lampe\tlamp
        das Fenster\twindow
        ein Satz ohne seine Übersetzung
        [Seite 2]
        der Stuhl\tchair
        die Tür\tdoor
        das Regal\tshelf
        """
        let pages = VocabListParser.pages(text)
        #expect(pages.map(\.number) == [1, 2])
        let first = try #require(pages.last?.rows.first)
        #expect(first.german == "der Stuhl")
        #expect(pages.allSatisfy { $0.rows.allSatisfy { !$0.german.contains("ohne seine") } })
    }

    @Test func textWithoutMarkersIsOnePage() {
        let pages = VocabListParser.pages("der Tisch – table\ndie Lampe – lamp\ndas Fenster – window")
        #expect(pages.count == 1)
        #expect(pages.first?.number == 1)
        #expect(pages.first?.rows.count == 3)
    }

    @Test func rowsCarryThePageTheyCameFrom() {
        let pages = VocabListParser.pages("[Seite 8]\n" + Self.nounSlide)
        #expect(pages.first?.rows.allSatisfy { $0.page == 8 } == true)
    }

    // MARK: - Which pages switch themselves on

    /// German on both sides is no German | English pair: its "English" would reach a card as
    /// German. Without a gloss header (`VocabGlossTableTests`) such a table gives no rows at all.
    @Test func aGermanOnlyTableGivesNoRows() throws {
        let page = try #require(VocabListParser.pages("""
        Wörter\tSo merkst du den Unterschied
        Datei / Ordner\tDie Datei heißt Plan.pdf. Sie liegt im Ordner.
        Browser / Webseite\tDer Browser ist ein Programm. Er zeigt die Webseite.
        E-Mail / Anhang\tDie E-Mail ist eine Nachricht. Der Anhang ist eine Datei darin.
        kopieren / einfügen\tIch kopiere den Link. Dann füge ich ihn in die E-Mail ein.
        """).first)
        #expect(page.rows.isEmpty)
        #expect(!page.looksLikeVocab)
    }

    // MARK: - What is not a row (Nov 2026, an IT workbook)

    /// The note under a noun table, split on its "=", used to become a card with German on its
    /// English side, once per page.
    @Test func aNoteSplitOnItsEqualsSignIsNotARow() throws {
        let page = try #require(VocabListParser.pages("""
        [Seite 9]
        Wort und Plural\tMeaning\tBeispiel
        die Anfrage die Anfragen\trequest\tIch beantworte eine Anfrage.
        die Aufgabe die Aufgaben\ttask / duty\tMeine Aufgabe ist der Support.
        die Erfahrung —\texperience\tIch habe Erfahrung im Support.
        Nomen mit Artikel. Darunter der Plural. „—“ = in dieser Lektion ohne Plural.
        """).first)
        #expect(page.rows.map(\.english) == ["request", "task / duty", "experience"])
        #expect(page.looksLikeVocab)
    }

    /// A slide title broken over two cells ("Tätigkeiten in der | IT") is no word and its meaning.
    @Test func aTitleCutOffAfterItsArticleIsNotARow() throws {
        let page = try #require(VocabListParser.pages("""
        [Seite 16]
        Aufgaben in der\tIT
        installieren\tto install\tWir installieren ein Programm.
        testen\tto test\tWir testen die Anwendung.
        speichern\tto save\tIch speichere die Datei.
        """).first)
        #expect(page.rows.map(\.german) == ["installieren", "testen", "speichern"])
    }

    /// A contents page in reading order: page ranges and the footer are not English.
    @Test func aContentsPageInReadingOrderGivesNoRows() throws {
        let page = try #require(VocabListParser.pages("""
        [Seite 7]
        Inhalt
        Wortschatz 30 Wörter und drei Hilfen  08–17
        Übungen 12 Aufgaben mit Lösungen  18–29
        Lösungen Antworten und Beispiele  30–35
        Wortlisten Alle Wörter zum Nachschlagen  36–39
        © Musterschule – All rights reserved
        """).first)
        #expect(page.rows.isEmpty)
        #expect(!page.looksLikeVocab)
    }

    /// The "English is German" test can't trust one word: alone, "bonnet" reads 0.94 German.
    @Test func readsGermanNeedsAnUmlautOrThreeWords() {
        #expect(VocabListParser.readsGerman("in dieser Lektion ohne Plural."))
        #expect(VocabListParser.readsGerman("Größe"))
        for english in ["activity / duty", "sound / in-depth", "bonnet", "smell", "dwarf", "fast",
                        "to provide / deploy", "fixing faults / errors", "chicken, hen", "sinner (male)",
                        // A German example in brackets doesn't make the English German.
                        "to doubt (ich zweifle an der Wahrheit – I doubt the truth)",
                        "to be afraid of (ich fürchte mich vor Hunden)",
                        // A gloss that opens like English, on a fairy-tale list.
                        "old expression: danach (after that)"] {
            #expect(!VocabListParser.readsGerman(english), "\(english)")
        }
    }

    @Test func aSheetOfBlanksIsNotVocabulary() throws {
        let page = try #require(VocabListParser.pages("""
        1 keyboard _______________\t6 to save _______________
        2 attachment _______________\t7 to paste _______________
        3 folder _______________\t8 to check _______________
        4 password _______________\t9 broken _______________
        """).first)
        #expect(!page.looksLikeVocab)
        #expect(page.rows.isEmpty)
    }

    @Test func aContentsTableIsNotVocabulary() throws {
        let page = try #require(VocabListParser.pages("""
        Bereich\tInhalt\tFolien
        Wortschatz\t40 Wörter und Beispiele\t08–17
        Üben\t16 Übungen mit verschiedenen Aufgaben\t18–33
        Lösungen\tAntworten und Beispielantworten\t34–43
        Wiederholen\tWortliste und nächste Schritte\t44–48
        """).first)
        #expect(!page.looksLikeVocab)
    }

    @Test func aLessonSlideSwitchesItselfOn() throws {
        let page = try #require(VocabListParser.pages(Self.nounSlide).first)
        #expect(page.looksLikeVocab)
        #expect(page.listConfidence == 1.0)
    }

    // MARK: - pluralPair stays narrow

    @Test func pluralPairSplitsAWrappedNounCell() {
        #expect(VocabForms.pluralPair("der Computer die Computer")?.plural == "die Computer")
        #expect(VocabForms.pluralPair("die Maus die Mäuse")?.singular == "die Maus")
        #expect(VocabForms.pluralPair("der USB-Stick die USB-Sticks")?.plural == "die USB-Sticks")
        #expect(VocabForms.pluralPair("das Passwort die Passwörter")?.plural == "die Passwörter")
        // A borrowed ending swapped for -en.
        #expect(VocabForms.pluralPair("das Benutzerkonto die Benutzerkonten")?.plural == "die Benutzerkonten")
        #expect(VocabForms.pluralPair("das Museum die Museen")?.singular == "das Museum")
        #expect(VocabForms.pluralPair("das Thema die Themen")?.plural == "die Themen")
        #expect(VocabForms.pluralPair("das Konto die Karten") == nil)
    }

    /// A teacher's own multi-form entry must be left whole for `VocabForms.split`, which is what
    /// the handout glossary matches against.
    @Test func pluralPairLeavesATeachersOwnFormsAlone() {
        #expect(VocabForms.pluralPair("der Kieselstein/ die Kieselsteine (pl)") == nil)
        #expect(VocabForms.pluralPair("die Sorge/ die Sorgen (pl)") == nil)
        #expect(VocabForms.pluralPair("das Gift, -e poison") == nil)
        #expect(VocabForms.pluralPair("der Lehrer, - teacher") == nil)
        #expect(VocabForms.pluralPair("die Frau das Haus") == nil)
    }

    // MARK: - The two-column path is untouched

    /// A tab line reads exactly as the explicit-separator path already read it — including keeping
    /// the sheet's "plural unchanged" mark on the German side, which is what `VocabForms.split`
    /// and the handout glossary work from.
    @Test func twoCellLineReadsLikeTheSeparatorPathDid() throws {
        let parsed = rows("der Lehrer, -\tteacher\ndie Katze, -n\tcat\ndas Haus, ¨-er\thouse")
        #expect(parsed.count == 3)
        let lehrer = try #require(parsed.first)
        #expect(lehrer.german == "der Lehrer, -")
        #expect(lehrer.english == "teacher")
        #expect(lehrer.example == nil)
        #expect(lehrer.forms == nil)
        #expect(VocabForms.split("das Haus, ¨-er").contains("Häuser"))
    }

    /// A plural mark sitting in its own cell is the German column's tail, not a third column.
    @Test func aPluralMarkCellFoldsBackOntoItsNoun() throws {
        let parsed = rows("das Ebenholz,\t-¨er\tebony\ndie Gemahlin,\t-nen\tbride\nder Neid\tenvy")
        let ebony = try #require(parsed.first)
        #expect(ebony.german == "das Ebenholz, -¨er")
        #expect(ebony.english == "ebony")
        #expect(ebony.example == nil)
    }

    /// The golden regression: the sheet behind `-classNotes.debugOpen builder`, which the feature
    /// doc records as 32 rows.
    @Test func theSeededVocabSheetStillReadsAsThirtyTwoRows() {
        let parsed = VocabListParser.parse(ClassNotesDebugSeeder.vocabSheetText)
        #expect(parsed.rows.filter(\.isComplete).count == 32)
        #expect(parsed.looksLikeList)
        #expect(parsed.title == "Vokabelliste für \u{201C}Hänsel und Gretel\u{201D}")
    }

    // MARK: - What reaches the card

    /// The two hops a plural makes between a parsed row and the face of a card. `DeckStore` builds
    /// the study session from `SavedDeck.vocabCards`, not from `SavedCard.vocabCard`, so both have
    /// to carry it — fixing only one leaves the caption invisible on the path a document deck is
    /// actually studied through.
    @Test func thePluralAndExampleSurviveTheRoundTrip() throws {
        let row = try #require(rows(Self.nounSlide).first)
        let card = VocabCard(
            germanWord: "Computer",
            englishTranslation: row.english,
            wordType: "noun",
            article: "der",
            exampleSentence: row.example,
            conjugations: nil,
            forms: row.forms
        )
        let deck = SavedDeck(topic: "Slides", wordCount: 1, includeExamples: true, vocabCards: [card])

        let stored = try #require(deck.cards.first)
        #expect(stored.formsLine == "Plural: die Computer")
        #expect(stored.exampleSentence == "Der Computer ist neu.")

        // The Library's study session.
        let viaDeck = try #require(deck.vocabCards.first)
        #expect(viaDeck.forms == "Plural: die Computer")
        #expect(viaDeck.exampleSentence == "Der Computer ist neu.")

        // The single-card path.
        #expect(stored.vocabCard.forms == "Plural: die Computer")
    }

    /// A word the sheet lists twice is one card that gathers what each mention had, whichever came
    /// first — a Wortliste repeats the lesson pages' words with no example and no plural.
    @MainActor
    @Test func aRepeatedWordBecomesOneCardThatKeepsTheRicherMention() throws {
        let sparse = VocabListRow(german: "der Computer", english: "computer")
        let rich = try #require(rows(Self.nounSlide).first)
        // The production merge, not a copy of it: a badge in the builder promises what this does.
        for order in [[sparse, rich], [rich, sparse]] {
            let merged = DocumentDeckService.merge(order)
            #expect(merged.count == 1)
            #expect(merged.first?.forms == "Plural: die Computer")
            #expect(merged.first?.exampleSentence == "Der Computer ist neu.")
        }
    }

    // MARK: - Reading the document once

    @Test func foldingThePagesMatchesParsingTheWholeText() {
        let marked = "[Seite 8]\n" + Self.nounSlide + "\n[Seite 9]\n" + Self.verbSlide
        for text in [Self.nounSlide, Self.verbSlide, marked] {
            let folded = VocabListParser.fold(VocabListParser.pages(text))
            let parsed = VocabListParser.parse(text)
            #expect(folded.rows.count == parsed.rows.count)
            #expect(folded.title == parsed.title)
            #expect(folded.listConfidence == parsed.listConfidence)
            #expect(folded.looksLikeList == parsed.looksLikeList)
        }
    }

    @Test func pageMarkersAreStrippedForThePicker() {
        let picked = DocumentDeckBuilderView.readingText("[Seite 8]\nder Tisch\n[Seite 9]\ndie Lampe")
        #expect(!picked.contains("[Seite"))
        #expect(picked.contains("der Tisch"))
        #expect(picked.contains("die Lampe"))
    }

    // MARK: - Dubletten

    @Test func aRepeatMarkNamesThePageTheFirstMentionWasOn() throws {
        let rows = [
            VocabListRow(german: "der Computer", english: "computer", page: 8),
            VocabListRow(german: "die Maus", english: "mouse", page: 8),
            VocabListRow(german: "der Computer", english: "computer", page: 34)
        ]
        let marks = DocumentDeckBuilderView.repeatMarks(in: rows)
        #expect(marks.count == 1)
        let mark = try #require(marks[rows[2].id])
        #expect(mark.ordinal == 2)
        #expect(mark.firstPage == 8)
    }

    @Test func anArticleOrACapitalDoesNotHideARepeat() {
        // The key is the one the merge uses, so these are the same card and must read as a repeat.
        let rows = [
            VocabListRow(german: "der Computer", english: "computer", page: 8),
            VocabListRow(german: "Computer", english: "computer", page: 34)
        ]
        #expect(DocumentDeckBuilderView.repeatMarks(in: rows).count == 1)
    }

    @Test func aRepeatIsOnlyARepeatAmongTheRowsOnScreen() {
        // The page-8 mention switched off: what is left is the only mention and wears no badge.
        let later = VocabListRow(german: "der Computer", english: "computer", page: 34)
        #expect(DocumentDeckBuilderView.repeatMarks(in: [later]).isEmpty)
    }

    @Test func theThirdMentionCountsThree() throws {
        let rows = (1...3).map { VocabListRow(german: "der Computer", english: "computer", page: $0) }
        let marks = DocumentDeckBuilderView.repeatMarks(in: rows)
        #expect(marks.count == 2)
        #expect(marks[rows[1].id]?.ordinal == 2)
        #expect(marks[rows[2].id]?.ordinal == 3)
        #expect(marks[rows[2].id]?.firstPage == 1)
    }

    @Test func aHandTypedFirstMentionHasNoPageToName() throws {
        let rows = [
            VocabListRow(german: "der Computer", english: "computer"),
            VocabListRow(german: "der Computer", english: "computer", page: 8)
        ]
        let marks = DocumentDeckBuilderView.repeatMarks(in: rows)
        #expect(try #require(marks[rows[1].id]).firstPage == nil)
    }

    // MARK: - A PDF's bytes are a PDF

    @Test func onlyRealPDFBytesPassTheDownloadCheck() {
        #expect(WebTextExtractor.looksLikePDF(Data("%PDF-1.7\nstuff".utf8), contentType: "application/pdf"))
        #expect(WebTextExtractor.looksLikePDF(Data("%PDF-1.4".utf8), contentType: nil))
        #expect(!WebTextExtractor.looksLikePDF(Data("<!doctype html><html>Sign in</html>".utf8), contentType: "text/html"))
        #expect(!WebTextExtractor.looksLikePDF(Data("<!doctype html>".utf8), contentType: "application/pdf"))
        #expect(!WebTextExtractor.looksLikePDF(Data(), contentType: "application/pdf"))
    }

    // MARK: - Typing the pages instead of tapping them

    @Test func pageRangesAreReadAndWrittenBack() {
        let available = Set(1...37)
        #expect(DocumentDeckBuilderView.pageSelection("8-15, 34-35", in: available) == Set(8...15).union(34...35))
        #expect(DocumentDeckBuilderView.pageSelection("15-8", in: available) == Set(8...15))
        #expect(DocumentDeckBuilderView.pageSelection("8,,9", in: available) == Set([8, 9]))
        #expect(DocumentDeckBuilderView.pageSelection("99", in: available) == [])
        #expect(DocumentDeckBuilderView.pageSelection("abc", in: available) == nil)
        #expect(DocumentDeckBuilderView.pageSelection("", in: available) == [])

        #expect(DocumentDeckBuilderView.describe(Set(8...15).union(34...35)) == "8-15, 34-35")
        #expect(DocumentDeckBuilderView.describe([8, 10, 11]) == "8, 10-11")
        #expect(DocumentDeckBuilderView.describe([]) == "")
        let selection = Set([2, 3, 4, 9])
        #expect(DocumentDeckBuilderView.pageSelection(DocumentDeckBuilderView.describe(selection), in: available) == selection)
    }
}

/// A German | German table under a header like "Einfach erklärt": phrases with the teacher's own
/// explanation, which becomes the card's sentence while the tutor supplies the English.
@Suite struct VocabGlossTableTests {
    private let gloss = """
    [Seite 17]
    Typische Wortverbindungen
    In der Anzeige\tEinfach erklärt
    fundierte Kenntnisse in Python\tDu kennst Python gut und kannst damit arbeiten.
    eine vergleichbare Qualifikation\tDu hast eine andere, ähnlich passende Ausbildung.
    Analyse und Behebung von Störungen\tDu findest die Ursache und löst das Problem.
    Beispiel: „Windows ist erforderlich.“ Windows = Muss.
    """

    @Test func aGlossTableKeepsItsPhrasesAndExplanations() throws {
        let page = try #require(VocabListParser.pages(gloss).first)
        #expect(page.isGloss)
        #expect(page.looksLikeVocab)
        #expect(page.rows.map(\.german) == ["fundierte Kenntnisse in Python", "eine vergleichbare Qualifikation",
                                            "Analyse und Behebung von Störungen"])
        #expect(page.rows.allSatisfy { $0.english.isEmpty })
        #expect(page.rows.first?.example == "Du kennst Python gut und kannst damit arbeiten.")
        #expect(VocabListParser.isGlossTable(gloss))
    }

    @Test func aMeaningHeaderOverEnglishIsAnOrdinaryList() throws {
        let list = """
        [Seite 3]
        Wort\tBedeutung
        das Haus\thouse
        der Baum\ttree
        die Katze\tcat
        """
        let page = try #require(VocabListParser.pages(list).first)
        #expect(!page.isGloss)
        #expect(page.rows.map(\.english) == ["house", "tree", "cat"])
    }

    /// A gloss header reached while a gloss table is already running is still a header, not a
    /// phrase with "Bedeutung im Lerntext" for its sentence (seen on an iPad, Nov 2026).
    @Test func aRepeatedGlossHeaderIsNotARow() throws {
        let page = try #require(VocabListParser.pages("""
        [Seite 18]
        Formulierung\tBedeutung im Lerntext
        Formulierung\tBedeutung im Lerntext
        erforderlich\tMuss: Das wird verlangt.
        wünschenswert\tKann: Das ist ein Vorteil.
        idealerweise\tKann: Das passt besonders gut.
        """).first)
        #expect(page.rows.map(\.german) == ["erforderlich", "wünschenswert", "idealerweise"])
    }

    @Test func glossHeaders() {
        #expect(VocabListParser.isGlossHeader("In der Anzeige\tEinfach erklärt"))
        #expect(VocabListParser.isGlossHeader("Formulierung\tBedeutung im Lerntext"))
        #expect(!VocabListParser.isGlossHeader("Deutsch\tEnglish"))
        #expect(!VocabListParser.isGlossHeader("fundierte Kenntnisse in Python\tDu kennst Python gut."))
    }
}

/// A real teacher's sheet, read the way the app reads it on iOS (`PDFTextExtractor` with the table
/// rebuild, then the parser), against what `scripts/vocab_sheet_probe.sh <pdf> --rows` printed on
/// the Mac. iOS PDFKit orders a bordered table's lines column by column and the Mac row by row,
/// so the probe alone can't vouch for a device. A real PDF never lives in the repo: put it in
/// `WORKSHEET_FIXTURE_DIR` with `<name>.vocab-rows.txt` beside it (the probe's output); on a
/// mismatch the iOS reading is written beside it as `<name>.ios.vocab-rows.txt` to diff.
@Suite struct VocabRealSheetTests {
    @Test func realSheetRowsMatchTheMacProbe() throws {
        guard let folder = ProcessInfo.processInfo.environment["WORKSHEET_FIXTURE_DIR"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".pdf") }
        for file in files {
            let base = ((folder as NSString).appendingPathComponent(file) as NSString).deletingPathExtension
            guard let expected = try? String(contentsOfFile: base + ".vocab-rows.txt", encoding: .utf8),
                  let data = FileManager.default.contents(atPath: base + ".pdf"),
                  let extracted = PDFTextExtractor.extract(from: data, rebuildingTables: true) else { continue }
            let actual = Self.rows(VocabListParser.pages(extracted.text))
            let matches = actual == expected.trimmingCharacters(in: .whitespacesAndNewlines)
            if !matches {
                try? actual.write(toFile: base + ".ios.vocab-rows.txt", atomically: true, encoding: .utf8)
            }
            #expect(matches, "\(file)")
        }
    }

    /// The probe's `--rows` format: the pages that switch themselves on, one row per line.
    static func rows(_ pages: [VocabListParser.Page]) -> String {
        pages.filter(\.looksLikeVocab).flatMap { page in
            page.rows.map { row in
                "p\(page.number) | \(row.german) | \(row.english) | \(row.example ?? "-") | \(row.forms ?? "-")"
                    + (row.confident ? "" : " | GUESS")
            }
        }.joined(separator: "\n")
    }
}

/// Kyle's rule for a document deck: a word or phrase with no English to match never becomes a
/// card. `DocumentDeckService.makesCard` is the one gate, and `merge` (every save) goes through it.
@Suite struct DocumentDeckCardRuleTests {
    private func row(_ german: String, _ english: String) -> VocabListRow {
        VocabListRow(german: german, english: english)
    }

    @Test func aCardNeedsEnglishOfItsOwn() {
        #expect(DocumentDeckService.makesCard(row("der Server", "server")))
        #expect(DocumentDeckService.makesCard(row("API / REST-Schnittstelle", "API / REST interface")))
        #expect(DocumentDeckService.makesCard(row("eine Störung beheben", "to fix a fault")))
        // No English, or none of its own.
        #expect(!DocumentDeckService.makesCard(row("die Berufserfahrung", "")))
        #expect(!DocumentDeckService.makesCard(row("die Berufserfahrung", " — ")))
        #expect(!DocumentDeckService.makesCard(row("Git", "?")))
        #expect(!DocumentDeckService.makesCard(row("Python", "Python")))
        #expect(!DocumentDeckService.makesCard(row("SQL", "sql")))
        #expect(!DocumentDeckService.makesCard(row("Windows / Linux", "Windows / Linux")))
        // German on the English side: a note split on "=", or a tutor answering in German.
        #expect(!DocumentDeckService.makesCard(row("Nomen mit Artikel.", "in dieser Lektion ohne Plural.")))
        #expect(!DocumentDeckService.makesCard(row("die Fernwartung", "Wartung über das Netz")))
    }

    @Test func mergeLeavesOutWhatIsNoCard() {
        let cards = DocumentDeckService.merge([
            row("der Server", "server"),
            row("Python", "Python"),
            row("idealerweise", ""),
            row("die Datenbank", "database"),
        ])
        #expect(cards.map(\.germanWord) == ["Server", "Datenbank"])
        #expect(cards.allSatisfy { !$0.englishTranslation.isEmpty })
    }
}
