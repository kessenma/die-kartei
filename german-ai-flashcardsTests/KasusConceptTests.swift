//
//  KasusConceptTests.swift
//  german-ai-flashcardsTests
//
//  Verstehen: the bundled items (`kasus_concepts.json`) all play, their golden numbers hold, the
//  facts' invariants hold (a Wer item is decided by a form, a Probe phrase is really ambiguous),
//  roles come off reasons the Kasus-Check's way, rounds compose as promised, every pick grades
//  and explains cleanly, the Kasus-Check walk, recording (Rollen and Wer never move the coach,
//  the Probe may, a read lesson is a round of nothing), and the hub's Weiter row with Verstehen.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

/// The bundled items, decoded straight from the app bundle (never `KasusConceptBank.bundled`,
/// whose DEBUG assert would stop the whole run on one broken item).
nonisolated enum BundledConcepts {
    static let file: KasusConceptFile? = {
        guard let url = Bundle.main.url(forResource: "kasus_concepts", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KasusConceptFile.self, from: data)
    }()

    static let ids: [String] = file?.items.map(\.id) ?? []
}

@Suite("Kasus concepts")
struct KasusConceptTests {

    private var lexicon: AppKasusLexicon { KasusTestData.lexicon }

    private var bank: KasusConceptBank {
        let url = Bundle.main.url(forResource: "kasus_concepts", withExtension: "json")!
        return try! KasusConceptBank(data: Data(contentsOf: url))
    }

    private func item(_ id: String) -> KasusConceptItem {
        BundledConcepts.file!.items.first { $0.id == id }!
    }

    private func audit(_ id: String) -> KasusConceptAudit {
        KasusConceptBank.audit(item(id), lexicon: lexicon)
    }

    private func playable(_ id: String) -> KasusConceptPlayable {
        let audit = audit(id)
        return KasusConceptPlayable(item: audit.item,
                                    playable: KasusPlayableStory(story: audit.item.story, report: audit.report, lexicon: lexicon),
                                    facts: audit.facts)
    }

    private func round(_ unit: KasusUnit, _ exercise: KasusConceptExercise, mode: KasusRolesMode = .direkt,
                       seed: UInt64 = 1) -> KasusConceptRound {
        KasusService.conceptRound(unit: unit, exercise: exercise, rolesMode: mode, bank: bank, lexicon: lexicon, seed: seed)!
    }

    // MARK: The file

    @Test("The file decodes, ids are unique and well formed, every English phrase is in its line")
    func file() throws {
        let file = try #require(BundledConcepts.file)
        #expect(file.items.count >= 100)
        #expect(Set(file.items.map(\.id)).count == file.items.count)
        for item in file.items {
            #expect(item.id.hasPrefix("kc-"), Comment(rawValue: "\(item.id)"))
            #expect(item.unit != nil, Comment(rawValue: "\(item.id) unit"))
            #expect(CEFRLevel(rawValue: item.level) != nil, Comment(rawValue: "\(item.id) level"))
            #expect(item.story.paragraphs.allSatisfy { !$0.de.isEmpty && !$0.en.isEmpty }, Comment(rawValue: "\(item.id) paragraphs"))
            for (index, phrase) in item.english {
                #expect(item.story.paragraphs.contains { $0.en.contains(phrase) }, Comment(rawValue: "\(item.id) #\(index + 1) „\(phrase)“"))
            }
        }
    }

    @Test("Every bundled item plays: no validator problem, no facts problem", arguments: BundledConcepts.ids)
    func everyItemPlays(_ id: String) {
        let audit = audit(id)
        #expect(audit.passes, Comment(rawValue: "\(id): \(audit.problems.joined(separator: " | "))"))
    }

    @Test("The golden numbers hold and the verify report reads ALL OK")
    func golden() {
        let result = KasusConceptFixtures.verify(bank: bank, lexicon: lexicon)
        #expect(result.failures.isEmpty, Comment(rawValue: result.failures.joined(separator: "\n")))
        #expect(result.text.hasSuffix("Concepts ALL OK"))
    }

    @Test("Which exercises a unit offers comes from its items")
    func offered() {
        #expect(bank.offered(for: .nominativ) == [.roles])
        for unit in [KasusUnit.akkusativ, .dativ, .genitiv, .alleFaelle] {
            #expect(bank.offered(for: unit) == KasusConceptExercise.allCases, Comment(rawValue: "\(unit)"))
        }
        #expect(KasusConceptBank.empty.offered(for: .dativ).isEmpty)
    }

    // MARK: Facts

    @Test("A Wer item is decided by a form, its doer is the subject, and half of them are object-first")
    func werFacts() {
        for unit in [KasusUnit.akkusativ, .dativ, .genitiv, .alleFaelle] {
            let items = bank.items(for: unit, kind: .whoDoesWhat).map { playable($0.id) }
            #expect(items.count >= 8, Comment(rawValue: "\(unit)"))
            for item in items {
                let clue = item.target(item.facts.clue!)!
                #expect(clue.proof == .form || clue.proof == .preposition, Comment(rawValue: item.id))
                #expect(item.doer?.spec.reason == .subject, Comment(rawValue: item.id))
                #expect(item.options.count == 2, Comment(rawValue: item.id))
            }
            let ovs = items.filter(\.facts.isOVS).count
            // About half object-first (exactly half in the hand-written eight per unit).
            #expect(Double(ovs) / Double(items.count) > 0.35 && Double(ovs) / Double(items.count) < 0.65,
                    Comment(rawValue: "\(unit): \(ovs) of \(items.count) object-first"))
            let pairs = bank.items(for: unit, kind: .sameMeaning).map { playable($0.id) }
            #expect(pairs.count >= 3, Comment(rawValue: "\(unit)"))
            for pair in pairs {
                #expect(pair.facts.clues.count == 2, Comment(rawValue: pair.id))
                #expect(pair.same != nil, Comment(rawValue: pair.id))
            }
        }
    }

    @Test("Picture choices: both readings shipped, each picture's doer is the animal that chases")
    func pictures() {
        let items = BundledConcepts.file!.items.filter { !$0.pictures.isEmpty }
        #expect(items.count >= 3)
        for raw in items {
            let item = playable(raw.id)
            #expect(item.hasPictureChoice, Comment(rawValue: raw.id))
            #expect(Set(raw.pictures.keys) == Set(item.options.map(\.index)), Comment(rawValue: raw.id))
            for (index, asset) in raw.pictures {
                #expect(PrepositionScene.exists(for: asset), Comment(rawValue: asset))
                #expect(PrepositionScene.image(for: asset, state: "neutral") != nil, Comment(rawValue: asset))
                // kasus3d-jagen-hund: the dog is the doer in that picture.
                let doer = item.target(index)!.spec.lemma.lowercased()
                #expect(asset.hasSuffix("-\(doer)"), Comment(rawValue: "\(raw.id): \(asset) for \(doer)"))
            }
        }
        // Grading is the phrase's: tapping the picture of the right reading is the doer.
        var round = KasusConceptRound(unit: .akkusativ, exercise: .wer, items: [playable("kc-akk-who-katze-ovs")])
        let answer = round.answer(.option(1))!
        #expect(answer.isRight)
    }

    @Test("A Probe phrase is an article phrase that could be two cases, never masculine")
    func probeFacts() {
        for unit in [KasusUnit.akkusativ, .dativ, .genitiv, .alleFaelle] {
            for item in bank.items(for: unit, kind: .probe).map({ playable($0.id) }) {
                let probe = item.probe!
                #expect(probe.target.candidates.count > 1, Comment(rawValue: item.id))
                #expect(probe.target.genus != .der, Comment(rawValue: item.id))
                #expect(probe.target.kind == .article, Comment(rawValue: item.id))
                #expect(probe.options(includeGenitive: false).contains(probe.answer) || probe.kasus == .genitiv, Comment(rawValue: item.id))
                #expect(probe.swappedSentence.contains(probe.swappedPhrase), Comment(rawValue: item.id))
                #expect(!probe.swappedSentence.contains(probe.target.surface), Comment(rawValue: item.id))
            }
        }
    }

    @Test("Rollen asks only roles in play, in reading order")
    func rolesFacts() {
        for unit in KasusUnit.allCases {
            let chips = Set(KasusRole.chips(for: unit))
            for item in bank.items(for: unit, kind: .roles).map({ playable($0.id) }) {
                #expect(!item.facts.asked.isEmpty, Comment(rawValue: item.id))
                let positions = item.askedTargets.map(\.range.location)
                #expect(positions == positions.sorted(), Comment(rawValue: item.id))
                for target in item.askedTargets {
                    #expect(chips.contains(item.facts.roles[target.index]!), Comment(rawValue: "\(item.id) \(target.surface)"))
                }
            }
        }
    }

    @Test("Broken items are refused: no form clue, an unambiguous probe, a wrong same")
    func negativeFixtures() {
        func story(_ text: String, _ targets: [KasusTargetSpec], paragraphs: [String]? = nil) -> KasusStory {
            KasusStory(id: "fixture", unitRaw: "dativ", level: "A2", source: .authored,
                       reviewed: .init(by: "", date: ""), title: "", titleEnglish: "",
                       question: .init(de: "", en: "", options: [], answer: 0),
                       paragraphs: (paragraphs ?? [text]).map { .init(de: $0, en: "x") },
                       targets: targets, notTargets: [])
        }
        func target(_ phrase: String, _ kasus: GrammarCase, _ genus: Gender, _ lemma: String,
                    _ reason: KasusReason, _ trigger: String) -> KasusTargetSpec {
            KasusTargetSpec(phrase: phrase, kasus: kasus, genus: genus, lemma: lemma, reason: reason, trigger: trigger)
        }
        // Nothing but word order says who chases: refused.
        let noClue = KasusConceptItem(
            id: "x-noclue", kind: .whoDoesWhat,
            story: story("Die Katze jagt die Frau.", [target("Die Katze", .nominativ, .die, "Katze", .subject, "jagt"),
                                                      target("die Frau", .akkusativ, .die, "Frau", .object, "jagt")]),
            detail: .whoDoesWhat(question: .init(de: "Wer jagt?", en: "Who?"), options: [0, 1], answer: 0))
        #expect(KasusConceptBank.audit(noClue, lexicon: lexicon).problems.contains { $0.contains("neither phrase") })
        // „dem Kind“ already shows its case: nothing to swap.
        let plain = KasusConceptItem(
            id: "x-plain", kind: .probe,
            story: story("Ich helfe dem Kind.", [target("dem Kind", .dativ, .das, "Kind", .dativeVerb, "helfe")]),
            detail: .probe(target: 0, noun: .mann))
        #expect(KasusConceptBank.audit(plain, lexicon: lexicon).problems.contains { $0.contains("already shows") })
        // The doers differ, but the item says the two mean the same.
        let wrongSame = KasusConceptItem(
            id: "x-same", kind: .sameMeaning,
            story: story("", [target("Der Hund", .nominativ, .der, "Hund", .subject, "sieht"),
                              target("die Katze", .akkusativ, .die, "Katze", .object, "sieht"),
                              target("Den Hund", .akkusativ, .der, "Hund", .object, "sieht"),
                              target("die Katze", .nominativ, .die, "Katze", .subject, "sieht")],
                         paragraphs: ["Der Hund sieht die Katze.", "Den Hund sieht die Katze."]),
            detail: .sameMeaning(same: true))
        #expect(KasusConceptBank.audit(wrongSame, lexicon: lexicon).problems.contains { $0.contains("same = true") })
        // A good item has no problems.
        let fine = KasusConceptItem(
            id: "x-fine", kind: .whoDoesWhat,
            story: story("Den Hund jagt die Katze.", [target("Den Hund", .akkusativ, .der, "Hund", .object, "jagt"),
                                                      target("die Katze", .nominativ, .die, "Katze", .subject, "jagt")]),
            detail: .whoDoesWhat(question: .init(de: "Wer jagt?", en: "Who?"), options: [0, 1], answer: 1))
        let fineAudit = KasusConceptBank.audit(fine, lexicon: lexicon)
        #expect(fineAudit.passes, Comment(rawValue: fineAudit.problems.joined(separator: " | ")))
        #expect(fineAudit.facts.isOVS)
        #expect(fineAudit.facts.clue == 0)
    }

    // MARK: Roles

    @Test("Roles come off reasons the Kasus-Check's way: a preposition wins, then the reason")
    func roleMapping() {
        let ball = playable("kc-dat-roles-ball")
        #expect(ball.facts.roles == [0: .subjekt, 1: .empfaenger, 2: .direktesObjekt])
        let kuchen = playable("kc-akk-roles-kuchen")
        #expect(kuchen.facts.roles[2] == .praeposition)
        let auto = playable("kc-gen-roles-auto")
        #expect(auto.facts.roles[1] == .gehoertZu)
        #expect(auto.facts.roles[2] == .praeposition)   // vor dem Haus: the preposition, not Wo?
        let katze = playable("kc-nom-roles-katze")
        #expect(katze.facts.roles[1] == .gleichSubjekt)
        let gefaellt = playable("kc-dat-roles-gefaellt")
        #expect(gefaellt.facts.roles[1] == .empfaenger)   // a Dativ verb's partner
        let ende = playable("kc-gen-roles-ende")
        #expect(ende.facts.roles[0] == .praeposition)     // „Am Ende“: a time phrase with a preposition
        // What each role reveals.
        #expect(KasusRole.subjekt.revealedCase(for: ball.target(0)!) == .nominativ)
        #expect(KasusRole.praeposition.revealedCase(for: kuchen.target(2)!) == .akkusativ)
        #expect(KasusRole.praeposition.revealedCase(for: auto.target(2)!) == .dativ)
    }

    @Test("The chips per unit follow the Check's order, and the walk leaves the last step out")
    func chips() {
        #expect(KasusRole.chips(for: .nominativ) == [.subjekt, .gleichSubjekt])
        #expect(KasusRole.chips(for: .akkusativ) == [.praeposition, .subjekt, .gleichSubjekt, .direktesObjekt])
        #expect(KasusRole.chips(for: .dativ) == [.praeposition, .subjekt, .gleichSubjekt, .empfaenger, .direktesObjekt])
        #expect(KasusRole.chips(for: .genitiv) == KasusRole.allCases)
        #expect(KasusRole.chips(for: .alleFaelle) == KasusRole.allCases)
        #expect(KasusRole.walkSteps(for: .dativ) == [.praeposition, .subjekt, .gleichSubjekt, .empfaenger])
        #expect(KasusRole.allCases.map(\.checkStep) == [1, 2, 3, 4, 5, 6])
        #expect(KasusConceptExercise(step: .roles) == .roles)
        #expect(KasusConceptExercise(step: .fill) == nil)
    }

    // MARK: Composing

    @Test("A round is seeded, sized and mixed as promised")
    func compose() {
        let a = round(.dativ, .wer, seed: 42), b = round(.dativ, .wer, seed: 42), c = round(.dativ, .wer, seed: 43)
        #expect(a.items.map(\.id) == b.items.map(\.id))
        #expect(a.items.map(\.id) != c.items.map(\.id))
        #expect(a.items.count == 10)
        #expect(a.items.filter { $0.kind == .sameMeaning }.count == 3)
        let ovs = a.items.filter { $0.kind == .whoDoesWhat && $0.facts.isOVS }.count
        #expect((3...4).contains(ovs), Comment(rawValue: "\(ovs) object-first"))
        #expect(Set(a.items.map(\.id)).count == a.items.count)
        #expect(a.steps.count == 10)

        for unit in [KasusUnit.akkusativ, .dativ, .genitiv, .alleFaelle] {
            for seed in 1...5 {
                let roles = round(unit, .roles, seed: UInt64(seed))
                #expect(roles.items.count == 8, Comment(rawValue: "\(unit) roles"))
                #expect(roles.steps.count >= 8, Comment(rawValue: "\(unit) roles steps"))
                #expect(KasusConceptRound.coversEnough(roles.items, exercise: .roles, unit: unit), Comment(rawValue: "\(unit) roles seed \(seed)"))
                let probe = round(unit, .probe, seed: UInt64(seed))
                #expect(probe.items.count == 8, Comment(rawValue: "\(unit) probe"))
                #expect(Set(probe.items.compactMap { $0.probe?.answer }).count >= 2, Comment(rawValue: "\(unit) probe seed \(seed)"))
            }
        }
        let nom = round(.nominativ, .roles)
        #expect(nom.items.count == 8)
        #expect(nom.steps.allSatisfy { $0.target != nil })
    }

    // MARK: Grading

    @Test("Rollen grades a chip, keeps the role picked and explains the phrase")
    func gradeRoles() {
        var right = round(.dativ, .roles)
        let target = right.currentTarget!
        let actual = right.currentRole!
        let answer = right.answer(.role(actual))!
        #expect(answer.isRight)
        #expect(answer.outcome == .right)
        #expect(answer.kasus == actual.revealedCase(for: target))
        #expect(answer.record.pick == actual.rawValue)
        #expect(answer.record.phrase == target.surface)
        #expect(RichMarkup.problems(answer.explanation).isEmpty, Comment(rawValue: answer.explanation))
        #expect(answer.explanation.contains("**\(actual.germanLabel)**"))
        #expect(right.cursor == 1)

        var wrong = round(.dativ, .roles)
        let other = KasusRole.chips(for: .dativ).first { $0 != wrong.currentRole! }!
        let miss = wrong.answer(.role(other))!
        #expect(!miss.isRight)
        #expect(miss.outcome == .wrongPick)
        #expect(miss.record.pick == other.rawValue)
        #expect(miss.explanation.hasPrefix("Not **\(other.germanLabel)**."))
        // A pick the exercise doesn't take changes nothing.
        #expect(wrong.answer(.form("dem Mann")) == nil)
        #expect(wrong.cursor == 1)
    }

    @Test("Wer macht was? grades the doer and „Gleich oder anders?“, filed under the clue's case")
    func gradeWer() {
        var round = self.round(.akkusativ, .wer)
        var sawOption = false, sawSame = false
        while let item = round.currentItem {
            if let doer = item.doer {
                sawOption = true
                let other = item.options.first { $0.index != doer.index }!
                let miss = round.answer(.option(other.index))!
                #expect(miss.outcome == .wrongPick)
                #expect(miss.record.pick == other.surface)
                let clue = item.target(item.facts.clue!)!
                #expect(miss.kasus == clue.kasus)
                #expect(miss.record.phrase == clue.surface)
                #expect(RichMarkup.problems(miss.explanation).isEmpty, Comment(rawValue: miss.explanation))
                #expect(miss.explanation.contains("„\(doer.surface)“ is the doer"))
                if item.facts.isOVS { #expect(miss.explanation.contains("Word order doesn't decide")) }
            } else if let same = item.same {
                sawSame = true
                let hit = round.answer(.same(same))!
                #expect(hit.isRight)
                #expect(hit.record.pick == (same ? "gleich" : "anders"))
                #expect(hit.record.sentence.hasPrefix("1. "))
                #expect(RichMarkup.problems(hit.explanation).isEmpty, Comment(rawValue: hit.explanation))
                #expect(hit.explanation.hasPrefix(same ? "**Gleich**" : "**Anders**"))
            }
        }
        #expect(sawOption && sawSame)
        #expect(round.isFinished)
        #expect(round.answer(.same(true)) == nil)
    }

    @Test("Die Probe grades the test noun's form and stores the swapped sentence")
    func gradeProbe() {
        var round = self.round(.genitiv, .probe)
        let item = round.currentItem!
        let probe = item.probe!
        let options = probe.options(includeGenitive: true)
        #expect(options.count == 4)
        let miss = options.first { !probe.isRight($0) }!
        let answer = round.answer(.form(miss))!
        #expect(answer.outcome == .caseMiss)
        #expect(answer.kasus == probe.kasus)
        #expect(answer.record.sentence == probe.swappedSentence)
        #expect(answer.record.phrase == probe.swappedPhrase)
        #expect(answer.record.answer == probe.swappedArticle)
        #expect(answer.record.genus == .der)
        #expect(answer.record.pick == miss.split(separator: " ").first.map(String.init))
        #expect(RichMarkup.problems(answer.explanation).isEmpty, Comment(rawValue: answer.explanation))
        #expect(answer.explanation.hasPrefix("Swap in *\(probe.noun.dictionaryForm)*"))
        #expect(probe.kasus(of: probe.answer) == probe.kasus)
        #expect(KasusProbeNoun.mann.form(.genitiv) == "des Mannes")
        #expect(KasusProbeNoun.hund.options(includeGenitive: false) == ["der Hund", "den Hund", "dem Hund"])
    }

    @Test("Every pick on every item explains itself in clean markup", arguments: BundledConcepts.ids)
    func explanationsAreClean(_ id: String) {
        let item = playable(id)
        guard let unit = item.item.unit else { return }
        func check(_ text: String) { #expect(RichMarkup.problems(text).isEmpty, Comment(rawValue: "\(id): \(text)")) }
        switch item.kind {
        case .roles:
            for target in item.askedTargets {
                let actual = item.facts.roles[target.index]!
                for role in KasusRole.chips(for: unit) {
                    check(KasusConceptExplanation.role(picked: role, actual: actual, for: target, in: item.story))
                    check(KasusConceptExplanation.whyNot(role, for: target, item: item))
                }
                check(KasusConceptExplanation.reveal(actual, for: target, in: item.story))
            }
        case .whoDoesWhat:
            check(KasusConceptExplanation.whoDoesWhat(item))
        case .sameMeaning:
            check(KasusConceptExplanation.sameMeaning(item))
        case .probe:
            check(KasusConceptExplanation.probe(item.probe!, in: item.story))
        }
        for paragraph in item.story.paragraphs.indices {
            let cases = Dictionary(uniqueKeysWithValues: item.targets.map { ($0.index, $0.kasus) })
            check(item.englishLine(paragraph: paragraph, highlighting: cases))
        }
    }

    @Test("The role labels, bridges, questions and exercise titles are clean markup")
    func labelsAreClean() {
        for role in KasusRole.allCases {
            for text in [role.bridge, role.question.de, role.question.en] {
                #expect(RichMarkup.problems(text).isEmpty, Comment(rawValue: text))
            }
        }
        for unit in KasusUnit.allCases {
            #expect(RichMarkup.problems(KasusRole.prepositionBridge(for: unit)).isEmpty)
        }
        for exercise in KasusConceptExercise.allCases {
            #expect(!exercise.germanTitle.isEmpty && !exercise.englishTitle.isEmpty && !exercise.blurb.isEmpty)
        }
    }

    // MARK: The walk

    @Test("Schritt für Schritt: Nein until the deciding question, Ja there; a wrong step costs the phrase")
    func walk() {
        // A round whose first phrase is the subject: „Die Frau gibt dem Kind den Ball.“ or alike.
        var round = self.round(.dativ, .roles, mode: .schritt, seed: 3)
        #expect(round.rolesMode == .schritt)
        #expect(round.walk?.questions == [.praeposition, .subjekt, .gleichSubjekt, .empfaenger])
        let actual = round.currentRole!
        var finished: KasusConceptAnswer?
        var steps = 0
        for question in round.walk!.questions {
            let decides = question == actual
            let result = round.answerStep(yes: decides)!
            steps += 1
            #expect(result.right)
            #expect(RichMarkup.problems(result.line).isEmpty, Comment(rawValue: result.line))
            if decides {
                #expect(result.line.hasPrefix("**Ja.**"))
                finished = result.finished
                break
            }
            #expect(result.line.hasPrefix("**Nein**,"))
            #expect(result.finished == nil)
        }
        if actual == .direktesObjekt {
            // Every question got its Nein: the last one ends the walk.
            #expect(round.answers.count == 1)
            #expect(round.answers[0].isRight)
        } else {
            #expect(finished?.isRight == true)
            #expect(round.answers.count == 1)
        }
        #expect(round.cursor == 1)
        #expect(round.walk?.position == 0)   // a fresh walk for the next phrase

        // A wrong Ja at the first question: explained, the walk goes on, the phrase isn't first-try.
        var wrong = self.round(.dativ, .roles, mode: .schritt, seed: 3)
        let role = wrong.currentRole!
        if role != .praeposition {
            let first = wrong.answerStep(yes: true)!
            #expect(!first.right)
            #expect(first.line.hasPrefix("**Nein.**"))
            #expect(first.finished == nil)
            #expect(wrong.walk?.position == 1)
            while let question = wrong.walk?.current {
                let result = wrong.answerStep(yes: question == role)!
                if result.finished != nil { break }
            }
            #expect(wrong.answers.count == 1)
            #expect(!wrong.answers[0].isRight)
            #expect(wrong.answers[0].record.pick == KasusRolesMode.schritt.rawValue)
        }

        // A wrong Nein at the deciding question ends the walk with the answer shown.
        var doch = self.round(.dativ, .roles, mode: .schritt, seed: 3)
        let deciding = doch.currentRole!
        if deciding != .direktesObjekt {
            var result: KasusConceptStepResult?
            while let question = doch.walk?.current {
                result = doch.answerStep(yes: false)
                if question == deciding { break }
            }
            #expect(result?.line.hasPrefix("**Doch**") == true)
            #expect(result?.finished?.isRight == false)
        }
        // Direkt mode has no walk, and answerStep does nothing.
        var direkt = self.round(.dativ, .roles, mode: .direkt)
        #expect(direkt.walk == nil)
        #expect(direkt.answerStep(yes: true) == nil)
    }

    // MARK: Recording

    private func store() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainer(for: LearnerProfile.self, StudyDay.self, KasusRound.self,
                                           configurations: SwiftData.ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return (container, ModelContext(container))
    }

    private func item(_ kasus: GrammarCase, _ genus: Gender, _ right: Bool) -> KasusItemResult {
        KasusItemResult(kasus: kasus, genus: genus, firstTry: right)
    }

    @Test("Rollen, Wer and a lesson never move the coach; the Probe may, even for an f/n/pl Akkusativ")
    func countsTowardSkill() {
        func counts(_ item: KasusItemResult, _ step: KasusRoundStep) -> Bool {
            KasusService.countsTowardSkill(item, step: step, hint: nil)
        }
        #expect(!counts(item(.dativ, .der, true), .roles))
        #expect(!counts(item(.akkusativ, .der, true), .wer))
        #expect(!counts(item(.dativ, .der, true), .lesson))
        #expect(counts(item(.dativ, .die, true), .probe))
        #expect(counts(item(.akkusativ, .die, false), .probe))
        #expect(!counts(item(.nominativ, .die, true), .probe))
        #expect(!counts(KasusItemResult(kasus: .dativ, genus: .die, firstTry: false, revealed: true), .probe))
    }

    @Test("A Probe round with three Dativ answers moves Dativ; a Rollen round moves nothing but counts")
    func recordRounds() throws {
        let (container, context) = try store()
        _ = container
        let probe = KasusRoundResult(storyID: KasusService.conceptRoundID(.dativ, .probe), unit: .dativ, step: .probe,
                                     items: [item(.dativ, .die, false), item(.dativ, .die, false), item(.dativ, .die, true),
                                             item(.akkusativ, .das, true)],
                                     durationSeconds: 40)
        let moves = KasusService.recordRound(probe, in: context)
        #expect(moves.map(\.focus) == [.dativ])
        #expect(moves.first?.total == 3)
        let roles = KasusRoundResult(storyID: KasusService.conceptRoundID(.dativ, .roles), unit: .dativ, step: .roles,
                                     items: Array(repeating: item(.dativ, .das, false), count: 6), durationSeconds: 60)
        #expect(KasusService.recordRound(roles, in: context).isEmpty)
        let days = try context.fetch(FetchDescriptor<StudyDay>())
        #expect(days.reduce(0) { $0 + $1.grammarExercises } == 10)
        let rounds = try context.fetch(FetchDescriptor<KasusRound>())
        #expect(rounds.count == 2)
        let progress = KasusProgress(rounds: rounds)
        #expect(progress.conceptDone(.dativ, .probe))
        #expect(progress.conceptDone(.dativ, .roles))
        #expect(!progress.conceptDone(.dativ, .wer))
        #expect(!progress.verstehenDone(.dativ, offered: [.roles, .wer, .probe]))
        let stored = rounds.first { $0.step == .roles }!
        #expect(stored.isConceptRound && stored.isListed && !stored.isLessonRound)
        #expect(stored.displayTitle(showsUnit: true) == "Rollen · Dativ")
        #expect(stored.displayDetail().hasPrefix("6 Rollen"))
    }

    @Test("A read lesson is one round of nothing, once, and no list shows it")
    func recordLessonRead() throws {
        let (container, context) = try store()
        _ = container
        #expect(KasusService.recordLessonRead(unit: .dativ, seconds: 95, in: context))
        #expect(!KasusService.recordLessonRead(unit: .dativ, seconds: 10, in: context))
        let rounds = try context.fetch(FetchDescriptor<KasusRound>())
        #expect(rounds.count == 1)
        let lesson = try #require(rounds.first)
        #expect(lesson.step == .lesson && lesson.askedCount == 0 && lesson.durationSeconds == 95)
        #expect(lesson.isLessonRound && !lesson.isListed)
        #expect(lesson.displayDetail().hasPrefix("gelesen"))
        let progress = KasusProgress(rounds: rounds)
        #expect(progress.lessonRead(.dativ) && !progress.lessonRead(.akkusativ))
        #expect(progress.verstehenDone(.dativ, offered: []))
        let days = try context.fetch(FetchDescriptor<StudyDay>())
        #expect(days.reduce(0) { $0 + $1.grammarExercises } == 0)
        #expect(days.reduce(0) { $0 + $1.grammarSeconds } == 95)
    }

    @Test("A round with a step this build doesn't know still reads")
    func unknownStep() {
        let round = KasusRound(storyID: "concept-dativ-future", unitRaw: "dativ", stepRaw: "future",
                               askedCount: 3, firstTryCount: 2, durationSeconds: 10)
        #expect(round.step == nil)
        #expect(round.stepLabel == "")
        #expect(round.displayDetail() == "10s")
        #expect(!round.isConceptRound && !round.isLessonRound && round.isListed)
        #expect(round.displayTitle(showsUnit: true) == "Dativ")
    }

    @Test("The hub's Weiter row: the lesson, then Rollen, then the story")
    func kasusPath() throws {
        let bank = KasusStoryBank.bundled.only([KasusTestData.schluesselID])
        let story = try #require(bank.story(id: KasusTestData.schluesselID))
        func played(_ steps: [(String, KasusUnit, KasusRoundStep)]) -> [KasusRound] {
            steps.map { KasusRound(storyID: $0.0, unitRaw: $0.1.rawValue, stepRaw: $0.2.rawValue,
                                   askedCount: 1, firstTryCount: 1, durationSeconds: 0,
                                   date: Date().addingTimeInterval(-86_400)) }
        }
        func next(_ rounds: [KasusRound]) -> KasusHero {
            KasusPath.next(profile: nil, level: .a1, rounds: rounds, bank: bank, concepts: self.bank)
        }
        let fresh = next([])
        #expect(fresh.unit == .dativ && fresh.action == .lesson && fresh.reason == .understand)
        #expect(fresh.subtitle == "Lektion · Verstehen")
        let read = next(played([(KasusService.lessonRoundID(.dativ), .dativ, .lesson)]))
        #expect(read.action == .concept(.roles) && read.reason == .understand)
        #expect(read.conceptSession?.exercise == .roles)
        let rolled = next(played([(KasusService.lessonRoundID(.dativ), .dativ, .lesson),
                                  (KasusService.conceptRoundID(.dativ, .roles), .dativ, .roles)]))
        #expect(rolled.storyID == story.id && rolled.step == .lesen && rolled.reason == .newStory)
        // Without the items in hand, the path is as before.
        let before = KasusPath.next(profile: nil, level: .a1, rounds: [], bank: bank)
        #expect(before.storyID == story.id && before.reason == .newStory)
    }
}
