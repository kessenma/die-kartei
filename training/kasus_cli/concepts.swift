//
//  concepts.swift
//  kasus-cli
//
//  The Verstehen items (Rollen, Wer macht was?, Die Probe) through the app's own planner, prompt
//  and gate, for the tutor capability probe (training/KASUS_CONCEPT_PROBE.md):
//
//    kasus-cli concept-prompts <kind:unit:from-to>...
//        One JSON line per plan: id, kind, unit, level, seed, maxTokens, temperature, system,
//        user, plan (with its template sentence). kind = roles | wer | probe | all; unit = a
//        KasusUnit or all; from-to asks for that many distinct plans, starting at seed `from`
//        (a seed that repeats an earlier template is skipped). e.g.  kasus-cli concept-prompts all:all:1-10
//
//    kasus-cli concept-check [file] [--template]
//        Reads JSON lines {plan, raw} plus any of id, model, seconds, tokens, error. Writes one
//        verdict per line to stdout and a table per model × exercise to stderr. --template
//        checks each line's plan.template instead of raw, as model "template": the no-model
//        baseline.
//
//    kasus-cli audit-concepts [file]
//        The bundled kasus_concepts.json (or a candidate file in the same format) through the same
//        audit; exit 1 unless every item passes.
//
//    kasus-cli concept-export [file] --prefix <p>
//        Reads JSON lines {plan, raw, english, phrasesEnglish, questionEnglish?} (a writer's
//        outputs), gates each, and prints a kasus_concepts.json-format file of the passing ones
//        to stdout (ids kc-<p>-<unit>-<kind>-<seed>). An English phrase that isn't in the English
//        line is left off its target and reported on stderr; a Wer item without a question in
//        English is skipped.
//

import Foundation

nonisolated struct ConceptPromptRecord: Codable {
    let id: String
    let kind: String
    let unit: String
    let level: String
    let seed: UInt64
    let maxTokens: Int
    let temperature: Float
    let system: String
    let user: String
    let plan: KasusConceptPlan
}

nonisolated struct ConceptCheckInput: Decodable {
    let plan: KasusConceptPlan
    let raw: String?
    let id: String?
    let model: String?
    let seconds: Double?
    let tokens: Int?
    let error: String?
}

/// The probe's name for an exercise: wer for whoDoesWhat.
func exerciseName(_ kind: KasusConceptKind) -> String {
    kind == .whoDoesWhat ? "wer" : kind.rawValue
}

func conceptPrompts(_ args: [String]) {
    guard !args.isEmpty else { fail("concept-prompts: give at least one kind:unit:from-to spec") }
    let lexicon = AppKasusLexicon()
    for spec in args {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 3 else { fail("bad spec \(spec): want kind:unit:from-to") }
        let units: [KasusUnit] = parts[1] == "all" ? KasusUnit.allCases
            : [KasusUnit(rawValue: parts[1]) ?? { fail("bad unit \(parts[1])") }()]
        let bounds = parts[2].split(separator: "-").compactMap { UInt64($0) }
        guard (1...2).contains(bounds.count), bounds.first! <= bounds.last! else { fail("bad seeds \(parts[2])") }
        for unit in units {
            let kinds: [KasusConceptKind] = switch parts[0] {
            case "all":   KasusConceptPlanner.kinds(for: unit)
            case "wer":   [.whoDoesWhat]
            case "roles": [.roles]
            case "probe": [.probe]
            default:      fail("bad kind \(parts[0]): roles, wer, probe or all")
            }
            for kind in kinds where KasusConceptPlanner.kinds(for: unit).contains(kind) {
                let count = Int(bounds.last! - bounds.first!) + 1
                let plans = KasusConceptPlanner.plans(kind: kind, unit: unit, from: bounds.first!, count: count, lexicon: lexicon)
                if plans.count < count { warn("only \(plans.count) distinct plans for \(kind.rawValue) \(unit.rawValue)") }
                for plan in plans {
                    let seed = plan.seed
                    let prompt = KasusConceptPrompt.build(plan)
                    let record = ConceptPromptRecord(id: plan.id, kind: exerciseName(kind), unit: unit.rawValue,
                                                     level: plan.level, seed: seed, maxTokens: KasusConceptPrompt.maxTokens,
                                                     temperature: KasusConceptPrompt.temperature,
                                                     system: prompt.system, user: prompt.user, plan: plan)
                    guard let data = try? encoder.encode(record) else { fail("couldn't encode \(plan.id)") }
                    print(String(decoding: data, as: UTF8.self))
                }
            }
        }
    }
}

func conceptCheck(_ args: [String]) {
    let template = args.contains("--template")
    let files = args.filter { $0 != "--template" }
    let data: Data
    if let path = files.first {
        guard let read = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
        data = read
    } else {
        data = FileHandle.standardInput.readDataToEndOfFile()
    }
    let lexicon = AppKasusLexicon()

    struct Row {
        let model: String
        let kind: String
        let passes: Bool
        let reject: String?
        let placedAll: Bool
        let orderAsked: Bool
        let orderOK: Bool
        let seconds: Double?
    }
    var rows: [Row] = []
    var malformed = 0
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        guard let input = try? JSONDecoder().decode(ConceptCheckInput.self, from: Data(line.utf8)) else {
            malformed += 1
            continue
        }
        let raw = template ? "SATZ: \(input.plan.template)" : (input.raw ?? "")
        let model = template ? "template" : (input.model ?? "?")
        let result = KasusConceptCheck.run(raw: raw, plan: input.plan, lexicon: lexicon)
        let kind = exerciseName(input.plan.kind)
        let orderAsked = input.plan.firstPhrase != nil
        let record: [String: Any] = [
            "id": input.id ?? input.plan.id, "model": model, "kind": kind, "unit": input.plan.unitRaw,
            "seed": input.plan.seed, "passes": result.passes, "firstReject": result.firstReject ?? NSNull(),
            "codes": result.codes.map(\.rawValue), "errors": result.errorCodes, "warnings": result.warningCodes,
            "facts": result.factsProblems, "sentence": result.sentence ?? NSNull(), "raw": raw,
            "placed": result.placed, "phrases": input.plan.phrases.map(\.expression), "extras": result.extras,
            "objectFirst": input.plan.isObjectFirst, "template": input.plan.template,
            "seconds": input.seconds ?? NSNull(), "tokens": input.tokens ?? NSNull(),
            "error": input.error ?? NSNull(),
        ]
        print(jsonLine(record))
        rows.append(Row(model: model, kind: kind, passes: result.passes, reject: result.firstReject,
                        placedAll: result.placed == input.plan.phrases.count, orderAsked: orderAsked,
                        orderOK: orderAsked && !result.codes.contains(.orderIgnored), seconds: input.seconds))
    }

    func pct(_ part: Int, _ whole: Int) -> String { whole == 0 ? "–" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%" }
    var lines = ["model                      exercise   n   pass        verbatim   order      median s  top rejects"]
    let models = Array(Set(rows.map(\.model))).sorted()
    for model in models {
        for kind in ["roles", "wer", "probe", "all"] {
            let group = rows.filter { $0.model == model && (kind == "all" || $0.kind == kind) }
            guard !group.isEmpty else { continue }
            let passed = group.filter(\.passes).count
            let verbatim = group.filter(\.placedAll).count
            let asked = group.filter(\.orderAsked)
            let order = asked.isEmpty ? "–" : "\(asked.filter(\.orderOK).count)/\(asked.count)"
            let secs = group.compactMap(\.seconds).sorted()
            let median = secs.isEmpty ? "–" : String(format: "%.1f", secs[secs.count / 2])
            var rejects: [String: Int] = [:]
            for row in group { if let r = row.reject { rejects[r, default: 0] += 1 } }
            let top = rejects.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            lines.append([model.padding(toLength: 26, withPad: " ", startingAt: 0),
                          kind.padding(toLength: 10, withPad: " ", startingAt: 0),
                          "\(group.count)".padding(toLength: 3, withPad: " ", startingAt: 0),
                          "\(passed) (\(pct(passed, group.count)))".padding(toLength: 11, withPad: " ", startingAt: 0),
                          pct(verbatim, group.count).padding(toLength: 10, withPad: " ", startingAt: 0),
                          order.padding(toLength: 10, withPad: " ", startingAt: 0),
                          median.padding(toLength: 9, withPad: " ", startingAt: 0), top].joined(separator: " "))
        }
    }
    warn(lines.joined(separator: "\n"))
    if malformed > 0 {
        warn("⚠️ \(malformed) malformed line(s) skipped")
        exit(2)
    }
}

nonisolated struct ConceptExportInput: Decodable {
    let plan: KasusConceptPlan
    let raw: String
    let english: String?
    let phrasesEnglish: [String]?
    let questionEnglish: String?
}

func conceptExport(_ args: [String]) {
    var prefix = "gen"
    var files: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "--prefix", i + 1 < args.count { prefix = args[i + 1]; i += 2; continue }
        files.append(args[i]); i += 1
    }
    let data: Data
    if let path = files.first {
        guard let read = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
        data = read
    } else {
        data = FileHandle.standardInput.readDataToEndOfFile()
    }
    let lexicon = AppKasusLexicon()
    let short = ["nominativ": "nom", "akkusativ": "akk", "dativ": "dat", "genitiv": "gen", "alleFaelle": "alle"]
    var items: [[String: Any]] = []
    var seen = Set<String>()
    var skipped = 0
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        guard let input = try? JSONDecoder().decode(ConceptExportInput.self, from: Data(line.utf8)) else {
            fail("a line doesn't decode: \(line.prefix(120))")
        }
        let plan = input.plan
        let result = KasusConceptCheck.run(raw: input.raw, plan: plan, lexicon: lexicon)
        guard result.passes, let item = result.item, let sentence = result.sentence else { skipped += 1; continue }
        let id = "kc-\(prefix)-\(short[plan.unitRaw] ?? plan.unitRaw)-\(exerciseName(plan.kind))-\(plan.seed)"
        guard seen.insert(sentence).inserted else { warn("\(id): same sentence as an earlier item, skipped"); skipped += 1; continue }
        guard let english = input.english?.trimmingCharacters(in: .whitespaces), !english.isEmpty else {
            warn("\(id): no English line, skipped"); skipped += 1; continue
        }
        var phraseEnglish: [Int: String] = [:]
        for (planned, target) in result.targetOf {
            guard let en = input.phrasesEnglish?[safe: planned], !en.isEmpty else { continue }
            if english.contains(en) { phraseEnglish[target] = en } else { warn("\(id): „\(en)“ isn't in „\(english)“, left off") }
        }
        let targets: [[String: Any]] = item.story.targets.enumerated().map { index, t in
            var target: [String: Any] = ["phrase": t.phrase, "case": t.kasus.rawValue, "genus": t.genus.columnLabel,
                                         "lemma": t.lemma, "reason": t.reason.rawValue, "trigger": t.trigger]
            if let en = phraseEnglish[index] { target["en"] = en }
            return target
        }
        var out: [String: Any] = ["id": id, "unit": plan.unitRaw, "level": plan.level, "kind": plan.kind.rawValue,
                                  "paragraphs": [["de": sentence, "en": english]], "targets": targets]
        switch item.detail {
        case .roles(let ask):
            if let ask { out["ask"] = ask }
        case .whoDoesWhat(let question, let options, let answer):
            guard let en = input.questionEnglish?.trimmingCharacters(in: .whitespaces), !en.isEmpty else {
                warn("\(id): no English question, skipped"); skipped += 1; continue
            }
            out["question"] = ["de": question.de, "en": en]
            out["options"] = options
            out["answer"] = answer
        case .probe(let target, let noun):
            out["probe"] = ["target": target, "noun": noun.rawValue]
        default:
            continue
        }
        items.append(out)
    }
    guard let json = try? JSONSerialization.data(withJSONObject: ["version": 1, "items": items],
                                                 options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
        fail("couldn't encode the items")
    }
    print(String(decoding: json, as: UTF8.self))
    warn("concept-export: \(items.count) items, \(skipped) skipped")
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

func auditConcepts(_ args: [String] = []) {
    let url = args.first(where: { !$0.hasPrefix("--") }).map { URL(fileURLWithPath: $0) }
        ?? Bundle.main.url(forResource: "kasus_concepts", withExtension: "json")
    guard let url, let data = try? Data(contentsOf: url),
          let bank = try? KasusConceptBank(data: data) else { fail("\(url?.lastPathComponent ?? "kasus_concepts.json") is missing or doesn't decode") }
    let lexicon = AppKasusLexicon()
    if args.contains("--golden") { printGolden(bank: bank, lexicon: lexicon) }
    var failed = 0
    for item in bank.items {
        let audit = KasusConceptBank.audit(item, lexicon: lexicon)
        if !audit.passes {
            failed += 1
            print("FAIL \(item.id): \(audit.problems.joined(separator: " | "))")
        }
    }
    print("audit-concepts: \(bank.items.count - failed)/\(bank.items.count) pass")
    if failed > 0 { exit(1) }
}

/// The `KasusConceptFixtures.golden` table for a bank, counted the way its verifier counts, ready
/// to paste: `kasus-cli audit-concepts [file] --golden`.
func printGolden(bank: KasusConceptBank, lexicon: AppKasusLexicon) {
    let caseNames: [GrammarCase: String] = [.nominativ: ".nominativ", .akkusativ: ".akkusativ", .dativ: ".dativ", .genitiv: ".genitiv"]
    for unit in KasusUnit.allCases {
        for kind in KasusConceptKind.allCases {
            let items = bank.items(for: unit, kind: kind)
            guard !items.isEmpty else { continue }
            var targets = 0, ovs = 0
            var byCase: [GrammarCase: Int] = [:]
            var proofs: [KasusProof: Int] = [:]
            for item in items {
                let audit = KasusConceptBank.audit(item, lexicon: lexicon)
                targets += audit.report.located.count
                for t in audit.report.located { byCase[t.kasus, default: 0] += 1; proofs[t.proof, default: 0] += 1 }
                if audit.facts.isOVS { ovs += 1 }
            }
            let cases = GrammarCase.allCases.compactMap { k in byCase[k].map { "\(caseNames[k] ?? ".\(k.rawValue)"): \($0)" } }.joined(separator: ", ")
            let proofText = "[.form: \(proofs[.form, default: 0]), .preposition: \(proofs[.preposition, default: 0]), .copula: \(proofs[.copula, default: 0]), .label: \(proofs[.label, default: 0])]"
            print("        \"\(unit.rawValue)/\(kind.rawValue)\": Golden(items: \(items.count), targets: \(targets), byCase: [\(cases)],")
            print("                      proofs: \(proofText)\(kind == .whoDoesWhat ? ", ovs: \(ovs)" : "")),")
        }
    }
}
