//
//  KasusConceptGenerationTests.swift
//  german-ai-flashcardsTests
//
//  Tutor-written Verstehen items (training/KASUS_CONCEPT_PROBE.md): the planner is deterministic
//  and covers every exercise and unit with distinct plans of at most one ambiguous phrase; every
//  plan's template sentence passes the gate (the no-model baseline); the prompt carries every
//  phrase and no markup; and the gate turns away what a tutor gets wrong, each with its own code.
//

import Foundation
import Testing
@testable import Die_Kartei

@MainActor
@Suite("Kasus concept generation")
struct KasusConceptGenerationTests {

    private var lexicon: AppKasusLexicon { KasusTestData.lexicon }

    private func plans(_ kind: KasusConceptKind, _ unit: KasusUnit, count: Int = 10) -> [KasusConceptPlan] {
        KasusConceptPlanner.plans(kind: kind, unit: unit, from: 1, count: count, lexicon: lexicon)
    }

    private var everyPlan: [KasusConceptPlan] {
        KasusUnit.allCases.flatMap { unit in KasusConceptPlanner.kinds(for: unit).flatMap { plans($0, unit) } }
    }

    // MARK: Planner

    @Test func samePlanForTheSameSeed() {
        for unit in KasusUnit.allCases {
            for kind in KasusConceptPlanner.kinds(for: unit) {
                for seed: UInt64 in 1...5 {
                    let a = KasusConceptPlanner.plan(kind: kind, unit: unit, seed: seed, lexicon: lexicon)
                    let b = KasusConceptPlanner.plan(kind: kind, unit: unit, seed: seed, lexicon: lexicon)
                    #expect(a == b, Comment(rawValue: "\(kind) \(unit) \(seed)"))
                }
            }
        }
    }

    @Test func tenDistinctPlansPerExerciseAndUnit() {
        #expect(KasusConceptPlanner.kinds(for: .nominativ) == [.roles])
        for unit in KasusUnit.allCases {
            for kind in KasusConceptPlanner.kinds(for: unit) {
                let found = plans(kind, unit)
                #expect(found.count == 10, Comment(rawValue: "\(kind) \(unit): \(found.count)"))
                #expect(Set(found.map(\.template)).count == found.count)
            }
        }
    }

    @Test func atMostOneAmbiguousPhrase() {
        for plan in everyPlan {
            let ambiguous = plan.phrases.filter {
                // An attribute's place behind its noun settles it („der Hund der Lehrerin“).
                $0.preposition == nil && !$0.isAttribute && !KasusConceptPlanner.Builder.formProves($0.kasus, $0.genus)
            }
            #expect(ambiguous.count <= 1, Comment(rawValue: plan.template))
        }
    }

    @Test func werPlansHaveAFormProvenClueAndHalfOpenWithTheObject() {
        let wer = KasusUnit.allCases.filter { $0 != .nominativ }.flatMap { plans(.whoDoesWhat, $0) }
        for plan in wer {
            #expect(plan.phrases.filter { !$0.isAttribute }.count == 2)
            #expect(plan.firstPhrase != nil)
            #expect(plan.phrases.contains { !$0.isAttribute && KasusConceptPlanner.Builder.formProves($0.kasus, $0.genus) },
                    Comment(rawValue: plan.template))
        }
        let objectFirst = wer.filter(\.isObjectFirst).count
        #expect(objectFirst > wer.count / 4 && objectFirst < wer.count * 3 / 4)
    }

    @Test func probePlansMarkAnAmbiguousPhrase() {
        for unit in KasusUnit.allCases where unit != .nominativ {
            for plan in plans(.probe, unit) {
                let index = try! #require(plan.probePhrase)
                let phrase = plan.phrases[index]
                let article = String(phrase.phrase.split(separator: " ").first ?? "")
                #expect(KasusForms.compatibleCases(determiner: article, genus: phrase.genus).count > 1,
                        Comment(rawValue: plan.template))
            }
        }
    }

    // MARK: Baseline and prompt

    @Test func everyTemplatePassesTheGate() {
        for plan in everyPlan {
            let result = KasusConceptCheck.run(raw: "SATZ: \(plan.template)", plan: plan, lexicon: lexicon)
            #expect(result.passes, Comment(rawValue: "\(plan.template): \(result.firstReject ?? "") \(result.factsProblems)"))
        }
    }

    @Test func promptCarriesEveryPhraseAndNoMarkup() {
        for plan in everyPlan {
            let prompt = KasusConceptPrompt.build(plan)
            for phrase in plan.phrases { #expect(prompt.user.contains(phrase.expression)) }
            for form in plan.verbForms { #expect(prompt.user.contains("„\(form)“")) }
            #expect(prompt.user.contains("SATZ:"))
            for mark in ["{", "}", "**", "nil"] { #expect(!prompt.user.contains(mark), Comment(rawValue: plan.id)) }
            #expect(prompt.user.contains("Beginne den Satz mit") == (plan.firstPhrase != nil))
        }
    }

    // MARK: The gate on a tutor's mistakes

    private func phrase(_ text: String, _ kasus: GrammarCase, _ genus: Gender, _ reason: KasusReason,
                        preposition: String? = nil) -> KasusConceptPlannedPhrase {
        KasusConceptPlannedPhrase(phrase: text, caseRaw: kasus.rawValue, genusRaw: genus.columnLabel,
                                  lemma: String(text.split(separator: " ").last!), reasonRaw: reason.rawValue,
                                  preposition: preposition)
    }

    /// „Den Hund jagt die Katze.“ Object first, the clue on „den“.
    private var jagen: KasusConceptPlan {
        KasusConceptPlan(kindRaw: KasusConceptKind.whoDoesWhat.rawValue, unitRaw: KasusUnit.akkusativ.rawValue,
                         level: "A1", seed: 1,
                         phrases: [phrase("die Katze", .nominativ, .die, .subject), phrase("den Hund", .akkusativ, .der, .object)],
                         verbLemma: "jagen", verbForms: ["jagt", "jagte"], verbShown: "jagt",
                         firstPhrase: 1, probePhrase: nil, template: "Den Hund jagt die Katze.")
    }

    private func check(_ raw: String, _ plan: KasusConceptPlan? = nil) -> KasusConceptCheckResult {
        KasusConceptCheck.run(raw: raw, plan: plan ?? jagen, lexicon: lexicon)
    }

    @Test func theRightSentencePasses() {
        let result = check("SATZ: Den Hund jagt die Katze.")
        #expect(result.passes, Comment(rawValue: "\(result.firstReject ?? "") \(result.factsProblems)"))
        // A place or a reason behind a preposition is allowed, and never asked.
        let park = check("SATZ: Den Hund jagte die Katze im Park.")
        #expect(park.passes, Comment(rawValue: "\(park.firstReject ?? "")"))
        #expect(park.extras == ["im Park"])
    }

    @Test(arguments: [
        ("SATZ: Der Hund jagt die Katze.", KasusConceptCheckCode.phraseAltered),       // an altered article
        ("SATZ: Den Hund jagt seine Katze.", .phraseAltered),                        // a possessive swap
        ("SATZ: Die Katze jagt den Hund.", .orderIgnored),                           // the wrong order
        ("SATZ: Den Hund jagt die Katze. Er rennt weg.", .notOneSentence),           // two sentences
        ("SATZ: Den Hund jagen die Katze.", .verbMissing),                           // a wrong verb form
        ("SATZ: Den Hund jagt die Katze, weil er bellt.", .notSimple),               // a second clause
        ("SATZ: Den Hund jagt die Katze den ganzen Tag.", .extraPhrase),             // a bare phrase nobody planned
        ("SATZ: Den Hund jagt die Katze für dich.", .extraPerson),                   // a person nobody planned
        ("SATZ: Erklärung: Den Hund jagt die Katze.", .notSimple),                   // a label left on
        ("SATZ:   ", .empty),
    ])
    func aMistakeIsTurnedAway(raw: String, code: KasusConceptCheckCode) {
        let result = check(raw)
        #expect(!result.passes, Comment(rawValue: raw))
        #expect(result.codes.contains(code), Comment(rawValue: "\(raw): \(result.codes)"))
    }

    @Test func aMissingSatzLineIsRecordedNotRejected() {
        let result = check("Den Hund jagt die Katze.")
        #expect(result.codes.contains(.formatMissing))
        #expect(result.passes)
    }

    @Test func aWrongVerbFormIsTurnedAway() {
        let lachen = KasusConceptPlan(kindRaw: KasusConceptKind.roles.rawValue, unitRaw: KasusUnit.nominativ.rawValue,
                                      level: "A1", seed: 1, phrases: [phrase("der Bruder", .nominativ, .der, .subject)],
                                      verbLemma: "lachen", verbForms: ["lacht", "lachte"], verbShown: "lacht",
                                      firstPhrase: nil, probePhrase: nil, template: "Der Bruder lacht.")
        #expect(check("SATZ: Der Bruder lacht.", lachen).passes)
        let wrong = check("SATZ: Der Bruder lachen.", lachen)
        #expect(!wrong.passes)
        #expect(wrong.codes.contains(.verbMissing))
    }

    @Test func twoAmbiguousPhrasesAreTurnedAway() {
        // „Die Tochter sucht die Zeitung“ reads either way round; only the order would say.
        let suchen = KasusConceptPlan(kindRaw: KasusConceptKind.roles.rawValue, unitRaw: KasusUnit.akkusativ.rawValue,
                                      level: "A1", seed: 1,
                                      phrases: [phrase("die Tochter", .nominativ, .die, .subject), phrase("die Zeitung", .akkusativ, .die, .object)],
                                      verbLemma: "suchen", verbForms: ["sucht", "suchte"], verbShown: "sucht",
                                      firstPhrase: nil, probePhrase: nil, template: "Die Tochter sucht die Zeitung.")
        let result = check("SATZ: Die Tochter sucht die Zeitung.", suchen)
        #expect(!result.passes)
        #expect(result.codes.contains(.ambiguousRoles))
    }

    @Test func aPlannedObjectBehindAPrepositionIsTurnedAway() {
        let sehen = KasusConceptPlan(kindRaw: KasusConceptKind.roles.rawValue, unitRaw: KasusUnit.akkusativ.rawValue,
                                     level: "A1", seed: 1,
                                     phrases: [phrase("der Fahrer", .nominativ, .der, .subject), phrase("den Spiegel", .akkusativ, .der, .object)],
                                     verbLemma: "sehen", verbForms: ["sieht", "sah"], verbShown: "sieht",
                                     firstPhrase: nil, probePhrase: nil, template: "Der Fahrer sieht den Spiegel.")
        #expect(check("SATZ: Der Fahrer sieht den Spiegel.", sehen).passes)
        let result = check("SATZ: Der Fahrer sah trotz des Lärms in den Spiegel.", sehen)
        #expect(!result.passes)
        #expect(result.codes.contains(.roleChanged))
        // Two objects in a row are not an attribute: „dem Kind einen Ball“.
        let geben = KasusConceptPlan(kindRaw: KasusConceptKind.roles.rawValue, unitRaw: KasusUnit.dativ.rawValue,
                                     level: "A1", seed: 1,
                                     phrases: [phrase("der Vater", .nominativ, .der, .subject), phrase("dem Kind", .dativ, .das, .recipient),
                                               phrase("einen Ball", .akkusativ, .der, .object)],
                                     verbLemma: "geben", verbForms: ["gibt", "gab"], verbShown: "gibt",
                                     firstPhrase: nil, probePhrase: nil, template: "Der Vater gibt dem Kind einen Ball.")
        #expect(check("SATZ: Der Vater gibt dem Kind heute einen Ball.", geben).passes)
    }

    @Test func aProbePhraseHangingOnANounIsTurnedAway() {
        let helfen = KasusConceptPlan(kindRaw: KasusConceptKind.probe.rawValue, unitRaw: KasusUnit.dativ.rawValue,
                                      level: "A1", seed: 1,
                                      phrases: [phrase("der Vater", .nominativ, .der, .subject), phrase("der Schwester", .dativ, .die, .dativeVerb)],
                                      verbLemma: "helfen", verbForms: ["hilft", "half"], verbShown: "hilft",
                                      firstPhrase: nil, probePhrase: 1, template: "Der Vater hilft der Schwester.")
        #expect(check("SATZ: Der Vater hilft der Schwester.", helfen).passes)
        let result = check("SATZ: Der Vater hilft Tante der Schwester.", helfen)
        #expect(!result.passes)
        #expect(result.codes.contains(.roleUnsure))
    }
    // MARK: Genitiv attributes

    @Test func genitivWerPlansCarryAnAttributeRightBehindItsNoun() {
        for plan in plans(.whoDoesWhat, .genitiv) {
            let attributes = plan.phrases.filter(\.isAttribute)
            #expect(attributes.count == 1, Comment(rawValue: plan.template))
            #expect(attributes.allSatisfy { $0.kasus == .genitiv && $0.reason == .attribute })
            if let head = attributes.first?.head {
                #expect(plan.template.lowercased().contains(plan.fullExpression(head).lowercased()), Comment(rawValue: plan.template))
            }
        }
    }

    @Test func anAttributeOnlyCountsBehindItsNoun() {
        var hund = phrase("den Hund", .akkusativ, .der, .object)
        hund = KasusConceptPlannedPhrase(phrase: hund.phrase, caseRaw: hund.caseRaw, genusRaw: hund.genusRaw,
                                         lemma: hund.lemma, reasonRaw: hund.reasonRaw, preposition: nil)
        var lehrer = KasusConceptPlannedPhrase(phrase: "des Lehrers", caseRaw: GrammarCase.genitiv.rawValue, genusRaw: Gender.der.columnLabel,
                                               lemma: "Lehrer", reasonRaw: KasusReason.attribute.rawValue, preposition: nil)
        lehrer.head = 1
        let plan = KasusConceptPlan(kindRaw: KasusConceptKind.whoDoesWhat.rawValue, unitRaw: KasusUnit.genitiv.rawValue,
                                    level: "B1", seed: 1,
                                    phrases: [phrase("die Katze", .nominativ, .die, .subject), hund, lehrer],
                                    verbLemma: "jagen", verbForms: ["jagt", "jagte"], verbShown: "jagt",
                                    firstPhrase: 1, probePhrase: nil, template: "Den Hund des Lehrers jagt die Katze.")
        let right = check("SATZ: Den Hund des Lehrers jagt die Katze.", plan)
        #expect(right.passes, Comment(rawValue: "\(right.firstReject ?? "") \(right.factsProblems) \(right.errorCodes)"))
        let moved = check("SATZ: Den Hund jagt die Katze des Lehrers.", plan)
        #expect(!moved.passes)
        #expect(moved.codes.contains(.phraseAltered) || moved.codes.contains(.orderIgnored))
    }
}
