//
//  KasusGenerationTests.swift
//  german-ai-flashcardsTests
//
//  Phase 3: tutor-written Kasus stories, with the model replaced by canned output (MLX doesn't run
//  in the simulator). The planner only plans phrases the validator can prove, the check places
//  them verbatim with their verb and harvests the rest, the gate rejects wrong German, contract B's
//  labels are scored against the form, and a passing story round-trips through the store and plays
//  like a bundled one.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

/// The units, as a nonisolated argument for `@Test(arguments:)`.
nonisolated enum GenerationUnit: String, CaseIterable, Sendable {
    case nominativ, akkusativ, dativ, genitiv, alleFaelle

    @MainActor var unit: KasusUnit { KasusUnit(rawValue: rawValue)! }
}

@Suite("Kasus story generation")
struct KasusGenerationTests {

    private let lexicon = KasusTestData.lexicon

    private func plan(_ unit: KasusUnit, _ level: CEFRLevel, _ seed: UInt64, governed: Bool = false) -> KasusStoryPlan {
        KasusStoryPlanner.plan(unit: unit, level: level, seed: seed, governed: governed, lexicon: lexicon)
    }

    private func check(_ unit: KasusUnit, _ raw: String) -> KasusCheckResult {
        KasusStoryCheck.run(raw: raw, plan: KasusGenerationFixtures.plan(for: unit), storyID: "kg-test", lexicon: lexicon)
    }

    private func explain(_ result: KasusCheckResult) -> String {
        ([result.summaryLine] + (result.report?.issueLines ?? [])
            + result.placements.map { "\($0.status.rawValue) \($0.expression) \($0.found ?? "")" }
            + result.harvest.map { "\($0.surface): \($0.verdict)" }).joined(separator: "\n")
    }

    // MARK: - Planner

    @Test("The same seed always gives the same plan")
    func plannerDeterminism() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for unit in KasusUnit.allCases {
            for seed: UInt64 in [0, 1, 42, 9_007_199] {
                let a = plan(unit, .b1, seed), b = plan(unit, .b1, seed)
                #expect(a == b, "\(unit.rawValue) seed \(seed)")
                #expect(try encoder.encode(a) == encoder.encode(b))
            }
        }
        let plans = (0..<10).map { plan(.dativ, .a2, UInt64($0)) }
        #expect(Set(plans.map(\.phrases)).count > 5, "different seeds plan different stories")
        #expect(KasusStoryPlan.retrySeed(after: 7) != 7)
        #expect(KasusStoryPlan.retrySeed(after: 7) == KasusStoryPlan.retrySeed(after: 7))
        #expect(KasusStoryPlan.randomSeed() < (1 << 53))
    }

    @Test("Every planned phrase is one the validator can prove")
    func provableFramesOnly() {
        for unit in KasusUnit.allCases {
            for level in [CEFRLevel.a1, .a2, .b1] {
                for seed in UInt64(0)..<12 {
                    let plan = plan(unit, level, seed)
                    for phrase in plan.phrases {
                        let label = "\(unit.rawValue) \(level.rawValue) #\(seed) „\(phrase.expression)“"
                        var cases = KasusForms.compatibleCases(determiner: phrase.determiner, genus: phrase.genus)
                        if let preposition = phrase.preposition {
                            cases.formIntersection(lexicon.prepositionCases(preposition) ?? [])
                            #expect(!KasusStoryPlanner.contracts(preposition, phrase.determiner), "\(label) would contract")
                        }
                        #expect(cases == [phrase.kasus], "\(label): form + preposition leave \(cases)")
                        #expect(lexicon.gender(forLemma: phrase.lemma) == .verified(phrase.genus), "\(label) gender")
                        #expect(!KasusForms.isNDeklination(phrase.lemma) && KasusForms.dualGenders(of: phrase.lemma) == nil,
                                "\(label) n-noun or dual gender")
                        #expect(phrase.expression == (phrase.preposition.map { "\($0) " } ?? "") + phrase.phrase, "\(label)")
                        #expect(phrase.frame.needsVerb == !phrase.verbForms.isEmpty, "\(label) verb forms")
                        #expect(phrase.reason.expectedCases(after: nil).map { $0.contains(phrase.kasus) } ?? true, "\(label)")
                        if phrase.kasus == .genitiv, phrase.genus != .die {
                            #expect(KasusForms.isGenitiveSingular(phrase.noun, of: phrase.lemma), "\(label) -(e)s")
                        }
                    }
                    #expect(Set(plan.phrases.map(\.lemma)).count == plan.phrases.count, "\(unit.rawValue) #\(seed) nouns repeat")
                }
            }
        }
    }

    @Test("Each unit plans its counts: 5–8 phrases, three of its case, mostly subjects for Nominativ")
    func unitCounts() {
        for unit in KasusUnit.allCases {
            for level in [CEFRLevel.a1, .a2, .b1] {
                for seed in UInt64(0)..<10 {
                    let plan = plan(unit, level, seed)
                    let label = "\(unit.rawValue) \(level.rawValue) #\(seed): \(plan.casesLine)"
                    let count = plan.phrases.count
                    #expect((5...8).contains(count), "\(label)")
                    #expect(KasusStoryPlanner.phraseCountRange(unit: unit, level: level, governed: false).contains(count), "\(label)")
                    let byCase = plan.phrases.reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
                    if let focus = unit.focusCase {
                        #expect(byCase[focus, default: 0] >= 3, "\(label)")
                        // Nominativ plans one Akkusativ object to tell its subjects apart from.
                        let allowed = Set(unit.casesInPlay + (unit == .nominativ ? [.akkusativ] : []))
                        #expect(Set(byCase.keys).isSubset(of: allowed), "\(label) plans a case not in play")
                    } else {
                        #expect(GrammarCase.allCases.allSatisfy { byCase[$0, default: 0] >= 2 }, "\(label)")
                    }
                    if unit == .nominativ {
                        #expect(plan.phrases.filter { $0.frame == .subject }.count >= count - 1, "\(label)")
                    }
                    #expect(plan.contract == .planned && plan.seed == seed && !plan.governed)
                }
            }
        }
        #expect(plan(.dativ, .a2, 3, governed: false).phrases.isEmpty == false)
        let contractB = KasusStoryPlanner.plan(unit: .dativ, level: .a2, seed: 3, governed: false,
                                               contract: .selfLabelled, lexicon: lexicon)
        #expect(contractB.phrases.isEmpty && contractB.contract == .selfLabelled)
    }

    @Test("Plans use the definite and ein articles, the two Endungen blanks, and both of them")
    func familyPreference() {
        var families = Set<KasusFamily>()
        for unit in KasusUnit.allCases {
            for seed in UInt64(0)..<8 {
                for phrase in plan(unit, .a2, seed).phrases {
                    let family = KasusForms.parseDeterminer(phrase.determiner)?.family
                    #expect(family == .definite || family == .ein, "„\(phrase.phrase)“")
                    if let family { families.insert(family) }
                }
            }
        }
        #expect(families == [.definite, .ein])
    }

    @Test("With the memory saver on: level at most A2, at most six phrases")
    func governedCaps() {
        for unit in KasusUnit.allCases {
            for level in [CEFRLevel.a1, .b1, .b2] {
                for seed in UInt64(0)..<6 {
                    let plan = plan(unit, level, seed, governed: true)
                    let label = "\(unit.rawValue) \(level.rawValue) #\(seed)"
                    #expect(plan.governed, "\(label)")
                    #expect(plan.phrases.count <= KasusStoryPlanner.governedMaxPhrases, "\(label)")
                    #expect(plan.level == (level == .a1 ? "A1" : "A2"), "\(label)")
                    if let focus = unit.focusCase {
                        #expect(plan.phrases.filter { $0.kasus == focus }.count >= 3, "\(label)")
                    }
                }
            }
        }
        #expect(plan(.genitiv, .b2, 1).level == "B1", "never above the word lists")
    }

    @Test("The learner's own nouns join the pool when their gender is verified")
    func learnerNouns() {
        let pool = KasusStoryPlanner.nounPool(bank: .bundled, level: .a1, learnerNouns: ["Hammer", "xyz", "Junge"],
                                              lexicon: lexicon, levelOf: KasusStoryPlanner.goetheLevel)
        let things = pool["things"]?.map(\.lemma) ?? []
        #expect(!things.contains("xyz"))
        #expect(!things.contains("Junge"), "n-nouns are skipped")
        #expect(!(pool["people"] ?? []).contains { $0.lemma == "Mann" }, "Mann is an A2 noun")
        #expect((pool["people"] ?? []).contains { $0.lemma == "Vater" })
    }

    // MARK: - The prompt

    @Test("The prompt carries every phrase with its verb and the level's constraints")
    func promptBuilder() {
        for unit in KasusUnit.allCases {
            let plan = plan(unit, .a2, 5)
            let prompt = KasusStoryPrompt.build(plan)
            #expect(prompt.system.contains("TITEL:") && prompt.system.contains("GESCHICHTE:"))
            #expect(prompt.user.contains(KasusStoryPrompt.phraseInstruction))
            #expect(prompt.user.contains(CEFRLevel.a2.storyConstraints))
            #expect(prompt.user.contains("Länge: 120–180 Wörter."))
            #expect(prompt.user.contains("Thema: \(plan.topic)"))
            for phrase in plan.phrases {
                #expect(prompt.user.contains("- \(phrase.expression)\(phrase.promptHint)\n")
                        || prompt.user.hasSuffix("- \(phrase.expression)\(phrase.promptHint)"), "„\(phrase.expression)“")
                if phrase.frame == .subject {
                    // The conjugated verb, never the infinitive („Der Bruder lachen laut.“).
                    #expect(phrase.verbShown != nil, "„\(phrase.expression)“")
                    #expect(phrase.promptHint == " (Subjekt: \(phrase.expression) \(phrase.verbShown ?? ""))", "„\(phrase.expression)“")
                    #expect(!phrase.promptHint.contains(phrase.verb ?? "–"))
                } else if let verb = phrase.verb {
                    #expect(phrase.promptHint.contains(verb))
                }
            }
            #expect(!prompt.user.contains("„den") && !prompt.user.contains("„dem"), "phrases are listed without quotes")
            #expect(KasusStoryPrompt.maxTokens(for: plan) == CEFRLevel.a2.storyMaxTokens)
        }
        let contractB = KasusStoryPlanner.plan(unit: .dativ, level: .a1, seed: 1, governed: false,
                                               contract: .selfLabelled, lexicon: lexicon)
        let prompt = KasusStoryPrompt.build(contractB)
        #expect(prompt.system.contains(KasusSelfLabels.heading))
        #expect(prompt.user.contains("den Ball | Akk") && prompt.user.contains("im Dativ"))
        #expect(!prompt.user.contains(KasusStoryPrompt.phraseInstruction))
        #expect(prompt.user.contains(CEFRLevel.a1.storyConstraints))
        #expect(KasusStoryPrompt.maxTokens(for: contractB) > CEFRLevel.a1.storyMaxTokens)
    }

    // MARK: - Locate, harvest, gate on canned output

    @Test("A good canned story places every phrase and passes", arguments: GenerationUnit.allCases)
    func goodFixture(_ unit: GenerationUnit) throws {
        let result = check(unit.unit, KasusGenerationFixtures.output(for: unit.unit, .good))
        #expect(result.passes, "\(explain(result))")
        #expect(result.placements.allSatisfy { $0.status == .placed }, "\(explain(result))")
        let report = try #require(result.report)
        #expect(report.errors.isEmpty, "\(explain(result))")
        if let focus = unit.unit.focusCase {
            #expect(report.gradableByCase[focus, default: 0] >= 3)
        }
        let story = try #require(result.story)
        #expect(story.source == .generated && story.id == "kg-test" && !story.hasQuestion && !story.hasEnglish)
        // Every planned target keeps its planned reason; every other target is inferred.
        let plannedPhrases = Set(KasusGenerationFixtures.plan(for: unit.unit).phrases.map(\.phrase))
        for target in report.located {
            if target.spec.reason == .inferred {
                #expect(target.proof == .form || target.proof == .preposition, "#\(target.index + 1) \(target.surface)")
            } else {
                #expect(plannedPhrases.contains(target.surface.prefix(1).lowercased() + target.surface.dropFirst()),
                        "#\(target.index + 1) \(target.surface)")
            }
            #expect(target.gradable, "#\(target.index + 1) \(target.surface)")
        }
    }

    @Test("An altered phrase is harvested instead, and the story still passes", arguments: GenerationUnit.allCases)
    func alteredFixture(_ unit: GenerationUnit) {
        let result = check(unit.unit, KasusGenerationFixtures.output(for: unit.unit, .altered))
        #expect(result.passes, "\(explain(result))")
        #expect(result.placements(.altered) == 1, "\(explain(result))")
        #expect(result.placements(.placed) == result.placements.count - 1)
    }

    @Test("One wrong article rejects the whole story", arguments: GenerationUnit.allCases)
    func wrongArticleFixture(_ unit: GenerationUnit) {
        let result = check(unit.unit, KasusGenerationFixtures.output(for: unit.unit, .wrongArticle))
        #expect(!result.passes, "\(explain(result))")
        #expect(result.rejectingCodes.contains { $0.isMorphology || $0 == .triggerPrepositionCase }, "\(explain(result))")
    }

    @Test("Too few gradable targets of the unit's case reject the story", arguments: GenerationUnit.allCases)
    func tooFewFixture(_ unit: GenerationUnit) {
        let result = check(unit.unit, KasusGenerationFixtures.output(for: unit.unit, .tooFew))
        #expect(!result.passes, "\(explain(result))")
        #expect(result.rejectingCodes == [.unitCaseCount], "\(explain(result))")
        #expect(result.placements.allSatisfy { $0.status == .missing || $0.status == .altered })
    }

    @Test("Altered: „ihrem Opa“ for „dem Opa“ becomes an inferred Dativ target")
    func alteredPhrase() throws {
        let result = check(.dativ, KasusGenerationFixtures.output(for: .dativ, .altered))
        let placement = try #require(result.placements.first { $0.expression == "dem Opa" })
        #expect(placement.status == .altered && placement.found == "ihrem Opa")
        let targets = try #require(result.report?.located.filter { $0.surface == "ihrem Opa" })
        #expect(targets.count == 2, "bei ihrem Opa, hilft ihrem Opa")
        #expect(targets.allSatisfy { $0.kasus == .dativ && $0.spec.reason == .inferred && $0.gradable })
        // A possessive is marked in Markieren but never becomes an Endungen gap.
        let playable = KasusService.prepare(try #require(result.story), lexicon: lexicon)
        let gaps = KasusService.endingGaps(in: playable, unit: .dativ, mixed: true, hint: .ohne)
        #expect(!gaps.contains { $0.target.surface == "ihrem Opa" })
        #expect(gaps.contains { $0.target.surface == "dem Kind" })
    }

    @Test("Trigger missing: the phrase stands but its verb doesn't, so it's harvested")
    func triggerMissing() throws {
        let raw = KasusGenerationFixtures.edit(KasusGenerationFixtures.dativGood,
                                               [("Mia hilft dem Opa gern.", "Mia sieht dem Opa gern zu.")])
        let result = check(.dativ, raw)
        #expect(result.passes, "\(explain(result))")
        let placement = try #require(result.placements.first { $0.expression == "dem Opa" })
        #expect(placement.status == .triggerMissing)
        let target = try #require(result.report?.located.first { $0.surface == "dem Opa" })
        #expect(target.spec.reason == .inferred && target.kasus == .dativ && target.gradable && target.blankable)
        #expect(target.spec.trigger.isEmpty && target.triggerRange == nil)
        #expect(result.report?.errors.isEmpty == true, "an inferred target needs no verb")
    }

    @Test("„mit den Hund“ rejects the story with trigger.prepositionCase")
    func mitDenHund() throws {
        let result = check(.dativ, KasusGenerationFixtures.output(for: .dativ, .wrongArticle))
        #expect(!result.passes)
        #expect(result.rejectingCodes.contains(.triggerPrepositionCase), "\(explain(result))")
        let wrong = try #require(result.harvest.first { $0.surface == "den Hund" })
        #expect(wrong.isWrong && wrong.preposition == "mit" && wrong.kasus == .akkusativ)
        #expect(result.placements.first { $0.expression == "mit dem Hund" }?.status == .altered)
    }

    @Test("An unplanned ambiguous phrase is never graded: not a target, not counted in Markieren")
    func unplannedAmbiguous() throws {
        let result = check(.dativ, KasusGenerationFixtures.dativGood)
        let zeitung = try #require(result.harvest.first { $0.surface == "die Zeitung" })
        #expect(zeitung.unverifiable == .ambiguousCase)
        #expect(result.report?.located.contains { $0.surface == "die Zeitung" } == false)
        let spielzeug = try #require(result.harvest.first { $0.surface == "das Spielzeug" })
        #expect(spielzeug.unverifiable == .ambiguousCase)

        let story = try #require(result.story)
        let playable = KasusService.prepare(story, lexicon: lexicon)
        let words = playable.numbered.words.filter { $0.text == "die" || $0.text == "Zeitung" }
        #expect(words.count == 2)
        #expect(words.allSatisfy { $0.role == .ungraded(.unchecked, target: nil) })
        // Marked in the Dativ round, they are neither right nor wrong.
        var round = KasusMarkRound(kasus: .dativ, text: playable.numbered, mode: .amEnde)
        for word in words { round.tap(word.id) }
        round.check()
        #expect(round.score.wrong == 0 && round.score.right == 0)
        #expect(words.allSatisfy { round.verdict(for: $0.id) == .notCounted(.unchecked) })
    }

    @Test("An unplanned provable phrase becomes a target explained by form and preposition only")
    func unplannedProvable() throws {
        let result = check(.dativ, KasusGenerationFixtures.dativGood)
        let report = try #require(result.report)
        let story = try #require(result.story)
        let ruecken = try #require(report.located.first { $0.surface == "dem Rücken" })
        #expect(ruecken.spec.reason == .inferred && ruecken.kasus == .dativ && ruecken.gradable && ruecken.blankable)
        #expect(ruecken.proof == .form && ruecken.preposition?.word == "mit" && ruecken.spec.trigger == "mit")
        let kueche = try #require(report.located.first { $0.surface == "der Küche" })
        #expect(kueche.proof == .preposition && kueche.kasus == .dativ)
        let sofa = try #require(report.located.first { $0.surface == "das Sofa" })
        #expect(sofa.kasus == .akkusativ, "„springt auf das Sofa“: a direction")

        for target in report.located where target.spec.reason == .inferred {
            let explanation = KasusExplanation.explanation(for: target, in: story)
            #expect(RichMarkup.problems(explanation).isEmpty, "\(target.surface): \(explanation)")
            let rule = KasusExplanation.inferredLine(for: target)
            #expect(!rule.contains("subject") && !rule.contains("object") && !rule.contains("receiver"),
                    "\(target.surface): \(rule)")
        }
        #expect(KasusRich.plain(KasusExplanation.inferredLine(for: ruecken)) == "mit always takes the Dativ: dem + a masculine noun.")
        // No position verb confirms a place („sucht … in der Küche“): the line doesn't claim Wo?,
        // and the phrase is marked but never blanked.
        #expect(KasusRich.plain(KasusExplanation.inferredLine(for: kueche))
                == "By its form, der could be Dativ or Genitiv, and in takes only Akkusativ or Dativ: so Dativ.")
        #expect(kueche.gradable && !kueche.blankable)
        let plain = try #require(report.located.first { $0.surface == "Der Ball" })
        #expect(KasusRich.plain(KasusExplanation.inferredLine(for: plain))
                == "der + a masculine noun can only be Nominativ: the article's form shows the case.")
    }

    @Test("The harvest never reads a relative pronoun or a plural form as a singular article")
    func harvestGuards() {
        let nouns = KasusNounIndex(lexicon: lexicon)
        func verdicts(_ text: String) -> [String: KasusHarvestedPhrase.Verdict] {
            KasusHarvest.harvest(paragraphs: [text], nouns: nouns, lexicon: lexicon)
                .reduce(into: [:]) { $0[$1.surface] = $1.verdict }
        }
        #expect(verdicts("Der Mann, der Kaffee trinkt, ist nett.")["der Kaffee"] == .unverifiable(.relative))
        #expect(verdicts("Das Haus, in dem Kinder spielen, ist alt.")["dem Kinder"] == .unverifiable(.relative))
        #expect(verdicts("Er spielt mit dem Kinder.")["dem Kinder"] == .wrong, "Kinder is plural: „dem Kinder“ is wrong")
        #expect(verdicts("Er spielt mit den Kindern.")["den Kindern"] == .proven)
        #expect(verdicts("Ich sehe die Kinder.")["die Kinder"] == .unverifiable(.ambiguousCase))
        #expect(verdicts("Er wartet wegen des Mann.")["des Mann"] == .wrong)
        #expect(verdicts("Das ist das Auto des Vaters.")["des Vaters"] == .proven)
        #expect(verdicts("Ich suche das Tasche.")["das Tasche"] == .wrong)
        #expect(verdicts("Ich gebe ihr Blumen.")["ihr Blumen"] == .unverifiable(.notAnArticle))
        #expect(verdicts("Er kommt um ein Uhr.")["ein Uhr"] == .unverifiable(.time))
        #expect(verdicts("Er kauft einen großen Hund.")["einen großen Hund"] == .unverifiable(.adjective))
        #expect(verdicts("Er hilft dem Jungen.")["dem Jungen"] == .unverifiable(.nNoun))
        #expect(verdicts("Sie wohnt bei Frau Meier.").isEmpty)
    }

    @Test("A position verb in the other half of „und“ doesn't reject an inferred target")
    func coordinatedWechsel() throws {
        let fine = KasusGenerationFixtures.edit(KasusGenerationFixtures.dativGood,
                                                [("Sie bringt ihm einen Tee", "Er sitzt da und wartet auf den Kaffee. Sie bringt ihm einen Tee")])
        let result = check(.dativ, fine)
        #expect(result.passes, "\(explain(result))")
        let wrong = KasusGenerationFixtures.edit(KasusGenerationFixtures.dativGood,
                                                 [("Er springt sofort auf das Sofa.", "Die Katze liegt auf den Stuhl.")])
        let rejected = check(.dativ, wrong)
        #expect(!rejected.passes)
        #expect(rejected.rejectingCodes.contains(.triggerWechselVerb), "\(explain(rejected))")
    }

    @Test("Markdown around a phrase comes off before locating")
    func markdownStripped() {
        let bold = KasusGenerationFixtures.dativGood
            .replacingOccurrences(of: "mit dem Hund im Park", with: "mit **dem Hund** im Park")
            .replacingOccurrences(of: "TITEL:", with: "**TITEL:**")
        let result = check(.dativ, bold)
        #expect(result.passes, "\(explain(result))")
        #expect(result.placements.first { $0.expression == "mit dem Hund" }?.status == .placed)
        #expect(result.title == "Wo ist der Ball?")
        #expect(check(.dativ, "").story == nil)
    }

    // MARK: - Contract B

    @Test("Contract B's label lines parse however the model bends them")
    func labelParsing() {
        let labels = KasusSelfLabels.parse("""
        den Ball | Akk
        - dem Opa | Dativ
        3. die Zeitung: Akkusativ
        „der Vater“ – Nominativ
        des Regens = Gen
        Quatsch ohne Fall
        der Hund | ?

        """)
        #expect(labels.map(\.phrase) == ["den Ball", "dem Opa", "die Zeitung", "der Vater", "des Regens", "Quatsch ohne Fall", "der Hund"])
        #expect(labels.map(\.kasus) == [.akkusativ, .dativ, .akkusativ, .nominativ, .genitiv, nil, nil])
        #expect(KasusSelfLabels.caseName("accusative") == .akkusativ)
        #expect(KasusSelfLabels.caseName("D") == .dativ)
        #expect(KasusSelfLabels.caseName("Plural") == nil)
    }

    @Test("Contract B is scored against the cases the form proves")
    func labelScoring() throws {
        let raw = KasusGenerationFixtures.dativGood + """

        FÄLLE:
        den Ball | Akk
        dem Opa | Akk
        die Zeitung | Akk
        mit dem Hund | Dat
        der Hut | Nom
        irgendwas
        """
        var plan = KasusStoryPlanner.plan(unit: .dativ, level: .a2, seed: 1, governed: false,
                                          contract: .selfLabelled, lexicon: lexicon)
        plan = KasusStoryPlan(unitRaw: plan.unitRaw, level: plan.level, seed: plan.seed, governed: false,
                              contract: .selfLabelled, topic: plan.topic, genreRaw: plan.genreRaw, phrases: [])
        let result = KasusStoryCheck.run(raw: raw, plan: plan, storyID: "kg-b", lexicon: lexicon)
        let labels = try #require(result.labels)
        #expect(labels.correct == 2, "den Ball, mit dem Hund · \(labels)")
        #expect(labels.wrong == 1, "dem Opa is Dativ")
        #expect(labels.unverifiable == 1, "die Zeitung could be Nom or Akk")
        #expect(labels.notInStory == 1)
        #expect(labels.unparseable == 1)
        #expect(labels.accuracy == 2.0 / 3.0)
        #expect(labels.unverifiableShare == 0.25)
        #expect(labels.mismatches == ["dem Opa: Akk, form says Dat"])
        #expect(labels.unlabelledProven > 0)
        let story = try #require(result.story)
        #expect(!story.paragraphs.contains { $0.de.contains("|") }, "the label block isn't story text")
        #expect(result.passes, "\(explain(result))")
        #expect(result.summaryLine.contains("labels 2/3 right"))
    }

    // MARK: - Generator

    @Test("The generator plays a good story on the first try")
    func generatorGood() async throws {
        let generator = KasusStoryGenerator(writer: KasusGenerationFixtures.writer(for: .dativ, .good), lexicon: lexicon)
        let result = await generator.generate(KasusGenerationFixtures.request(for: .dativ))
        #expect(result.outcome == .generated)
        #expect(result.attempts.count == 1 && result.passedFirstTry && result.note == nil)
        #expect(result.story?.source == .generated && result.story?.unitRaw == "dativ")
        #expect(result.modelID == "canned:good" && !result.governed)
        #expect(generator.phase == .finished && !generator.isRunning)
    }

    @Test("Two failed checks fall back to a bundled story of the unit, with the note")
    func generatorFallback() async throws {
        let writer = KasusGenerationFixtures.writer(for: .dativ, .wrongArticle)
        let generator = KasusStoryGenerator(writer: writer, lexicon: lexicon)
        var request = KasusGenerationFixtures.request(for: .dativ)
        request.fallbackStoryID = "ks-dat-a2-umzug"
        let result = await generator.generate(request)
        #expect(result.outcome == .fallback)
        #expect(result.attempts.count == 2 && writer.writes == 2 && !result.passedAfterRetry)
        #expect(result.note == KasusStoryGenerator.fallbackNote)
        #expect(result.story?.id == "ks-dat-a2-umzug" && result.story?.source == .authored)

        request.fallbackStoryID = "ks-nom-a1-foto"   // another unit's: the unit's first instead
        let other = await KasusStoryGenerator(writer: KasusGenerationFixtures.writer(for: .dativ, .tooFew),
                                              lexicon: lexicon).generate(request)
        #expect(other.outcome == .fallback && other.story?.unitRaw == "dativ")
    }

    @Test("The retry plans again with the next seed")
    func generatorRetrySeed() async throws {
        let writer = KasusCannedWriter(texts: [KasusGenerationFixtures.tooFewA2])
        let generator = KasusStoryGenerator(writer: writer, lexicon: lexicon)
        let result = await generator.generate(KasusGenerationRequest(unit: .dativ, level: .a2, seed: 11))
        #expect(result.outcome == .fallback && result.attempts.count == 2)
        #expect(result.attempts[0].plan.seed == 11)
        #expect(result.attempts[1].plan.seed == KasusStoryPlan.retrySeed(after: 11))
        #expect(result.attempts[0].plan != result.attempts[1].plan)
        #expect(result.attempts[1].user.contains(KasusStoryPrompt.phraseInstruction))
    }

    @Test("A governed tutor gets the capped plan")
    func generatorGoverned() async {
        let writer = KasusCannedWriter(texts: [KasusGenerationFixtures.tooFewA2], memorySaverActive: true)
        let result = await KasusStoryGenerator(writer: writer, lexicon: lexicon)
            .generate(KasusGenerationRequest(unit: .genitiv, level: .b1, seed: 4, retries: 0))
        #expect(result.governed && result.attempts.count == 1)
        #expect(result.attempts[0].plan.level == "A2" && result.attempts[0].plan.phrases.count <= 6)
    }

    @Test("A load refusal is a failure with the bundled story on offer")
    func generatorPrepareFailure() async {
        let writer = KasusCannedWriter(texts: [KasusGenerationFixtures.dativGood])
        writer.prepareFailure = "Pictures are being drawn right now. The tutor loads once they finish."
        let result = await KasusStoryGenerator(writer: writer, lexicon: lexicon)
            .generate(KasusGenerationFixtures.request(for: .dativ))
        #expect(result.outcome == .failed && result.attempts.isEmpty && writer.writes == 0)
        #expect(result.note == writer.prepareFailure && result.story?.unitRaw == "dativ")
    }

    @Test("Cancel ends the run")
    func generatorCancel() async {
        let writer = KasusGenerationFixtures.writer(for: .dativ, .good, delay: .milliseconds(400))
        let generator = KasusStoryGenerator(writer: writer, lexicon: lexicon)
        let task = Task { await generator.generate(KasusGenerationFixtures.request(for: .dativ)) }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(generator.isRunning)
        generator.cancel()
        let result = await task.value
        #expect(result.outcome == .cancelled && result.story == nil)
    }

    @Test("Availability: hidden with the toggle off, never a model the device can't run")
    func availability() {
        #expect(KasusStoryGenerator.availability(selectedStoryModel: .hero, enabled: false) == .hidden)
        let offline = ModelReadiness(appleIntelligence: false, tutor: nil, fittingTutor: nil, hasImageModel: false)
        let answer = KasusStoryGenerator.availability(selectedStoryModel: .hero, readiness: offline, enabled: true)
        switch answer {
        case .ready:                  Issue.record("no tutor is on disk")
        case .hidden:                 Issue.record("the toggle is on")
        case .needsDownload(let m):   #expect(MLXModel.germanTutors.contains(m))
        case .tooSmall:               break
        }
        #expect(KasusStoryGenerator.defaultEnabled, "on by default in DEBUG")
    }

    // MARK: - Storage

    @Test("A generated story round-trips through the store and plays like a bundled one")
    func storeRoundTrip() async throws {
        let container = try ModelContainer(for: GeneratedKasusStory.self, KasusRound.self,
                                           configurations: SwiftData.ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let generator = KasusStoryGenerator(writer: KasusGenerationFixtures.writer(for: .dativ, .good), lexicon: lexicon)
        let result = await generator.generate(KasusGenerationFixtures.request(for: .dativ))
        let saved = try #require(KasusStoryStore.save(result, in: context))
        let story = try #require(result.story)

        let rows = KasusStoryStore.stories(for: .dativ, in: context)
        #expect(rows.count == 1 && rows.first?.id == story.id)
        #expect(KasusStoryStore.stories(for: .akkusativ, in: context).isEmpty)
        #expect(saved.story == story && saved.plan == result.passing?.plan)
        #expect(saved.unitRaw == "dativ" && saved.level == "A2" && saved.modelID == "canned:good")
        #expect(saved.title == story.title && saved.attempts == 1 && saved.validatorSummary.hasPrefix("PASS"))
        #expect(KasusStoryStore.story(id: story.id, in: context) == story)
        #expect(KasusStoryStore.bank(in: context).story(id: story.id) == story)
        #expect(KasusStoryStore.bank(in: context).stories.count == KasusStoryBank.bundled.stories.count + 1)

        let session = KasusSession(generated: story, unit: .dativ)
        #expect(session.storyID == story.id && session.story == story)
        let playable = try #require(KasusService.prepare(session))
        #expect(playable.report.passes)
        #expect(playable.gradable.count == result.passing?.check?.report?.located.filter(\.gradable).count)
        #expect(!KasusMarking.cases(for: .dativ, in: playable.numbered).isEmpty)

        let failed = await KasusStoryGenerator(writer: KasusGenerationFixtures.writer(for: .dativ, .tooFew), lexicon: lexicon)
            .generate(KasusGenerationFixtures.request(for: .dativ))
        #expect(KasusStoryStore.save(failed, in: context) == nil, "a fallback is never saved")

        KasusStoryStore.delete(saved, in: context)
        #expect(KasusStoryStore.stories(for: .dativ, in: context).isEmpty)
    }

    // MARK: - Debug plumbing and the Lab

    @Test("-kasus.debugGenerate reads its unit and fixture")
    func debugLaunchArguments() throws {
        let defaults = try #require(UserDefaults(suiteName: "kasus.debugGenerate.test"))
        defer { defaults.removePersistentDomain(forName: "kasus.debugGenerate.test") }
        #expect(KasusGenerateDebug.fromLaunchArguments(defaults) == nil)
        defaults.set("Dativ", forKey: KasusGenerateDebug.unitKey)
        #expect(KasusGenerateDebug.fromLaunchArguments(defaults) == .init(unit: .dativ, fixture: .good))
        defaults.set("alle", forKey: KasusGenerateDebug.unitKey)
        defaults.set("wrongarticle", forKey: KasusGenerateDebug.fixtureKey)
        #expect(KasusGenerateDebug.fromLaunchArguments(defaults) == .init(unit: .alleFaelle, fixture: .wrongArticle))
        defaults.set("nirgends", forKey: KasusGenerateDebug.unitKey)
        #expect(KasusGenerateDebug.fromLaunchArguments(defaults) == nil)
    }

    @Test("The Lab exports one JSONL line per attempt and summarises per model")
    func labExport() async throws {
        var runs: [KasusLabRun] = []
        for kind in [KasusCannedOutput.good, .wrongArticle] {
            let result = await KasusStoryGenerator(writer: KasusGenerationFixtures.writer(for: .dativ, kind), lexicon: lexicon)
                .generate(KasusGenerationFixtures.request(for: .dativ))
            runs.append(KasusLabRun(result: result, readsRight: kind == .good))
        }
        let lines = KasusLab.jsonl(runs).split(separator: "\n")
        #expect(lines.count == 3, "one good attempt, two failed ones")
        let records = try lines.map { try JSONDecoder().decode(KasusLabRecord.self, from: Data($0.utf8)) }
        #expect(records[0].passed && records[0].placements6)
        #expect(records[1].report.errorCodes["trigger.prepositionCase"] != nil)
        #expect(records.allSatisfy { !$0.raw.isEmpty && $0.plan.phrases.count == 6 && $0.unit == "dativ" })

        let summaries = KasusLab.summaries(runs)
        #expect(summaries.count == 2, "canned:good and canned:wrongArticle")
        let good = try #require(summaries.first { $0.modelID == "canned:good" })
        #expect(good.runs == 1 && good.passedFirstTry == 1 && good.passedAfterRetry == 1)
        #expect(good.planned == 6 && good.verbatim == 6 && good.readsRight == 1)
        #expect(good.gradableByCase[.dativ, default: 0] >= 3)
        let bad = try #require(summaries.first { $0.modelID == "canned:wrongArticle" })
        #expect(bad.passedAfterRetry == 0 && bad.readsWrong == 1 && bad.topErrors.first?.code == "trigger.prepositionCase")
        #expect(KasusLab.fileName(for: "gemma4_E4B_german") == "kasus-lab_gemma4_E4B_german.jsonl")
        #expect(KasusLab.fileName(for: "canned:good") == "kasus-lab_canned_good.jsonl")
    }

    @Test("The inferred reason decides nothing by itself")
    func inferredReason() {
        #expect(KasusReason.inferred.expectedCases(after: nil) == nil)
        #expect(!KasusReason.inferred.needsPreposition)
        #expect(KasusReason(rawValue: "inferred") == .inferred)
    }
}

private extension KasusLabRecord {
    /// Every planned phrase placed.
    var placements6: Bool { report.placements.count == 6 && report.placements.allSatisfy { $0.status == .placed } }
}
