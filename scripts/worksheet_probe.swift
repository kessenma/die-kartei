//
//  worksheet_probe.swift
//
//  Runs the real worksheet parser (Services/Worksheet) over a PDF and prints how each page read:
//  its verdict, title, instruction, where its options come from, and every item with its gaps,
//  choices and flags. Compiled by scripts/worksheet_probe.sh, which is the way to run it:
//
//    scripts/worksheet_probe.sh ~/Downloads/<sheet>.pdf            every page, one block each
//    scripts/worksheet_probe.sh ~/Downloads/<sheet>.pdf --page 21  one page, with its raw lines
//    scripts/worksheet_probe.sh ~/Downloads/<sheet>.pdf --rects    plus where each gap sits
//    scripts/worksheet_probe.sh ~/Downloads/<sheet>.pdf --signature  a diffable summary
//    scripts/worksheet_probe.sh ~/Downloads/<sheet>.pdf --key      the Lösungen pages as the key
//    scripts/worksheet_probe.sh ~/Downloads/<sheet>.pdf --phrases  phrase cards from the key
//    scripts/worksheet_probe.sh ~/Downloads/<sheet>.pdf --key-signature  the key, diffable
//      (save it as <sheet>.key.txt beside the PDF in WORKSHEET_FIXTURE_DIR for the iOS test)
//
//  Runs on macOS PDFKit. iOS can order a page's text differently; the parser sorts by position to
//  make that moot, and WorksheetParserTests compares the iOS reading against this signature when
//  WORKSHEET_FIXTURE_DIR is set. Never commit a teacher's PDF: point this at ~/Downloads.
//

import Foundation
import PDFKit

let args = CommandLine.arguments.dropFirst()
guard let path = args.first(where: { !$0.hasPrefix("--") && Int($0) == nil }) else {
    print("usage: worksheet_probe.sh <file.pdf> [--page N] [--rects] [--signature] [--key] [--phrases] [--key-signature]")
    exit(2)
}
let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
guard let document = PDFDocument(url: url) else { print("can't open \(path)"); exit(1) }

var onlyPage: Int?
if let flag = args.firstIndex(of: "--page"), args.index(after: flag) < args.endIndex {
    onlyPage = Int(args[args.index(after: flag)])
}
let showRects = args.contains("--rects")
let signatureOnly = args.contains("--signature")

let exercises = WorksheetPDFReader.parse(document)

func describe(_ options: WorksheetOptions?) -> String {
    switch options {
    case .none: return "–"
    case .closedSet(let words)?: return "closed[\(words.joined(separator: ","))]"
    case .articles(let words)?: return "articles[\(words.joined(separator: ","))]"
    case .wordBank(let words, let once)?: return "bank\(once ? "·once" : "")[\(words.joined(separator: ","))]"
    case .letters(let options)?: return "letters[\(options.map { "\($0.letter)=\($0.text)" }.joined(separator: ","))]"
    }
}

func render(_ item: WorksheetItem) -> String {
    item.segments.map { segment -> String in
        switch segment {
        case .text(let text, _): return text
        case .gap(let gap): return gap.isLong ? "[____]" : "[__]"
        case .choice(let choice): return "{" + choice.options.map(\.text).joined(separator: "|") + "}"
        case .lineBreak: return " ⏎ "
        }
    }.joined()
}

if args.contains("--phrases") {
    // The phrase cards `KeyPhraseExtractor` offers from the exercises filled with her key.
    let reading = WorksheetKeyReader.read(pages: WorksheetPDFReader.pageTexts(of: document), exercises: exercises)
    let phrases = KeyPhraseExtractor.phrases(from: exercises, key: reading.key, samples: reading.samples)
    for phrase in phrases {
        let english = phrase.english.map { " = \($0)" } ?? ""
        print("p\(phrase.page)\(phrase.isSentence ? " [sentence]" : "") \(phrase.german)\(english)")
    }
    print("\n\(phrases.count) phrases")
    exit(0)
}

if args.contains("--key-signature") {
    let reading = WorksheetKeyReader.read(pages: WorksheetPDFReader.pageTexts(of: document), exercises: exercises)
    print(WorksheetKeyReader.signature(reading))
    exit(0)
}

if args.contains("--key") {
    // What `WorksheetKeyReader` makes of the teacher's Lösungen pages: per exercise how many of
    // its answers found a blank, every key → answer, and what found no place.
    let reading = WorksheetKeyReader.read(pages: WorksheetPDFReader.pageTexts(of: document), exercises: exercises)
    let byPage = Dictionary(exercises.map { ($0.page, $0) }, uniquingKeysWith: { first, _ in first })
    for found in reading.exercises {
        let page = found.page.map { "p\($0)" } ?? "no page"
        print("Übung \(found.number) → \(page) · \(found.placed)/\(found.answers) placed\(found.isSample ? " · samples" : "")")
        guard let number = found.page, let exercise = byPage[number] else { continue }
        for key in exercise.answerKeys {
            if let answer = reading.key[key] { print("    \(key) = \(answer)") }
            if let sample = reading.samples[key] { print("    \(key) ≈ \(sample)") }
        }
    }
    if !reading.unmatched.isEmpty {
        print("\nunmatched (\(reading.unmatched.count)):")
        for line in reading.unmatched { print("  \(line)") }
    }
    print("\n\(reading.key.count) key answers · \(reading.samples.count) samples · \(reading.exercises.count) exercises")
    exit(0)
}

if signatureOnly {
    for exercise in exercises where exercise.isExercise {
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
        print("p\(exercise.page) \(exercise.verdict.rawValue)\(exercise.hasTypedAnswers ? " typed" : "") | " + parts.joined(separator: " || "))
    }
    exit(0)
}

for exercise in exercises {
    if let onlyPage, exercise.page != onlyPage { continue }
    if onlyPage == nil, !exercise.isExercise {
        print("p\(exercise.page)  –  \(exercise.title)")
        continue
    }
    print("\n=== p\(exercise.page)  \(exercise.verdict.rawValue.uppercased())  \(exercise.displayTitle)")
    if let subtitle = exercise.subtitle { print("    subtitle: \(subtitle)") }
    if let instruction = exercise.instruction { print("    instruction: \(instruction)") }
    if exercise.hasTypedAnswers { print("    ⚠︎ already has typed answers") }
    if !exercise.nouns.isEmpty { print("    nouns: \(exercise.nouns.joined(separator: ", "))") }
    if let ref = exercise.answerKeyRef { print("    answers on: \(ref)") }
    let page = document.page(at: exercise.page - 1)!
    let geometry = WorksheetPDFReader.geometry(of: exercise, on: page)
    for section in exercise.sections {
        print("  [\(section.key)] \(section.heading ?? "") options: \(describe(section.options))")
        for item in section.items {
            var flags: [String] = []
            if item.writeBelow { flags.append("write-below") }
            if let marks = item.marks { flags.append("marks:\(marks.rawValue)") }
            if item.caseTag { flags.append("case") }
            if let hint = item.hint { flags.append("hint:\(hint)") }
            if let chunks = item.chunks { flags.append("chunks:\(chunks.count)") }
            if item.isContext { flags.append("context") }
            print("    \(item.label ?? "·") \(render(item))" + (flags.isEmpty ? "" : "   ‹\(flags.joined(separator: " "))›"))
            if showRects {
                for gap in item.gaps {
                    let rect = geometry.gaps[gap.key].map { String(format: "%.0f,%.0f %.0f×%.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? "UNPLACED"
                    print("        \(gap.key)  \(rect)")
                }
            }
        }
    }
    if !geometry.unplaced.isEmpty { print("    unplaced: \(geometry.unplaced.joined(separator: ", "))") }
    if !exercise.notes.isEmpty { print("    notes: \(exercise.notes.joined(separator: " / "))") }
    if onlyPage != nil {
        print("  raw lines:")
        for line in WorksheetPDFReader.lines(on: page) {
            print(String(format: "    %5.0f %5.0f %4.0f  ", line.box.minX, line.box.minY, line.box.height) + line.text)
        }
    }
}
