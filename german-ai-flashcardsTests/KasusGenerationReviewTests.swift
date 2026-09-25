//
//  KasusGenerationReviewTests.swift
//  german-ai-flashcardsTests
//
//  The Phase 3 review fixes, each pinned to the German that prompted it: the subject verb in the
//  third person („Der Bruder lachen laut.“ never counts), the sentence checks on a tutor's story,
//  two-way phrases that name Wo?/Wohin? only when a verb confirms it, adjectives that no longer
//  hide a wrong article, copula and pronoun traps, verbs used as nouns, the planner's collocations
//  and levels, the length rule, and the generator's retry, trimming and stop. Canned text
//  throughout: MLX doesn't run in the simulator.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Kasus generation review")
struct KasusGenerationReviewTests {

    private let lexicon = KasusTestData.lexicon

    private func check(_ unit: KasusUnit, _ raw: String, plan: KasusStoryPlan? = nil) -> KasusCheckResult {
        KasusStoryCheck.run(raw: raw, plan: plan ?? KasusGenerationFixtures.plan(for: unit), storyID: "kg-review", lexicon: lexicon)
    }

    private func dativ(_ edits: [(String, String)]) -> KasusCheckResult {
        check(.dativ, KasusGenerationFixtures.edit(KasusGenerationFixtures.dativGood, edits))
    }

    private func explain(_ result: KasusCheckResult) -> String {
        ([result.summaryLine] + (result.report?.issueLines ?? [])
            + result.harvest.map { "\($0.surface): \($0.verdict)" }).joined(separator: "\n")
    }

    private func verdicts(_ text: String) -> [String: KasusHarvestedPhrase.Verdict] {
        KasusHarvest.harvest(paragraphs: [text], nouns: KasusNounIndex(lexicon: lexicon), lexicon: lexicon)
            .reduce(into: [:]) { $0[$1.surface] = $1.verdict }
    }

    private func sentenceCodes(_ text: String) -> [KasusIssueCode] {
        KasusSentenceCheck.problems(in: [KasusScannedParagraph(text)], lexicon: lexicon).map(\.code)
    }

    // MARK: - Subjects in the third person

    @Test("A subject verb counts only in the third person singular, never as the bare infinitive")
    func subjectForms() throws {
        let lachen = try #require(KasusTriggerBank.bundled.subjectVerbs.first { $0.lemma == "lachen" })
        let forms = KasusStoryPlanner.subjectForms(lachen)
        #expect(forms.contains("lacht") && forms.contains("lachte") && forms.contains("hat gelacht"))
        #expect(forms.contains("kann lachen") && forms.contains("zu lachen"))
        #expect(!forms.contains("lachen") && !forms.contains("lache") && !forms.contains("lachst"))
        let kommen = try #require(KasusTriggerBank.bundled.subjectVerbs.first { $0.lemma == "kommen" })
        #expect(KasusStoryPlanner.subjectForms(kommen).contains("ist gekommen"))
    }

    @Test("„Der Bruder spielen …“ isn't placed and rejects the story; with a modal it's fine")
    func subjectInfinitive() throws {
        let broken = check(.nominativ, KasusGenerationFixtures.edit(KasusGenerationFixtures.nominativGood,
                                                                  [("Der Bruder spielt mit Paul", "Der Bruder spielen mit Paul")]))
        #expect(broken.placements.first { $0.expression == "der Bruder" }?.status == .triggerMissing)
        #expect(!broken.passes && broken.rejectingCodes.contains(.verbAgreement), "\(explain(broken))")

        let modal = check(.nominativ, KasusGenerationFixtures.edit(KasusGenerationFixtures.nominativGood,
                                                                 [("Der Bruder spielt mit Paul im Garten.", "Der Bruder will mit Paul im Garten spielen.")]))
        let placement = try #require(modal.placements.first { $0.expression == "der Bruder" })
        #expect(placement.status == .placed && placement.found == "will spielen", "\(explain(modal))")
        #expect(modal.passes, "\(explain(modal))")
    }

    // MARK: - Sentence checks

    @Test("The sentence checks catch the probe's broken German")
    func sentenceChecksCatch() {
        #expect(sentenceCodes("Ich ist nach meinem Fahrrad gegangen.") == [.verbAgreement])
        #expect(sentenceCodes("Dann ist ich müde.") == [.verbAgreement])
        #expect(sentenceCodes("Er lachen laut.") == [.verbAgreement])
        #expect(sentenceCodes("Dann kam ich auf einen stand.") == [.lowercaseNoun])
        #expect(sentenceCodes("Er kaufte einen Schicklebesele.") == [.unknownWord])
        #expect(sentenceCodes("Die Reise war aufregungsvoll.") == [.unknownWord])
        #expect(sentenceCodes("Ich musste noch etwas erledigen. Ich musste noch etwas erledigen. Ich musste noch etwas erledigen.")
                == [.repeatedSentence])
    }

    @Test("The sentence checks leave correct German alone")
    func sentenceChecksSpare() {
        for text in [
            "Tom und ich gehen nach Hause.",
            "Ich weiß, dass er morgen kommen kann.",
            "Er ist müde, weil er arbeiten muss.",
            "Heute will er lange schlafen.",
            "Das habe ich gesehen.",
            "Die kleine Mia lacht. Mia spielt im Garten.",
            "Sie hören die klingelnde Glocke.",
            "Sie sahen sich an, als sie ihn anstarrte.",
            "Er weichte das Brot ein.",
            "Wir kaufen ein paar Äpfel und ein bisschen Käse.",
            "Er war derjenige, der mich immer ermutigt hat.",
            "Der nächste Tag war ein solcher Tag.",
        ] {
            #expect(sentenceCodes(text).isEmpty, "„\(text)“: \(sentenceCodes(text))")
        }
    }

    @Test("A broken sentence rejects a story that passes every form check")
    func sentenceRejects() {
        let result = dativ([("Sie ist sechs Jahre alt.", "Sie ist sechs Jahre alt. Ich ist sehr müde.")])
        #expect(!result.passes && result.rejectingCodes == [.verbAgreement], "\(explain(result))")
    }

    @Test("„Ich habe ein Hund“ and „Es gibt ein Hund“ reject the story")
    func objectNominativ() {
        for line in ["Ich habe ein Hund.", "Es gibt ein Hund."] {
            let result = dativ([("Sie ist sechs Jahre alt.", "Sie ist sechs Jahre alt. \(line)")])
            #expect(!result.passes && result.rejectingCodes.contains(.objectNominativ), "\(line)\n\(explain(result))")
        }
    }

    // MARK: - Two-way prepositions

    @Test("An unplanned two-way phrase names Wo? only when a position verb confirms it")
    func twoWayInferred() throws {
        let confirmed = dativ([("Sie bringt ihm einen Tee", "Sein Buch liegt unter dem Tisch. Sie bringt ihm einen Tee")])
        #expect(confirmed.passes, "\(explain(confirmed))")
        let tisch = try #require(confirmed.report?.located.first { $0.surface == "dem Tisch" })
        #expect(tisch.spec.reason == .inferred && tisch.wechselVerb == "liegt" && tisch.gradable && tisch.blankable)
        #expect(KasusRich.plain(KasusExplanation.inferredLine(for: tisch))
                == "dem + a masculine noun can only be Dativ, so after unter it's Wo? (a place). liegt says where something is.")

        // „Oma freut sich über die Blumen“: no Wo/Wohin verb, so no direction is claimed.
        let akk = check(.akkusativ, KasusGenerationFixtures.akkusativGood)
        let blumen = try #require(akk.report?.located.first { $0.surface == "die Blumen" && $0.preposition?.word == "über" })
        #expect(blumen.gradable && !blumen.blankable)
        #expect(KasusRich.plain(KasusExplanation.inferredLine(for: blumen))
                == "By its form, die could be Nominativ or Akkusativ, and über takes only Akkusativ or Dativ: so Akkusativ.")
    }

    @Test("A two-way phrase describing a noun goes plain instead of rejecting the story")
    func twoWayAttributive() throws {
        let result = dativ([("Sie bringt ihm einen Tee", "Er legt das Buch auf den Tisch neben der Tür. Sie bringt ihm einen Tee")])
        #expect(result.passes, "\(explain(result))")
        let tuer = try #require(result.report?.targets.first { $0.spec.phrase == "der Tür" })
        #expect(tuer.issues.map(\.code) == [.wechselUnconfirmed] && tuer.located?.gradable == false)
        let tisch = try #require(result.report?.located.first { $0.surface == "den Tisch" })
        #expect(tisch.wechselVerb == "legt" && tisch.gradable)
    }

    // MARK: - The harvest

    @Test("An adjective no longer hides a wrong article")
    func adjectiveWrongArticle() {
        #expect(verdicts("Ich suche das große Tasche.")["das große Tasche"] == .wrong)
        #expect(verdicts("Er spielt mit den kleinen Hund.")["den kleinen Hund"] == .wrong)
        #expect(verdicts("Er kauft einen großen Hund.")["einen großen Hund"] == .unverifiable(.adjective))
        #expect(verdicts("Er kommt trotz des starken Regens.")["des starken Regens"] == .unverifiable(.adjective))
        let result = dativ([("mit dem Hund im Park", "mit den kleinen Hund im Park")])
        #expect(!result.passes && result.rejectingCodes.contains(.triggerPrepositionCase), "\(explain(result))")
    }

    @Test("sein takes no Akkusativ object; a Dativ next to it is left ungraded")
    func copula() {
        let akk = dativ([("Sie ist sechs Jahre alt.", "Sie ist sechs Jahre alt. Die Nachbarn waren ihren Gast.")])
        #expect(!akk.passes && akk.rejectingCodes.contains(.copulaAkkusativ), "\(explain(akk))")
        let moment = dativ([("Sie ist sechs Jahre alt.", "Sie ist sechs Jahre alt. Sie war einen Moment still.")])
        #expect(!(moment.report?.errors.contains { $0.code == .copulaAkkusativ } ?? true), "\(explain(moment))")
        #expect(verdicts("Das ist dem Kind egal.")["dem Kind"] == .unverifiable(.copula))
        #expect(verdicts("Er hilft dem Kind.")["dem Kind"] == .proven)
    }

    @Test("A bare „ihr“ is never read as an article")
    func pronounIhr() {
        #expect(verdicts("Habt ihr Hunger?")["ihr Hunger"] == .unverifiable(.notAnArticle))
        #expect(verdicts("Er gibt ihr Kaffee.")["ihr Kaffee"] == .unverifiable(.notAnArticle))
        #expect(verdicts("Sie sucht ihren Hund.")["ihren Hund"] == .proven)
    }

    @Test("A verb used as a noun isn't a Dativ plural: „beim Spielen“ passes")
    func nominalised() {
        #expect(verdicts("Die Kinder gehen zum Spielen in den Park.")["zum Spielen"] == .unverifiable(.nominalised))
        #expect(verdicts("Beim Arbeiten hört er Musik.")["Beim Arbeiten"] == .unverifiable(.nominalised))
        #expect(verdicts("Er spielt mit dem Kinder.")["dem Kinder"] == .wrong)
        #expect(verdicts("Er spielt mit dem Kindern.")["dem Kindern"] == .wrong)
        let result = dativ([("Im Garten spielt sie jeden Tag.", "Beim Spielen im Garten ist sie jeden Tag glücklich.")])
        #expect(!(result.report?.errors.contains { $0.code.isMorphology } ?? true), "\(explain(result))")
    }

    @Test("A Genitiv plural that hangs on nothing is a wrong gender, not a graded Genitiv")
    func genitivePluralRole() {
        #expect(verdicts("Der Zimmer ist groß.")["Der Zimmer"] == .unverifiable(.genitiveRole))
        #expect(verdicts("Das ist das Zimmer der Kinder.")["der Kinder"] == .proven)
    }

    @Test("A planned object after a preposition is the preposition's, not the verb's")
    func plannedAfterPreposition() throws {
        let raw = KasusGenerationFixtures.edit(KasusGenerationFixtures.akkusativGood,
                                               [("Tim sucht den Ball.", "Tim sucht Steine für den Ball.")])
        let result = check(.akkusativ, raw)
        #expect(result.placements.first { $0.expression == "den Ball" }?.status == .triggerMissing)
        let ball = try #require(result.report?.located.first { $0.surface == "den Ball" })
        #expect(ball.spec.reason == .inferred && ball.spec.trigger == "für" && ball.kasus == .akkusativ)
    }

    // MARK: - Parsing and length

    @Test("A numbered list comes off, and its sentences read as paragraphs")
    func numberedLines() {
        let parsed = KasusStoryText.parse("""
        TITEL: Ein Tag
        GESCHICHTE:
        1. Es regnet.
        2. Mia sucht den Ball.
        3. Sie findet ihn.
        4. Alle lachen.
        5. Der Tag ist gut.
        """)
        #expect(parsed.paragraphs == ["Es regnet. Mia sucht den Ball. Sie findet ihn. Alle lachen.", "Der Tag ist gut."])
        #expect(KasusStoryText.clean("- Hallo") == "Hallo" && KasusStoryText.clean("12) Hallo") == "Hallo")
        #expect(KasusStoryText.clean("**Titel**") == "Titel")
    }

    @Test("Length only warns, unless a story is under half the level's range")
    func lengthRule() throws {
        let fixture = KasusGenerationFixtures.plan(for: .dativ)
        let b1 = KasusStoryPlan(unitRaw: fixture.unitRaw, level: "B1", seed: 0, governed: false, contract: .planned,
                                topic: fixture.topic, genreRaw: fixture.genreRaw, phrases: fixture.phrases)
        let result = check(.dativ, KasusGenerationFixtures.dativGood, plan: b1)
        let report = try #require(result.report)
        #expect(report.wordCount < 200 && report.wordCount >= 100)
        #expect(result.passes, "\(explain(result))")
        #expect(report.warnings.contains { $0.code == .wordCount } && !report.errors.contains { $0.code == .wordCount })
    }

    @Test("The Endungen Tipp for a form-only gap doesn't point at who or what")
    func formOnlyTipp() throws {
        let result = check(.dativ, KasusGenerationFixtures.dativGood)
        let playable = KasusService.prepare(try #require(result.story), lexicon: lexicon)
        let gaps = KasusService.endingGaps(in: playable, unit: .dativ, mixed: true, hint: .ohne)
        let formOnly = try #require(gaps.first { $0.isFormOnly })
        #expect(formOnly.triggerClue == "Find the verb. Ask wer?, wen?, wem? or wessen?")
    }

    // MARK: - The planner

    @Test("Planner collocations: people sing, chairs are sat on, kin and mass nouns stay definite")
    func plannerCollocations() {
        let bank = KasusTriggerBank.bundled
        let definiteOnly = Set(bank.definiteOnly ?? [])
        let animals = Set(bank.nouns["animals"] ?? [])
        let seatsAndFloor = Set((bank.nouns["seats"] ?? []) + (bank.nouns["floor"] ?? []))
        let peopleVerbs: Set<String> = ["singen", "lachen", "weinen", "kochen", "rufen", "arbeiten", "tanzen"]
        var definiteFeminineAfterVonBei = false
        for unit in KasusUnit.allCases {
            for level in [CEFRLevel.a1, .a2, .b1] {
                for seed in UInt64(0)..<30 {
                    let plan = KasusStoryPlanner.plan(unit: unit, level: level, seed: seed, governed: false, lexicon: lexicon)
                    for phrase in plan.phrases {
                        let label = "\(unit.rawValue) \(level.rawValue) #\(seed) „\(phrase.expression)“ (\(phrase.verb ?? "–"))"
                        let family = KasusForms.parseDeterminer(phrase.determiner)?.family
                        if phrase.frame == .subject {
                            #expect(phrase.lemma != "Fisch", "\(label)")
                            if peopleVerbs.contains(phrase.verb ?? "") { #expect(!animals.contains(phrase.lemma), "\(label)") }
                        }
                        if definiteOnly.contains(phrase.lemma) { #expect(family == .definite, "\(label)") }
                        if phrase.preposition == "um" || phrase.preposition == "nach" { #expect(family == .definite, "\(label)") }
                        if phrase.preposition == "zu" { #expect(family == .ein, "\(label)") }
                        if ["sitzen", "sich setzen"].contains(phrase.verb ?? ""), phrase.preposition == "auf" {
                            #expect(seatsAndFloor.contains(phrase.lemma), "\(label)")
                        }
                        if ["von", "bei"].contains(phrase.preposition ?? ""), phrase.determiner == "der" {
                            definiteFeminineAfterVonBei = true
                        }
                        #expect(!["folgen", "vertrauen"].contains(phrase.verb ?? ""), "\(label)")
                        if level == .a1 {
                            #expect(!["singen", "rufen", "weinen", "tragen", "schenken", "zeigen", "sich setzen"].contains(phrase.verb ?? ""),
                                    "\(label): an A2 verb in an A1 plan")
                        }
                    }
                }
            }
        }
        #expect(definiteFeminineAfterVonBei, "„bei der Oma“ is planned now: only dem contracts after von and bei")
        #expect(KasusStoryPlanner.contracts("zu", "der") && KasusStoryPlanner.contracts("bei", "dem"))
        #expect(!KasusStoryPlanner.contracts("bei", "der") && !KasusStoryPlanner.contracts("von", "der"))
    }

    // MARK: - The generator

    @Test("The retry asks for the tutor again, and a refusal there is a failure")
    func retryPrepares() async {
        let writer = RefusingOnRetryWriter()
        let result = await KasusStoryGenerator(writer: writer, lexicon: lexicon)
            .generate(KasusGenerationFixtures.request(for: .dativ))
        #expect(result.outcome == .failed && result.attempts.count == 1 && writer.prepares == 2)
        #expect(result.note == RefusingOnRetryWriter.refusal && result.story?.unitRaw == "dativ")
    }

    @Test("A write cut off mid-sentence is trimmed to its last full sentence")
    func trimsCutOffWrites() {
        let cut = "TITEL: X\nGESCHICHTE:\nMia lacht. Der Hund schläft auf dem"
        #expect(KasusStoryGenerator.completeSentences(cut, endedEarly: true) == "TITEL: X\nGESCHICHTE:\nMia lacht.")
        #expect(KasusStoryGenerator.completeSentences(cut, endedEarly: false) == "TITEL: X\nGESCHICHTE:\nMia lacht.")
        #expect(KasusStoryGenerator.completeSentences("Mia lacht.", endedEarly: true) == "Mia lacht.")
        #expect(KasusStoryGenerator.completeSentences("Mia sagt: „Hallo.“ Dann geht sie", endedEarly: false) == "Mia sagt: „Hallo.“")
    }

    @Test("Abbrechen shows as stopping until the run ends")
    func stoppingState() async {
        let writer = KasusGenerationFixtures.writer(for: .dativ, .good, delay: .milliseconds(400))
        let generator = KasusStoryGenerator(writer: writer, lexicon: lexicon)
        let task = Task { await generator.generate(KasusGenerationFixtures.request(for: .dativ)) }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!generator.isStopping)
        generator.cancel()
        #expect(generator.isStopping)
        let result = await task.value
        #expect(result.outcome == .cancelled && !generator.isStopping)
    }

    // MARK: - Contract B

    @Test("A label in the dictionary form is matched by its noun and counted apart")
    func labelsByNoun() {
        let harvest = KasusHarvest.harvest(paragraphs: ["Mia sucht den Ball. Tim findet den Ball."],
                                           nouns: KasusNounIndex(lexicon: lexicon), lexicon: lexicon)
        let score = KasusSelfLabels.score(KasusSelfLabels.parse("der Ball | Nom\nden Ball | Akk\ndie Katze | Nom"), harvest: harvest)
        #expect(score.byNoun == 1 && score.wrong == 1 && score.correct == 1 && score.notInStory == 1, "\(score)")
    }
}

/// Writes the Dativ fixture's wrong-article text, and refuses to prepare the second time: the
/// tutor was taken or dropped while the first try was checked.
@MainActor
private final class RefusingOnRetryWriter: KasusStoryWriter {
    static let refusal = "The tutor is still answering. Try again in a moment."
    let modelID = "test:refusing"
    var memorySaverActive = false
    var liveTokenCount = 0
    private(set) var prepares = 0

    func prepare() async -> String? {
        prepares += 1
        return prepares > 1 ? Self.refusal : nil
    }

    func write(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> KasusWriterOutput {
        KasusWriterOutput(text: KasusGenerationFixtures.output(for: .dativ, .wrongArticle), tokenCount: 120, endedEarly: false)
    }

    func stop() {}
}
