//
//  KasusValidatorTests.swift
//  german-ai-flashcardsTests
//
//  The answer key. Every planted-error fixture must raise exactly its code, every bundled story
//  must pass with its golden numbers against the app's real lexicon, and the located targets keep
//  the contract the views are written against (`KasusLocatedTarget`'s table).
//

import Foundation
import Testing
@testable import Die_Kartei

/// The three fixture sets, as a nonisolated argument: `KasusFixtures` itself is main-actor
/// isolated, which `@Test(arguments:)` can't read.
nonisolated enum FixtureSet: String, CaseIterable, Sendable {
    case plan, extra, phase2

    @MainActor var fixtures: [KasusFixture] {
        switch self {
        case .plan:   KasusFixtures.plan
        case .extra:  KasusFixtures.extra
        case .phase2: KasusFixtures.phase2
        }
    }
}

@Suite("Kasus validator")
struct KasusValidatorTests {

    // MARK: Fixtures

    @Test("Every planted-error fixture raises exactly its code", arguments: FixtureSet.allCases)
    func fixtures(_ set: FixtureSet) {
        for fixture in set.fixtures {
            let report = KasusValidator.validate(fixture.story, source: .authored, lexicon: KasusTestData.lexicon)
            // A fixture is one short paragraph, so the story.* rules (length, cases per unit) don't apply.
            let raised = Set(report.errors.map(\.code).filter { !$0.isStoryLevel })
            let expected: Set<KasusIssueCode> = fixture.expected.map { [$0] } ?? []
            #expect(raised == expected, "\(fixture.name)\n\(report.issueLines.joined(separator: "\n"))")
            if let proofs = fixture.expectedProofs {
                #expect(report.located.map(\.proof) == proofs, "\(fixture.name)")
            }
            if let kinds = fixture.expectedKinds {
                #expect(report.located.map(\.kind) == kinds, "\(fixture.name)")
            }
            for target in report.located {
                #expect(target.blankable == (target.gradable && target.kind == .article),
                        "\(fixture.name) #\(target.index + 1) \(target.surface) as a \(target.kind.rawValue)")
            }
        }
    }

    @Test("The fixture sets keep their size")
    func fixtureCounts() {
        #expect(KasusFixtures.plan.count == 11, "one per row of the plan's verification table")
        #expect(KasusFixtures.extra.count == 12)
        #expect(KasusFixtures.phase2.count == 23)
    }

    // MARK: Bundled stories

    @Test("Every bundled story passes with its golden numbers", arguments: BundledStories.ids)
    func bundledStory(_ id: String) throws {
        let story = try #require(KasusTestData.story(id))
        let report = KasusTestData.report(story)
        #expect(report.passes, "\(report.summaryLine)\n\(report.issueLines.joined(separator: "\n"))")
        #expect(report.warnings.isEmpty, "\(report.issueLines.joined(separator: "\n"))")

        let golden = try #require(KasusFixtures.golden[id], "add \(id) to KasusFixtures.golden")
        #expect(report.targets.count == golden.targets)
        #expect(report.located.count == golden.targets, "every target is found in the text")
        let byCase = report.located.reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
        for kasus in GrammarCase.allCases {
            #expect(byCase[kasus, default: 0] == golden.byCase[kasus, default: 0], "\(kasus.name) targets")
        }
        for proof in KasusProof.allCases {
            #expect(report.proofTally[proof, default: 0] == golden.proofs[proof, default: 0], "\(proof.rawValue) proofs")
        }
        #expect(report.kindTally[.contraction, default: 0] == golden.contractions, "contractions")
        #expect(report.kindTally[.pronoun, default: 0] == golden.pronouns, "pronouns")
        #expect(report.located.filter { $0.proof == .label }.map(\.surface) == golden.labels,
                "the label-proven targets a teacher checks")
    }

    @Test("Every bundled story is well-formed", arguments: BundledStories.ids)
    func storyShape(_ id: String) throws {
        let story = try #require(KasusTestData.story(id))
        #expect(story.unit != nil, "unit \(story.unitRaw)")
        #expect(story.cefr != nil, "level \(story.level)")
        #expect(story.question.options.indices.contains(story.question.answer))
        #expect(story.paragraphs.allSatisfy { !$0.de.isEmpty && !$0.en.isEmpty })
        #expect(story.reviewed.by.isEmpty == story.reviewed.date.isEmpty, "reviewed needs both who and when")
        #expect(id.hasPrefix("ks-"))
    }

    @Test("Every story has golden numbers, and the ids are unique")
    func goldenCoverage() {
        #expect(!BundledStories.ids.isEmpty, "kasus_stories.json is missing from the app bundle")
        #expect(Set(BundledStories.ids).count == BundledStories.ids.count)
        #expect(Set(KasusFixtures.golden.keys) == Set(BundledStories.ids))
    }

    @Test("Located targets keep the contract the views rely on", arguments: BundledStories.ids)
    func locatedContract(_ id: String) throws {
        let story = try #require(KasusTestData.story(id))
        for target in KasusTestData.report(story).located {
            let label = "#\(target.index + 1) \(target.surface)"
            let paragraph = story.paragraphs[target.paragraphIndex].de as NSString
            #expect(NSMaxRange(target.range) <= paragraph.length, "\(label) range")
            #expect(paragraph.substring(with: target.range) == target.surface, "\(label) surface")
            #expect(paragraph.substring(with: target.determinerRange) == target.determiner, "\(label) determiner")
            #expect(paragraph.substring(with: target.nounRange) == target.noun, "\(label) noun")
            #expect(NSMaxRange(target.sentenceRange) <= paragraph.length, "\(label) sentence")
            #expect(target.candidates.contains(target.kasus), "\(label) candidates")
            #expect(target.blankable == (target.gradable && target.kind == .article), "\(label) blankable")
            switch target.kind {
            case .article:
                #expect(target.parsed != nil, "\(label) parsed")
                #expect(target.contractedArticle == nil)
                #expect(target.caseForm == target.determiner.lowercased())
            case .contraction:
                #expect(target.parsed == nil, "\(label) parsed")
                #expect(target.contractedArticle != nil, "\(label) contracted article")
                #expect(target.preposition != nil, "\(label) preposition")
                #expect(!target.blankable)
            case .pronoun:
                #expect(target.parsed == nil, "\(label) parsed")
                #expect(target.determinerRange == target.range && target.nounRange == target.range, "\(label) ranges")
                #expect(!target.hasNounGender)
                #expect(!target.blankable)
            }
        }
    }

    @Test("The debugVerify report reads ALL OK")
    func debugVerifyReport() {
        let result = KasusFixtures.verify(stories: KasusTestData.stories, lexicon: KasusTestData.lexicon)
        #expect(result.failures.isEmpty, "\(result.failures.joined(separator: "\n"))")
        #expect(result.text.hasSuffix("ALL OK"))
        #expect(result.text.contains("ks-dat-a2-schluessel OK · 26 targets · form 20 · preposition 2 · copula 0 · label 4 · 0 errors"))
    }

    // MARK: Policy

    @Test("A generated story may not lean on labels")
    func generatedPolicy() throws {
        let story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        let report = KasusValidator.validate(story, source: .generated, lexicon: KasusTestData.lexicon)
        #expect(report.passes, "\(report.issueLines.joined(separator: "\n"))")
        for target in report.located {
            if target.proof == .label { #expect(!target.gradable, "#\(target.index + 1) \(target.surface) is label-proven") }
            if case .verified = target.genderVerdict {} else {
                #expect(!target.gradable, "#\(target.index + 1) \(target.surface) has no verified gender")
            }
        }
        let authored = KasusTestData.report(story)
        #expect(report.located.filter(\.gradable).count < authored.located.filter(\.gradable).count)
    }

    @Test("Story-level rules: cases per unit, length per level")
    func storyRules() {
        func story(unit: String, level: String, _ targets: [KasusTargetSpec]) -> KasusStory {
            KasusStory(id: "test", unitRaw: unit, level: level, source: .authored,
                       reviewed: .init(by: "", date: ""), title: "", titleEnglish: "",
                       question: .init(de: "", en: "", options: [""], answer: 0),
                       paragraphs: [.init(de: "Ich helfe dem Mann.", en: "")], targets: targets, notTargets: [])
        }
        let dem = KasusTargetSpec(phrase: "dem Mann", kasus: .dativ, genus: .der, lemma: "Mann",
                                  reason: .dativeVerb, trigger: "helfe")
        func codes(_ story: KasusStory, _ source: KasusStorySource) -> [KasusIssueCode: KasusIssue.Severity] {
            KasusValidator.validate(story, source: source, lexicon: KasusTestData.lexicon).storyIssues
                .reduce(into: [:]) { $0[$1.code] = $1.severity }
        }

        let short = story(unit: "dativ", level: "A2", [dem])
        #expect(codes(short, .authored) == [.unitCaseCount: .error, .wordCount: .warning],
                "one Dativ target, four words")
        #expect(codes(short, .generated) == [.unitCaseCount: .error, .wordCount: .error])
        #expect(codes(story(unit: "alleFaelle", level: "A2", [dem]), .authored)[.unitCaseCount] == .error)
        #expect(codes(story(unit: "nirgends", level: "A2", [dem]), .authored)[.unitCaseCount] == .error)
        #expect(codes(story(unit: "dativ", level: "Z9", [dem]), .authored)[.wordCount] == .warning)
    }

    @Test("Severity and rejection by source")
    func severities() {
        typealias Policy = KasusValidator.Policy
        #expect(Policy.severity(of: .lexConflict, source: .authored) == .warning)
        #expect(Policy.severity(of: .lexUnverified, source: .generated) == .warning)
        #expect(Policy.severity(of: .wordCount, source: .authored) == .warning)
        #expect(Policy.severity(of: .wordCount, source: .generated) == .error)
        #expect(Policy.severity(of: .untargetedDeterminer, source: .authored) == .error)
        #expect(Policy.severity(of: .untargetedDeterminer, source: .generated) == .warning)
        #expect(Policy.severity(of: .caseMismatch, source: .authored) == .error)

        let rejecting: Set<KasusIssueCode> = [.impossibleForm, .caseMismatch, .pluralForm, .nDeklination, .genitiveS,
                                              .triggerPrepositionCase, .triggerWechselVerb, .lexGender,
                                              .unitCaseCount, .wordCount]
        for code in KasusIssueCode.allCases {
            #expect(Policy.rejectsGeneratedStory(code) == rejecting.contains(code), "\(code.rawValue)")
        }
    }

    @Test("Issue codes are stable histogram keys")
    func issueCodes() {
        #expect(KasusIssueCode.allCases.map(\.rawValue) == [
            "locate.notFound", "np.unknownDeterminer", "morph.impossibleForm", "morph.caseMismatch",
            "morph.pluralForm", "morph.nDeklination", "morph.genitiveS", "lex.gender", "lex.conflict",
            "lex.unverified", "trigger.missing", "trigger.prepositionCase", "trigger.wechselVerb",
            "reason.caseMismatch", "coverage.untargetedDeterminer", "story.unitCaseCount", "story.wordCount",
        ])
    }
}
