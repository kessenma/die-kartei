//
//  KasusStoryPlan.swift
//  german-ai-flashcards
//
//  What the app hands the tutor before it writes a Kasus story (Phase 3): 5–8 phrases whose case
//  the validator can prove, each with the verb or preposition that decides it. The model only
//  writes prose around them; the app stays the answer key. Built by `KasusStoryPlanner` from a
//  seed, so the same seed always gives the same plan, and stored as JSON with every generated
//  story (`GeneratedKasusStory.planData`) and every Lab record.
//
//  Two contracts, for the Lab:
//    A (`planned`)       the app plans the phrases; the story must use them verbatim.
//    B (`selfLabelled`)  no plan; the tutor writes freely and labels every noun phrase itself in a
//                        „FÄLLE:“ block, scored against the cases the form proves.
//

import Foundation

nonisolated enum KasusContract: String, Codable, CaseIterable, Hashable {
    case planned = "A"
    case selfLabelled = "B"

    var label: String {
        switch self {
        case .planned:      "A · planned phrases"
        case .selfLabelled: "B · the tutor labels"
        }
    }
}

/// The sentence frame a planned phrase lives in. Each one is provable by construction: the form
/// alone (den/einen + masculine, dem/einem, des/eines, der/ein + masculine as a subject), or the
/// form narrowed by a fixed-case or two-way preposition.
nonisolated enum KasusFrameKind: String, Codable, CaseIterable, Hashable {
    /// der/ein + masculine, the subject of a planned verb. Nominativ by form.
    case subject
    /// den/einen + masculine, the object of a planned transitive verb. Akkusativ by form.
    case object
    /// dem/einem + masculine or neuter with a Dativ verb (helfen, danken …).
    case dativeVerb
    /// dem/einem + masculine or neuter, the receiver of geben, schenken, zeigen …
    case recipient
    /// A fixed-case preposition + article + noun („mit dem Hund“, „für die Katze“).
    case preposition
    /// auf/unter/neben + Dativ with a position verb (liegen, stehen, sitzen): Wo?
    case wechselWo
    /// auf/unter/neben + Akkusativ with a placement verb (legen, stellen, setzen): Wohin?
    case wechselWohin
    /// wegen/trotz + a curated Genitiv noun („wegen des Regens“).
    case genitivePreposition

    /// The validator's reason for a target in this frame.
    var reason: KasusReason {
        switch self {
        case .subject:              .subject
        case .object:               .object
        case .dativeVerb:           .dativeVerb
        case .recipient:            .recipient
        case .preposition,
             .genitivePreposition:  .preposition
        case .wechselWo:            .wechselWo
        case .wechselWohin:         .wechselWohin
        }
    }

    /// Frames whose phrase needs a verb in the same sentence before it counts as placed.
    var needsVerb: Bool {
        switch self {
        case .preposition, .genitivePreposition: false
        default:                                 true
        }
    }
}

/// One phrase the story must contain.
nonisolated struct KasusPlannedPhrase: Codable, Hashable, Identifiable {
    /// Position in the plan, from 0.
    let id: Int
    let frame: KasusFrameKind
    /// What the model is told to write verbatim: „mit dem Hund“, „den Ball“.
    let expression: String
    /// The target inside it, determiner + noun: „dem Hund“.
    let phrase: String
    /// A `GrammarCase` raw value.
    let caseRaw: String
    /// m · f · n (`Gender.columnLabel`). Planned nouns are always singular.
    let genusRaw: String
    /// The singular dictionary form.
    let lemma: String
    /// The preposition in the expression, lowercased; nil for a verb frame.
    let preposition: String?
    /// The infinitive the prompt names as the phrase's verb („sich setzen“ for a placement with
    /// setzen); nil for a preposition frame.
    let verb: String?
    /// Every form that counts as that verb in the sentence (lowercased; a separable verb's split
    /// form, or a helper and the verb, is two words: „hat gelacht“, „kann lachen“). For a subject,
    /// only the forms a third-person singular subject takes. For a two-way preposition: every
    /// position (Wo) or placement (Wohin) form, since any of them settles the case. Empty for a
    /// preposition frame.
    let verbForms: [String]
    /// A subject's verb as the prompt shows it, conjugated for the phrase („lacht“), so the tutor
    /// doesn't copy an infinitive into „Der Bruder lachen laut.“ Nil for the other frames, and in
    /// plans from before it existed.
    var verbShown: String? = nil

    var kasus: GrammarCase { GrammarCase(rawValue: caseRaw) ?? .nominativ }
    var genus: Gender { Gender(columnLabel: genusRaw) ?? .der }
    var reason: KasusReason { frame.reason }

    /// The determiner as planned, lowercased: „dem“.
    var determiner: String { phrase.split(separator: " ").first.map(String.init) ?? phrase }
    /// The noun as written in the phrase: „Hund“, „Regens“.
    var noun: String { phrase.split(separator: " ").last.map(String.init) ?? phrase }

    /// What follows the expression in the prompt's list: „ (Verb: helfen)“, „ (Subjekt: der Hund
    /// schläft)“, „ (Verb: liegen; wo?)“. Empty for a preposition frame.
    var promptHint: String {
        guard let verb else { return "" }
        switch frame {
        case .subject:      return verbShown.map { " (Subjekt: \(expression) \($0))" } ?? " (Subjekt, Verb: \(verb))"
        case .wechselWo:    return " (Verb: \(verb); wo?)"
        case .wechselWohin: return " (Verb: \(verb); wohin?)"
        default:            return " (Verb: \(verb))"
        }
    }
}

nonisolated struct KasusStoryPlan: Codable, Hashable {
    /// The plan format; bump when a field changes meaning. 2: subject verbs are third-person
    /// singular only, shown conjugated (`verbShown`).
    var version: Int = 2
    /// A `KasusUnit` raw value.
    let unitRaw: String
    /// A `CEFRLevel` raw value, after the memory saver's cap.
    let level: String
    /// What the planner's random numbers came from. Kept under 2^53 so JSON readers outside
    /// Swift (the training scripts) read it exactly.
    let seed: UInt64
    /// Memory saver was active for the tutor: level at most A2, at most 6 phrases.
    let governed: Bool
    let contract: KasusContract
    /// The story's topic line in the prompt.
    let topic: String
    /// A `StoryGenre` raw value.
    let genreRaw: String
    /// Empty for contract B.
    let phrases: [KasusPlannedPhrase]

    /// A fresh seed, under 2^53.
    static func randomSeed() -> UInt64 { UInt64.random(in: 0..<(1 << 53)) }

    /// The seed of the retry after `seed`: a different plan, still repeatable.
    static func retrySeed(after seed: UInt64) -> UInt64 {
        (seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407) & ((1 << 53) - 1)
    }

    /// A story id for a generated story: „kg-dativ-a2-3f9a1c0b“.
    static func newStoryID(unitRaw: String, level: String) -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        return "kg-\(unitRaw)-\(level.lowercased())-\(suffix)"
    }

    /// Phrases per case, in table order: „Nom 1 · Akk 1 · Dat 4“.
    var casesLine: String {
        let counts = phrases.reduce(into: [String: Int]()) { $0[$1.caseRaw, default: 0] += 1 }
        return ["nominativ", "akkusativ", "dativ", "genitiv"].compactMap { raw in
            counts[raw].map { "\(GrammarCase(rawValue: raw)?.short ?? raw) \($0)" }
        }.joined(separator: " · ")
    }
}

@MainActor
extension KasusStoryPlan {
    var unit: KasusUnit? { KasusUnit(rawValue: unitRaw) }
    var cefr: CEFRLevel? { CEFRLevel(rawValue: level) }
    var genre: StoryGenre { StoryGenre(rawValue: genreRaw) ?? .alltag }
}
