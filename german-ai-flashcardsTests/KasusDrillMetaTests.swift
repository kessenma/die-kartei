//
//  KasusDrillMetaTests.swift
//  german-ai-flashcardsTests
//
//  The registry (`KasusRoundStep.swift`): the stored raw values stay what they are, every kind's
//  raw value is its step's, filing ids never move, the Verstehen exercises read the same strings
//  they used to carry, and Verlauf, the calendar and the round detail print per-step strings from
//  the meta. A new step is one case and one meta row; these tests say what that row must keep.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@Suite("Kasus drill registry")
struct KasusDrillMetaTests {

    @Test("The stored raw values, pinned")
    func rawValues() {
        #expect(KasusRoundStep.allCases.map(\.rawValue) == [
            "find", "fill", "quick", "build", "roles", "wer", "probe", "lesson",
            "blitz", "pair", "dativverben", "fehler", "reflexcase", "reflexperson", "bridge",
        ])
        #expect(KasusRoundStep.allCases.count == 15)
    }

    @Test("A kind's raw value is its step's; the story steps and the lesson are no kinds")
    func kinds() {
        for kind in KasusDrillKind.allCases {
            #expect(kind.rawValue == kind.step.rawValue)
            #expect(KasusDrillKind(rawValue: kind.rawValue) == kind)
            #expect(KasusDrillKind(step: kind.step) == kind)
            #expect(kind.meta == kind.step.meta)
        }
        #expect(KasusDrillKind(step: .find) == nil)
        #expect(KasusDrillKind(step: .fill) == nil)
        #expect(KasusDrillKind(step: .lesson) == nil)
        #expect(KasusDrillKind(rawValue: "future") == nil)
        #expect(Set(KasusDrillKind.allCases.map(\.step)).count == KasusDrillKind.allCases.count)
    }

    @Test("Every step has a row that fits its filing")
    func metaRows() {
        for step in KasusRoundStep.allCases {
            let meta = step.meta
            #expect(!meta.germanTitle.isEmpty && !meta.englishTitle.isEmpty && !meta.symbol.isEmpty)
            #expect(!meta.countNoun.de.isEmpty && !meta.countNoun.en.isEmpty)
            #expect(meta.minItemsPerFocus >= KasusService.minItemsPerCase)
            switch meta.filing {
            case .story:
                #expect(KasusDrillKind(step: step) == nil && meta.placement == .story)
                #expect(step.roundID(topicKey: "dativ").isEmpty)
            case .lesson:
                #expect(step == .lesson && meta.coachPolicy == .never)
            case .topicDrill, .concept:
                #expect(KasusDrillKind(step: step) != nil)
                #expect(step.roundID(topicKey: "dativ").hasSuffix(meta.filing == .concept ? "dativ-\(step.rawValue)" : "-dativ"))
            }
            if meta.coachPolicy == .never { #expect(!meta.marksUnitDone || step == .quick) }
        }
        #expect(KasusRoundStep.allCases.filter(\.meta.marksUnitDone) == [.quick])
        #expect(KasusRoundStep.allCases.filter(\.isConcept) == [.roles, .wer, .probe, .lesson])
        #expect(KasusRoundStep.allCases.filter { $0.meta.filing == .topicDrill }.contains(.build))
        #expect(KasusRoundStep.reflexPerson.meta.singleCaseAllowed && !KasusRoundStep.quick.meta.singleCaseAllowed)
        #expect(!KasusRoundStep.blitz.meta.allowsReference && KasusRoundStep.quick.meta.allowsReference)
    }

    @Test("Filing ids never move")
    func roundIDs() {
        #expect(KasusRoundStep.quick.roundID(topicKey: "dativ") == "quick-dativ")
        #expect(KasusRoundStep.build.roundID(topicKey: "dativ") == "build-dativ")
        #expect(KasusRoundStep.roles.roundID(topicKey: "dativ") == "concept-dativ-roles")
        #expect(KasusRoundStep.wer.roundID(topicKey: "akkusativ") == "concept-akkusativ-wer")
        #expect(KasusRoundStep.probe.roundID(topicKey: "genitiv") == "concept-genitiv-probe")
        #expect(KasusRoundStep.lesson.roundID(topicKey: "dativ") == "concept-dativ-lesson")
        #expect(KasusRoundStep.blitz.roundID(topicKey: "dativ") == "blitz-dativ")
        #expect(KasusRoundStep.reflexCase.roundID(topicKey: "reflexiv") == "reflexcase-reflexiv")
        #expect(KasusService.quickRoundID(for: .dativ) == "quick-dativ")
        #expect(KasusService.buildRoundID(for: .alleFaelle) == "build-alleFaelle")
        #expect(KasusService.conceptRoundID(.dativ, .roles) == "concept-dativ-roles")
        #expect(KasusService.lessonRoundID(.dativ) == "concept-dativ-lesson")
        #expect(KasusService.conceptIDPrefix == "concept-")

        let items = [KasusItemResult(kasus: .dativ, genus: .der, firstTry: true)]
        #expect(KasusService.quickResult(unit: .dativ, items: items, durationSeconds: 1).storyID == "quick-dativ")
        #expect(KasusService.quickResult(unit: .dativ, items: items, durationSeconds: 1, step: .build).storyID == "build-dativ")
        let blitz = KasusService.drillResult(step: .blitz, topic: .kasus(.dativ), items: items, durationSeconds: 1)
        #expect(blitz.storyID == "blitz-dativ" && blitz.topic == .kasus(.dativ) && blitz.unit == .dativ)
        // Nothing but the Schnellrunde may ever file under quick-<unit>.
        #expect(KasusRoundStep.allCases.filter { $0.roundID(topicKey: "dativ") == "quick-dativ" } == [.quick])
    }

    @Test("A result built with a unit files under that unit's key")
    func resultConvenience() {
        let result = KasusRoundResult(storyID: "test", unit: .akkusativ, step: .fill, hintLevel: .ohne,
                                      items: [], durationSeconds: 3, feedbackMode: .sofort)
        #expect(result.topic == .kasus(.akkusativ) && result.unit == .akkusativ)
        #expect(result.hintLevel == .ohne && result.feedbackMode == .sofort)
        #expect(KasusService.round(for: result).unitRaw == "akkusativ")
    }

    @Test("The Verstehen exercises read the strings they used to carry")
    func conceptExerciseForwards() {
        #expect(KasusConceptExercise.roles.germanTitle == "Rollen")
        #expect(KasusConceptExercise.roles.englishTitle == "Who does what?")
        #expect(KasusConceptExercise.roles.symbol == "tag.fill")
        #expect(KasusConceptExercise.roles.roundSize == 8 && KasusConceptExercise.roles.minimumItems == 4 && KasusConceptExercise.roles.minutes == 4)
        #expect(KasusConceptExercise.wer.germanTitle == "Wer macht was?" && KasusConceptExercise.wer.englishTitle == "Only the ending tells")
        #expect(KasusConceptExercise.wer.symbol == "person.2.fill" && KasusConceptExercise.wer.roundSize == 10 && KasusConceptExercise.wer.minimumItems == 6 && KasusConceptExercise.wer.minutes == 3)
        #expect(KasusConceptExercise.probe.germanTitle == "Die Probe" && KasusConceptExercise.probe.englishTitle == "Swap in der Mann")
        #expect(KasusConceptExercise.probe.symbol == "arrow.2.squarepath" && KasusConceptExercise.probe.roundSize == 8 && KasusConceptExercise.probe.minimumItems == 4 && KasusConceptExercise.probe.minutes == 3)
        #expect(KasusConceptExercise.roles.blurb == "Name each phrase's job: the doer, the done-to, the receiver …")
        for exercise in KasusConceptExercise.allCases {
            #expect(exercise.roundStep == exercise.kind.step)
            #expect(KasusConceptExercise(step: exercise.roundStep) == exercise)
        }
        #expect(KasusRoundStep.quick.germanLabel == "Schnellrunde" && KasusRoundStep.build.germanLabel == "Bau das Wort")
        #expect(KasusRoundStep.find.legacyGermanLabel == "Finden" && KasusRoundStep.fill.legacyGermanLabel == "Einsetzen")
        #expect(KasusRoundStep.quick.legacyGermanLabel == "Schnellrunde")
    }

    @Test("Verlauf and the round detail print per-step strings from the meta")
    @MainActor
    func historyStrings() {
        func round(_ step: KasusRoundStep, asked: Int = 10, right: Int = 7, seconds: Int = 65) -> KasusRound {
            KasusRound(storyID: step.roundID(topicKey: "dativ"), unitRaw: "dativ", stepRaw: step.rawValue,
                       askedCount: asked, firstTryCount: right, durationSeconds: seconds)
        }
        #expect(round(.quick).displayDetail() == "10 Sätze · 1m 5s")
        #expect(round(.build).displayDetail() == "10 Wörter · 1m 5s")
        #expect(round(.roles, asked: 8).displayDetail() == "8 Rollen · 1m 5s")
        #expect(round(.wer).displayDetail() == "10 Sätze · 1m 5s")
        #expect(round(.probe, asked: 8).displayDetail() == "8 Formen · 1m 5s")
        #expect(round(.lesson, asked: 0, right: 0).displayDetail() == "gelesen · 1m 5s")
        #expect(round(.blitz, asked: 23).displayDetail() == "23 Sätze · 1m 5s")
        #expect(round(.quick).displayTitle(showsUnit: true) == "Schnellrunde · Dativ")
        #expect(round(.build).displayTitle(showsUnit: true) == "Bau das Wort · Dativ")
        #expect(round(.roles).displayTitle(showsUnit: true) == "Rollen · Dativ")
        #expect(round(.blitz).displayTitle(showsUnit: true) == "Blitzrunde · Dativ")
        #expect(round(.quick).isQuickRound && round(.build).isQuickRound && round(.blitz).isQuickRound)
        #expect(!round(.roles).isQuickRound && round(.roles).isConceptRound && !round(.blitz).isConceptRound)
        #expect(round(.quick).topic == .kasus(.dativ))

        #expect(KasusItemOutcome.wrongPick.labels(for: .roles) == ("Andere Rolle", "Another role"))
        #expect(KasusItemOutcome.wrongPick.labels(for: .wer) == ("Anders gelesen", "Read the other way"))
        #expect(KasusItemOutcome.wrongPick.labels(for: .quick) == ("Anderer Fall", "Marked as another case"))
        #expect(KasusItemOutcome.caseMiss.labels(for: .roles) == ("Falscher Fall", "Wrong case"))
        #expect(KasusItemOutcome.wrongPick.labels(for: .reflexPerson) == ("Andere Person", "Another person"))
        #expect(KasusItemOutcome.wrongPick.labels(for: nil) == ("Anderer Fall", "Marked as another case"))
    }

    @Test("A round under a topic this build doesn't know still reads as a plain Kasus row")
    @MainActor
    func unknownTopic() {
        let round = KasusRound(storyID: "reflexcase-reflexiv", unitRaw: "reflexiv", stepRaw: "reflexcase",
                               askedCount: 10, firstTryCount: 6, durationSeconds: 40)
        #expect(round.unit == nil && round.topic == nil)
        #expect(round.step == .reflexCase && round.isQuickRound && round.isListed)
        #expect(round.displayTitle(showsUnit: true) == "Akkusativ oder Dativ?")
        #expect(round.displayDetail() == "10 Sätze · 40s")
        let progress = KasusProgress(rounds: [round])
        #expect(progress.drillDone(.reflexCase, topicKey: "reflexiv"))
        #expect(!progress.drillDone(.reflexCase, topicKey: "dativ"))
    }

    @Test("Done marks key on the step's own round id in the topic")
    func doneMarks() {
        let quick = KasusRound(storyID: "quick-dativ", unitRaw: "dativ", stepRaw: "quick",
                               askedCount: 10, firstTryCount: 9, durationSeconds: 50)
        let roles = KasusRound(storyID: "concept-dativ-roles", unitRaw: "dativ", stepRaw: "roles",
                               askedCount: 8, firstTryCount: 8, durationSeconds: 90)
        let progress = KasusProgress(rounds: [quick, roles])
        #expect(progress.quickRoundDone(.dativ) && !progress.quickRoundDone(.akkusativ))
        #expect(progress.drillDone(.quick, topicKey: "dativ") && !progress.drillDone(.build, topicKey: "dativ"))
        #expect(progress.conceptDone(.dativ, .roles) && !progress.conceptDone(.dativ, .wer))
        #expect(!progress.lessonRead(.dativ))
        #expect(progress.isDone(storyID: "quick-dativ", topicKey: "dativ", step: .quick))
    }

    @Test("The coach policy per step gives the old answers")
    func coachPolicy() {
        func counts(_ kasus: GrammarCase, _ genus: Gender, _ step: KasusRoundStep, hint: KasusHintLevel? = nil) -> Bool {
            KasusService.countsTowardSkill(KasusItemResult(kasus: kasus, genus: genus, firstTry: true), step: step, hint: hint)
        }
        #expect(!counts(.dativ, .der, .find) && !counts(.dativ, .der, .roles) && !counts(.dativ, .der, .wer) && !counts(.dativ, .der, .lesson))
        #expect(counts(.dativ, .der, .probe) && counts(.akkusativ, .die, .probe))
        #expect(counts(.akkusativ, .der, .quick) && !counts(.akkusativ, .die, .quick))
        #expect(counts(.dativ, .die, .build) && !counts(.akkusativ, .plural, .build))
        #expect(!counts(.dativ, .der, .fill, hint: .lern) && counts(.dativ, .die, .fill, hint: .ohne))
        #expect(!counts(.nominativ, .der, .probe))
        // The new kinds, by their policy.
        #expect(!counts(.dativ, .der, .blitz) && !counts(.dativ, .der, .pair) && !counts(.dativ, .der, .bridge))
        #expect(counts(.dativ, .der, .reflexCase) && counts(.akkusativ, .die, .reflexPerson))
        #expect(counts(.dativ, .der, .dativVerbs) && !counts(.akkusativ, .die, .dativVerbs))
        #expect(counts(.dativ, .der, .fehler) && !counts(.akkusativ, .das, .fehler))
    }

    @Test("A topic keys on the unit's raw value and offers the unit's exercises")
    @MainActor
    func topics() {
        #expect(GrammarTopic(key: "dativ") == .kasus(.dativ))
        #expect(GrammarTopic(key: "Dativ") == .kasus(.dativ))
        #expect(GrammarTopic(key: "alleFaelle") == .kasus(.alleFaelle))
        #expect(GrammarTopic(key: "reflexiv") == nil)
        #expect(GrammarTopic.allCases.map(\.key) == KasusUnit.allCases.map(\.rawValue))
        for topic in GrammarTopic.allCases {
            #expect(GrammarTopic(key: topic.key) == topic)
            #expect(topic.unit != nil && topic.germanTitle == topic.unit?.germanTitle)
            #expect(topic.casesInPlay == topic.unit?.casesInPlay && topic.focus == topic.unit?.focus)
        }
        #expect(GrammarTopic.kasus(.dativ).exercises() == [.roles, .wer, .probe, .quick, .build])
        #expect(GrammarTopic.kasus(.nominativ).exercises() == [.roles, .quick, .build])
        #expect(GrammarTopic.kasus(.dativ).lessonPractice == .roles)
    }
}
