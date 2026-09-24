//
//  KasusStory.swift
//  german-ai-flashcards
//
//  The story format behind Finden and Einsetzen (`Resources/kasus_stories.json`). The text is
//  plain prose in paragraphs; targets are stand-off annotations listed in reading order, and the
//  validator finds each one by walking forward from the previous. So there are no offsets to count
//  and no markup for an author (or, later, a model) to get wrong.
//
//  Stored fields are authored facts only: phrase, case, gender, lemma, reason, trigger. Everything
//  else (the range, the determiner, the possible cases, the proof, the explanation, whether a
//  target can be graded) is derived at load by `KasusValidator` into a `KasusLocatedTarget`.
//

import Foundation

// MARK: - Stored

nonisolated struct KasusStoryFile: Codable {
    let version: Int
    let stories: [KasusStory]
}

nonisolated struct KasusStory: Codable, Identifiable, Hashable {
    let id: String
    /// A `KasusUnit` raw value: nominativ · akkusativ · dativ · genitiv · alleFaelle.
    let unitRaw: String
    /// A `CEFRLevel` raw value, "A1" … "B1". A soft label; nothing is gated on it.
    let level: String
    let source: KasusStorySource
    let reviewed: Reviewed
    let title: String
    let titleEnglish: String
    let question: Question
    let paragraphs: [Paragraph]
    let targets: [KasusTargetSpec]
    let notTargets: [KasusNotTarget]

    /// Who proofread the story and when. Empty strings until a teacher has read it.
    nonisolated struct Reviewed: Codable, Hashable {
        let by: String
        let date: String
    }

    /// The Lesen comprehension question. Unscored; `answer` indexes `options`.
    nonisolated struct Question: Codable, Hashable {
        let de: String
        let en: String
        let options: [String]
        let answer: Int
    }

    nonisolated struct Paragraph: Codable, Hashable {
        let de: String
        let en: String
    }

    enum CodingKeys: String, CodingKey {
        case id, unitRaw = "unit", level, source, reviewed, title, titleEnglish, question,
             paragraphs, targets, notTargets
    }
}

@MainActor
extension KasusStory {
    /// Nil for an unknown raw value; the validator reports that as story.unitCaseCount.
    var unit: KasusUnit? { KasusUnit(rawValue: unitRaw) }
    var cefr: CEFRLevel? { CEFRLevel(rawValue: level) }
}

nonisolated enum KasusStorySource: String, Codable, Hashable {
    /// Written and checked by hand. Must pass with zero errors; label-proven targets are allowed.
    case authored
    /// Written by the on-device tutor (Phase 3). Held to the stricter generated policy.
    case generated
}

/// One case-marked phrase: determiner + noun, no adjectives until adjective endings are checked.
nonisolated struct KasusTargetSpec: Codable, Hashable {
    /// Exactly as it appears in the text; the first letter may differ in case.
    let phrase: String
    let kasus: GrammarCase
    /// m · f · n · pl in the JSON. The plural carries the number.
    let genus: Gender
    /// The singular dictionary form, always, even for a plural target. Gender is checked on it.
    let lemma: String
    let reason: KasusReason
    /// The word that decides the case: the preposition, or the verb.
    let trigger: String

    init(phrase: String, kasus: GrammarCase, genus: Gender, lemma: String, reason: KasusReason, trigger: String) {
        self.phrase = phrase
        self.kasus = kasus
        self.genus = genus
        self.lemma = lemma
        self.reason = reason
        self.trigger = trigger
    }

    enum CodingKeys: String, CodingKey {
        case phrase, kasus = "case", genus, lemma, reason, trigger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phrase = try container.decode(String.self, forKey: .phrase)
        let caseRaw = try container.decode(String.self, forKey: .kasus)
        guard let kasus = GrammarCase(rawValue: caseRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .kasus, in: container,
                                                   debugDescription: "unknown case \(caseRaw)")
        }
        self.kasus = kasus
        let genusRaw = try container.decode(String.self, forKey: .genus)
        guard let genus = Gender(columnLabel: genusRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .genus, in: container,
                                                   debugDescription: "unknown genus \(genusRaw) (m, f, n or pl)")
        }
        self.genus = genus
        lemma = try container.decode(String.self, forKey: .lemma)
        reason = try container.decode(KasusReason.self, forKey: .reason)
        trigger = try container.decode(String.self, forKey: .trigger)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phrase, forKey: .phrase)
        try container.encode(kasus.rawValue, forKey: .kasus)
        try container.encode(genus.columnLabel, forKey: .genus)
        try container.encode(lemma, forKey: .lemma)
        try container.encode(reason, forKey: .reason)
        try container.encode(trigger, forKey: .trigger)
    }
}

/// A determiner phrase the coverage rule should let through: a pronoun, a relative „die“, an idiom,
/// a contraction („am Montag“) while contractions can't be targets.
nonisolated struct KasusNotTarget: Codable, Hashable {
    let phrase: String
    let why: Kind

    nonisolated enum Kind: String, Codable, Hashable {
        case pronoun, demonstrative, relative, idiom, contraction
    }
}

/// Why a target has its case. Each reason maps to the case it demands (`expectedCases`), and the
/// explanations follow the Kasus-Check order: preposition → noun it hangs on → subject →
/// sein-predicate → receiver or Dativ verb → otherwise Akkusativ.
nonisolated enum KasusReason: String, Codable, CaseIterable, Hashable {
    case subject          // nom: the one doing the verb
    case predicate        // nom: what main-verb sein/werden/bleiben/heißen equates with the subject
    case object           // akk: what the verb acts on
    case wechselWohin     // akk: two-way preposition, a direction
    case time             // akk („jeden Tag“), or dat after an/in/vor/zwischen („vor dem Termin“)
    case recipient        // dat: the receiver
    case dativeVerb       // dat: helfen, danken, gefallen …
    case wechselWo        // dat: two-way preposition, a place
    case dativeOther      // dat: possessive Dativ, with an adjective, „mir ist kalt“
    case attribute        // gen: whose / of what
    case preposition      // whatever the preposition governs
    case prepObject       // fixed by the verb (warten auf + Akk); the labelled case is trusted

    /// Reasons whose trigger is a preposition standing next to the phrase.
    var needsPreposition: Bool {
        switch self {
        case .preposition, .wechselWo, .wechselWohin, .prepObject: true
        default: false
        }
    }

    /// The cases this reason allows, given the preposition that governs the phrase (if any).
    /// Nil means the reason doesn't decide: `prepObject` trusts the label, and `preposition`
    /// without a preposition is a trigger problem, not a case one.
    func expectedCases(after preposition: KasusPrepositionContext?) -> Set<GrammarCase>? {
        switch self {
        case .subject, .predicate:                           return [.nominativ]
        case .object, .wechselWohin:                         return [.akkusativ]
        case .recipient, .dativeVerb, .wechselWo, .dativeOther: return [.dativ]
        case .attribute:                                     return [.genitiv]
        case .preposition:                                   return preposition?.cases
        case .prepObject:                                    return nil
        case .time:
            guard let preposition else { return [.akkusativ] }
            if ["an", "in", "vor", "zwischen"].contains(preposition.word) { return [.dativ] }
            if preposition.isTwoWay { return [.akkusativ] }   // „über das Wochenende“
            return preposition.cases
        }
    }
}

// MARK: - Derived at load, never stored

/// How the case was established. `.label` means only the annotation decides: the form fits
/// several cases and nothing next to it narrows them („seine Mutter“ after „fragt“).
nonisolated enum KasusProof: String, CaseIterable, Hashable {
    case form          // the determiner fits exactly one case with this gender
    case preposition   // the preposition in front narrows it to one
    case copula        // a main-verb sein/werden/bleiben/heißen narrows it to the Nominativ
    case label         // several cases fit; a human checked the role
}

/// The preposition governing a target, as found in the text.
nonisolated struct KasusPrepositionContext: Hashable {
    /// Lowercased: „Nach“ at a sentence start is "nach".
    let word: String
    let cases: Set<GrammarCase>
    let isTwoWay: Bool
    let position: Position
    /// Reached back across „und/oder + noun phrase“ („mit dem Hund und der Katze“).
    let viaCoordination: Bool
    /// UTF-16 range of the preposition in the paragraph.
    let range: NSRange

    nonisolated enum Position: Hashable { case before, after }
}

/// A target found in the text, with everything derived from it. Built by `KasusValidator` and
/// never stored.
///
/// Ranges are UTF-16 `NSRange`s into `story.paragraphs[paragraphIndex].de`: the convention
/// `TappableText` uses, so a renderer can intersect them with its own word runs. Convert with
/// `Range(range, in: paragraph)` when a `String.Index` range is handier.
nonisolated struct KasusLocatedTarget: Identifiable, Hashable {
    /// Position in `story.targets`.
    let index: Int
    let spec: KasusTargetSpec
    let paragraphIndex: Int
    /// The whole phrase, determiner to noun.
    let range: NSRange
    let determinerRange: NSRange
    let nounRange: NSRange
    /// The sentence the phrase sits in, for "misses in their sentences".
    let sentenceRange: NSRange
    /// The trigger word in the text: the governing preposition, or the first match of the verb in
    /// the sentence. Nil when the trigger couldn't be found.
    let triggerRange: NSRange?
    /// The phrase, determiner and noun exactly as written („Der Schlüssel“, „Der“, „Schlüssel“).
    let surface: String
    let determiner: String
    let noun: String
    /// Nil when the first word is no known determiner (np.unknownDeterminer).
    let parsed: KasusDeterminer?
    /// Every case the determiner fits with this gender, by form alone.
    let candidates: Set<GrammarCase>
    /// The preposition that decides the case. Nil when there is none, or when it is a soft one
    /// (um, ohne, seit …) that isn't acting as a preposition here: the reason isn't `preposition`
    /// and the trigger names another word.
    let preposition: KasusPrepositionContext?
    /// The main-verb copula form, for `predicate` targets.
    let copulaVerb: String?
    /// The position or placement verb that settles a two-way preposition („liegt“, „legt“).
    let wechselVerb: String?
    let proof: KasusProof
    /// The lemma's gender, as the lexicon (or the plural-only / dual-gender lists) reports it.
    let genderVerdict: KasusLexiconVerdict
    /// The noun reads the same in the plural (Schlüssel), so Ohne Hilfe shows an sg/pl tag.
    let numberAmbiguous: Bool
    /// Can be marked in Finden and scored. Authored: no errors. Generated: also form-, preposition-
    /// or copula-proven, with a verified gender.
    var gradable: Bool
    /// Can become an Einsetzen blank. Every gradable Phase 1 target (no contractions or pronouns
    /// yet).
    var blankable: Bool

    var id: Int { index }
    var kasus: GrammarCase { spec.kasus }
    var genus: Gender { spec.genus }
    var family: KasusFamily? { parsed?.family }
    /// The Einsetzen answer: the determiner as written. Grading ignores case.
    var answer: String { determiner }
}
