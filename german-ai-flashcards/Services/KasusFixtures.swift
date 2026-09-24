//
//  KasusFixtures.swift
//  german-ai-flashcards
//
//  Planted-error stories that prove the validator catches what it claims to, plus the golden
//  numbers for the bundled stories and a round trip of the forms engine over every table cell.
//  `-kasus.debugVerify 1` prints `verify(stories:lexicon:)`; the Phase 2 test target runs the same
//  fixtures. Every fixture is a one-paragraph story, so the story.* rules (word count, cases per
//  unit) are ignored when judging one.
//

#if DEBUG
import Foundation

struct KasusFixture {
    let name: String
    /// The only error code the fixture may raise; nil means it must raise none.
    let expected: KasusIssueCode?
    /// When set, the proofs of the located targets, in order.
    let expectedProofs: [KasusProof]?
    let story: KasusStory
}

enum KasusFixtures {

    /// One per row of the plan's verification table.
    static let plan: [KasusFixture] = [
        fixture("„mit den Hund“", .triggerPrepositionCase, "Jonas spielt mit den Hund.",
                [target("den Hund", .akkusativ, .der, "Hund", .preposition, "mit")]),
        fixture("„auf die Rand“", .impossibleForm, "Er sitzt auf die Rand.",
                [target("die Rand", .dativ, .der, "Rand", .wechselWo, "auf")]),
        fixture("„Ich helfe den Mann“", .caseMismatch, "Ich helfe den Mann.",
                [target("den Mann", .dativ, .der, "Mann", .dativeVerb, "helfe")]),
        fixture("„das Tasche“", .lexGender, "Ich suche das Tasche.",
                [target("das Tasche", .akkusativ, .das, "Tasche", .object, "suche")]),
        fixture("„eine Kinder“", .impossibleForm, "Ich sehe eine Kinder.",
                [target("eine Kinder", .akkusativ, .plural, "Kind", .object, "sehe")]),
        fixture("„mit den Termin“ labelled pl", .pluralForm, "Ich bin mit den Termin zufrieden.",
                [target("den Termin", .dativ, .plural, "Termin", .preposition, "mit")]),
        fixture("„den Junge“", .nDeklination, "Ich sehe den Junge.",
                [target("den Junge", .akkusativ, .der, "Junge", .object, "sehe")]),
        fixture("an untargeted determiner", .untargetedDeterminer, "Ich sehe den Hund und die Katze.",
                [target("den Hund", .akkusativ, .der, "Hund", .object, "sehe")]),
        fixture("a missing phrase", .locateNotFound, "Ich sehe den Hund.",
                [target("den Hund", .akkusativ, .der, "Hund", .object, "sehe"),
                 target("den Ball", .akkusativ, .der, "Ball", .object, "sehe")]),
        fixture("„liegt unter den Tisch“ as wechselWohin", .triggerWechselVerb, "Er liegt unter den Tisch.",
                [target("den Tisch", .akkusativ, .der, "Tisch", .wechselWohin, "unter")]),
        fixture("„um dem Hund zu helfen“", nil, "Jonas kommt, um dem Hund zu helfen.",
                [target("dem Hund", .dativ, .der, "Hund", .dativeVerb, "helfen")]),
    ]

    /// The proofs the bundled story doesn't exercise, the Genitiv and n-noun endings, known
    /// plurals, and coverage past an adjective.
    static let extra: [KasusFixture] = [
        fixture("copula „Das ist die Mutter“", nil, "Das ist die Mutter.",
                [target("die Mutter", .nominativ, .die, "Mutter", .predicate, "ist")],
                proofs: [.copula]),
        fixture("coordination „mit dem Hund und der Katze“", nil, "Er spielt mit dem Hund und der Katze.",
                [target("dem Hund", .dativ, .der, "Hund", .preposition, "mit"),
                 target("der Katze", .dativ, .die, "Katze", .preposition, "mit")],
                proofs: [.form, .preposition]),
        fixture("postposition „den Fluss entlang“", nil, "Wir gehen den Fluss entlang.",
                [target("den Fluss", .akkusativ, .der, "Fluss", .preposition, "entlang")],
                proofs: [.form]),
        fixture("Genitiv „das Auto des Mannes“", nil, "Das ist das Auto des Mannes.",
                [target("das Auto", .nominativ, .das, "Auto", .predicate, "ist"),
                 target("des Mannes", .genitiv, .der, "Mann", .attribute, "Auto")],
                proofs: [.copula, .form]),
        fixture("„des Mann“", .genitiveS, "Das ist das Auto des Mann.",
                [target("das Auto", .nominativ, .das, "Auto", .predicate, "ist"),
                 target("des Mann", .genitiv, .der, "Mann", .attribute, "Auto")]),
        fixture("„des Haus“", .genitiveS, "Er bleibt wegen des Haus.",
                [target("des Haus", .genitiv, .das, "Haus", .preposition, "wegen")]),
        fixture("„des Busses“", nil, "Er wartet wegen des Busses.",
                [target("des Busses", .genitiv, .der, "Bus", .preposition, "wegen")]),
        fixture("„des Studentens“", .nDeklination, "Er kommt wegen des Studentens.",
                [target("des Studentens", .genitiv, .der, "Student", .preposition, "wegen")]),
        fixture("„des Namens“", nil, "Er fragt wegen des Namens.",
                [target("des Namens", .genitiv, .der, "Name", .preposition, "wegen")]),
        fixture("„den Herren“ for one man", .nDeklination, "Ich sehe den Herren.",
                [target("den Herren", .akkusativ, .der, "Herr", .object, "sehe")]),
        fixture("„die Hunds“", .pluralForm, "Hier spielen die Hunds.",
                [target("die Hunds", .nominativ, .plural, "Hund", .subject, "spielen")]),
        fixture("„einen großen Ball“ untargeted", .untargetedDeterminer, "Er kauft einen großen Ball.", []),
    ]

    static var all: [KasusFixture] { plan + extra }

    /// What each bundled story must come out as. A change to the text, the targets or the rules
    /// that moves these numbers shows up in the debug report.
    struct Golden {
        let targets: Int
        let byCase: [GrammarCase: Int]
        let proofs: [KasusProof: Int]
    }

    static let golden: [String: Golden] = [
        "ks-dat-a2-schluessel": Golden(
            targets: 26,
            byCase: [.nominativ: 6, .akkusativ: 11, .dativ: 9],
            proofs: [.form: 20, .preposition: 2, .copula: 0, .label: 4]
        ),
    ]

    // MARK: - Running

    struct VerifyResult {
        let text: String
        let failures: [String]
    }

    /// Validates the bundled stories, runs every fixture and the round trip. The text's first line
    /// per story is its `summaryLine`.
    static func verify(stories: [KasusStory], lexicon: some KasusLexicon) -> VerifyResult {
        var lines: [String] = []
        var failures: [String] = []

        for story in stories {
            let report = KasusValidator.validate(story, source: story.source, lexicon: lexicon)
            lines.append(report.summaryLine)
            let gradable = GrammarCase.allCases.compactMap { kasus in
                report.gradableByCase[kasus].map { "\(kasus.short) \($0)" }
            }.joined(separator: " · ")
            lines.append("  cases \(report.casesLine) · gradable \(gradable) · \(report.wordCount) words")
            lines += report.issueLines.map { "  " + $0 }
            if !report.passes { failures.append("\(story.id) fails validation") }
            if let golden = golden[story.id] {
                let byCase = report.located.reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
                var misses: [String] = []
                if report.targets.count != golden.targets { misses.append("targets \(report.targets.count) ≠ \(golden.targets)") }
                for kasus in GrammarCase.allCases where byCase[kasus, default: 0] != golden.byCase[kasus, default: 0] {
                    misses.append("\(kasus.short) \(byCase[kasus, default: 0]) ≠ \(golden.byCase[kasus, default: 0])")
                }
                for proof in KasusProof.allCases where report.proofTally[proof, default: 0] != golden.proofs[proof, default: 0] {
                    misses.append("\(proof.rawValue) \(report.proofTally[proof, default: 0]) ≠ \(golden.proofs[proof, default: 0])")
                }
                if !report.warnings.isEmpty { misses.append("\(report.warnings.count) warnings") }
                lines.append(misses.isEmpty ? "  golden ✓" : "  golden ✗ " + misses.joined(separator: ", "))
                failures += misses.map { "\(story.id) golden: \($0)" }
            }
        }

        for (title, set) in [("Fixtures (plan)", plan), ("Fixtures (extra)", extra)] {
            let results = set.map { run($0, lexicon: lexicon) }
            lines.append("\(title) \(results.filter(\.passed).count)/\(set.count)")
            for result in results {
                lines.append("  \(result.passed ? "PASS" : "FAIL")  \(result.line)")
                if !result.passed { failures.append("fixture \(result.line)") }
            }
        }

        let roundTrip = roundTrip()
        lines.append(roundTrip.failures.isEmpty
                     ? "Round trip: \(roundTrip.cells) table cells OK"
                     : "Round trip: \(roundTrip.failures.count) of \(roundTrip.cells) cells FAILED")
        lines += roundTrip.failures.map { "  " + $0 }
        failures += roundTrip.failures

        lines.append(failures.isEmpty ? "ALL OK" : "\(failures.count) FAILED")
        return VerifyResult(text: lines.joined(separator: "\n"), failures: failures)
    }

    private static func run(_ fixture: KasusFixture, lexicon: some KasusLexicon) -> (passed: Bool, line: String) {
        let report = KasusValidator.validate(fixture.story, source: .authored, lexicon: lexicon)
        let raised = report.errors.map(\.code).filter { !$0.isStoryLevel }
        let codes = Set(raised)
        var passed = fixture.expected.map { codes == [$0] } ?? codes.isEmpty
        var line = "\(fixture.name) → \(fixture.expected?.rawValue ?? "no error")"
        if let proofs = fixture.expectedProofs {
            let actual = report.located.map(\.proof)
            if actual != proofs {
                passed = false
                line += " · proofs \(actual.map(\.rawValue)) ≠ \(proofs.map(\.rawValue))"
            } else {
                line += " · proofs \(actual.map(\.rawValue).joined(separator: ", "))"
            }
        }
        if !passed || codes.count != raised.count {
            line += " · raised [\(raised.map(\.rawValue).joined(separator: ", "))]"
            let messages = report.errors.filter { !$0.code.isStoryLevel }.map(\.message)
            if !messages.isEmpty { line += " · " + messages.joined(separator: " | ") }
        }
        return (passed, line)
    }

    /// Every cell of the endings table, for every family: the engine's form matches
    /// `GrammarCase.article` / `einEnding`, parses back to its family and stem (capitalised too),
    /// and `compatibleCases` returns exactly the cases that share it. ein has no plural.
    static func roundTrip() -> (cells: Int, failures: [String]) {
        var cells = 0
        var failures: [String] = []
        let families: [(KasusFamily, String)] = [(.definite, ""), (.ein, "ein"), (.kein, "kein")]
            + KasusForms.possessiveStems.map { (.possessive, $0) }
        for (family, stem) in families {
            for genus in Gender.allCases {
                var byForm: [String: Set<GrammarCase>] = [:]
                for kasus in GrammarCase.allCases {
                    let ending = kasus.einEnding(genus)
                    let table: String? = switch family {
                    case .definite: kasus.article(genus)
                    case .ein where genus == .plural: nil
                    default: (stem == "euer" && !ending.isEmpty ? "eur" : stem) + ending
                    }
                    let engine = KasusForms.form(family: family, stem: stem, case: kasus, genus: genus)
                    if engine != table {
                        failures.append("\(family) \(stem) \(kasus.short) \(genus.columnLabel): engine \(engine ?? "∅") ≠ table \(table ?? "∅")")
                    }
                    guard let table else { continue }
                    cells += 1
                    byForm[table, default: []].insert(kasus)
                }
                for (form, cases) in byForm {
                    let parsed = KasusForms.parseDeterminer(form)
                    if parsed?.family != family || parsed?.stem != stem {
                        failures.append("„\(form)“ parses as \(parsed.map { "\($0.family) \($0.stem)" } ?? "nothing")")
                    }
                    for written in [form, form.capitalized] {
                        let back = KasusForms.compatibleCases(determiner: written, genus: genus)
                        if back != cases {
                            failures.append("„\(written)“ \(genus.columnLabel): \(back.map(\.short).sorted()) ≠ \(cases.map(\.short).sorted())")
                        }
                    }
                }
            }
            if family == .ein {
                for form in KasusForms.fullFamilyOptions(family: .ein, stem: "ein", includeGenitive: true)
                where !KasusForms.compatibleCases(determiner: form, genus: .plural).isEmpty {
                    failures.append("„\(form)“ fits a plural noun, but ein has no plural")
                }
            }
        }
        return (cells, failures)
    }

    // MARK: - Building

    private static func fixture(_ name: String, _ expected: KasusIssueCode?, _ text: String,
                                _ targets: [KasusTargetSpec], proofs: [KasusProof]? = nil) -> KasusFixture {
        let story = KasusStory(
            id: "fixture",
            unitRaw: "dativ",
            level: "A2",
            source: .authored,
            reviewed: .init(by: "", date: ""),
            title: name,
            titleEnglish: name,
            question: .init(de: "", en: "", options: [""], answer: 0),
            paragraphs: [.init(de: text, en: "")],
            targets: targets,
            notTargets: []
        )
        return KasusFixture(name: name, expected: expected, expectedProofs: proofs, story: story)
    }

    private static func target(_ phrase: String, _ kasus: GrammarCase, _ genus: Gender, _ lemma: String,
                               _ reason: KasusReason, _ trigger: String) -> KasusTargetSpec {
        KasusTargetSpec(phrase: phrase, kasus: kasus, genus: genus, lemma: lemma, reason: reason, trigger: trigger)
    }
}
#endif
