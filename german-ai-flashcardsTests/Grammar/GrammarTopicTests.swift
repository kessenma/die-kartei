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
        // A topic without a focus yet never moves, however many answers count.
        let topic = KasusRound(storyID: "reflexcase-reflexiv", unitRaw: "reflexiv", stepRaw: "reflexcase", askedCount: 8,
                               firstTryCount: 8, durationSeconds: 10, items: Array(repeating: item(.dativ, counts: true), count: 8))
        #expect(topic.coachMoves.isEmpty)
    }
}
