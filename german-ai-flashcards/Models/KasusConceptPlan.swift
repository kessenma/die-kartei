//
//  KasusConceptPlan.swift
//  german-ai-flashcards
//
//  A plan for ONE tutor-written Verstehen item: the phrases the app picked (article, noun, case,
//  role), the one verb they share, and for a Wer item which phrase opens the sentence. The tutor
//  only writes the sentence around them; the case of every phrase is the app's, proven again by
//  the validator from the form (KasusConceptCheck). The tutor never decides a case.
//
//  Unlike `KasusStoryPlan` (5–8 phrases, a verb each, never an ambiguous form), a concept plan
//  shares one verb across a subject and its partners, and a Probe plan deliberately holds a phrase
//  whose article could be two cases.
//
//  Foundation only, so `training/kasus_cli` compiles it.
//

import Foundation

nonisolated struct KasusConceptPlannedPhrase: Codable, Hashable {
    /// „den Hund“, as the sentence must contain it (any capitalisation of the first letter).
    let phrase: String
    let caseRaw: String
    let genusRaw: String
    let lemma: String
    /// A `KasusReason` raw value: subject, object, recipient, dativeVerb, preposition.
    let reasonRaw: String
    /// The preposition in front, for a preposition phrase („für“, „mit“, „wegen“).
    let preposition: String?
    /// A Genitiv attribute: the index of the phrase it hangs on, which it follows directly
    /// („der Hund des Lehrers“).
    var head: Int? = nil

    var isAttribute: Bool { head != nil }

    var kasus: GrammarCase { GrammarCase(rawValue: caseRaw) ?? .nominativ }
    var genus: Gender { Gender(columnLabel: genusRaw) ?? .der }
    var reason: KasusReason { KasusReason(rawValue: reasonRaw) ?? .object }
    /// What the sentence holds: the preposition and the phrase („für den Hund“).
    var expression: String { preposition.map { "\($0) \(phrase)" } ?? phrase }
}

nonisolated struct KasusConceptPlan: Codable, Hashable {
    var version: Int = 1
    /// A `KasusConceptKind` raw value: roles, whoDoesWhat, probe.
    let kindRaw: String
    let unitRaw: String
    let level: String
    let seed: UInt64
    /// The phrases, subject first.
    let phrases: [KasusConceptPlannedPhrase]
    let verbLemma: String
    /// Every form that counts as the verb in the sentence (lowercased; may be two words).
    let verbForms: [String]
    /// The form the prompt shows („jagt“).
    let verbShown: String
    /// Wer: the index (into `phrases`) of the phrase the sentence must open with.
    let firstPhrase: Int?
    /// Probe: the index of the phrase whose article could be two cases.
    let probePhrase: Int?
    /// The sentence a template writes from this plan, with no model: the baseline.
    let template: String

    var kind: KasusConceptKind { KasusConceptKind(rawValue: kindRaw) ?? .roles }

    /// A phrase as the sentence holds it, with the Genitiv attribute that hangs on it
    /// („den Hund des Lehrers“).
    func fullExpression(_ index: Int) -> String {
        let attributes = phrases.filter { $0.head == index }.map(\.phrase)
        return ([phrases[index].expression] + attributes).joined(separator: " ")
    }
    var subject: KasusConceptPlannedPhrase? { phrases.first { $0.reason == .subject } }
    var id: String { "\(kindRaw)-\(unitRaw)-\(level)-\(seed)" }

    /// Object first: the phrase that opens the sentence isn't the subject.
    var isObjectFirst: Bool {
        guard let firstPhrase, phrases.indices.contains(firstPhrase) else { return false }
        return phrases[firstPhrase].reason != .subject
    }
}
