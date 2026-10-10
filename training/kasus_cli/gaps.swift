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

// MARK: - The batch

/// Items from a file or stdin: JSON lines (one item each), or a `{version, items}` file.
func readGapItems(_ args: [String]) -> [GapChoiceItem] {
    let path = args.first { !$0.hasPrefix("--") }
    let data: Data
    if let path {
        guard let read = try? Data(contentsOf: URL(fileURLWithPath: path)) else { fail("can't read \(path)") }
        data = read
    } else {
        data = FileHandle.standardInput.readDataToEndOfFile()
    }
    if let file = try? JSONDecoder().decode(GapChoiceFile.self, from: data) { return file.items }
    var items: [GapChoiceItem] = []
    var malformed = 0
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        if let item = try? JSONDecoder().decode(GapChoiceItem.self, from: Data(line.utf8)) { items.append(item) } else { malformed += 1 }
    }
    if malformed > 0 { warn("⚠️ \(malformed) malformed line(s) skipped") }
    return items
}

func gapOption(_ args: [String], _ name: String) -> String? {
    guard let at = args.firstIndex(of: name), args.indices.contains(at + 1) else { return nil }
    return args[at + 1]
}

/// `gap-plans <case|person|all> [--count N] [--seed S] [--prefix p]`: the planner's pack as JSON
/// lines, in item format, never a sentence the bundle already has.
func gapPlans(_ args: [String]) {
    let which = args.first { !$0.hasPrefix("--") } ?? "all"
    let focuses: [GapChoiceFocus] = switch which {
    case "case":   [.case]
    case "person": [.person]
    case "all":    [.case, .person]
    default:       fail("gap-plans: want case, person or all, not \(which)")
    }
    let count = Int(gapOption(args, "--count") ?? "120") ?? 120
    let seed = UInt64(gapOption(args, "--seed") ?? "7") ?? 7
    let prefix = gapOption(args, "--prefix") ?? "s"
    for focus in focuses {
        // Never a sentence this drill already asks; the other drill may ask it another way.
        let bundled = Set(GapChoiceBank.bundledUnchecked.items.filter { $0.focus == focus }.map { $0.filled.lowercased() })
        let items = GapChoicePlanner.pack(focus: focus, count: count, seed: seed, excluding: bundled, prefix: prefix)
        for item in items {
            guard let data = try? encoder.encode(item) else { fail("couldn't encode \(item.id)") }
            print(String(decoding: data, as: UTF8.self))
        }
        warn("gap-plans: \(items.count) \(focus.rawValue) items (\(GapChoicePlanner.candidates(focus: focus).count) candidates, seed \(seed))")
    }
}

/// `gap-check [file]`: one JSON line per item (id, passes, firstReject, codes, errors, warnings,
/// sentence), the composition on stderr. Exit 1 when anything fails.
func gapCheck(_ args: [String]) {
    let items = readGapItems(args)
    let lexicon = AppKasusLexicon()
    var failed = 0
    var rejects: [String: Int] = [:]
    for item in items {
        let result = GapChoiceCheck.run(item, lexicon: lexicon)
        if !result.passes { failed += 1; rejects[result.firstReject ?? "?", default: 0] += 1 }
        print(jsonLine(["id": item.id, "focus": item.focus.rawValue, "passes": result.passes,
                        "firstReject": result.firstReject ?? NSNull(), "codes": result.codes.map(\.rawValue),
                        "errors": result.errors, "warnings": result.warnings, "sentence": item.filled] as [String: Any]))
    }
    let composition = GapChoiceCheck.composition(items)
    warn("gap-check: \(items.count - failed)/\(items.count) pass"
         + (rejects.isEmpty ? "" : " · rejects " + rejects.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
         + " · composition " + (composition.isEmpty ? "OK" : composition.map { "\($0.code.rawValue) \($0.detail)" }.joined(separator: "; ")))
    if failed > 0 || !composition.isEmpty { exit(1) }
}

/// `gap-export [file]`: the passing items as a `gap_choice_items.json`-format file on stdout,
/// duplicate sentences and sentences the bundle already has dropped.
func gapExport(_ args: [String]) {
    let items = readGapItems(args)
    let lexicon = AppKasusLexicon()
    var seen = Set(GapChoiceBank.bundledUnchecked.items.map(GapChoiceCheck.sentenceKey))
    var ids = Set(GapChoiceBank.bundledUnchecked.items.map(\.id))
    var kept: [GapChoiceItem] = []
    var skipped: [String] = []
    for item in items {
        let result = GapChoiceCheck.run(item, lexicon: lexicon)
        guard result.passes else { skipped.append("\(item.id): \(result.firstReject ?? "fails")"); continue }
        guard seen.insert(GapChoiceCheck.sentenceKey(item)).inserted else { skipped.append("\(item.id): duplicate sentence"); continue }
        guard ids.insert(item.id).inserted else { skipped.append("\(item.id): duplicate id"); continue }
        kept.append(item)
    }
    struct Export: Encodable { let version: Int; let items: [GapChoiceItem] }
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? pretty.encode(Export(version: 1, items: kept)) else { fail("couldn't encode the export") }
    print(String(decoding: data, as: UTF8.self))
    for line in skipped { warn("  skipped \(line)") }
    warn("gap-export: \(kept.count) items, \(skipped.count) skipped")
}
