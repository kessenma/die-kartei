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
//  mrmn is m: dem.“), extending `EndingsQuestion.explanation` in CaseEndingsView.
//
//  Every string is written in the `KasusRich` markup (KasusRichText.swift), so render it with
//  `Text(kasusRich:)`, and use `KasusRich.plain(_:)` where plain text is needed:
//    - an article form in its gender's color: {m:dem}, {f:der}, {pl:den};
//    - a case name in its case's color: {dat:Dativ}; Wo?/Wohin? in the two-way violet;
//    - the German trigger word in italics (*mit*, *hilft*); a phrase from the story in „quotes“;
//    - the rule's key word in bold (**always**, **subject**).
//  Tokens never sit inside ** or *. This file stays Foundation-only: the markup is plain text.
//

import Foundation

nonisolated enum KasusExplanation {

    /// The full explanation for a target: the form note (label-proven targets only), what a
    /// contraction stands for, the Kasus-Check line, the code-word line, and a note on the noun's
    /// own ending where it has one.
    static func explanation(for target: KasusLocatedTarget, in story: KasusStory) -> String {
        [formNote(for: target), contractionNote(for: target),
         esGibtLine(for: target, in: story) ?? ruleLine(for: target), trapNote(for: target),
         codeWordLine(for: target), nounNote(for: target)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// „es gibt“ gives nothing: the thing that is there is its object, which is why it's
    /// Akkusativ („es gibt einen Kiosk“, never „ein Kiosk“). Replaces the "what *gibt* acts on"
    /// line. Nil unless the target is the object of gibt/gab with „es“ right next to it.
    static func esGibtLine(for target: KasusLocatedTarget, in story: KasusStory) -> String? {
        let verb = target.spec.trigger.lowercased()
        guard target.spec.reason == .object, target.preposition == nil,
              ["gibt", "gab", "gäbe"].contains(verb),
              story.paragraphs.indices.contains(target.paragraphIndex) else { return nil }
        let paragraph = story.paragraphs[target.paragraphIndex].de as NSString
        guard NSMaxRange(target.sentenceRange) <= paragraph.length else { return nil }
        let sentence = paragraph.substring(with: target.sentenceRange)
        guard sentence.range(of: "\\b(es\\s+\(verb)|\(verb)\\s+es)\\b",
                             options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let here = verb == "gibt" ? "" : " (here *\(verb)*)"
        return "*es gibt*\(here) **always** takes the \(caseName(.akkusativ)): *es* is the subject, and „\(target.surface)“, the thing that is there, is the object."
    }

    /// Finden's note for a target only its role decides: „By its form, {f:seine} could be
    /// {nom:Nominativ} or {akk:Akkusativ}. Here it's what *fragt* acts on → {akk:Akkusativ}.“ Nil
    /// when the form or a preposition proves the case.
    static func ambiguityNote(for target: KasusLocatedTarget) -> String? {
        guard let form = formNote(for: target) else { return nil }
        return form + " " + ruleLine(for: target)
    }

    /// „By its form, {f:seine} could be {nom:Nominativ} or {akk:Akkusativ}.“
    static func formNote(for target: KasusLocatedTarget) -> String? {
        guard target.proof == .label, target.candidates.count > 1 else { return nil }
        let cases = GrammarCase.allCases.filter(target.candidates.contains).map(caseName)
        return "By its form, \(form(target.caseForm, target.genus)) could be \(list(cases))."
    }

    /// „*im* is short for *in* {m:dem}.“ Nil unless the target opens with a contraction.
    static func contractionNote(for target: KasusLocatedTarget) -> String? {
        guard target.kind == .contraction, let article = target.contractedArticle,
              let preposition = target.preposition?.word else { return nil }
        return "*\(target.determiner.lowercased())* is short for *\(preposition)* \(form(article, target.genus))."
    }

    /// The Kasus-Check step that decides this target.
    static func ruleLine(for target: KasusLocatedTarget) -> String {
        if target.spec.reason == .inferred { return inferredLine(for: target) }
        let phrase = "„\(target.surface)“"
        let trigger = "*\(target.spec.trigger)*"
        let kasus = caseName(target.kasus)
        let isLabel = target.proof == .label && target.candidates.count > 1

        // 1. A preposition in front decides.
        if let preposition = target.preposition {
            let word = "*\(preposition.word)*"
            if target.spec.reason == .prepObject {
                return "\(word) belongs to the verb here, and that pair **always** takes the \(kasus)."
            }
            if target.spec.reason == .time, preposition.isTwoWay {
                return "\(word) in a **time** phrase takes the \(kasus)."
            }
            if preposition.isTwoWay {
                let rule = target.kasus == .dativ
                    ? "\(word) + {wechsel:Wo?} (a place) → \(caseName(.dativ))."
                    : "\(word) + {wechsel:Wohin?} (a direction) → \(caseName(.akkusativ))."
                guard let verb = target.wechselVerb else { return rule }
                let hint = target.kasus == .dativ
                    ? "*\(verb)* says **where something is**."
                    : "*\(verb)* says **where something goes**."
                return rule + " " + hint
            }
            if preposition.position == .after {
                return preposition.word == "entlang"
                    ? "*entlang* after the noun takes the \(caseName(.akkusativ))."
                    : "\(word) takes the \(kasus), even after the noun."
            }
            if preposition.cases.count > 1 {
                return "\(word) in front of the noun takes the \(kasus) here."
            }
            // The rule card says it too: in speech the Genitiv prepositions often take the Dativ.
            if preposition.cases == [.genitiv] {
                return "\(word) takes the \(kasus) (in speech you'll often hear the \(caseName(.dativ)))."
            }
            return "\(word) **always** takes the \(kasus)."
        }

        switch target.spec.reason {
        // 2. Hangs on another noun.
        case .attribute:
            return target.spec.trigger.isEmpty
                ? "\(phrase) hangs on another noun and says **whose** → \(kasus)."
                : "\(phrase) hangs on \(trigger) and says **whose** → \(kasus)."
        // 3. The subject.
        case .subject:
            let line = "\(phrase) is the **subject** of \(trigger) → \(kasus)."
            return [line, reversedRoleNote(for: target)].compactMap { $0 }.joined(separator: " ")
        // 4. What sein/werden/bleiben/heißen equates with the subject.
        case .predicate:
            let verb = "*\(target.copulaVerb ?? target.spec.trigger)*"
            return "\(verb) links \(phrase) back to the subject, so it stays \(kasus)."
        // 5. The receiver, or a Dativ verb.
        case .recipient:
            return "\(phrase) is the **receiver** of \(trigger) → \(kasus)."
        case .dativeVerb:
            // Named by its infinitive too, since that's what a dictionary lists: *hilft* (*helfen*).
            var verb = trigger
            if let lemma = KasusForms.dativeVerbLemma(for: target.spec.trigger),
               lemma.caseInsensitiveCompare(target.spec.trigger) != .orderedSame {
                verb += " (*\(lemma)*)"
            }
            let line = "\(verb) is one of the verbs that **always** take the \(kasus)."
            return [line, reversedRoleNote(for: target)].compactMap { $0 }.joined(separator: " ")
        case .dativeOther:
            return "\(phrase) is the person this happens to: a fixed \(kasus) use."
        case .time:
            return "\(phrase) is a **time** phrase with no preposition → \(kasus)."
        // 6. Otherwise Akkusativ.
        case .object:
            return isLabel
                ? "Here it's what \(trigger) acts on → \(kasus)."
                : "\(phrase) is the **object**: what \(trigger) acts on → \(kasus)."
        case .wechselWo, .wechselWohin, .preposition, .prepObject, .inferred:
            // A preposition reason with no preposition found; the validator has already flagged it.
            return "\(phrase) is \(kasus) here."
        }
    }

    /// A generated story's unplanned phrase (`KasusReason.inferred`): only the article's form and
    /// the preposition in front prove its case, so that is all the line says. No verb, no role.
    /// After a two-way preposition it names Wo?/Wohin? only when the validator found a position or
    /// placement verb that agrees („in der Küche“ could be a place, or a time, or „freut sich
    /// über“: the article shows the case, not the reason).
    ///   „{m:den} + a masculine noun can only be {akk:Akkusativ}: the article's form shows the case.“
    ///   „*mit* **always** takes the {dat:Dativ}: {m:dem} + a masculine noun.“
    ///   „By its form, {f:die} could be {nom:Nominativ} or {akk:Akkusativ}; *für* **always** takes the {akk:Akkusativ}.“
    ///   „*an* takes the {akk:Akkusativ} or the {dat:Dativ}; here {m:dem} + a masculine noun can only be {dat:Dativ}.“
    static func inferredLine(for target: KasusLocatedTarget) -> String {
        let kasus = caseName(target.kasus)
        let article = form(target.caseForm, target.genus)
        let noun = target.genus == .plural ? "a plural noun" : "a \(target.genus.genderName) noun"
        guard let preposition = target.preposition else {
            return "\(article) + \(noun) can only be \(kasus): the article's form shows the case."
        }
        let word = "*\(preposition.word)*"
        let place = target.kasus == .dativ ? "{wechsel:Wo?} (a place)" : "{wechsel:Wohin?} (a direction)"
        let verbHint = target.wechselVerb.map { verb in
            target.kasus == .dativ ? "*\(verb)* says **where something is**." : "*\(verb)* says **where something goes**."
        }
        if target.candidates.count <= 1 {
            if preposition.isTwoWay {
                guard let verbHint else {
                    return "\(word) takes the \(caseName(.akkusativ)) or the \(caseName(.dativ)); here \(article) + \(noun) can only be \(kasus)."
                }
                return "\(article) + \(noun) can only be \(kasus), so after \(word) it's \(place). \(verbHint)"
            }
            let always = preposition.cases.count == 1 ? "**always** takes" : "takes"
            return "\(word) \(always) the \(kasus): \(article) + \(noun)."
        }
        let cases = GrammarCase.allCases.filter(target.candidates.contains).map(caseName)
        let byForm = "By its form, \(article) could be \(list(cases))"
        if preposition.isTwoWay {
            let both = "\(byForm), and \(word) takes only \(caseName(.akkusativ)) or \(caseName(.dativ)): so \(kasus)"
            guard let verbHint else { return both + "." }
            return "\(both), \(place). \(verbHint)"
        }
        let always = preposition.cases.count == 1 ? "**always** takes" : "takes"
        return "\(byForm); \(word) \(always) the \(kasus)."
    }

    /// „Masculine {dat:Dativ} in „{m:m}{f:r}{n:m}{pl:n}“ is {m:m}: {m:dem}.“ (the code letters in their
    /// gender colors, as the table and the Schnellrunde print them). ein-words in the three no-ending spots
    /// say so instead. A contraction explains the article inside it; a pronoun names its pair
    /// („**mir** is *ich* in the {dat:Dativ}; the {akk:Akkusativ} is *mich*.“).
    static func codeWordLine(for target: KasusLocatedTarget) -> String? {
        let kasus = target.kasus
        let genus = target.genus
        if target.kind == .pronoun {
            guard let pronoun = KasusForms.pronoun(target.determiner) else { return nil }
            let other: GrammarCase = pronoun.kasus == .dativ ? .akkusativ : .dativ
            return "**\(pronoun.word)** is *\(pronoun.nominative)* in the \(caseName(pronoun.kasus)); the \(caseName(other)) is *\(pronoun.otherCase)*."
        }
        let cell = "\(genus.genderName.capitalized) \(caseName(kasus))"
        let letter = kasus.article(genus).suffix(1)
        if target.kind == .contraction {
            guard let article = target.contractedArticle, article == kasus.article(genus) else { return nil }
            return "\(cell) in „\(codeWord(kasus))“ is \(form(String(letter), genus)): \(form(article, genus))."
        }
        guard let parsed = target.parsed,
              let answer = KasusForms.form(parsed, case: kasus, genus: genus)
        else { return nil }
        let einWord = [KasusFamily.ein, .kein, .possessive].contains(parsed.family)
        if einWord && kasus.einEnding(genus).isEmpty {
            return "\(cell) is one of the spots with **no ending**: \(form(answer, genus))."
        }
        return "\(cell) in „\(codeWord(kasus))“ is \(form(String(letter), genus)): \(form(answer, genus))."
    }

    /// The noun's own ending: n-nouns, the Genitiv -s, the Dativ plural -n. Nil for a pronoun.
    static func nounNote(for target: KasusLocatedTarget) -> String? {
        guard target.kind != .pronoun else { return nil }
        let lemma = target.spec.lemma
        let noun = target.noun
        switch (target.kasus, target.genus) {
        case (.nominativ, _):
            return nil
        case (_, .der) where KasusForms.isNDeklination(lemma):
            let ending = KasusForms.nDeklinationEnding(lemma: lemma, kasus: target.kasus)
            return "*\(lemma)* is an **n-noun**, so it adds -\(ending) too: *\(noun)*."
        case (.genitiv, .der), (.genitiv, .das):
            return KasusForms.isAdjectivalNoun(lemma) ? nil : "The noun adds **-(e)s** too: *\(noun)*."
        case (.dativ, .plural):
            return noun.hasSuffix("n") ? "In the \(caseName(.dativ)) plural the noun ends in **-n** too: *\(noun)*." : nil
        default:
            return nil
        }
    }

    /// Einsetzen, when the pick is the right case for another gender („in dem Tasche“).
    /// „Right case, **wrong gender**: {m:dem} is masculine {dat:Dativ}. This noun is feminine, so
    /// {f:der}.“
    static func genderSlipNote(pick: String, answer: String, genus: Gender, kasus: GrammarCase? = nil) -> String {
        let picked = pick.lowercased()
        let wanted = answer.lowercased()
        if let parsed = KasusForms.parseDeterminer(answer) {
            let cases = kasus.map { [$0] }
                ?? GrammarCase.allCases.filter { KasusForms.form(parsed, case: $0, genus: genus) == parsed.word }
            for kasus in cases {
                let others = KasusForms.gendersOfSlip(pick: picked, kasus: kasus, genus: genus,
                                                      family: parsed.family, stem: parsed.stem)
                if !others.isEmpty {
                    return "Right case, **wrong gender**: \(genderedForm(picked, others)) is \(genderNames(others)) \(caseName(kasus)). This noun is \(genus.genderName), so \(form(wanted, genus))."
                }
            }
        }
        return "Right case, **wrong gender**. This noun is \(genus.genderName), so \(form(wanted, genus))."
    }

    /// Einsetzen, when the pick is the right case in the other number on a noun that reads the
    /// same in both („nimmt die Schlüssel“ for one key, „für den Nachbarn“ for several).
    /// „Right case, **wrong number**: {pl:die} is the plural {akk:Akkusativ}. *Schlüssel* looks the
    /// same in the plural, but here it's one, so {m:den}.“
    static func numberSlipNote(pick: String, answer: String, kasus: GrammarCase, noun: String,
                               answerIsPlural: Bool = false) -> String {
        let wanted = answer.lowercased()
        let picked = pick.lowercased()
        // The singular form's gender is whichever singular gender has that form in this case;
        // „dem“ fits masculine and neuter alike, so it stays bold instead of taking a color.
        let singular = answerIsPlural ? picked : wanted
        let genders = KasusForms.parseDeterminer(singular).map { parsed in
            [Gender.der, .die, .das].filter { KasusForms.form(parsed, case: kasus, genus: $0) == singular }
        } ?? []
        let singularForm = genderedForm(singular, genders)
        if answerIsPlural {
            return "Right case, **wrong number**: \(singularForm) is the singular \(caseName(kasus)). *\(noun)* looks the same in the singular, but here it's more than one, so \(form(wanted, .plural))."
        }
        return "Right case, **wrong number**: \(form(picked, .plural)) is the plural \(caseName(kasus)). *\(noun)* looks the same in the plural, but here it's one, so \(singularForm)."
    }

    // MARK: - Markup

    /// A case name in its case's color: „{dat:Dativ}“.
    static func caseName(_ kasus: GrammarCase) -> String {
        "{\(kasus.short.lowercased()):\(kasus.name)}"
    }

    /// The code word with each letter in its column's gender color („{m:m}{f:r}{n:m}{pl:n}“), the
    /// same as `EndingsQuestion.codeWord` in the Schnellrunde.
    static func codeWord(_ kasus: GrammarCase) -> String {
        zip(kasus.code, Gender.allCases).map { "{\($1.columnLabel):\($0)}" }.joined()
    }

    /// An article form in its gender's color: „{m:dem}“. Braces can't appear inside a token, so a
    /// word that has one falls back to bold.
    static func form(_ word: String, _ genus: Gender) -> String {
        guard !word.contains("{"), !word.contains("}") else { return "**\(word)**" }
        return "{\(genus.columnLabel):\(word)}"
    }

    /// A form in its gender's color when only one gender has it, else bold: „dem“ is masculine
    /// and neuter, so no one color is right.
    private static func genderedForm(_ word: String, _ genders: [Gender]) -> String {
        genders.count == 1 ? form(word, genders[0]) : "**\(word)**"
    }

    /// "masculine", "masculine or neuter".
    private static func genderNames(_ genders: [Gender]) -> String {
        list(genders.map(\.genderName))
    }

    // MARK: - Helpers

    /// gefallen, gehören and schmecken turn the English roles around.
    private static func reversedRoleNote(for target: KasusLocatedTarget) -> String? {
        let dativ = caseName(.dativ)
        return switch KasusForms.dativeVerbLemma(for: target.spec.trigger) {
        case "gefallen":  "With *gefallen*, the thing liked is the **subject** and the person is \(dativ)."
        case "gehören":   "With *gehören*, the thing owned is the **subject** and the owner is \(dativ)."
        case "schmecken": "With *schmecken*, the food is the **subject** and the person is \(dativ)."
        default:          nil
        }
    }

    /// Verbs that feel like they have a receiver but take the Akkusativ.
    private static let akkusativTraps: [String: [String]] = [
        "fragen":   ["frage", "fragst", "fragt", "fragen", "fragte", "fragtest", "fragten", "gefragt"],
        "anrufen":  ["anrufen", "angerufen", "rufe an", "rufst an", "ruft an", "rufen an", "rief an", "riefen an"],
        "besuchen": ["besuche", "besuchst", "besucht", "besuchen", "besuchte", "besuchten"],
    ]

    /// „*fragen* takes the {akk:Akkusativ}, even though it can feel like there's a receiver.“
    static func trapNote(for target: KasusLocatedTarget) -> String? {
        guard target.spec.reason == .object, target.preposition == nil else { return nil }
        let trigger = target.spec.trigger.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let verb = akkusativTraps.first(where: { $0.value.contains(trigger) })?.key else { return nil }
        return "*\(verb)* takes the \(caseName(.akkusativ)), even though it can feel like there's a receiver."
    }

    /// "Nominativ or Akkusativ", "Nominativ, Akkusativ or Dativ".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
    }
}
