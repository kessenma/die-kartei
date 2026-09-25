//
//  KasusPlayStateTests.swift
//  german-ai-flashcardsTests
//
//  The story player's two state machines, `KasusMarkPlay` (Markieren) and `KasusEndingsPlay`
//  (Endungen), without any UI: where the record-once and Lösung zeigen rules live. A round is
//  handed on to be recorded exactly once, on its first attempt; Noch mal, a mode switch and a
//  second Prüfen never record again; „Nächster Fall“ is a round of its own; Lösung zeigen flags
//  only the attempt that was recorded; a DEBUG prefill records nothing; and a reset leaves
//  nothing from the last attempt showing.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Kasus player state")
struct KasusPlayStateTests {
    let story: KasusStory
    let playable: KasusPlayableStory

    init() throws {
        story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
    }

    // MARK: Markieren

    private func markPlay(_ mode: KasusFeedbackMode = .amEnde) -> KasusMarkPlay {
        var play = KasusMarkPlay()
        play.start(in: playable, unit: .dativ, mode: mode)
        return play
    }

    /// Marks the mixed prefill's words on the round on screen.
    private func markSome(_ play: inout KasusMarkPlay) throws {
        var round = try #require(play.round)
        for id in KasusService.debugMarks(for: round, answers: .mixed) { round.tap(id) }
        play.round = round
    }

    private func check(_ play: inout KasusMarkPlay) -> KasusRoundResult? {
        play.check(storyID: story.id, unit: .dativ, in: playable)
    }

    @Test("Markieren records its first Prüfen once; Noch mal and a second Prüfen never again")
    func markRecordsOnce() throws {
        var play = markPlay()
        #expect(play.cases == [.dativ, .akkusativ, .nominativ] && play.round?.kasus == .dativ)
        try markSome(&play)
        let first = try #require(check(&play))
        #expect(first.id == play.round?.id && first.markCase == .dativ && play.isPlayed && play.attemptRecorded)
        #expect(check(&play) == nil, "already checked")

        play.retry()
        #expect(play.round?.attempt == 2 && play.round?.isChecked == false && !play.attemptRecorded)
        try markSome(&play)
        #expect(check(&play) == nil, "Noch mal is never recorded")
        #expect(play.showAnswers() == nil, "Lösung zeigen on an unrecorded attempt flags nothing")
    }

    @Test("Lösung zeigen flags the recorded attempt once, and only after Prüfen")
    func markShowAnswers() throws {
        var play = markPlay()
        try markSome(&play)
        #expect(play.showAnswers() == nil, "nothing to show before Prüfen")
        let result = try #require(check(&play))
        #expect(play.showAnswers() == result.id)
        #expect(play.round?.answersShown == true)
        #expect(play.showAnswers() == nil, "only once")
    }

    @Test("Switching the mode after Prüfen starts a fresh attempt of the same round, never recorded twice")
    func markSwitchMode() throws {
        var play = markPlay()
        try markSome(&play)
        let result = try #require(check(&play))
        play.switchMode(to: .sofort, in: playable)
        #expect(play.round?.id == result.id && play.round?.mode == .sofort && play.round?.marked.isEmpty == true)
        try markSome(&play)
        #expect(check(&play) == nil)
        #expect(play.showAnswers() == nil, "the fresh attempt wasn't the recorded one")
    }

    @Test("Nächster Fall is a new round, recorded on its own")
    func markNextCase() throws {
        var play = markPlay()
        try markSome(&play)
        let dative = try #require(check(&play))
        play.startCase(play.caseIndex + 1, in: playable, mode: .amEnde)
        #expect(play.round?.kasus == .akkusativ && play.round?.id != dative.id)
        try markSome(&play)
        let akk = try #require(check(&play))
        #expect(akk.markCase == .akkusativ && akk.id != dative.id)
        #expect(play.recordedIDs == [dative.id, akk.id])
    }

    @Test("„Alle Fälle“ goes off with Noch mal, a mode switch and the next case")
    func markAllCasesResets() throws {
        var play = markPlay()
        try markSome(&play)
        _ = check(&play)
        play.showAllCases = true
        play.retry()
        #expect(!play.showAllCases, "a fresh attempt mustn't open with every answer colored in")

        _ = check(&play)
        play.showAllCases = true
        play.switchMode(to: .sofort, in: playable)
        #expect(!play.showAllCases)

        play.showAllCases = true
        play.startCase(1, in: playable, mode: .amEnde)
        #expect(!play.showAllCases)
    }

    @Test("A DEBUG prefill is checked like a round but never handed on")
    func markPrefill() throws {
        var play = markPlay()
        play.prefilled = true
        try markSome(&play)
        #expect(check(&play) == nil)
        #expect(play.isPlayed, "the step bar still shows it as played")
        #expect(play.showAnswers() == nil)
    }

    // MARK: Endungen

    private func endingsPlay(_ mode: KasusFeedbackMode, hint: KasusHintLevel = .ohne) -> KasusEndingsPlay {
        var play = KasusEndingsPlay()
        play.hintOverride = hint
        play.modeOverride = mode
        play.start(in: playable, unit: .dativ, germanLevel: .a2)
        return play
    }

    private func result(_ play: inout KasusEndingsPlay) -> KasusRoundResult? {
        play.resultIfFinished(storyID: story.id, unit: .dativ, story: story)
    }

    /// Picks every gap's answer except `wrong` ones, which get another ending.
    private func fillAll(_ play: inout KasusEndingsPlay, wrong: Int = 1) throws {
        var round = try #require(play.round)
        for (i, gap) in round.gaps.enumerated() {
            var pick = gap.answer
            if i < wrong { pick = try #require(gap.options.first { $0 != gap.answer }) }
            round.choose(pick, for: gap.id)
        }
        play.round = round
    }

    @Test("Endungen Am Ende records at Prüfen once; Noch mal doesn't, and Lösung zeigen flags the recorded one")
    func endingsAmEnde() throws {
        var play = endingsPlay(.amEnde)
        let gaps = try #require(play.round?.gaps)
        try #require(gaps.count >= 3)
        #expect(play.activeGap == gaps.first?.id, "a fresh round focuses its first gap")
        try fillAll(&play)
        #expect(result(&play) == nil, "not finished before Prüfen")
        var round = try #require(play.round)
        round.check()
        play.round = round
        let recorded = try #require(result(&play))
        #expect(recorded.id == round.id && recorded.feedbackMode == .amEnde && play.attemptRecorded)
        #expect(result(&play) == nil, "once")
        #expect(play.showAnswers() == recorded.id)

        play.retry()
        #expect(play.round?.attempt == 2 && play.round?.picks.isEmpty == true && play.activeGap == gaps.first?.id)
        try fillAll(&play)
        round = try #require(play.round)
        round.check()
        play.round = round
        #expect(result(&play) == nil, "Noch mal is never recorded")
        #expect(play.showAnswers() == nil)
    }

    @Test("Endungen Sofort records at the last pick; Lösung zeigen first rides along in that result")
    func endingsSofort() throws {
        var play = endingsPlay(.sofort)
        var round = try #require(play.round)
        let first = try #require(round.gaps.first)
        round.choose(first.answer, for: first.id)
        play.round = round
        #expect(result(&play) == nil)
        // Giving up on the rest: nothing was recorded yet, so there's no id to flag...
        #expect(play.showAnswers() == nil)
        // ...and the round, now finished, carries the flag itself.
        let recorded = try #require(result(&play))
        #expect(recorded.revealedAnswers && recorded.answeredCount == 1)
        #expect(recorded.items.filter(\.revealed).count == (play.round?.gaps.count ?? 0) - 1)
    }

    @Test("A Tipp locks the help level and the mode, like a pick, until the round is finished")
    func endingsTippLocks() throws {
        var play = endingsPlay(.sofort)
        var round = try #require(play.round)
        #expect(!round.settingsLocked)
        let gap = try #require(round.gaps.first)
        round.recordTipp(.answer, for: gap.id)
        #expect(round.settingsLocked, "rebuilding the round would forget the Tipp")
        play.round = round
        try fillAll(&play, wrong: 0)
        #expect(play.round?.isFinished == true && play.round?.settingsLocked == false)
        let recorded = try #require(result(&play))
        let tipped = try #require(recorded.items.first { $0.targetIndex == gap.id })
        #expect(tipped.tipp == .answer && !KasusService.countsTowardSkill(tipped, step: .fill, hint: .ohne),
                "an answer the Tipp showed never counts")
    }

    @Test("A mode switch before the first pick keeps the round and its id")
    func endingsSwitchMode() throws {
        var play = endingsPlay(.sofort)
        let id = try #require(play.round?.id)
        let generation = play.generation
        play.switchMode(to: .amEnde)
        #expect(play.round?.id == id && play.round?.mode == .amEnde && play.generation == generation + 1)
    }
}
