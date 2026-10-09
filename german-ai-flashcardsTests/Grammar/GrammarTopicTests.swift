//
//  GrammarTopicTests.swift
//  german-ai-flashcardsTests
//
//  The topic layer: every topic's lesson prose is clean markup, a unit's topic answers what the
//  unit did, a round files and reads back by its topic, and the coach moves read off a stored
//  round agree with the recording rule.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Grammar topics")
struct GrammarTopicTests {

    @Test("Every topic's rule lines, cards and memory aids are clean markup")
    @MainActor
    func cleanMarkup() {
        for topic in GrammarTopic.allCases {
            for line in topic.ruleLines { #expect(RichMarkup.problems(line).isEmpty, "\(topic.key): \(line)") }
            for card in topic.lessonCards {
                for line in card.lines { #expect(RichMarkup.problems(line).isEmpty, "\(topic.key): \(line)") }
            }
            for aid in topic.mnemonics { #expect(RichMarkup.problems(aid.line).isEmpty, "\(topic.key): \(aid.line)") }
        }
    }

    @Test("A unit's topic is the unit")
    @MainActor
    func unitTopics() {
        for unit in KasusUnit.allCases {
            let topic = GrammarTopic.kasus(unit)
            #expect(topic.key == unit.rawValue && topic.unit == unit)
            #expect(topic.symbol == unit.symbol && topic.levelLabel == unit.levelLabel && topic.englishRole == unit.englishRole)
            #expect(topic.ruleLines == unit.ruleLines && topic.emphasis == unit.focusCase)
            #expect(topic.lessonCards.map(\.title) == KasusLesson.cards(for: unit).map(\.title))
            #expect(topic.mnemonics == KasusMnemonics.forUnit(unit))
        }
    }

    @Test("Lesson reads file under the topic key, for a unit and for a topic")
    @MainActor
    func lessonReads() {
        let dativ = KasusRound(storyID: KasusRoundStep.lesson.roundID(topicKey: "dativ"), unitRaw: "dativ",
                               stepRaw: "lesson", askedCount: 0, firstTryCount: 0, durationSeconds: 60)
        let reflexiv = KasusRound(storyID: KasusRoundStep.lesson.roundID(topicKey: "reflexiv"), unitRaw: "reflexiv",
                                  stepRaw: "lesson", askedCount: 0, firstTryCount: 0, durationSeconds: 60)
        let progress = KasusProgress(rounds: [dativ, reflexiv])
        #expect(progress.lessonRead(.dativ) && progress.lessonRead(topicKey: "dativ"))
        #expect(progress.lessonRead(topicKey: "reflexiv") && !progress.lessonRead(.akkusativ))
        #expect(reflexiv.isLessonRound && !reflexiv.isListed && reflexiv.topic == .reflexiv)
    }

    @Test("Coach moves read off a stored round agree with the recording rule")
    func coachMoves() {
        func item(_ kasus: GrammarCase, counts: Bool) -> KasusRoundItem {
            var item = KasusRoundItem(sentence: "s", phraseStart: 0, phrase: "p", answer: "dem", pick: "dem",
                                      kasus: kasus, genus: .der, outcome: .right, explanation: "why")
            item.countsTowardSkill = counts
            return item
        }
        let moved = KasusRound(storyID: "quick-dativ", unitRaw: "dativ", stepRaw: "quick", askedCount: 5, firstTryCount: 5,
                               durationSeconds: 10, items: [item(.dativ, counts: true), item(.dativ, counts: true),
                                                            item(.dativ, counts: true), item(.akkusativ, counts: true),
                                                            item(.nominativ, counts: false)])
        #expect(moved.coachMoves == [.dativ])
        let few = KasusRound(storyID: "quick-dativ", unitRaw: "dativ", stepRaw: "quick", askedCount: 2, firstTryCount: 2,
                             durationSeconds: 10, items: [item(.dativ, counts: true), item(.dativ, counts: true)])
        #expect(few.coachMoves.isEmpty)
        // A topic that isn't a case pools both cases into its one focus, from six counting answers.
        let topic = KasusRound(storyID: "reflexcase-reflexiv", unitRaw: "reflexiv", stepRaw: "reflexcase", askedCount: 8,
                               firstTryCount: 8, durationSeconds: 10,
                               items: Array(repeating: item(.dativ, counts: true), count: 4) + Array(repeating: item(.akkusativ, counts: true), count: 4))
        #expect(topic.coachMoves == [.reflexivverben])
        let fewTopic = KasusRound(storyID: "reflexcase-reflexiv", unitRaw: "reflexiv", stepRaw: "reflexcase", askedCount: 5,
                                  firstTryCount: 5, durationSeconds: 10, items: Array(repeating: item(.dativ, counts: true), count: 5))
        #expect(fewTopic.coachMoves.isEmpty)
    }

    @Test("The reflexive topic has a lesson in the units' shape, and its focus files under Strukturen")
    @MainActor
    func reflexivTopic() {
        let cards = GrammarTopic.reflexiv.lessonCards
        #expect((4...6).contains(cards.count) && Set(cards.map(\.title)).count == cards.count)
        #expect(cards.first?.showsColorKey == true && cards.last?.mnemonic != nil)
        for card in cards {
            #expect(card.example?.en.isEmpty == false, Comment(rawValue: "„\(card.title)“ has no English twin"))
        }
        #expect(GrammarTopic.reflexiv.ruleLines.count == 3)
        #expect(GrammarFocus.reflexivverben.introducedAt == .a2)
        #expect(GrammarRoute(.reflexivverben) == .topic(.reflexiv) && GrammarRoute.topic(.reflexiv).presentation == .launch)
        #expect(PyramidCoachSection.area(for: .reflexivverben) == .strukturen)
        // The badge threshold stays allCases.count / 2, now 7 of 14.
        #expect(GrammarFocus.allCases.count == 14)
    }
}
