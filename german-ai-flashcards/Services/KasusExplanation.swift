//
//  KasusExplanation.swift
//  german-ai-flashcards
//
//  The "why" behind every Kasus answer, built only from what the validator proved: the proof, the
//  reason, the trigger, the gender and the form. There is no authored explanation text, so a new
//  story (or a generated one) explains itself.
//
//  The lines follow the Kasus-Check order the rule card teaches: preposition in front → hangs on
//  another noun → subject → what sein equates with the subject → receiver or Dativ verb →
//  otherwise Akkusativ. Then the code-word line from the endings table („Masculine Dativ in
//  „mrmn“ is m: dem.“), extending `EndingsQuestion.explanation` in CaseEndingsView.
//

import Foundation

nonisolated enum KasusExplanation {

    /// The full explanation for a target: the form note (label-proven targets only), the
    /// Kasus-Check line, the code-word line, and a note on the noun's own ending where it has one.
    static func explanation(for target: KasusLocatedTarget, in story: KasusStory) -> String {
        [formNote(for: target), ruleLine(for: target), trapNote(for: target), codeWordLine(for: target), nounNote(for: target)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Finden's note for a target only its role decides: „By its form, seine could be Nominativ or
    /// Akkusativ. Here it's what „fragt“ acts on → Akkusativ.“ Nil when the form or a preposition
    /// proves the case.
    static func ambiguityNote(for target: KasusLocatedTarget) -> String? {
        guard let form = formNote(for: target) else { return nil }
        return form + " " + ruleLine(for: target)
    }

    /// „By its form, seine could be Nominativ or Akkusativ.“
    static func formNote(for target: KasusLocatedTarget) -> String? {
        guard target.proof == .label, target.candidates.count > 1 else { return nil }
        let cases = GrammarCase.allCases.filter(target.candidates.contains).map(\.name)
        return "By its form, \(target.determiner.lowercased()) could be \(list(cases))."
    }

    /// The Kasus-Check step that decides this target.
    static func ruleLine(for target: KasusLocatedTarget) -> String {
        let phrase = "„\(target.surface)“"
        let trigger = "„\(target.spec.trigger)“"
        let kasus = target.kasus.name
        let isLabel = target.proof == .label && target.candidates.count > 1

        // 1. A preposition in front decides.
        if let preposition = target.preposition {
            let word = preposition.word
            if target.spec.reason == .prepObject {
                return "„\(word)“ belongs to the verb here, and that pair always takes the \(kasus)."
            }
            if target.spec.reason == .time, preposition.isTwoWay {
                return "„\(word)“ in a time phrase takes the \(kasus)."
            }
            if preposition.isTwoWay {
                let rule = target.kasus == .dativ
                    ? "\(word) + Wo? (a place) → Dativ."
                    : "\(word) + Wohin? (a direction) → Akkusativ."
                guard let verb = target.wechselVerb else { return rule }
                let hint = target.kasus == .dativ
                    ? "„\(verb)“ says where something is."
                    : "„\(verb)“ says where something goes."
                return rule + " " + hint
            }
            if preposition.position == .after {
                return word == "entlang"
                    ? "„entlang“ after the noun takes the Akkusativ."
                    : "„\(word)“ takes the \(kasus), even after the noun."
            }
            if preposition.cases.count > 1 {
                return "„\(word)“ in front of the noun takes the \(kasus) here."
            }
            return "„\(word)“ always takes the \(kasus)."
        }

        switch target.spec.reason {
        // 2. Hangs on another noun.
        case .attribute:
            return target.spec.trigger.isEmpty
                ? "\(phrase) hangs on another noun and says whose → Genitiv."
                : "\(phrase) hangs on „\(target.spec.trigger)“ and says whose → Genitiv."
        // 3. The subject.
        case .subject:
            let line = "\(phrase) is the subject of \(trigger) → Nominativ."
            return [line, reversedRoleNote(for: target)].compactMap { $0 }.joined(separator: " ")
        // 4. What sein/werden/bleiben/heißen equates with the subject.
        case .predicate:
            let verb = "„\(target.copulaVerb ?? target.spec.trigger)“"
            return "\(verb) links \(phrase) back to the subject, so it stays Nominativ."
        // 5. The receiver, or a Dativ verb.
        case .recipient:
            return "\(phrase) is the receiver of \(trigger) → Dativ."
        case .dativeVerb:
            let line = "\(trigger) is one of the verbs that always take the Dativ."
            return [line, reversedRoleNote(for: target)].compactMap { $0 }.joined(separator: " ")
        case .dativeOther:
            return "\(phrase) is the person this happens to, one of the fixed Dativ uses → Dativ."
        case .time:
            return "\(phrase) is a time phrase with no preposition → Akkusativ."
        // 6. Otherwise Akkusativ.
        case .object:
            return isLabel
                ? "Here it's what \(trigger) acts on → Akkusativ."
                : "\(phrase) is what \(trigger) acts on → Akkusativ."
        case .wechselWo, .wechselWohin, .preposition, .prepObject:
            // A preposition reason with no preposition found; the validator has already flagged it.
            return "\(phrase) is \(kasus) here."
        }
    }

    /// „Masculine Dativ in „mrmn“ is m: dem.“ ein-words in the three no-ending spots say so instead.
    static func codeWordLine(for target: KasusLocatedTarget) -> String? {
        guard let parsed = target.parsed,
              let form = KasusForms.form(parsed, case: target.kasus, genus: target.genus)
        else { return nil }
        let cell = "\(target.genus.genderName.capitalized) \(target.kasus.name)"
        if parsed.family != .definite && target.kasus.einEnding(target.genus).isEmpty {
            return "\(cell) is one of the spots with no ending: \(form)."
        }
        let letter = target.kasus.article(target.genus).suffix(1)
        return "\(cell) in „\(target.kasus.code)“ is \(letter): \(form)."
    }

    /// The noun's own ending: n-nouns, the Genitiv -s, the Dativ plural -n.
    static func nounNote(for target: KasusLocatedTarget) -> String? {
        let lemma = target.spec.lemma
        let noun = target.noun
        switch (target.kasus, target.genus) {
        case (.nominativ, _):
            return nil
        case (_, .der) where KasusForms.isNDeklination(lemma):
            return "\(lemma) is an n-noun, so it adds -n too: \(noun)."
        case (.genitiv, .der), (.genitiv, .das):
            return KasusForms.isAdjectivalNoun(lemma) ? nil : "The noun adds -(e)s too: \(noun)."
        case (.dativ, .plural):
            return noun.hasSuffix("n") ? "In the Dativ plural the noun ends in -n too: \(noun)." : nil
        default:
            return nil
        }
    }

    /// Einsetzen, when the pick is the right case for another gender („in dem Tasche“).
    /// „Right case, wrong gender: „dem“ is masculine Dativ. This noun is feminine, so der.“
    static func genderSlipNote(pick: String, answer: String, genus: Gender, kasus: GrammarCase? = nil) -> String {
        let picked = pick.lowercased()
        let wanted = answer.lowercased()
        if let parsed = KasusForms.parseDeterminer(answer) {
            let cases = kasus.map { [$0] }
                ?? GrammarCase.allCases.filter { KasusForms.form(parsed, case: $0, genus: genus) == parsed.word }
            for kasus in cases {
                if let other = KasusForms.genderOfSlip(pick: picked, kasus: kasus, genus: genus,
                                                        family: parsed.family, stem: parsed.stem) {
                    return "Right case, wrong gender: „\(picked)“ is \(other.genderName) \(kasus.name). This noun is \(genus.genderName), so \(wanted)."
                }
            }
        }
        return "Right case, wrong gender. This noun is \(genus.genderName), so \(wanted)."
    }

    /// Einsetzen, when the pick is the plural of the right case on a noun that reads the same in
    /// the plural („nimmt die Schlüssel“ for one key).
    /// „Right case, wrong number: „die“ is the plural Akkusativ. „Schlüssel“ looks the same in the
    /// plural, but here it's one, so den.“
    static func numberSlipNote(pick: String, answer: String, kasus: GrammarCase, noun: String) -> String {
        "Right case, wrong number: „\(pick.lowercased())“ is the plural \(kasus.name). „\(noun)“ looks the same in the plural, but here it's one, so \(answer.lowercased())."
    }

    // MARK: - Helpers

    /// gefallen, gehören and schmecken turn the English roles around.
    private static func reversedRoleNote(for target: KasusLocatedTarget) -> String? {
        switch KasusForms.dativeVerbLemma(for: target.spec.trigger) {
        case "gefallen":  "With „gefallen“, the thing liked is the subject and the person is Dativ."
        case "gehören":   "With „gehören“, the thing owned is the subject and the owner is Dativ."
        case "schmecken": "With „schmecken“, the food is the subject and the person is Dativ."
        default:          nil
        }
    }

    /// Verbs that feel like they have a receiver but take the Akkusativ.
    private static let akkusativTraps: [String: [String]] = [
        "fragen":   ["frage", "fragst", "fragt", "fragen", "fragte", "fragtest", "fragten", "gefragt"],
        "anrufen":  ["anrufen", "angerufen", "rufe an", "rufst an", "ruft an", "rufen an", "rief an", "riefen an"],
        "besuchen": ["besuche", "besuchst", "besucht", "besuchen", "besuchte", "besuchten"],
    ]

    /// "„fragen“ takes the Akkusativ, even though it can feel like there's a receiver."
    static func trapNote(for target: KasusLocatedTarget) -> String? {
        guard target.spec.reason == .object, target.preposition == nil else { return nil }
        let trigger = target.spec.trigger.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let verb = akkusativTraps.first(where: { $0.value.contains(trigger) })?.key else { return nil }
        return "„\(verb)“ takes the Akkusativ, even though it can feel like there's a receiver."
    }

    /// "Nominativ or Akkusativ", "Nominativ, Akkusativ or Dativ".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
    }
}
