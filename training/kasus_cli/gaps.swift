//
//  gaps.swift
//  kasus-cli
//
//  The gap-choice commands: today `audit-gaps`, which gates the bundled pack (or a file in the
//  same format) item by item, checks the pack's composition and, with `--golden`, prints the
//  `GapChoiceFixtures.golden` rows to paste. The batch commands (gap-plans, gap-check,
//  gap-export) join it with the planner.
//

import Foundation

func auditGaps(_ args: [String] = []) {
    let url = args.first(where: { !$0.hasPrefix("--") }).map { URL(fileURLWithPath: $0) }
        ?? Bundle.main.url(forResource: "gap_choice_items", withExtension: "json")
    guard let url, let data = try? Data(contentsOf: url),
          let bank = try? GapChoiceBank(data: data) else { fail("\(url?.lastPathComponent ?? "gap_choice_items.json") is missing or doesn't decode") }
    let lexicon = AppKasusLexicon()
    if args.contains("--golden") { printGapGolden(bank: bank) }
    var failed = 0
    for item in bank.items {
        let result = GapChoiceCheck.run(item, lexicon: lexicon)
        if !result.passes {
            failed += 1
            print("FAIL \(item.id): \(result.errors.joined(separator: " | "))")
        }
        for warning in result.warnings { warn("  warning \(item.id): \(warning)") }
    }
    let composition = GapChoiceCheck.composition(bank.items)
    for problem in composition { print("FAIL composition: \(problem.code.rawValue) \(problem.detail)") }
    print("audit-gaps: \(bank.items.count - failed)/\(bank.items.count) pass · composition \(composition.isEmpty ? "OK" : "\(composition.count) problem(s)")")
    if failed > 0 || !composition.isEmpty { exit(1) }
}

/// The `GapChoiceFixtures.golden` table for a bank, counted the way its verifier counts, ready to
/// paste: `kasus-cli audit-gaps [file] --golden`.
func printGapGolden(bank: GapChoiceBank) {
    let packs = Dictionary(grouping: bank.items) { "\($0.topic)/\($0.focus.rawValue)" }
    for key in packs.keys.sorted() {
        let items = packs[key] ?? []
        let akk = items.filter { $0.kasus == .akkusativ }.count
        let dat = items.filter { $0.kasus == .dativ }.count
        let inline = items.filter { $0.presentation == .inline }.count
        print("        \"\(key)\": Golden(items: \(items.count), akk: \(akk), dat: \(dat), inline: \(inline)),")
    }
}
