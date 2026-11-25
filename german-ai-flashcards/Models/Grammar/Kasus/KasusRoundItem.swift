//
//  KasusRoundItem.swift
//  german-ai-flashcards
//
//  One answer in a `KasusRound`, and how it went. Plain strings and raw values, so a later change
//  to a story or the rules never rewrites an old round, and a build that doesn't know an outcome
//  reads it as a case miss. `KasusRound.itemsData` holds them as JSON.
//
//  Foundation only and `nonisolated`: compiled into training/kasus_cli next to the registry
//  (`KasusRoundStep.swift`), whose meta names these outcomes.
//

import Foundation

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

    /// The labels for this outcome in a round of `step`, where the step's meta words it its own
    /// way: a `wrongPick` in Rollen is another role, in Wer macht was? the other reading, in a
    /// reflexive drill another person. The defaults otherwise.
    func labels(for step: KasusRoundStep?) -> (german: String, english: String) {
        if let step, let own = step.meta.outcomeLabels[self] { return (own.de, own.en) }
        return (germanLabel, englishLabel)
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
    /// Milliseconds from the step appearing to the first graded pick (roadmap item 5, answer time).
    /// Nil on items from before it was measured and on Markieren, which is not one pick.
    var answerMs: Int? = nil

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
