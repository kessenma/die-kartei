//
//  KasusRound.swift
//  german-ai-flashcards
//
//  One scored step on the Grammatik path: a story's Markieren (one case) or Endungen, or a unit's
//  Schnellrunde. Rounds from before Markieren and Endungen replaced the brush-sorting Finden and
//  the whole-article Einsetzen keep their step raw values (find, fill) and have no feedback mode,
//  which is how `stepLabel` tells them apart.
//  Written by `KasusService.recordRound`, read by the day detail in the streak calendar, the story
//  rows' step marks and the hub's "Weiter" pick (`KasusPath.next`). The step enum and its meta
//  (the registry) are in `KasusRoundStep.swift`; the answers' types in `KasusRoundItem.swift`.
//
//  Everything keys on (storyID, unitRaw, stepRaw), never on a display string, so a retitled story
//  keeps its history. A Schnellrunde has no story; it is filed under "quick-<unit>".
//
//  Each round also keeps its answers (`items`, one `KasusRoundItem` each: the sentence, the pick,
//  the answer and why), which is what Verlauf's round detail shows. Rounds recorded before that
//  have none and show their counts only. A Markieren round counts words, not items: `askedCount`
//  is the words to find, `firstTryCount` those marked, `wrongCount` the words marked wrongly, and
//  its score is the class sheet's (`markScore`). Lösung zeigen after recording sets
//  `revealedAnswers` on the same row (`KasusService.markAnswersShown`).
//
//  Additive, with every field defaulted: the store recreates itself when a migration fails, so a
//  new model must never be the thing that makes one fail.
//

import Foundation
import SwiftData

@Model
final class KasusRound {
    var date: Date = Date()
    /// The story's id, or "quick-<unit>" for a Schnellrunde (`KasusService.quickRoundID(for:)`).
    var storyID: String = ""
    /// A `KasusUnit` raw value.
    var unitRaw: String = ""
    /// A `KasusRoundStep` raw value: find · fill · quick.
    var stepRaw: String = ""
    /// A `KasusHintLevel` raw value for Einsetzen; empty for Finden and the Schnellrunde.
    var hintLevelRaw: String = ""
    var askedCount: Int = 0
    var firstTryCount: Int = 0
    var durationSeconds: Int = 0
    /// Encoded `[String: CaseTally]`, keyed by `GrammarCase` raw value.
    var perCaseData: Data?
    /// Encoded `[KasusRoundItem]`, in reading (or question) order. Nil on rounds recorded before
    /// the history kept answers, and on the debug checks' synthetic rounds.
    var itemsData: Data? = nil
    /// A `KasusFeedbackMode` raw value (sofort · amEnde) for Markieren and Endungen. Empty on the
    /// Schnellrunde and on rounds from before the two exercises.
    var feedbackModeRaw: String = ""
    /// Markieren: the `GrammarCase` raw value the round asked. Empty otherwise.
    var markCaseRaw: String = ""
    /// Markieren: words marked that weren't in the asked case. The class score is
    /// max(0, firstTryCount − wrongCount) / askedCount.
    var wrongCount: Int = 0
    /// Lösung zeigen was tapped on this round, before or after it was recorded.
    var revealedAnswers: Bool = false
    /// `KasusRoundResult.id`, so Lösung zeigen after recording finds this row. Empty on older rounds.
    var roundKey: String = ""

    init(
        storyID: String,
        unitRaw: String,
        stepRaw: String,
        hintLevelRaw: String = "",
        askedCount: Int,
        firstTryCount: Int,
        durationSeconds: Int,
        perCase: [GrammarCase: CaseTally] = [:],
        items: [KasusRoundItem] = [],
        date: Date = Date(),
        feedbackModeRaw: String = "",
        markCaseRaw: String = "",
        wrongCount: Int = 0,
        revealedAnswers: Bool = false,
        roundKey: String = ""
    ) {
        self.date = date
        self.storyID = storyID
        self.unitRaw = unitRaw
        self.stepRaw = stepRaw
        self.hintLevelRaw = hintLevelRaw
        self.askedCount = askedCount
        self.firstTryCount = firstTryCount
        self.durationSeconds = durationSeconds
        self.perCase = perCase
        self.items = items
        self.feedbackModeRaw = feedbackModeRaw
        self.markCaseRaw = markCaseRaw
        self.wrongCount = wrongCount
        self.revealedAnswers = revealedAnswers
        self.roundKey = roundKey
    }

    /// One case's share of the round.
    nonisolated struct CaseTally: Codable, Hashable {
        var asked: Int = 0
        var firstTry: Int = 0
    }

    var unit: KasusUnit? { KasusUnit(rawValue: unitRaw) }
    /// The topic the round files under: a unit of the case path, or a topic of its own.
    var topic: GrammarTopic? { GrammarTopic(key: unitRaw) }
    var step: KasusRoundStep? { KasusRoundStep(rawValue: stepRaw) }
    var hintLevel: KasusHintLevel? { KasusHintLevel(rawValue: hintLevelRaw) }
    /// A unit drill with no story: the Schnellrunde, or Bau das Wort on its sentences.
    var isQuickRound: Bool { step?.meta.filing == .topicDrill }
    /// A Verstehen round (Rollen, Wer macht was?, Die Probe) or a read lesson.
    var isConceptRound: Bool { step?.isConcept == true }
    /// A read lesson: no answers, never listed.
    var isLessonRound: Bool { step == .lesson }
    var feedbackMode: KasusFeedbackMode? { KasusFeedbackMode(rawValue: feedbackModeRaw) }
    /// Markieren's asked case. Nil on every other round, the old Finden's included.
    var markCase: GrammarCase? { GrammarCase(rawValue: markCaseRaw) }
    /// A Markieren round (one case, counted in words), not an old brush-sorting Finden.
    var isMarkingRound: Bool { step == .find && markCase != nil }
    /// Recorded before Markieren and Endungen replaced Finden and Einsetzen.
    var isLegacyStoryRound: Bool { (step == .find || step == .fill) && feedbackModeRaw.isEmpty }

    /// This round really happened: not one of the synthetic rows `-kasus.debugVerifyRecord keep`
    /// leaves behind. The one predicate every aggregation over time, days or cases applies — a
    /// read lesson *is* study (reading a lesson is grammar time), it just isn't a listed row.
    var countsAsStudy: Bool {
        #if DEBUG
        storyID != KasusService.debugVerifyStoryID
        #else
        true
        #endif
    }

    /// A row in Verlauf and in a topic's „Deine Runden“: a round that really happened and asked
    /// something. A read lesson answers nothing; the unit screen's ✓ is where it shows.
    var isListed: Bool { countsAsStudy && !isLessonRound }

    /// „Markieren · Dativ“, „Endungen“, „Schnellrunde“, or the old „Finden“ / „Einsetzen“ for a
    /// round recorded before those two exercises.
    var stepLabel: String {
        guard let step else { return "" }
        if isLegacyStoryRound { return step.legacyGermanLabel }
        if let markCase { return "\(step.germanLabel) · \(markCase.name)" }
        return step.germanLabel
    }

    /// Markieren's score the class sheet's way: „6 / 10“, with the right, wrong and missed words.
    /// Nil for every other round.
    var markScore: KasusMarkScore? {
        guard isMarkingRound else { return nil }
        return KasusMarkScore(caseWords: askedCount, right: firstTryCount, wrong: wrongCount)
    }

    /// „Lösung angezeigt · Answers shown“, for a round whose answers Lösung zeigen showed.
    static let answersShownLabel = "Lösung angezeigt · Answers shown"

    /// The coach's skills this round moved, read back from its stored answers the way
    /// `recordRound` counted them: per case for a round of the case path (a case needs
    /// `KasusService.minItemsPerCase` counting answers), pooled into the topic's focus for a topic
    /// that isn't a case (the step's `minItemsPerFocus`). Empty for a round without answers.
    var coachMoves: [GrammarFocus] {
        let counting = items.filter(\.countsTowardSkill)
        guard !counting.isEmpty, let step else { return [] }
        if let topic, topic.unit == nil {
            guard let focus = topic.focus, counting.count >= step.meta.minItemsPerFocus else { return [] }
            return [focus]
        }
        return GrammarCase.allCases.compactMap { kasus in
            guard let focus = kasus.focus,
                  counting.filter({ $0.kasus == kasus }).count >= KasusService.minItemsPerCase else { return nil }
            return focus
        }
    }

    /// Lösung zeigen after the round was recorded: the round and every answer it showed are
    /// flagged. A gap left empty becomes `revealed`; a wrong or missed answer keeps its outcome
    /// (it was the learner's) and gains `revealed`. In Markieren only the missed and partly
    /// marked phrases were shown; a wrong mark was the learner's and stays as it was, as
    /// `KasusService.markResult` does it. The counts don't change.
    func applyAnswersShown() {
        revealedAnswers = true
        let marking = isMarkingRound
        items = items.map { item in
            var item = item
            switch item.outcome {
            case .unanswered:
                item.outcomeRaw = KasusItemOutcome.revealed.rawValue
                item.revealed = true
            case .right, .revealed:
                break
            case .wrongPick where marking, .wrongMark where marking:
                break
            default:
                item.revealed = true
            }
            return item
        }
    }

    /// The answers, in reading order. Empty for a round recorded before the history kept them.
    var items: [KasusRoundItem] {
        get {
            guard let itemsData else { return [] }
            return (try? JSONDecoder().decode([KasusRoundItem].self, from: itemsData)) ?? []
        }
        set { itemsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    /// First tries per case. A Markieren round reads its one case from `markScore` (the class
    /// sheet's points), whatever was stored, so its bars always agree with its score.
    var perCase: [GrammarCase: CaseTally] {
        get {
            if let markScore, let markCase {
                return [markCase: CaseTally(asked: markScore.caseWords, firstTry: markScore.points)]
            }
            guard let perCaseData,
                  let raw = try? JSONDecoder().decode([String: CaseTally].self, from: perCaseData)
            else { return [:] }
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, tally in
                GrammarCase(rawValue: key).map { ($0, tally) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            perCaseData = try? JSONEncoder().encode(raw)
        }
    }
}
