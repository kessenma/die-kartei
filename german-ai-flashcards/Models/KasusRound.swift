//
//  KasusRound.swift
//  german-ai-flashcards
//
//  One scored step on the Grammatik path: a story's Finden or Einsetzen, or a unit's Schnellrunde.
//  Written by `KasusService.recordRound`, read by the day detail in the streak calendar, the story
//  rows' step marks and the hub's "Weiter" pick (`KasusPath.next`).
//
//  Everything keys on (storyID, unitRaw, stepRaw), never on a display string, so a retitled story
//  keeps its history. A Schnellrunde has no story; it is filed under "quick-<unit>".
//
//  Each round also keeps its answers (`items`, one `KasusRoundItem` each: the sentence, the pick,
//  the answer and why), which is what Verlauf's round detail shows. Rounds recorded before that
//  have none and show their counts only.
//
//  Additive, with every field defaulted: the store recreates itself when a migration fails, so a
//  new model must never be the thing that makes one fail.
//

import Foundation
import SwiftData

/// Which exercise a `KasusRound` records.
nonisolated enum KasusRoundStep: String, Codable, CaseIterable {
    /// Finden: mark the cases in the story. Counts for the streak only.
    case find
    /// Einsetzen: fill in the articles.
    case fill
    /// Schnellrunde: the endings drill for one unit.
    case quick

    var germanLabel: String {
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
        date: Date = Date()
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

    /// The answers, in reading order. Empty for a round recorded before the history kept them.
    var items: [KasusRoundItem] {
        get {
            guard let itemsData else { return [] }
            return (try? JSONDecoder().decode([KasusRoundItem].self, from: itemsData)) ?? []
        }
        set { itemsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var perCase: [GrammarCase: CaseTally] {
        get {
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
    /// Finden: its case had a brush, and it wasn't painted.
    case missed
    /// Finden: painted with another case's brush, or painted when its case had none.
    case wrongPick

    var isRight: Bool { self == .right }

    var germanLabel: String {
        switch self {
        case .right:      "Richtig"
        case .caseMiss:   "Falscher Fall"
        case .genderSlip: "Genus-Fehler"
        case .numberSlip: "Singular/Plural"
        case .missed:     "Übersehen"
        case .wrongPick:  "Anderer Fall"
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
        }
    }

    var symbol: String {
        switch self {
        case .right:      "checkmark.circle"
        case .caseMiss:   "arrow.uturn.left.circle"
        case .genderSlip: "person.2.circle"
        case .numberSlip: "number.circle"
        case .missed:     "eye.slash"
        case .wrongPick:  "paintbrush.pointed"
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
    /// Finden's painted brush.
    var pickedCase: GrammarCase? { pick.flatMap(GrammarCase.init(rawValue:)) }
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
