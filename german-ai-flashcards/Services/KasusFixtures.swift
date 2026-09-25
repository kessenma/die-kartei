//
//  KasusFixtures.swift
//  german-ai-flashcards
//
//  Planted-error stories that prove the validator catches what it claims to, plus the golden
//  numbers for every bundled story and a round trip of the forms engine over every table cell.
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
    /// When set, the kinds of the located targets, in order. Spot-only kinds must never be
    /// blankable, and an error-free article target always is.
    var expectedKinds: [KasusTargetKind]? = nil
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

    /// Phase 2: contraction and pronoun targets (spot-only), idioms as notTargets, and the
    /// dieser/jeder/welcher family.
    static let phase2: [KasusFixture] = [
        fixture("contraction „im Garten“", nil, "Der Hund liegt im Garten.",
                [target("Der Hund", .nominativ, .der, "Hund", .subject, "liegt"),
                 target("im Garten", .dativ, .der, "Garten", .wechselWo, "im")],
                proofs: [.form, .form], kinds: [.article, .contraction]),
        fixture("contraction „ins Kino“", nil, "Wir gehen heute ins Kino.",
                [target("ins Kino", .akkusativ, .das, "Kino", .wechselWohin, "in")],
                proofs: [.preposition], kinds: [.contraction]),
        fixture("contraction „zur Schule“", nil, "Sie fährt mit dem Rad zur Schule.",
                [target("dem Rad", .dativ, .das, "Rad", .preposition, "mit"),
                 target("zur Schule", .dativ, .die, "Schule", .preposition, "zu")],
                proofs: [.form, .preposition], kinds: [.article, .contraction]),
        fixture("time „Am Montag“", nil, "Am Montag hat er einen Termin.",
                [target("Am Montag", .dativ, .der, "Montag", .time, "Am"),
                 target("einen Termin", .akkusativ, .der, "Termin", .object, "hat")],
                proofs: [.form, .form], kinds: [.contraction, .article]),
        fixture("„zur Arzt“", .caseMismatch, "Er geht zur Arzt.",
                [target("zur Arzt", .dativ, .der, "Arzt", .preposition, "zu")]),
        fixture("„ins Garten“", .impossibleForm, "Er geht ins Garten.",
                [target("ins Garten", .akkusativ, .der, "Garten", .wechselWohin, "ins")]),
        fixture("„liegt ins Bett“ as wechselWohin", .triggerWechselVerb, "Er liegt ins Bett.",
                [target("ins Bett", .akkusativ, .das, "Bett", .wechselWohin, "ins")]),
        fixture("an untargeted contraction", .untargetedDeterminer, "Wir essen im Garten.", []),
        fixture("idioms „Zum Glück“, „am besten“", nil, "Zum Glück schmeckt der Kuchen am besten.",
                [target("der Kuchen", .nominativ, .der, "Kuchen", .subject, "schmeckt")],
                notTargets: [.init(phrase: "Zum Glück", why: .idiom), .init(phrase: "am besten", why: .idiom)]),
        fixture("pronoun „mit mir“", nil, "Er spielt mit mir.",
                [target("mir", .dativ, .der, "ich", .preposition, "mit")],
                proofs: [.form], kinds: [.pronoun]),
        fixture("pronoun reached back „mit dem Hund und mir“", nil, "Er spielt mit dem Hund und mir.",
                [target("dem Hund", .dativ, .der, "Hund", .preposition, "mit"),
                 target("mir", .dativ, .der, "ich", .preposition, "mit")],
                proofs: [.form, .form], kinds: [.article, .pronoun]),
        fixture("„Ich helfe dich“", .caseMismatch, "Ich helfe dich.",
                [target("dich", .dativ, .der, "du", .dativeVerb, "helfe")]),
        fixture("„für ihm“", .triggerPrepositionCase, "Er kauft Blumen für ihm.",
                [target("ihm", .dativ, .der, "er", .preposition, "für")]),
        fixture("„ihn“ for a feminine noun", .lexGender, "Ich finde ihn nicht.",
                [target("ihn", .akkusativ, .die, "er", .object, "finde")]),
        fixture("an untargeted pronoun", .untargetedDeterminer, "Er sieht mich und hilft mir.",
                [target("mich", .akkusativ, .der, "ich", .object, "sieht")]),
        fixture("„diesen Film“", nil, "Ich kenne diesen Film.",
                [target("diesen Film", .akkusativ, .der, "Film", .object, "kenne")],
                proofs: [.form], kinds: [.article]),
        fixture("time „jeden Tag“", nil, "Er läuft jeden Tag.",
                [target("jeden Tag", .akkusativ, .der, "Tag", .time, "läuft")],
                proofs: [.form]),
        fixture("„mit diesem Bus“", nil, "Wir fahren mit diesem Bus.",
                [target("diesem Bus", .dativ, .der, "Bus", .preposition, "mit")],
                proofs: [.form]),
        fixture("„Ich helfe dieser Frau“", nil, "Ich helfe dieser Frau.",
                [target("dieser Frau", .dativ, .die, "Frau", .dativeVerb, "helfe")],
                proofs: [.label]),
        fixture("„Welchen Hund“", nil, "Welchen Hund meinst du?",
                [target("Welchen Hund", .akkusativ, .der, "Hund", .object, "meinst")],
                proofs: [.form]),
        fixture("„jede Kinder“", .impossibleForm, "Ich sehe jede Kinder.",
                [target("jede Kinder", .akkusativ, .plural, "Kind", .object, "sehe")]),
        fixture("„Dieses Mann“", .caseMismatch, "Dieses Mann ist nett.",
                [target("Dieses Mann", .nominativ, .der, "Mann", .subject, "ist")]),
        fixture("an untargeted „diesen Film“", .untargetedDeterminer, "Ich kenne diesen Film.", []),
    ]

    static var all: [KasusFixture] { plan + extra + phase2 }

    /// What each bundled story must come out as. A change to the text, the targets or the rules
    /// that moves these numbers shows up in the debug report. Every bundled story needs one.
    struct Golden {
        let targets: Int
        let byCase: [GrammarCase: Int]
        let proofs: [KasusProof: Int]
        /// Spot-only targets: contractions and pronouns, marked in Finden, never blanked.
        var contractions = 0
        var pronouns = 0
        /// The label-proven targets by surface, in reading order: what the teacher checks.
        var labels: [String] = []
    }

    static let golden: [String: Golden] = [
        "ks-dat-a2-schluessel": Golden(
            targets: 26,
            byCase: [.nominativ: 6, .akkusativ: 11, .dativ: 9],
            proofs: [.form: 20, .preposition: 2, .copula: 0, .label: 4],
            labels: ["seine Mutter", "Die Mutter", "Das Tier", "seiner Mutter"]
        ),
        "ks-nom-a1-foto": Golden(
            targets: 16,
            byCase: [.nominativ: 15, .akkusativ: 1],
            proofs: [.form: 11, .preposition: 0, .copula: 2, .label: 3],
            labels: ["eine Frau", "ein Mädchen", "Das Foto"]
        ),
        "ks-akk-a1-picknick": Golden(
            targets: 17,
            byCase: [.nominativ: 2, .akkusativ: 15],
            proofs: [.form: 15, .preposition: 2, .copula: 0, .label: 0],
            pronouns: 1
        ),
        "ks-akk-a1-berlin": Golden(
            targets: 18,
            byCase: [.nominativ: 5, .akkusativ: 13],
            proofs: [.form: 16, .preposition: 2, .copula: 0, .label: 0],
            pronouns: 2
        ),
        "ks-dat-a2-umzug": Golden(
            targets: 28,
            byCase: [.nominativ: 5, .akkusativ: 8, .dativ: 15],
            proofs: [.form: 24, .preposition: 2, .copula: 0, .label: 2],
            contractions: 5,
            pronouns: 4,
            labels: ["das Sofa", "das Sofa"]
        ),
        "ks-gen-b1-grossmutter": Golden(
            targets: 51,
            byCase: [.nominativ: 10, .akkusativ: 13, .dativ: 17, .genitiv: 11],
            proofs: [.form: 41, .preposition: 6, .copula: 2, .label: 2],
            contractions: 6,
            pronouns: 4,
            labels: ["Die Küche", "meiner Großmutter"]
        ),
        "ks-alle-b1-gespraech": Golden(
            targets: 37,
            byCase: [.nominativ: 7, .akkusativ: 9, .dativ: 17, .genitiv: 4],
            proofs: [.form: 26, .preposition: 10, .copula: 1, .label: 0],
            contractions: 4,
            pronouns: 1
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
            let kinds = report.kindTally
            let blankable = GrammarCase.allCases.compactMap { kasus in
                let count = report.located.filter { $0.blankable && $0.kasus == kasus }.count
                return count > 0 ? "\(kasus.short) \(count)" : nil
            }.joined(separator: " · ")
            lines.append("  spot-only: contraction \(kinds[.contraction, default: 0]) · pronoun \(kinds[.pronoun, default: 0]) · blankable \(blankable)")
            let labels = report.located.filter { $0.proof == .label }
            if !labels.isEmpty {
                lines.append("  label: " + labels.map { "#\($0.index + 1) \($0.surface) (\($0.kasus.short), \($0.spec.trigger))" }
                    .joined(separator: " · "))
            }
            lines += report.issueLines.map { "  " + $0 }
            if !report.passes { failures.append("\(story.id) fails validation") }
            // Spot-only targets never reach Einsetzen; an error-free article target always does.
            for target in report.located where target.blankable != (target.gradable && target.kind == .article) {
                failures.append("\(story.id) #\(target.index + 1) \(target.surface): blankable \(target.blankable) as a \(target.kind.rawValue)")
            }
            guard let golden = golden[story.id] else {
                lines.append("  golden ✗ none: add this story to KasusFixtures.golden")
                failures.append("\(story.id) has no golden numbers")
                continue
            }
            let byCase = report.located.reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
            var misses: [String] = []
            if report.targets.count != golden.targets { misses.append("targets \(report.targets.count) ≠ \(golden.targets)") }
            for kasus in GrammarCase.allCases where byCase[kasus, default: 0] != golden.byCase[kasus, default: 0] {
                misses.append("\(kasus.short) \(byCase[kasus, default: 0]) ≠ \(golden.byCase[kasus, default: 0])")
            }
            for proof in KasusProof.allCases where report.proofTally[proof, default: 0] != golden.proofs[proof, default: 0] {
                misses.append("\(proof.rawValue) \(report.proofTally[proof, default: 0]) ≠ \(golden.proofs[proof, default: 0])")
            }
            if kinds[.contraction, default: 0] != golden.contractions {
                misses.append("contractions \(kinds[.contraction, default: 0]) ≠ \(golden.contractions)")
            }
            if kinds[.pronoun, default: 0] != golden.pronouns {
                misses.append("pronouns \(kinds[.pronoun, default: 0]) ≠ \(golden.pronouns)")
            }
            if labels.map(\.surface) != golden.labels {
                misses.append("labels [\(labels.map(\.surface).joined(separator: ", "))] ≠ [\(golden.labels.joined(separator: ", "))]")
            }
            if !report.warnings.isEmpty { misses.append("\(report.warnings.count) warnings") }
            lines.append(misses.isEmpty ? "  golden ✓" : "  golden ✗ " + misses.joined(separator: ", "))
            failures += misses.map { "\(story.id) golden: \($0)" }
        }

        for (title, set) in [("Fixtures (plan)", plan), ("Fixtures (extra)", extra), ("Fixtures (phase 2)", phase2)] {
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
        if let kinds = fixture.expectedKinds {
            let actual = report.located.map(\.kind)
            let wrongBlank = report.located.filter { $0.blankable != ($0.gradable && $0.kind == .article) }
            if actual != kinds || !wrongBlank.isEmpty {
                passed = false
                line += " · kinds \(actual.map(\.rawValue)) ≠ \(kinds.map(\.rawValue))"
                if !wrongBlank.isEmpty { line += " · blankable wrong on \(wrongBlank.map(\.surface))" }
            } else {
                line += " · \(actual.filter(\.isSpotOnly).isEmpty ? "all blankable" : "spot-only " + report.located.filter { $0.kind.isSpotOnly }.map(\.surface).joined(separator: ", "))"
            }
        }
        if !passed || codes.count != raised.count {
            line += " · raised [\(raised.map(\.rawValue).joined(separator: ", "))]"
            let messages = report.errors.filter { !$0.code.isStoryLevel }.map(\.message)
            if !messages.isEmpty { line += " · " + messages.joined(separator: " | ") }
        }
        return (passed, line)
    }

    /// The der-word endings as a teacher's table writes them (dieser, diese, dieses, diese …),
    /// kept apart from the engine's derivation from the definite article.
    private static let derWordTable: [GrammarCase: [String]] = [
        .nominativ: ["er", "e", "es", "e"],
        .akkusativ: ["en", "e", "es", "e"],
        .dativ:     ["em", "er", "em", "en"],
        .genitiv:   ["es", "er", "es", "er"],
    ]

    /// Every cell of the endings table, for every family: the engine's form matches
    /// `GrammarCase.article` / `einEnding` (or the der-word table), parses back to its family and
    /// stem (capitalised too), and `compatibleCases` returns exactly the cases that share it. ein
    /// and jeder have no plural.
    static func roundTrip() -> (cells: Int, failures: [String]) {
        var cells = 0
        var failures: [String] = []
        let families: [(KasusFamily, String)] = [(.definite, ""), (.ein, "ein"), (.kein, "kein")]
            + KasusForms.possessiveStems.map { (.possessive, $0) }
            + KasusForms.derWordStems.map { (.derWord, $0) }
        for (family, stem) in families {
            for genus in Gender.allCases {
                var byForm: [String: Set<GrammarCase>] = [:]
                for kasus in GrammarCase.allCases {
                    let ending = kasus.einEnding(genus)
                    let column = Gender.allCases.firstIndex(of: genus) ?? 0
                    let table: String? = switch family {
                    case .definite: kasus.article(genus)
                    case .ein where genus == .plural: nil
                    case .derWord where stem == "jed" && genus == .plural: nil
                    case .derWord: stem + (derWordTable[kasus]?[column] ?? "?")
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
            if family == .ein || (family == .derWord && stem == "jed") {
                for form in KasusForms.fullFamilyOptions(family: family, stem: stem, includeGenitive: true)
                where !KasusForms.compatibleCases(determiner: form, genus: .plural).isEmpty {
                    failures.append("„\(form)“ fits a plural noun, but \(stem) has no plural")
                }
            }
        }
        return (cells, failures)
    }

    // MARK: - Building

    private static func fixture(_ name: String, _ expected: KasusIssueCode?, _ text: String,
                                _ targets: [KasusTargetSpec], proofs: [KasusProof]? = nil,
                                kinds: [KasusTargetKind]? = nil, notTargets: [KasusNotTarget] = []) -> KasusFixture {
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
            notTargets: notTargets
        )
        return KasusFixture(name: name, expected: expected, expectedProofs: proofs, expectedKinds: kinds, story: story)
    }

    private static func target(_ phrase: String, _ kasus: GrammarCase, _ genus: Gender, _ lemma: String,
                               _ reason: KasusReason, _ trigger: String) -> KasusTargetSpec {
        KasusTargetSpec(phrase: phrase, kasus: kasus, genus: genus, lemma: lemma, reason: reason, trigger: trigger)
    }
}
#endif
