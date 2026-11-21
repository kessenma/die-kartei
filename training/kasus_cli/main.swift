//
//  main.swift
//  kasus-cli
//
//  The app's Kasus story pipeline without the model call, so a teacher model's stories can be
//  planned, prompted and checked by the same code the app runs (training/KASUS_STORY_DATA.md).
//  Plans, prompts and verdicts come from the compiled app sources in sources.txt.
//
//    kasus-cli selftest
//        Resource counts, the validator's fixtures and the bundled stories' golden numbers through
//        this binary's lexicon. Exit 1 on anything off: a missing resource changes verdicts
//        without an error.
//
//    kasus-cli prompts <spec>... [--governed] [--contract A|B]
//        One JSON line per plan: id, plan, the exact system and user prompt, maxTokens, temperature.
//        spec = unit:level:seed, or unit:level:from-to for a seed range; unit `all` is all five.
//        e.g.  kasus-cli prompts dativ:A2:1003 all:B1:1-50
//
//    kasus-cli concept-prompts | concept-check | audit-concepts
//        The Verstehen items: see concepts.swift.
//
//    kasus-cli check [file]
//        Reads JSON lines (a file, or stdin): {plan, raw} plus any of id, model, run, attempt,
//        endedEarly, tokens, seconds, system, user, error. Writes one Kasus Lab record per line to
//        stdout (the app's KasusLabRecord, plus id, run and promptDrift) and the Lab's summary per
//        model to stderr. Lines that share model and run are one run (attempt 1, then the retry);
//        a line without a run is its own. A contract-A write is trimmed to its last full sentence
//        first, as the app does. promptDrift is true when a line's system or user differs from the
//        prompt this build makes for its plan: the story was written to another prompt.
//

import Foundation

// MARK: - I/O

nonisolated struct PromptRecord: Codable {
    let id: String
    let unit: String
    /// As asked; `plan.level` is after the memory saver's cap.
    let level: String
    let seed: UInt64
    let contract: String
    let governed: Bool
    let casesLine: String
    let maxTokens: Int
    let temperature: Float
    let system: String
    let user: String
    let plan: KasusStoryPlan
}

nonisolated struct CheckInput: Decodable {
    let plan: KasusStoryPlan
    let raw: String
    let id: String?
    let model: String?
    let run: String?
    let attempt: Int?
    let endedEarly: Bool?
    let tokens: Int?
    let seconds: Double?
    let system: String?
    let user: String?
    /// The write threw; `raw` is whatever came back, usually nothing.
    let error: String?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func jsonLine(_ object: Any) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

// MARK: - selftest

func selftest() {
    var problems: [String] = []
    func count(_ label: String, _ value: Int) {
        print("\(label): \(value)")
        if value == 0 { problems.append("\(label) is empty: is the resource linked next to the binary?") }
    }
    print("wiktionary_de.db available: \(WiktionaryValidator.shared.isAvailable)")
    if !WiktionaryValidator.shared.isAvailable { problems.append("wiktionary_de.db is not available") }
    for level in GoetheLevel.allCases { count("Goethe \(level.rawValue) entries", GoetheVocabService.entries(for: level).count) }
    count("prepositions", PrepositionService.all().count)
    count("verb pairs", VerbPrepositionService.all().count)
    count("trigger topics", KasusTriggerBank.bundled.topics.count)
    count("bundled stories", KasusStoryBank.bundled.stories.count)
    // Loading the gap-choice bank runs its gate and composition check (an assert on a failure).
    count("gap-choice items", GapChoiceBank.bundled.items.count)
    let packA = GapChoicePlanner.pack(focus: .case, count: 40, seed: 7)
    let packB = GapChoicePlanner.pack(focus: .case, count: 40, seed: 7)
    print("gap-plans case:40:7: \(packA.count) items · first \(packA.first?.filled ?? "–")")
    if packA.map(\.id) != packB.map(\.id) { problems.append("the gap planner gave two packs for one seed") }
    let composition = GapChoiceCheck.composition(packA)
    if !composition.isEmpty { problems.append("the gap planner's case pack fails composition: " + composition.map(\.detail).joined(separator: "; ")) }

    let lexicon = AppKasusLexicon()
    let a = KasusStoryPlanner.plan(unit: .dativ, level: .a2, seed: 1003, governed: false, lexicon: lexicon)
    let b = KasusStoryPlanner.plan(unit: .dativ, level: .a2, seed: 1003, governed: false, lexicon: lexicon)
    print("plan dativ:A2:1003: \(a.casesLine) · \(a.phrases.map(\.expression).joined(separator: " | "))")
    if a != b { problems.append("the planner gave two plans for one seed") }
    if a.phrases.isEmpty { problems.append("the planner planned no phrases for dativ:A2:1003") }

    let verify = KasusFixtures.verify(stories: KasusStoryBank.bundled.stories, lexicon: lexicon)
    print(verify.text)
    problems += verify.failures

    if problems.isEmpty {
        print("selftest OK")
    } else {
        fail("selftest FAILED\n" + problems.map { "  " + $0 }.joined(separator: "\n"))
    }
}

// MARK: - prompts

func prompts(_ args: [String]) {
    var governed = false
    var contract = KasusContract.planned
    var specs: [String] = []
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--governed": governed = true
        case "--contract":
            index += 1
            guard index < args.count, let parsed = KasusContract(rawValue: args[index].uppercased()) else {
                fail("--contract takes A or B")
            }
            contract = parsed
        default: specs.append(args[index])
        }
        index += 1
    }
    guard !specs.isEmpty else { fail("prompts: give at least one unit:level:seed spec") }

    let lexicon = AppKasusLexicon()
    for spec in specs {
        let parts = spec.split(separator: ":").map(String.init)
        guard parts.count == 3 else { fail("bad spec \(spec): want unit:level:seed or unit:level:from-to") }
        let units: [KasusUnit]
        if parts[0] == "all" {
            units = KasusUnit.allCases
        } else if let unit = KasusUnit(rawValue: parts[0]) {
            units = [unit]
        } else {
            fail("bad unit \(parts[0]): one of \(KasusUnit.allCases.map(\.rawValue).joined(separator: ", ")), all")
        }
        guard let level = CEFRLevel(rawValue: parts[1].uppercased()) else { fail("bad level \(parts[1])") }
        let bounds = parts[2].split(separator: "-").compactMap { UInt64($0) }
        guard (1...2).contains(bounds.count), bounds.first! <= bounds.last! else { fail("bad seed \(parts[2])") }
        for unit in units {
            for seed in bounds.first!...bounds.last! {
                let plan = KasusStoryPlanner.plan(unit: unit, level: level, seed: seed, governed: governed,
                                                  contract: contract, lexicon: lexicon)
                let prompt = KasusStoryPrompt.build(plan)
                let id = "\(unit.rawValue)-\(level.rawValue)-\(seed)-\(contract.rawValue)" + (governed ? "-g" : "")
                let record = PromptRecord(id: id, unit: unit.rawValue, level: level.rawValue, seed: seed,
                                          contract: contract.rawValue, governed: governed, casesLine: plan.casesLine,
                                          maxTokens: KasusStoryPrompt.maxTokens(for: plan),
                                          temperature: KasusStoryPrompt.temperature,
                                          system: prompt.system, user: prompt.user, plan: plan)
                guard let data = try? encoder.encode(record) else { fail("couldn't encode \(id)") }
                print(String(decoding: data, as: UTF8.self))
            }
        }
    }
}

// MARK: - check

func check(_ args: [String]) {
    let data: Data
    if let path = args.first {
        guard let read = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
        data = read
    } else {
        data = FileHandle.standardInput.readDataToEndOfFile()
    }

    struct Line { let index: Int; let input: CheckInput }
    var lines: [Line] = []
    var malformed = 0
    for (index, text) in String(decoding: data, as: UTF8.self).split(separator: "\n").enumerated() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        do {
            let input = try JSONDecoder().decode(CheckInput.self, from: Data(trimmed.utf8))
            guard input.plan.unit != nil else { throw CocoaError(.coderInvalidValue) }
            lines.append(Line(index: index + 1, input: input))
        } catch {
            malformed += 1
            warn("line \(index + 1): skipped, not a check input (\(error.localizedDescription))")
        }
    }

    // Runs in order of first appearance.
    var order: [String] = []
    var byRun: [String: [Line]] = [:]
    for line in lines {
        let key = (line.input.model ?? "unknown") + "\u{1}" + (line.input.run ?? "line-\(line.index)")
        if byRun[key] == nil { order.append(key) }
        byRun[key, default: []].append(line)
    }

    let lexicon = AppKasusLexicon()
    var labRuns: [KasusLabRun] = []
    var drifted = 0
    for key in order {
        let runLines = byRun[key]!.sorted { ($0.input.attempt ?? 1) < ($1.input.attempt ?? 1) }
        var attempts: [KasusGenerationAttempt] = []
        var extras: [(id: String?, run: String?, drift: Bool)] = []
        for line in runLines {
            let input = line.input
            let plan = input.plan
            let prompt = KasusStoryPrompt.build(plan)
            let drift = (input.system.map { $0 != prompt.system } ?? false) || (input.user.map { $0 != prompt.user } ?? false)
            if drift { drifted += 1 }
            let endedEarly = input.endedEarly ?? false
            let check: KasusCheckResult?
            if input.error != nil && input.raw.isEmpty {
                check = nil
            } else {
                let raw = plan.contract == .planned
                    ? KasusStoryGenerator.completeSentences(input.raw, endedEarly: endedEarly) : input.raw
                check = KasusStoryCheck.run(raw: raw, plan: plan, lexicon: lexicon)
            }
            attempts.append(KasusGenerationAttempt(number: input.attempt ?? attempts.count + 1, plan: plan,
                                                   system: input.system ?? prompt.system,
                                                   user: input.user ?? prompt.user, raw: input.raw,
                                                   seconds: input.seconds ?? 0, tokenCount: input.tokens ?? 0,
                                                   endedEarly: endedEarly, check: check, error: input.error))
            extras.append((input.id, input.run, drift))
        }
        let first = runLines[0].input
        let passing = attempts.first(where: \.passes)
        let outcome: KasusGenerationResult.Outcome = passing != nil ? .generated
            : attempts.allSatisfy({ $0.check == nil }) ? .failed : .fallback
        let request = KasusGenerationRequest(unit: first.plan.unit!, level: first.plan.cefr ?? .a2,
                                             contract: first.plan.contract, seed: first.plan.seed)
        let result = KasusGenerationResult(outcome: outcome, story: passing?.check?.story, note: nil,
                                           attempts: attempts, modelID: first.model ?? "unknown",
                                           governed: first.plan.governed, request: request)
        let labRun = KasusLabRun(result: result)
        labRuns.append(labRun)
        for (record, extra) in zip(KasusLab.records(for: labRun), extras) {
            guard let data = try? encoder.encode(record),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            object["id"] = extra.id ?? NSNull()
            object["run"] = extra.run ?? NSNull()
            object["promptDrift"] = extra.drift
            print(jsonLine(object))
        }
    }

    // The Lab's table, one block per model.
    for summary in KasusLab.summaries(labRuns) {
        let attempts = labRuns.filter { $0.modelID == summary.modelID }.flatMap(\.result.attempts)
        let gradable = GrammarCase.allCases.map { kasus in
            "\(kasus.short) \(String(format: "%.1f", summary.gradableByCase[kasus] ?? 0))"
        }.joined(separator: " · ")
        var lines = [
            "── \(summary.modelID)",
            "  runs \(summary.runs) · attempts \(attempts.count) · passing attempts \(attempts.filter(\.passes).count)",
            "  passed first try \(summary.passedFirstTry) · after retry \(summary.passedAfterRetry)",
            "  planned \(summary.planned) · verbatim \(summary.verbatim) · altered \(summary.altered) · missing \(summary.missing)",
            "  gradable per attempt \(gradable)",
            "  errors " + summary.topErrors.prefix(6).map { "\($0.code) \($0.count)" }.joined(separator: " · "),
        ]
        if let accuracy = summary.labelAccuracy {
            lines.append("  labels \(String(format: "%.0f%%", accuracy * 100)) right · by noun \(summary.labelsByNoun) · not in story \(summary.labelsNotInStory)")
        }
        if let seconds = summary.medianSeconds, let tokens = summary.medianTokens {
            lines.append("  median \(String(format: "%.1f", seconds)) s · \(tokens) tokens")
        }
        warn(lines.joined(separator: "\n"))
    }
    if drifted > 0 { warn("⚠️ \(drifted) line(s) were written to a prompt this build doesn't make (promptDrift)") }
    if malformed > 0 {
        warn("⚠️ \(malformed) malformed line(s) skipped")
        exit(2)
    }
}

// MARK: - main

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "selftest": selftest()
case "prompts":  prompts(Array(arguments.dropFirst()))
case "check":    check(Array(arguments.dropFirst()))
case "concept-prompts": conceptPrompts(Array(arguments.dropFirst()))
case "concept-check":   conceptCheck(Array(arguments.dropFirst()))
case "audit-concepts":  auditConcepts(Array(arguments.dropFirst()))
case "concept-export":  conceptExport(Array(arguments.dropFirst()))
case "audit-gaps":      auditGaps(Array(arguments.dropFirst()))
case "audit-endings":   auditEndings(Array(arguments.dropFirst()))
case "gap-plans":       gapPlans(Array(arguments.dropFirst()))
case "gap-check":       gapCheck(Array(arguments.dropFirst()))
case "gap-export":      gapExport(Array(arguments.dropFirst()))
default:
    fail("usage: kasus-cli selftest | prompts <unit:level:seed[-to]>... [--governed] [--contract A|B] | check [file]"
         + " | concept-prompts <kind:unit:from-to>... | concept-check [file] [--template] | audit-concepts [file]"
         + " | concept-export [file] --prefix <p> | audit-gaps [file] [--golden]"
         + " | gap-plans <case|person|all> [--count N] [--seed S] [--prefix p] | gap-check [file] | gap-export [file]")
}
