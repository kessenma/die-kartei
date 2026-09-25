//
//  KasusRound.swift
//  german-ai-flashcards
//
//  One scored step on the Grammatik path: a story's Markieren (one case) or Endungen, or a unit's
//  Schnellrunde. Rounds from before Markieren and Endungen replaced the brush-sorting Finden and
//  the whole-article Einsetzen keep their step raw values (find, fill) and have no feedback mode,
//  which is how `stepLabel` tells them apart.
//  Written by `KasusService.recordRound`, read by the day detail in the streak calendar, the story
//  rows' step marks and the hub's "Weiter" pick (`KasusPath.next`).
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

/// Which exercise a `KasusRound` records. The raw values are stored; never rename one.
nonisolated enum KasusRoundStep: String, Codable, CaseIterable {
    /// Markieren: mark every word in one case (before it, Finden's brush sorting). Counts for the
    /// streak only.
    case find
    /// Endungen: fill in the article endings (before it, Einsetzen's whole articles).
    case fill
    /// Schnellrunde: the endings drill for one unit.
    case quick

    var germanLabel: String {
        switch self {
        case .find:  "Markieren"
        case .fill:  "Endungen"
        case .quick: "Schnellrunde"
        }
    }

    /// The name the step had before Markieren and Endungen, for rounds recorded then.
    var legacyGermanLabel: String {
        switch self {
        case .find:  "Finden"
        case .fill:  "Einsetzen"
        case .quick: "Schnellrunde"
        }
    }
}

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
    var step: KasusRoundStep? { KasusRoundStep(rawValue: stepRaw) }
    var hintLevel: KasusHintLevel? { KasusHintLevel(rawValue: hintLevelRaw) }
    var isQuickRound: Bool { step == .quick }
    var feedbackMode: KasusFeedbackMode? { KasusFeedbackMode(rawValue: feedbackModeRaw) }
    /// Markieren's asked case. Nil on every other round, the old Finden's included.
    var markCase: GrammarCase? { GrammarCase(rawValue: markCaseRaw) }
    /// A Markieren round (one case, counted in words), not an old brush-sorting Finden.
    var isMarkingRound: Bool { step == .find && markCase != nil }
    /// Recorded before Markieren and Endungen replaced Finden and Einsetzen.
    var isLegacyStoryRound: Bool { (step == .find || step == .fill) && feedbackModeRaw.isEmpty }

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

// MARK: - Answers

/// How one answer went, as the round history names it. Stored by raw value; never rename one.
nonisolated enum KasusItemOutcome: String, Codable, CaseIterable {
    case right
    /// Einsetzen, Schnellrunde: a form of another case.
    case caseMiss
    /// Right case, another gender („dem Tasche“).
    case genderSlip
    /// Right case, the plural of a noun that reads the same („die Schlüssel“ for one key).
    case numberSlip
    /// Markieren: none of its words marked. The old Finden: its case had a brush, and it wasn't
    /// painted.
    case missed
    /// Markieren: a word marked in a phrase of another case (the pick is the asked case). The old
    /// Finden: painted with another case's brush, or painted when its case had none.
    case wrongPick
    /// Markieren: some of its words marked, not all.
    case partial
    /// Markieren: an ordinary word marked (a verb, a preposition …). No case, no gender.
    case wrongMark
    /// Endungen, Am Ende: the gap was still empty at Prüfen.
    case unanswered
    /// Endungen: Lösung zeigen filled the gap before the learner answered it.
    case revealed

    var isRight: Bool { self == .right }

    var germanLabel: String {
        switch self {
        case .right:      "Richtig"
        case .caseMiss:   "Falscher Fall"
        case .genderSlip: "Genus-Fehler"
        case .numberSlip: "Singular/Plural"
        case .missed:     "Übersehen"
        case .wrongPick:  "Anderer Fall"
        case .partial:    "Teilweise"
        case .wrongMark:  "Falsch markiert"
        case .unanswered: "Leer"
        case .revealed:   "Lösung angezeigt"
        }
    }

    var englishLabel: String {
        switch self {
        case .right:      "Right first try"
        case .caseMiss:   "Wrong case"
        case .genderSlip: "Wrong gender"
        case .numberSlip: "Wrong number"
        case .missed:     "Not marked"
        case .wrongPick:  "Marked as another case"
        case .partial:    "Only partly marked"
        case .wrongMark:  "Marked, but has no case here"
        case .unanswered: "Left empty"
        case .revealed:   "Answer shown"
        }
    }

    /// The English label in a round's history. In Markieren a `wrongPick` is a word of another
    /// case's phrase marked in this case's round: it *is* another case, whereas the old Finden
    /// painted it with another case's brush.
    func englishLabel(inMarkingRound marking: Bool) -> String {
        marking && self == .wrongPick ? "It's another case" : englishLabel
    }

    var symbol: String {
        switch self {
        case .right:      "checkmark.circle"
        case .caseMiss:   "arrow.uturn.left.circle"
        case .genderSlip: "person.2.circle"
        case .numberSlip: "number.circle"
        case .missed:     "eye.slash"
        case .wrongPick:  "paintbrush.pointed"
        case .partial:    "circle.lefthalf.filled"
        case .wrongMark:  "xmark.circle"
        case .unanswered: "circle.dashed"
        case .revealed:   "eye"
        }
    }
}

/// One answer in a `KasusRound`: enough to show it again in its sentence, corrected, with why.
/// Plain strings, so a later change to the story or the rules never rewrites an old round.
nonisolated struct KasusRoundItem: Codable, Hashable {
    /// The sentence as written, with the right answer in place.
    var sentence: String
    /// Where `phrase` starts in `sentence`, in UTF-16 units. Nil when unknown: search for it.
    var phraseStart: Int?
    /// The phrase as written, determiner to noun („dem Schlüssel“).
    var phrase: String
    /// The right determiner as written („dem“).
    var answer: String
    /// Einsetzen and the Schnellrunde: the first pick. Finden: the painted brush's `GrammarCase`
    /// raw value. Nil for a Finden phrase left unpainted.
    var pick: String?
    var caseRaw: String
    var genusRaw: String
    var outcomeRaw: String
    /// Whether this answer counted toward the coach's case skill (`KasusService.countsTowardSkill`).
    /// Filled in by `recordRound`.
    var countsTowardSkill: Bool = false
    /// Why, in the `KasusRich` markup: the slip note for a slip, the case explanation otherwise.
    var explanation: String
    /// The story target's index; nil in the Schnellrunde.
    var targetIndex: Int?
    /// False for a pronoun („mir“), whose genus is no noun's gender, so a view leaves it
    /// uncolored. Nil on items saved before it existed, which were all article phrases.
    var hasNounGender: Bool?
    /// Lösung zeigen showed this answer: a gap it filled, or a wrong or missed answer shown after
    /// Prüfen. Nil (false) on items from before it existed.
    var revealed: Bool? = nil
    /// Markieren: how many of the phrase's words were marked, and how many it has. Nil elsewhere.
    var markedWords: Int? = nil
    var wordCount: Int? = nil

    init(sentence: String, phraseStart: Int?, phrase: String, answer: String, pick: String?,
         kasus: GrammarCase, genus: Gender, outcome: KasusItemOutcome, explanation: String,
         targetIndex: Int? = nil, hasNounGender: Bool? = nil) {
        self.sentence = sentence
        self.phraseStart = phraseStart
        self.phrase = phrase
        self.answer = answer
        self.pick = pick
        self.caseRaw = kasus.rawValue
        self.genusRaw = genus.rawValue
        self.outcomeRaw = outcome.rawValue
        self.explanation = explanation
        self.targetIndex = targetIndex
        self.hasNounGender = hasNounGender
    }

    var kasus: GrammarCase? { GrammarCase(rawValue: caseRaw) }
    var genus: Gender? { Gender(rawValue: genusRaw) }
    var outcome: KasusItemOutcome { KasusItemOutcome(rawValue: outcomeRaw) ?? .caseMiss }
    /// Finden's painted brush; Markieren's asked case on a `wrongPick` or `wrongMark`.
    var pickedCase: GrammarCase? { pick.flatMap(GrammarCase.init(rawValue:)) }
    var wasRevealed: Bool { revealed ?? false }
    /// The gender whose color the answer wears; nil for a pronoun. An item saved before
    /// `hasNounGender` existed is judged by its answer.
    var formGenus: Gender? {
        (hasNounGender ?? (KasusForms.pronoun(answer) == nil)) ? genus : nil
    }

    /// A story target in its sentence. Falls back to the phrase alone when the sentence range
    /// doesn't hold the phrase.
    static func story(_ target: KasusLocatedTarget, in story: KasusStory, pick: String?,
                      outcome: KasusItemOutcome, explanation: String) -> KasusRoundItem {
        var sentence = target.surface
        var phraseStart = 0
        if story.paragraphs.indices.contains(target.paragraphIndex) {
            let paragraph = story.paragraphs[target.paragraphIndex].de as NSString
            let range = target.sentenceRange
            if range.location <= target.range.location, NSMaxRange(target.range) <= NSMaxRange(range),
               NSMaxRange(range) <= paragraph.length {
                let raw = paragraph.substring(with: range)
                let leading = raw.prefix(while: \.isWhitespace)
                sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                phraseStart = target.range.location - range.location - leading.utf16.count
            }
        }
        return KasusRoundItem(sentence: sentence, phraseStart: phraseStart, phrase: target.surface,
                              answer: target.answer, pick: pick, kasus: target.kasus, genus: target.genus,
                              outcome: outcome, explanation: explanation, targetIndex: target.index,
                              hasNounGender: target.hasNounGender)
    }
}

extension KasusRoundItem {
    /// Markieren: an ordinary word marked in a round that asked `asked`. The phrase is the word,
    /// with no answer and no gender; the explanation says why it isn't part of the case.
    static func markedWord(_ word: KasusWord, in sentence: KasusSentence, asked: GrammarCase,
                           explanation: String) -> KasusRoundItem {
        var item = KasusRoundItem(sentence: sentence.text, phraseStart: word.range.location, phrase: word.text,
                                  answer: "", pick: asked.rawValue, kasus: asked, genus: .der,
                                  outcome: .wrongMark, explanation: explanation, hasNounGender: false)
        item.genusRaw = ""
        item.markedWords = 1
        item.wordCount = 1
        return item
    }
}

extension KasusPickOutcome {
    /// The stored form of an Einsetzen pick's grade.
    var itemOutcome: KasusItemOutcome {
        switch self {
        case .right:       .right
        case .genderSlip:  .genderSlip
        case .numberSlip:  .numberSlip
        case .caseMiss:    .caseMiss
        }
    }
}

extension EndingsQuestion {
    /// A Schnellrunde answer for the round history: the frame with the right article in place.
    func roundItem(pick: String) -> KasusRoundItem {
        let (before, after) = parts
        let outcome: KasusItemOutcome = pick == answer ? .right : isGenderSlip(pick) ? .genderSlip : .caseMiss
        return KasusRoundItem(sentence: before + answer + after, phraseStart: before.utf16.count,
                              phrase: "\(answer) \(nounForm)", answer: answer, pick: pick,
                              kasus: kasus, genus: gender, outcome: outcome,
                              // The slip note for a gender slip, as the drill showed it.
                              explanation: feedback(pick: pick))
    }
}
