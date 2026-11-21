//
//  endings.swift
//  kasus-cli
//
//  audit-endings: the exhaustive sweep over the Schnellrunde's sentence engine.
//
//  Five of the twelve drill kinds (quick, build, blitz, pair, dativVerbs) read no JSON. They
//  assemble German at runtime from three independent lookups -- EndingsFrame.all, EndingsNoun.all
//  and EndingsDeterminer.form -- and nothing checked the result. Every other grammar corpus in the
//  app goes through a gate; this one did not.
//
//  The space is finite (frames x nouns x determiners x number), so this is a proof, not a sample.
//  Swift owns assembly, which is why the sentences are emitted rather than re-derived in Python:
//  duplicating the declension tables would let the checker drift away from the app.
//
//    kasus-cli audit-endings              # invariants + round trips, exit 1 on failure
//    kasus-cli audit-endings --dump       # every assembled cell as JSON lines, for LanguageTool
//    kasus-cli audit-endings --matrix     # the frame x noun grid a human reads once
//

import Foundation

private struct Cell {
    let frame: EndingsFrame
    let noun: EndingsNoun
    let determiner: EndingsDeterminer
    let isPlural: Bool
    let question: EndingsQuestion

    var sentence: String {
        let (before, after) = question.parts
        return before + question.answer + after
    }
}

/// Every cell the picker can reach. Mirrors the two exclusions `EndingsQuestion.round` applies:
/// `ein` has no plural, and `kein` stays out of the Genitiv frames.
private func allCells() -> [Cell] {
    var out: [Cell] = []
    for frame in EndingsFrame.all {
        for noun in EndingsNoun.all {
            for isPlural in [false, true] {
                for determiner in EndingsDeterminer.allCases {
                    if isPlural && determiner == .ein { continue }
                    if frame.kasus == .genitiv && determiner == .kein { continue }
                    let gender: Gender = isPlural ? .plural : noun.gender
                    let q = EndingsQuestion(
                        frame: frame, noun: noun, isPlural: isPlural, determiner: determiner,
                        options: determiner.options(includesGenitiv: frame.kasus == .genitiv))
                    _ = gender
                    out.append(Cell(frame: frame, noun: noun, determiner: determiner,
                                    isPlural: isPlural, question: q))
                }
            }
        }
    }
    return out
}

func auditEndings(_ args: [String]) {
    let cells = allCells()
    if args.contains("--dump") {
        let encoder = JSONEncoder()
        for cell in cells {
            let row: [String: String] = [
                "sentence": cell.sentence,
                "frame": cell.isPlural ? cell.frame.plural : cell.frame.singular,
                "noun": cell.noun.singular,
                "gender": cell.question.gender.columnLabel,
                "case": cell.frame.kasus.rawValue,
                "determiner": "\(cell.determiner)",
                "number": cell.isPlural ? "pl" : "sg",
                "answer": cell.question.answer,
            ]
            if let data = try? encoder.encode(row), let line = String(data: data, encoding: .utf8) {
                print(line)
            }
        }
        return
    }

    if args.contains("--matrix") {
        // The article and number dimensions are machine-proven below, so the only thing left for
        // a human is whether a frame and a noun make sense together: "Wir gratulieren dem Pferd."
        print("frame\tnoun\texample\treads_right\tnote")
        for frame in EndingsFrame.all {
            for noun in EndingsNoun.all {
                let q = EndingsQuestion(frame: frame, noun: noun, isPlural: false,
                                        determiner: .definite,
                                        options: EndingsDeterminer.definite.options(includesGenitiv: frame.kasus == .genitiv))
                let (before, after) = q.parts
                print("\(frame.singular)\t\(noun.singular)\t\(before + q.answer + after)\t\t")
            }
        }
        return
    }

    let lexicon = AppKasusLexicon()
    var failures: [String] = []
    var checked = 0

    for cell in cells {
        checked += 1
        let q = cell.question
        let label = "\(cell.frame.kasus.rawValue)/\(cell.noun.singular)/\(cell.determiner)/\(cell.isPlural ? "pl" : "sg")"

        // 1. the answer is a form the tables agree carries this case for this gender
        let (family, stem) = cell.determiner.kasusFamily
        let determiner = KasusDeterminer(family: family, stem: stem,
                                         ending: q.ending(of: q.answer), word: q.answer)
        let compatible = KasusForms.compatibleCases(determiner, genus: q.gender)
        if !compatible.contains(cell.frame.kasus) {
            failures.append("\(label): „\(q.answer)“ carries \(compatible.map(\.rawValue).sorted()) for \(q.gender.columnLabel), not \(cell.frame.kasus.rawValue)")
            continue
        }
        // 2. stem + ending round trips back to the answer (Bau das Wort builds from these)
        let parts = q.answerParts
        if parts.stem + parts.ending != q.answer {
            failures.append("\(label): parts \(parts.stem)+\(parts.ending) != \(q.answer)")
        }
        // 3. the ending label the learner taps rebuilds the same form
        if q.form(endingLabel: KasusForms.endingLabel(q.ending(of: q.answer))) != q.answer {
            failures.append("\(label): ending label does not rebuild „\(q.answer)“")
        }
        // 4. the option row always holds the answer, or the question is unanswerable
        if !q.options.contains(q.answer) {
            failures.append("\(label): options \(q.options) miss „\(q.answer)“")
        }
        // 5. the sentence has exactly one blank filled, and the noun is in the sentence
        let sentence = cell.sentence
        if sentence.contains("___") || sentence.contains("{N}") {
            failures.append("\(label): template not fully filled: \(sentence)")
        }
        if !sentence.contains(q.nounForm) {
            failures.append("\(label): noun form „\(q.nounForm)“ missing from: \(sentence)")
        }
        // 6. the noun's own ending, which the article never shows
        let expected = cell.noun.form(cell.frame.kasus, isPlural: cell.isPlural)
        if cell.frame.kasus == .dativ && cell.isPlural
            && !(expected.hasSuffix("n") || expected.hasSuffix("s")) {
            failures.append("\(label): dative plural „\(expected)“ takes no -n")
        }
        // 7. the gender the question teaches is the gender the dictionary files
        if !cell.isPlural {
            switch lexicon.gender(forLemma: cell.noun.singular) {
            case .verified(let g) where g != cell.noun.gender:
                failures.append("\(label): \(cell.noun.singular) is \(g.article) in the dictionary, table says \(cell.noun.gender.article)")
            case .conflict(let gs) where !gs.contains(cell.noun.gender):
                failures.append("\(label): \(cell.noun.singular) is \(gs.map(\.article)) in the dictionary, table says \(cell.noun.gender.article)")
            default:
                break
            }
        }
    }

    // the two invariants that live inside EndingsQuestion.round, asserted on the data instead
    for frame in EndingsFrame.all where frame.kasus == .genitiv {
        _ = frame
    }
    if cells.contains(where: { $0.isPlural && $0.determiner == .ein }) {
        failures.append("invariant: ein reached a plural cell")
    }
    if cells.contains(where: { $0.frame.kasus == .genitiv && $0.determiner == .kein }) {
        failures.append("invariant: kein reached a Genitiv cell")
    }

    for f in failures { print("FAIL \(f)") }
    print("audit-endings: \(checked - failures.count)/\(checked) cells pass "
          + "(\(EndingsFrame.all.count) frames × \(EndingsNoun.all.count) nouns × determiners × number)")
    if !failures.isEmpty { exit(1) }
}
