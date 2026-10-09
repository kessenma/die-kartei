//
//  KasusLab.swift
//  german-ai-flashcards
//
//  The numbers behind the Kasus Lab (Settings ▸ Developer, DEBUG): how each tutor does at writing
//  Kasus stories, so the developer can decide whether the feature ships, or whether a tutor needs
//  a fine-tune for this workload. No thresholds: the table is read, not judged.
//
//  Per model: gate pass rate (first try / after the retry), planned phrases verbatim / altered /
//  missing, gradable targets per case, the top validator issue codes, contract B's label accuracy
//  and share of unverifiable labels, the developer's „reads right / wrong“ taps, median seconds and
//  tokens, and how many runs had the memory saver on.
//
//  The export is JSONL, one line per attempt (raw output, plan, report), for
//  `training/results/kasus-lab_<model>.jsonl`: if a tutor is fine-tuned for this, the validator
//  is the data filter. Nothing here touches a ModelContext; the Lab never writes rounds, the
//  profile or a GeneratedKasusStory. DEBUG only, like the Lab screen.
//

#if DEBUG
import Foundation

/// One Lab run: a generation and the developer's verdict on how it reads.
struct KasusLabRun: Identifiable {
    let id = UUID()
    let result: KasusGenerationResult
    /// „Liest sich richtig · Reads right“ (true) or „falsch · wrong“ (false); nil until tapped.
    var readsRight: Bool?

    var modelID: String { result.modelID }
}

/// One exported line: an attempt with its plan, raw output and report.
nonisolated struct KasusLabRecord: Codable, Hashable {
    let model: String
    let unit: String
    let level: String
    let contract: String
    let governed: Bool
    /// 1 for the first try, 2 for the retry.
    let attempt: Int
    let seed: UInt64
    let seconds: Double
    let tokens: Int
    let endedEarly: Bool
    let passed: Bool
    /// The run's outcome: generated · fallback · failed · cancelled.
    let outcome: String
    let readsRight: Bool?
    let system: String
    let user: String
    let raw: String
    let plan: KasusStoryPlan
    let report: Report

    nonisolated struct Report: Codable, Hashable {
        let summary: String?
        let storyID: String?
        let wordCount: Int?
        let errorCodes: [String: Int]
        let warningCodes: [String: Int]
        let gradableByCase: [String: Int]
        let placements: [KasusPhrasePlacement]
        /// proven · wrong · unverifiable.<why>
        let harvest: [String: Int]
        let labels: KasusLabelScore?
        /// The validator's lines („error   trigger.prepositionCase  #11 …“).
        let issues: [String]
        /// The write threw.
        let error: String?
    }
}

/// One model's row in the Lab table.
struct KasusLabSummary: Identifiable {
    let modelID: String
    var id: String { modelID }
    let runs: Int
    let passedFirstTry: Int
    let passedAfterRetry: Int
    /// Over every attempt's planned phrases.
    let planned: Int
    let verbatim: Int
    let altered: Int
    let missing: Int
    /// Mean gradable targets per case, over attempts that produced a story.
    let gradableByCase: [GrammarCase: Double]
    /// Error codes over every attempt, most frequent first.
    let topErrors: [(code: String, count: Int)]
    let topWarnings: [(code: String, count: Int)]
    /// Contract B, pooled over its attempts.
    let labelAccuracy: Double?
    let unverifiableShare: Double?
    /// Labels matched only by their noun (a dictionary form), and labels not found at all.
    let labelsByNoun: Int
    let labelsNotInStory: Int
    let readsRight: Int
    let readsWrong: Int
    let medianSeconds: Double?
    let medianTokens: Int?
    let governedRuns: Int
}

@MainActor
enum KasusLab {

    /// The export's file name: „kasus-lab_gemma4_E4B_german.jsonl“.
    static func fileName(for modelID: String) -> String {
        let safe = modelID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return "kasus-lab_\(String(safe)).jsonl"
    }

    static func records(for run: KasusLabRun) -> [KasusLabRecord] {
        let result = run.result
        return result.attempts.map { attempt in
            let check = attempt.check
            let report = check?.report
            func tally(_ issues: [KasusIssue]) -> [String: Int] {
                issues.reduce(into: [:]) { $0[$1.code.rawValue, default: 0] += 1 }
            }
            let harvest = (check?.harvest ?? []).reduce(into: [String: Int]()) { counts, phrase in
                let key = switch phrase.verdict {
                case .proven:                 "proven"
                case .wrong:                  "wrong"
                case .unverifiable(let why):  "unverifiable.\(why.rawValue)"
                }
                counts[key, default: 0] += 1
            }
            return KasusLabRecord(
                model: result.modelID,
                unit: result.request.unit.rawValue,
                level: attempt.plan.level,
                contract: attempt.plan.contract.rawValue,
                governed: result.governed,
                attempt: attempt.number,
                seed: attempt.plan.seed,
                seconds: (attempt.seconds * 10).rounded() / 10,
                tokens: attempt.tokenCount,
                endedEarly: attempt.endedEarly,
                passed: attempt.passes,
                outcome: result.outcome.rawValue,
                readsRight: run.readsRight,
                system: attempt.system,
                user: attempt.user,
                raw: attempt.raw,
                plan: attempt.plan,
                report: .init(
                    summary: check?.summaryLine,
                    storyID: check?.story?.id,
                    wordCount: report?.wordCount,
                    errorCodes: tally(report?.errors ?? []),
                    warningCodes: tally(report?.warnings ?? []),
                    gradableByCase: (report?.gradableByCase ?? [:]).reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
                    placements: check?.placements ?? [],
                    harvest: harvest,
                    labels: check?.labels,
                    issues: report?.issueLines ?? [],
                    error: attempt.error
                )
            )
        }
    }

    /// Every attempt of every run, one JSON object per line.
    static func jsonl(_ runs: [KasusLabRun]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return runs.flatMap(records(for:)).compactMap { record in
            (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) }
        }.joined(separator: "\n")
    }

    /// One row per model, in the order the models first appear.
    static func summaries(_ runs: [KasusLabRun]) -> [KasusLabSummary] {
        var order: [String] = []
        for run in runs where !order.contains(run.modelID) { order.append(run.modelID) }
        return order.map { model in summary(runs.filter { $0.modelID == model }, modelID: model) }
    }

    static func summary(_ runs: [KasusLabRun], modelID: String) -> KasusLabSummary {
        let attempts = runs.flatMap(\.result.attempts)
        let placements = attempts.flatMap { $0.check?.placements ?? [] }
        let reports = attempts.compactMap { $0.check?.report }
        var gradable: [GrammarCase: Double] = [:]
        if !reports.isEmpty {
            for kasus in GrammarCase.allCases {
                gradable[kasus] = Double(reports.reduce(0) { $0 + $1.gradableByCase[kasus, default: 0] }) / Double(reports.count)
            }
        }
        func top(_ issues: [KasusIssue]) -> [(code: String, count: Int)] {
            let counts = issues.reduce(into: [String: Int]()) { $0[$1.code.rawValue, default: 0] += 1 }
            return counts.map { (code: $0.key, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.code < $1.code }
        }
        var pooled = KasusLabelScore()
        var anyLabels = false
        for labels in attempts.compactMap({ $0.check?.labels }) {
            anyLabels = true
            pooled.correct += labels.correct
            pooled.wrong += labels.wrong
            pooled.unverifiable += labels.unverifiable
            pooled.byNoun += labels.byNoun
            pooled.notInStory += labels.notInStory
        }
        func median<T: Comparable>(_ values: [T]) -> T? {
            guard !values.isEmpty else { return nil }
            return values.sorted()[values.count / 2]
        }
        let written = attempts.filter { $0.check != nil }
        return KasusLabSummary(
            modelID: modelID,
            runs: runs.count,
            passedFirstTry: runs.filter(\.result.passedFirstTry).count,
            passedAfterRetry: runs.filter(\.result.passedAfterRetry).count,
            planned: placements.count,
            verbatim: placements.filter(\.isVerbatim).count,
            altered: placements.filter { $0.status == .altered }.count,
            missing: placements.filter { $0.status == .missing }.count,
            gradableByCase: gradable,
            topErrors: top(reports.flatMap(\.errors)),
            topWarnings: top(reports.flatMap(\.warnings)),
            labelAccuracy: anyLabels ? pooled.accuracy : nil,
            unverifiableShare: anyLabels ? pooled.unverifiableShare : nil,
            labelsByNoun: pooled.byNoun,
            labelsNotInStory: pooled.notInStory,
            readsRight: runs.filter { $0.readsRight == true }.count,
            readsWrong: runs.filter { $0.readsRight == false }.count,
            medianSeconds: median(written.map(\.seconds)),
            medianTokens: median(written.map(\.tokenCount)),
            governedRuns: runs.filter(\.result.governed).count
        )
    }
}
#endif
