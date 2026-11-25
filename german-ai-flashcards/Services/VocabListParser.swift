//
//  VocabListParser.swift
//  german-ai-flashcards
//
//  Reads a teacher's vocabulary sheet (a German | English table, as PDFKit or the photo scanner
//  hands it over: one row per line, the columns separated by nothing but a space) into
//  German/English pairs. A row that wraps onto a second line is stitched back together; a ✓ in the
//  sheet's "study for the quiz" column is kept as a mark. Where the columns have no separator the
//  split is found by cues (an article on the left, "to …" on the right, an umlaut, "(pl)") plus
//  Apple's on-device language recognizer, and rows where that was a guess are flagged so the
//  learner checks them.
//
//  A table `OCRTableLayout` rebuilt arrives with its columns tab-joined, and then the sheet can
//  say more than two things per row: a third column is the teacher's example sentence, and a
//  Wortliste's `Deutsch | English | Deutsch | English` double block is two rows on one line. Such
//  a page is read in "table mode", where a line with only one cell is slide prose (a title, a
//  footnote) rather than a German column still waiting for its English.
//
//  Pages are read one at a time, split on the `[Seite N]` markers the extractor writes, so nothing
//  dangling at the foot of one page attaches to the head of the next.
//
//  Pure Foundation + NaturalLanguage, so it can be exercised on a Mac against a real PDF.
//

import Foundation
import NaturalLanguage

/// One German | English row read out of a vocabulary sheet.
nonisolated struct VocabListRow: Identifiable, Hashable {
    var id = UUID()
    var german: String
    var english: String
    /// The sheet marked the row (✓, ✔, ☑, ★).
    var marked: Bool = false
    /// The split between the two columns came from a separator or a strong cue, not a guess.
    var confident: Bool = true
    /// The sheet's example sentence for this row ("Der Computer ist neu."), from a third column.
    var example: String? = nil
    /// A one-line caption for the card ("Plural: die Computer"), from a noun cell that put the
    /// plural on its own line.
    var forms: String? = nil
    /// Which `[Seite N]` the row came from, 1-based; nil for a row the learner added by hand.
    var page: Int? = nil
    /// Nomen, Verb, Adjektiv or Adverb, once something has worked it out (`WordClassInference`).
    /// The parser never sets it: reading a sheet and knowing a word's class are different jobs, and
    /// one of them needs a dictionary. Nil means "nobody knows yet", which shows no tag.
    var wordClass: WordClass? = nil

    /// A row is a card when it has both sides; an example or a plural on its own is not one.
    var isComplete: Bool {
        !german.trimmingCharacters(in: .whitespaces).isEmpty && !english.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// What part of speech a word is.
///
/// `rawValue` is exactly the string `VocabCard.wordType` and `SavedCard.wordType` store, which is
/// what `WordTypeFilter` (`Features/Home/HomeView.swift`), `WiktionaryValidator.evaluate` and
/// `GoetheWordType.normalize` read. Renaming a case silently changes what those screens filter on,
/// so a test pins the four strings.
nonisolated enum WordClass: String, CaseIterable, Identifiable, Codable {
    case noun, verb, adjective, adverb

    var id: String { rawValue }

    /// The label the app shows, in the German the rest of the grammar screens use.
    var german: String {
        switch self {
        case .noun: "Nomen"
        case .verb: "Verb"
        case .adjective: "Adjektiv"
        case .adverb: "Adverb"
        }
    }
}

nonisolated enum VocabListParser {
    struct Result {
        var rows: [VocabListRow]
        /// A title the sheet named itself with ("Vokabelliste für „Hänsel und Gretel“"), if any.
        var title: String?
        var hasMarks: Bool { rows.contains(where: \.marked) }
        var guessedCount: Int { rows.filter { !$0.confident }.count }
        /// How many lines of the source were read as rows, 0…1. A vocabulary sheet scores high;
        /// running prose (a story, a worksheet of questions) scores low and should be picked from
        /// as text instead.
        var listConfidence: Double
        var looksLikeList: Bool { rows.count >= 3 && listConfidence >= 0.5 }
    }

    /// One `[Seite N]` of a sheet, read on its own. The raw counts travel with it so `parse` can
    /// fold them back into one honest "rows per content line" figure rather than averaging.
    struct Page: Identifiable {
        var number: Int
        var rows: [VocabListRow]
        var title: String?
        var contentLines: Int
        var pairedLines: Int
        /// A table that explains German in German under a header like "In der Anzeige | Einfach
        /// erklärt": the left column is the phrase, the right its explanation, kept as the row's
        /// `example`, and the English is the tutor's to fill. See docs/PHRASES.md.
        var isGloss: Bool = false

        var id: Int { number }
        var listConfidence: Double { contentLines == 0 ? 0 : Double(pairedLines) / Double(contentLines) }
        var looksLikeList: Bool { rows.count >= 3 && listConfidence >= 0.5 }
        /// Whether to switch this page on by itself: it reads as a list *and* its right-hand column
        /// reads English. A "So merkst du den Unterschied" slide is German on both sides and reads
        /// as a list just as well, so `looksLikeList` alone would take it.
        /// A page whose every row is a guessed split isn't a table either: a contents page read in
        /// reading order guesses all of its lines. On her sheets no page that switches itself on
        /// has a single guess (Nov 2026).
        var looksLikeVocab: Bool {
            if isGloss { return rows.count >= 3 }
            return looksLikeList
                && rows.contains(where: \.confident)
                && VocabListParser.englishShare(of: rows) >= 0.5
                && VocabListParser.germanShare(of: rows) >= 0.5
        }
        var hasMarks: Bool { rows.contains(where: \.marked) }
        var guessedCount: Int { rows.filter { !$0.confident }.count }
    }

    private static let markCharacters = CharacterSet(charactersIn: "✓✔☑✅★")
    private static let explicitSeparators = ["\t", " – ", " — ", " = ", "=", " - "]
    /// The English column often opens with one of these.
    private static let englishOpeners = ["to ", "the ", "a ", "an ", "old expression", "here:", "colloquial", "coll.", "lit.", "literally", "in the ", "on the ", "at the ", "someone", "something", "sth", "sb"]
    private static let germanArticles: Set<String> = ["der", "die", "das", "ein", "eine", "einen", "einem", "einer", "sich", "den", "dem"]
    /// ", -e" / ", ¨-er" / ", -" at the end of a noun entry: how sheets note the plural.
    static let pluralEndingPattern = #",\s*¨?-\s*¨?[a-zäöüß]{0,3}$"#
    /// "(m)", "(f.)", "n." after a noun.
    static let genderMarkerPattern = #"(\(|\s)[mfn]\.?\)?$"#

    /// The whole sheet: every page's rows, and one `listConfidence` folded from the raw counts
    /// rather than averaged, so it keeps meaning "how many of the source's lines read as rows".
    static func parse(_ text: String) -> Result { fold(pages(text)) }

    /// The same sum, over pages a caller already has. `parse` is `fold(pages(_:))`; a caller holding
    /// the pages (the deck builder) folds them instead of reading the document a second time.
    static func fold(_ parsed: [Page]) -> Result {
        let content = parsed.reduce(0) { $0 + $1.contentLines }
        let paired = parsed.reduce(0) { $0 + $1.pairedLines }
        return Result(
            rows: parsed.flatMap(\.rows),
            title: parsed.compactMap(\.title).first,
            listConfidence: content == 0 ? 0 : Double(paired) / Double(content)
        )
    }

    /// The sheet read page by page, split on the `[Seite N]` markers `PDFTextExtractor` writes, so
    /// a dangling German column, a header or a footer never leaks across a page break. A text with
    /// no markers (a photo, a paste, a handout whose text was cleaned) comes back as one page
    /// numbered 1.
    static func pages(_ text: String) -> [Page] {
        var out: [Page] = []
        var number = 1
        var buffer: [String] = []

        func flush() {
            defer { buffer = [] }
            let body = buffer.joined(separator: "\n")
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            out.append(parse(page: body, number: number))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            if let marker = pageMarker(rawLine.trimmingCharacters(in: .whitespaces)) {
                flush()
                number = marker
            } else {
                buffer.append(rawLine)
            }
        }
        flush()
        return out
    }

    /// `[Seite 8]` → 8.
    private static func pageMarker(_ line: String) -> Int? {
        guard let range = line.range(of: #"^\[Seite \d+\]$"#, options: .regularExpression) else { return nil }
        return Int(line[range].filter(\.isNumber))
    }

    private static func parse(page text: String, number: Int) -> Page {
        let rawLines = text.components(separatedBy: .newlines)
        // A rebuilt table joins its columns with tabs. One stray tab is not a table, three are.
        let tableMode = rawLines.filter { $0.contains("\t") }.count >= 3

        var rows: [VocabListRow] = []
        var title: String?
        var contentLines = 0
        var pairedLines = 0
        /// The page's table explains German in German (`Page.isGloss`); set by its header row.
        var glossMode = false
        var glossRows = 0
        /// A German-only line waiting for the line that carries its English.
        var pendingGerman: String?
        var pendingMarked = false
        /// The last line read was dropped as not a row, so an English line after it is its tail.
        var afterDropped = false

        for rawLine in rawLines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if title == nil, cells(of: line).count <= 1, let found = titleLine(line) {
                title = found
                continue
            }
            // Checked in gloss mode too: a header reached while a gloss table is already running
            // must not come back as a phrase with "Bedeutung im Lerntext" as its sentence. Seen on
            // an iPad (Nov 2026: "Formulierung" between page 17's rows and page 18's), though
            // neither the Mac nor the simulator reads that page that way.
            if tableMode, isGlossHeader(line) {
                glossMode = true
                continue
            }
            if isHeader(line) { continue }
            // A slide's brand strip, e-mail and deck code are neither a header nor content: they
            // must not cost `listConfidence`, and must never become a pending German column.
            if tableMode, isFurniture(line) { continue }

            let marked = line.unicodeScalars.contains { markCharacters.contains($0) }
            line = String(String.UnicodeScalarView(line.unicodeScalars.filter { !markCharacters.contains($0) }))
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                // A mark on a line of its own belongs to the row above.
                if marked, !rows.isEmpty { rows[rows.count - 1].marked = true }
                continue
            }

            if tableMode {
                let cells = self.cells(of: line)
                // One cell means nothing sat beside it. Usually that is slide prose — a title, a
                // subtitle, the footnote under the table — which must not become a row and, above
                // all, must not become a pending German column waiting to glue onto the next row.
                // A real row whose two columns happened to touch is the exception, and it has to
                // earn its way back in on a split the scorer is sure of.
                guard cells.count >= 2 else {
                    // Under a gloss table a one-cell line is its note ("Beispiel: … Windows = Muss."),
                    // and its "=" must not make it a row.
                    if glossMode { continue }
                    let split = splitColumns(line)
                    let recovered = VocabListRow(german: split.german, english: split.english, marked: marked)
                    guard split.kind == .mixed, split.confident, isUsable(recovered),
                          split.german.split(separator: " ").count <= 8 else { continue }
                    contentLines += 1
                    pairedLines += 1
                    rows.append(recovered)
                    continue
                }
                // Under a gloss header a German | German row is a phrase and its explanation. A row
                // whose right side reads English is paired the usual way: "Wort | Bedeutung" can
                // head an ordinary German | English list too.
                if glossMode, cells.count == 2, !cells.contains(where: { $0.contains("___") }),
                   cells[0].split(separator: " ").count <= 8,
                   languageProbability(cells[1], of: .english) < 0.5 {
                    contentLines += 1
                    pairedLines += 1
                    glossRows += 1
                    rows.append(VocabListRow(german: cells[0], english: "", marked: marked, confident: true,
                                             example: cells[1]))
                    continue
                }
                contentLines += 1
                let produced = tableRows(fromCells: cells, marked: marked)
                // Table rows are short; a line of prose that happens to have two cells is not a row.
                if let first = produced.first, first.german.split(separator: " ").count <= 8 { pairedLines += 1 }
                rows.append(contentsOf: produced)
                continue
            }

            let split = splitColumns(line)
            switch split.kind {
            case .mixed:
                contentLines += 1
                let german = [pendingGerman, split.german].compactMap { $0 }.joined(separator: " ")
                let row = VocabListRow(german: german, english: split.english, marked: marked || pendingMarked, confident: split.confident)
                pendingGerman = nil
                pendingMarked = false
                // A contents line ("Übungen 16 Aufgaben  27–42"), a footer, a note split on its
                // "=": read, but not a row, and nothing after it may wrap onto the row before.
                guard isUsable(row) else {
                    afterDropped = true
                    continue
                }
                // Table rows are short; a sentence that happens to split is not a row.
                if split.german.split(separator: " ").count <= 8 { pairedLines += 1 }
                rows.append(row)
                afterDropped = false
            case .germanOnly:
                contentLines += 1
                afterDropped = false
                if marked {
                    // A marked row with no English: complete as far as the sheet goes.
                    let german = [pendingGerman, line].compactMap { $0 }.joined(separator: " ")
                    rows.append(VocabListRow(german: german, english: "", marked: true, confident: false))
                    pendingGerman = nil
                    pendingMarked = false
                } else {
                    pendingGerman = [pendingGerman, line].compactMap { $0 }.joined(separator: " ")
                }
            case .englishOnly:
                contentLines += 1
                if let german = pendingGerman {
                    let row = VocabListRow(german: german, english: line, marked: marked || pendingMarked, confident: false)
                    pendingGerman = nil
                    pendingMarked = false
                    afterDropped = !isUsable(row)
                    if !afterDropped { rows.append(row) }
                } else if afterDropped {
                    // The wrapped tail of a line that wasn't a row.
                    continue
                } else if !rows.isEmpty {
                    // The English column wrapped onto a second line.
                    rows[rows.count - 1].english += " " + line
                    if marked { rows[rows.count - 1].marked = true }
                }
            }
        }
        if let german = pendingGerman {
            rows.append(VocabListRow(german: german, english: "", marked: pendingMarked, confident: false))
        }
        return Page(
            number: number,
            rows: rows.map { tidy($0, page: number) },
            title: title,
            contentLines: contentLines,
            pairedLines: pairedLines,
            isGloss: glossRows >= 3
        )
    }

    /// A header row that announces a German explanation column: "In der Anzeige ⇥ Einfach erklärt",
    /// "Formulierung ⇥ Bedeutung im Lerntext", "Begriff ⇥ Bedeutung im IT-Kontext".
    static func isGlossHeader(_ line: String) -> Bool {
        let parts = cells(of: line)
        guard parts.count == 2, parts[0].split(separator: " ").count <= 4 else { return false }
        let right = parts[1].lowercased()
        return ["einfach erklärt", "erklärung", "auf deutsch", "das heißt"].contains(right)
            || right.hasPrefix("bedeutung")
    }

    /// Whether a page of rebuilt table text explains German in German (`Page.isGloss`), so the
    /// table rebuild keeps it although its right column isn't English.
    static func isGlossTable(_ text: String) -> Bool {
        pages(text).contains(where: \.isGloss)
    }

    // MARK: - Tab-delimited tables

    /// A cell holding nothing but a sheet's plural mark — "-¨er", "-nen", ", -e". A teacher writes
    /// it beside the noun, and the column finder can put the gap between them wide enough to read
    /// as its own column; it is the German cell's tail, never a column of its own.
    private static let markerOnlyPattern = #"^[,\s]*¨?-\s*¨?[a-zäöüß]{0,3}$"#

    /// A line's cells, trimmed, with the empty ones (a blank ✓ column, a padding cell) dropped and
    /// a plural mark folded back onto the cell it belongs to.
    private static func cells(of line: String) -> [String] {
        var out: [String] = []
        for cell in line.components(separatedBy: "\t").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard !cell.isEmpty else { continue }
            if !out.isEmpty, cell.range(of: markerOnlyPattern, options: .regularExpression) != nil {
                out[out.count - 1] += cell.hasPrefix(",") ? cell : " " + cell
            } else {
                out.append(cell)
            }
        }
        return out
    }

    /// A tab-delimited table line read as cells. 2 cells → one pair (what the explicit-separator
    /// path already did); 3 → that pair plus the sheet's example sentence; 4, 6, … → that many
    /// pairs side by side, which is how a Wortliste prints two blocks on one line. Nil when the
    /// line has no tab or only one filled cell.
    static func tabbedRows(in line: String) -> [VocabListRow]? {
        guard line.contains("\t") else { return nil }
        let cells = self.cells(of: line)
        guard cells.count >= 2 else { return nil }
        return tableRows(fromCells: cells, marked: false)
    }

    private static func tableRows(fromCells cells: [String], marked: Bool) -> [VocabListRow] {
        // A line to fill in is an exercise, not a word — every Übung on a worksheet has one.
        guard !cells.contains(where: { $0.contains("___") }) else { return [] }
        return built(fromCells: cells, marked: marked).filter(isUsable)
    }

    /// A card needs a word on each side. A contents table pairing "Üben" with "18–33" has no word
    /// on the right, and a slide titled "Geräte und Zubehör I" splits off a lone "I" that the
    /// recognizer happily reads as English — neither is a row, however well the split scores.
    /// Nor is a line of the slide's own: its footer ("© … All rights reserved"), a title broken
    /// over two cells ("Tätigkeiten in der | IT"), or a note split on its "=" ("Nomen mit Artikel
    /// lernen … | in diesem Lernkontext ohne Plural."), whose "English" is German.
    static func isUsable(_ row: VocabListRow) -> Bool {
        func isWord(_ side: String) -> Bool {
            side.contains(where: \.isLetter) && side.trimmingCharacters(in: .whitespaces).count >= 2
        }
        guard isWord(row.german), isWord(row.english) else { return false }
        if isFurnitureCell(row.german) || isFurnitureCell(row.english) { return false }
        // Two numbered answer columns side by side ("1 Anforderungen | 1 Berlin"), as a key page
        // prints two exercises' solutions: a numbered word is never its own meaning's number.
        if startsWithNumber(row.german), startsWithNumber(row.english) { return false }
        if endsOnPrepositionAndArticle(row.german) { return false }
        return !readsGerman(row.english)
    }

    /// A German column never stops on "in der", "mit dem": that is a title or a sentence cut off
    /// where a cell ended. An article alone at the end can be a pronoun ("Wer ist der"), so only
    /// the pair counts.
    static func endsOnPrepositionAndArticle(_ german: String) -> Bool {
        let tokens = german.lowercased().split(separator: " ").map(String.init)
        guard tokens.count >= 2, articleForms.contains(tokens[tokens.count - 1]) else { return false }
        return prepositions.contains(tokens[tokens.count - 2])
    }

    /// `englishOpeners` without "an ", which opens German too ("an der Wand").
    private static let unambiguousEnglishOpeners = englishOpeners.filter { $0 != "an " }

    private static func startsWithNumber(_ side: String) -> Bool {
        side.range(of: #"^\d+[.)]?\s"#, options: .regularExpression) != nil
    }

    private static let articleForms: Set<String> = ["der", "die", "das", "den", "dem", "des", "ein", "eine",
                                                    "einen", "einem", "einer", "eines"]
    private static let prepositions: Set<String> = ["in", "an", "auf", "mit", "von", "zu", "für", "bei", "aus",
                                                    "nach", "über", "unter", "vor", "hinter", "neben", "zwischen",
                                                    "durch", "gegen", "ohne", "um", "seit", "während", "wegen"]

    /// An "English" side that is German: an umlaut or ß, or three words or more that the
    /// recognizer is sure are German. Fewer words can't decide it: alone, "bonnet" reads 0.94
    /// German and "smell" 0.92. What sits in brackets is left out: "to doubt (ich zweifle an der
    /// Wahrheit – I doubt the truth)" is English with a German example, and reads 1.00 German
    /// whole. So is a gloss that opens like English ("old expression: danach (after that)"). Measured
    /// on 23 PDFs in ~/Downloads (Nov 2026): every real English column, brackets out, stayed under
    /// 0.55; her notes split on "=" read 1.00.
    static func readsGerman(_ english: String) -> Bool {
        let lower = english.lowercased()
        if unambiguousEnglishOpeners.contains(where: { lower.hasPrefix($0) }) { return false }
        let outside = english.replacingOccurrences(of: #"\([^)]*\)?"#, with: " ", options: .regularExpression)
        if outside.unicodeScalars.contains(where: { "äöüßÄÖÜ".unicodeScalars.contains($0) }) { return true }
        let words = outside.split(whereSeparator: { !$0.isLetter }).count
        return words >= 3 && languageProbability(outside, of: .german) >= 0.8
    }

    private static func built(fromCells cells: [String], marked: Bool) -> [VocabListRow] {
        switch cells.count {
        case 0, 1:
            return []
        case 2:
            return [pair(cells[0], cells[1], marked: marked)]
        case 3:
            // Positionally the middle cell is the meaning and the last is the example, but a sheet
            // ordered "Wort | Beispiel | Meaning" reads the other way. Only a clear margin flips
            // it: a lone noun like "computer" reads near 50/50 and must not decide anything.
            let middleEnglish = languageProbability(cells[1], of: .english)
            let lastEnglish = languageProbability(cells[2], of: .english)
            let swapped = lastEnglish > middleEnglish + 0.2
            var row = pair(cells[0], swapped ? cells[2] : cells[1], marked: marked)
            row.example = swapped ? cells[1] : cells[2]
            return [row]
        default:
            let width = blockWidth(cells)
            var out: [VocabListRow] = []
            var index = 0
            // An odd tail (a stray cell at the end of the line) is dropped rather than guessed at.
            while index + width <= cells.count {
                out += built(fromCells: Array(cells[index..<(index + width)]), marked: marked)
                index += width
            }
            return out
        }
    }

    /// How many cells make up one pair on a line of several: two (`Deutsch | English` twice over),
    /// or three when the count allows it and the triples' middles read more English than the
    /// pairs' second cells would.
    private static func blockWidth(_ cells: [String]) -> Int {
        guard cells.count % 3 == 0 else { return 2 }
        guard cells.count % 2 == 0 else { return 3 }
        return englishness(of: cells, every: 3) > englishness(of: cells, every: 2) ? 3 : 2
    }

    /// How English the second cell of each block reads, taken as one text: a column of single
    /// nouns is far steadier to judge together than one word at a time.
    private static func englishness(of cells: [String], every width: Int) -> Double {
        let seconds = stride(from: 1, to: cells.count, by: width).map { cells[$0] }
        guard !seconds.isEmpty else { return 0 }
        return languageProbability(seconds.joined(separator: ". "), of: .english)
    }

    /// One cell against the next, trimmed the way the explicit-separator path trims them — the
    /// trailing ", -" of "der Lehrer, - teacher" is the sheet's "plural unchanged" mark, not part
    /// of the word. A first cell that wrapped onto its plural is split into word and caption.
    private static func pair(_ rawGerman: String, _ rawEnglish: String, marked: Bool) -> VocabListRow {
        let spaced = rawGerman.trimmingCharacters(in: .whitespaces)
        let trimmed = spaced.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        var german = trimmed.isEmpty ? spaced : trimmed
        var forms: String?
        if let plural = VocabForms.pluralPair(german) {
            german = plural.singular
            forms = "Plural: \(plural.plural)"
        }
        return VocabListRow(
            german: german,
            english: rawEnglish.trimmingCharacters(in: .whitespaces),
            marked: marked,
            forms: forms
        )
    }

    // MARK: - Lines

    private static func titleLine(_ line: String) -> String? {
        let lower = line.lowercased()
        for prefix in ["vokabelliste", "wortliste", "vokabeln", "vocabulary", "wortschatz"] where lower.hasPrefix(prefix) {
            return line
        }
        return nil
    }

    /// A table's header row. On a tab-joined line every cell has to be a header word, so a content
    /// row like "das Wort⇥word" survives while "Wort und Plural⇥Meaning⇥Beispiel" does not.
    private static func isHeader(_ line: String) -> Bool {
        let cells = self.cells(of: line)
        if cells.count > 1 { return cells.allSatisfy(isHeaderCell) }
        return isHeaderCell(line)
    }

    private static func isHeaderCell(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
        let headers: Set<String> = ["deutsch", "englisch", "english", "german", "quiz", "study for", "study for quiz", "deutsch english", "deutsch englisch", "german english", "deutsch english study for", "deutsch englisch study for", "wort", "bedeutung", "word", "meaning", "wort und plural", "wörter", "beispiel", "beispielsatz", "situation", "so merkst du den unterschied", "du lernst"]
        if headers.contains(lower) { return true }
        if lower.hasPrefix("name:") { return true }
        if lower.range(of: #"^(deutsch|german)\s+(english|englisch)\b"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^(seite|page)\s+\d+$"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// A slide's furniture: the brand strip, the e-mail, the copyright line, the deck code. One
    /// such cell condemns the line — a footer row's other cells ("Shohdy German Way", "Learn.
    /// Practice. Succeed.") are ordinary words and match nothing by themselves.
    private static func isFurniture(_ line: String) -> Bool {
        cells(of: line).contains(where: isFurnitureCell)
    }

    private static func isFurnitureCell(_ cell: String) -> Bool {
        let lower = cell.lowercased()
        if cell.contains("©") || lower.contains("all rights reserved") || lower.contains("alle rechte vorbehalten") {
            return true
        }
        if cell.range(of: #"^\S+@\S+\.\S+$"#, options: .regularExpression) != nil { return true }
        // A deck or version code: one long unspaced run with digits in it and no German letter.
        if !cell.contains(" "), cell.count >= 12, cell.filter(\.isNumber).count >= 2,
           cell.rangeOfCharacter(from: CharacterSet(charactersIn: "äöüßÄÖÜ")) == nil {
            return true
        }
        return false
    }

    // MARK: - Columns

    private enum LineKind { case mixed, germanOnly, englishOnly }

    private struct Split {
        var kind: LineKind
        var german: String = ""
        var english: String = ""
        var confident: Bool = true
    }

    private static func splitColumns(_ line: String) -> Split {
        // 1. An explicit separator settles it.
        for separator in explicitSeparators {
            if let range = line.range(of: separator) {
                // "der Lehrer, - teacher": the dash is the sheet's "plural unchanged" mark, not a
                // separator, so the comma it leaves behind goes too.
                let left = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                let right = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !left.isEmpty, !right.isEmpty { return Split(kind: .mixed, german: left, english: right) }
            }
        }
        if let range = line.range(of: #"\S\s{2,}\S"#, options: .regularExpression) {
            let gap = line[range].firstIndex(where: \.isWhitespace) ?? range.lowerBound
            let left = String(line[..<gap]).trimmingCharacters(in: .whitespaces)
            let right = String(line[gap...]).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty, !right.isEmpty { return Split(kind: .mixed, german: left, english: right) }
        }

        // 2. Two quoted segments: an idiom and its rendering.
        let quotes = quotedSegments(in: line)
        if quotes.count >= 2 {
            let german = quotes[0].text
            let english = String(line[quotes[0].range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !english.isEmpty { return Split(kind: .mixed, german: german, english: english) }
        }

        // 3. Score every split point between words.
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2 else {
            return Split(kind: looksEnglish(line) ? .englishOnly : .germanOnly, confident: false)
        }
        var best = (index: tokens.count, score: -Double.infinity, strong: false)
        var second = -Double.infinity
        for index in 0...tokens.count {
            let left = tokens[..<index].joined(separator: " ")
            let right = tokens[index...].joined(separator: " ")
            let (score, strong) = splitScore(left: left, right: right)
            if score > best.score {
                second = best.score
                best = (index, score, strong)
            } else if score > second {
                second = score
            }
        }
        let margin = best.score - second
        let confident = best.strong || margin > 0.45
        switch best.index {
        case 0: return Split(kind: .englishOnly, confident: confident)
        case tokens.count: return Split(kind: .germanOnly, confident: confident)
        default:
            return Split(
                kind: .mixed,
                german: tokens[..<best.index].joined(separator: " "),
                english: tokens[best.index...].joined(separator: " "),
                confident: confident
            )
        }
    }

    /// How plausible "left is German, right is English" is, and whether a strong cue decided it.
    private static func splitScore(left: String, right: String) -> (Double, Bool) {
        var score = 0.0
        var strong = false
        let leftGerman = left.isEmpty ? 0.5 : languageProbability(left, of: .german)
        score += leftGerman
        if !right.isEmpty { score += languageProbability(right, of: .english) } else { score += 0.5 }

        let rightLower = right.lowercased()
        let leftLower = left.lowercased()
        let leftTokens = leftLower.split(separator: " ").map(String.init)
        let leftFirst = leftTokens.first ?? ""
        let leftHasArticle = germanArticles.contains(leftFirst)
        let leftHasUmlaut = left.unicodeScalars.contains { "äöüßÄÖÜ".unicodeScalars.contains($0) }
        // "das" alone is never the German column, whatever the recognizer makes of the rest
        // ("das Gift, -e poison": "Gift" reads as English, but the noun belongs on the left).
        if !left.isEmpty, leftTokens.allSatisfy({ germanArticles.contains($0) }) { score -= 2.5 }
        // A noun's plural ending ("das Gift, -e", "der Apfel, ¨-", "die Lehrerin, -nen") or a
        // gender marker closes the German column; a gloss never opens with either.
        if leftLower.range(of: pluralEndingPattern, options: .regularExpression) != nil
            || leftLower.range(of: genderMarkerPattern, options: .regularExpression) != nil {
            score += 1.0; strong = true
        }
        if rightLower.range(of: #"^[¨\-]"#, options: .regularExpression) != nil
            || rightLower.range(of: #"^\(?[mfn]\.?\)?(\s|$)"#, options: .regularExpression) != nil {
            score -= 1.5
        }
        // A column split needs a German-looking left side; an English line that happens to contain
        // "to …" mid-way (a wrapped gloss) is not two columns.
        let leftPlausible = left.isEmpty || leftHasArticle || leftHasUmlaut || leftGerman >= 0.3
        if !right.isEmpty, !left.isEmpty, !leftPlausible { score -= 1.2 }
        if !right.isEmpty {
            if leftPlausible, englishOpeners.contains(where: { rightLower.hasPrefix($0) }) { score += 0.9; strong = true }
            if rightLower.hasPrefix("“") || rightLower.hasPrefix("\"") { score += 0.4 }
            // A gloss never opens with a bare conjunction or "of": that word belongs to the left.
            for opener in ["of ", "and ", "or ", "und ", "oder "] where rightLower.hasPrefix(opener) { score -= 0.8 }
        }
        if !left.isEmpty {
            if leftHasArticle { score += 0.35 }
            if leftLower.hasSuffix("(pl)") || leftLower.hasSuffix("(pl.)") { score += 0.9; strong = true }
            if leftHasUmlaut { score += 0.3 }
            // A German column tends to end on a word; an English column rarely starts mid-form ("/ hat").
            if leftLower.hasSuffix("/") { score -= 0.6 }
        }
        // Umlauts on the supposedly English side count against the split.
        if right.unicodeScalars.contains(where: { "äöüßÄÖÜ".unicodeScalars.contains($0) }) { score -= 0.8 }
        // English rarely holds a German article.
        for token in rightLower.split(separator: " ").prefix(3) where germanArticles.contains(String(token)) { score -= 0.5 }
        return (score, strong)
    }

    static func looksEnglish(_ text: String) -> Bool {
        languageProbability(text, of: .english) > languageProbability(text, of: .german)
    }

    /// How German the left-hand column reads, 0…1. A page of English prompts answered in English
    /// ("Wie heißt das auf Deutsch?" with blanks) passes `englishShare` on the right, and has to be
    /// turned away on the left.
    static func germanShare(of rows: [VocabListRow]) -> Double {
        let complete = rows.filter(\.isComplete)
        guard !complete.isEmpty else { return 0 }
        let perRow = Double(complete.filter { !looksEnglish($0.german) }.count) / Double(complete.count)
        let column = languageProbability(complete.map(\.german).joined(separator: ". "), of: .german)
        return max(perRow, column)
    }

    /// How English the right-hand column reads, 0…1 — the test that tells a German | English table
    /// from a German | German one (a "So merkst du den Unterschied" slide reads as a list just as
    /// well). The per-row vote, backed by the column read as one text: single nouns like
    /// "computer" or "laptop" read near 50/50 on their own, a whole column of them does not. The
    /// larger of the two wins, so a sheet that already passed on the per-row vote cannot start
    /// failing.
    static func englishShare(of rows: [VocabListRow]) -> Double {
        let complete = rows.filter(\.isComplete)
        guard !complete.isEmpty else { return 0 }
        let perRow = Double(complete.filter { looksEnglish($0.english) }.count) / Double(complete.count)
        let column = languageProbability(complete.map(\.english).joined(separator: ". "), of: .english)
        return max(perRow, column)
    }

    private static func languageProbability(_ text: String, of language: NLLanguage) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        if hypotheses.isEmpty { return 0.5 }
        return hypotheses[language] ?? 0
    }

    private static func quotedSegments(in line: String) -> [(text: String, range: Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        var openIndex: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if "“„\"".contains(character), openIndex == nil {
                openIndex = index
            } else if "”“\"".contains(character), let open = openIndex, index > open {
                let inner = String(line[line.index(after: open)..<index])
                result.append((inner, open..<line.index(after: index)))
                openIndex = nil
            }
            index = line.index(after: index)
        }
        return result
    }

    private static func tidy(_ row: VocabListRow, page: Int) -> VocabListRow {
        var row = row
        row.german = row.german.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            // A scan reads the plural's umlaut mark "-¨e" as `-"e` or `-*e`.
            .replacingOccurrences(of: #",\s*-?\s*["*”“]\s*([a-zäöüß]{0,3})$"#, with: ", -¨$1", options: .regularExpression)
        row.english = row.english.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        row.example = collapsed(row.example)
        row.forms = collapsed(row.forms)
        // "binden / band / hat gebunden" is the card "binden" with its forms as the caption, the
        // way a wrapped plural already is; whole, it read as a six-word phrase. See docs/PHRASES.md.
        if row.forms == nil, let listed = CardKind.listedForms(row.german) {
            row.german = listed.headword
            row.forms = listed.forms
        }
        row.page = page
        return row
    }

    private static func collapsed(_ text: String?) -> String? {
        guard let cleaned = text?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces), !cleaned.isEmpty else { return nil }
        return cleaned
    }
}

/// The forms a teacher lists in one entry, split out so each can be found in a text:
/// "der Kieselstein/ die Kieselsteine (pl)" → ["der Kieselstein", "die Kieselsteine"];
/// "anzünden/ zündete…an/ hat angezündet" → ["anzünden", "zündete", "angezündet"].
nonisolated enum VocabForms {
    static func split(_ german: String) -> [String] {
        var out: [String] = []
        var remaining = german
        // "das Gift, -e" → the singular and the plural it spells out ("Gifte"); "¨" marks an umlaut.
        if let ending = remaining.range(of: VocabListParser.pluralEndingPattern, options: .regularExpression) {
            let singular = String(remaining[..<ending.lowerBound]).trimmingCharacters(in: .whitespaces)
            let suffix = String(remaining[ending]).lowercased()
            remaining = singular
            let cleanSingular = singular.replacingOccurrences(of: VocabListParser.genderMarkerPattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if let noun = cleanSingular.split(separator: " ").last.map(String.init), noun.count >= 2 {
                var plural = suffix.contains("¨") ? umlauted(noun) : noun
                plural += suffix.filter { $0.isLetter }
                if plural.lowercased() != noun.lowercased() { out.append(plural) }
            }
        }
        for part in remaining.components(separatedBy: CharacterSet(charactersIn: "/,;")) {
            for alternative in part.components(separatedBy: "->") {
                var form = alternative
                    .replacingOccurrences(of: #"\((pl|pl\.|sg|Pl\.)\)"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\s*(hat|ist|haben|sind)\s+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                // A separable verb written "zündete…an": the finite part is what a text shows.
                if let dots = form.range(of: #"[…\.]{1,3}"#, options: .regularExpression),
                   form.distance(from: form.startIndex, to: dots.lowerBound) > 2 {
                    form = String(form[..<dots.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                form = form.replacingOccurrences(of: VocabListParser.genderMarkerPattern, with: "", options: .regularExpression)
                form = form.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
                if form.count >= 2 { out.append(form) }
            }
        }
        return out.isEmpty ? [german] : out
    }

    /// "der Computer die Computer" → ("der Computer", "die Computer"): a first cell that wrapped,
    /// with the plural on its own line. Deliberately narrow — exactly article + word twice, and no
    /// slash anywhere — so a teacher's own "der Kieselstein/ die Kieselsteine (pl)" is left whole
    /// for `split` to take apart.
    static func pluralPair(_ cell: String) -> (singular: String, plural: String)? {
        guard !cell.contains("/") else { return nil }
        let tokens = cell.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count == 4 else { return nil }
        let articles: Set<String> = ["der", "die", "das"]
        guard articles.contains(tokens[0].lowercased()), articles.contains(tokens[2].lowercased()),
              isPlural(tokens[3], of: tokens[1]) else { return nil }
        return ("\(tokens[0]) \(tokens[1])", "\(tokens[2]) \(tokens[3])")
    }

    /// Whether one word is plausibly the other's plural: German builds it by adding to the stem,
    /// sometimes umlauting it, so the singular is a prefix of the plural once both are written
    /// without umlauts ("Maus" → "Mäuse" → "mause"). Two unrelated nouns are not a pair.
    private static func isPlural(_ plural: String, of singular: String) -> Bool {
        guard singular.count >= 2 else { return false }
        if plural.lowercased().hasPrefix(singular.lowercased()) { return true }
        if plainVowels(plural).hasPrefix(plainVowels(singular)) { return true }
        // A borrowed ending swapped for -en: Konto → Konten, Museum → Museen, Thema → Themen,
        // Virus → Viren.
        let lower = singular.lowercased(), pluralLower = plural.lowercased()
        for ending in ["um", "us", "a", "o"] where lower.hasSuffix(ending) {
            let stem = String(lower.dropLast(ending.count))
            if stem.count >= 3, pluralLower.hasSuffix("en"), pluralLower.hasPrefix(stem) { return true }
        }
        return false
    }

    private static func plainVowels(_ word: String) -> String {
        var out = ""
        for character in word.lowercased() {
            switch character {
            case "ä": out.append("a")
            case "ö": out.append("o")
            case "ü": out.append("u")
            default: out.append(character)
            }
        }
        return out
    }

    /// The umlaut a plural marks: the last a/o/u of the stem, "Apfel" → "Äpfel", "Haus" → "Häus"
    /// (an "au" becomes "äu"), "Tochter" → "Töchter".
    static func umlauted(_ noun: String) -> String {
        var chars = Array(noun)
        guard let index = chars.lastIndex(where: { "aouAOU".contains($0) }) else { return noun }
        let map: [Character: Character] = ["a": "ä", "o": "ö", "u": "ü", "A": "Ä", "O": "Ö", "U": "Ü"]
        if "uU".contains(chars[index]), index > 0, "aA".contains(chars[index - 1]) {
            chars[index - 1] = chars[index - 1] == "A" ? "Ä" : "ä"
            return String(chars)
        }
        if let replacement = map[chars[index]] { chars[index] = replacement }
        return String(chars)
    }
}
