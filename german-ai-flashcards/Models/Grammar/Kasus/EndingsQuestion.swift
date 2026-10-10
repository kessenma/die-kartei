//
//  EndingsQuestion.swift
//  german-ai-flashcards
//
//  The Schnellrunde's engine: the nouns to hang an article on, the article families, the
//  sentence frames (with the Kasus-Check reason each one teaches) and one question with its
//  options, grading and explanation. A round is the frames × nouns × determiners, weighted by
//  `quota` so every case in play is asked and the unit's own case most; seeded when a test or a
//  screenshot needs the same round twice. Bau das Wort plays the same questions by their ending
//  (`endingLabels`), and the variants of the endings drill (Dativ-Verben, a confusion pair, the
//  Blitzrunde) pick frames by family or options by hand.
//
//  Foundation only and `nonisolated`: compiled into training/kasus_cli. The screen that plays it
//  is in Features/Grammar.
//

import Foundation

/// A noun to hang an article on. People and animals only, so every sentence frame makes sense.
nonisolated struct EndingsNoun: Hashable {
    let singular: String
    let plural: String
    /// Genitive singular. Masculine and neuter add -(e)s, feminine nouns don't change.
    let genitive: String
    let gender: Gender   // .der / .die / .das

    /// Dative plural: + n unless the plural already ends in -n or -s.
    var dativePlural: String {
        plural.hasSuffix("n") || plural.hasSuffix("s") ? plural : plural + "n"
    }

    /// Genitive plural: the plural as it is. Only the article changes (der).
    var genitivePlural: String { plural }

    /// The noun as it stands after the article in this case and number.
    func form(_ kasus: GrammarCase, isPlural: Bool) -> String {
        switch (kasus, isPlural) {
        case (.dativ, true):    dativePlural
        case (.genitiv, true):  genitivePlural
        case (.genitiv, false): genitive
        case (_, true):         plural
        case (_, false):        singular
        }
    }

    static let all: [EndingsNoun] = [
        .init(singular: "Mann", plural: "Männer", genitive: "Mannes", gender: .der),
        .init(singular: "Hund", plural: "Hunde", genitive: "Hundes", gender: .der),
        .init(singular: "Lehrer", plural: "Lehrer", genitive: "Lehrers", gender: .der),
        .init(singular: "Vater", plural: "Väter", genitive: "Vaters", gender: .der),
        .init(singular: "Freund", plural: "Freunde", genitive: "Freundes", gender: .der),
        .init(singular: "Bruder", plural: "Brüder", genitive: "Bruders", gender: .der),
        .init(singular: "Sohn", plural: "Söhne", genitive: "Sohnes", gender: .der),
        .init(singular: "Arzt", plural: "Ärzte", genitive: "Arztes", gender: .der),
        .init(singular: "Frau", plural: "Frauen", genitive: "Frau", gender: .die),
        .init(singular: "Katze", plural: "Katzen", genitive: "Katze", gender: .die),
        .init(singular: "Lehrerin", plural: "Lehrerinnen", genitive: "Lehrerin", gender: .die),
        .init(singular: "Freundin", plural: "Freundinnen", genitive: "Freundin", gender: .die),
        .init(singular: "Kind", plural: "Kinder", genitive: "Kindes", gender: .das),
        .init(singular: "Mädchen", plural: "Mädchen", genitive: "Mädchens", gender: .das),
        .init(singular: "Baby", plural: "Babys", genitive: "Babys", gender: .das),
        .init(singular: "Pferd", plural: "Pferde", genitive: "Pferdes", gender: .das),
    ]
}

/// Which article family fills the blank.
nonisolated enum EndingsDeterminer: CaseIterable, Hashable {
    case definite, ein, mein, kein

    func form(_ kasus: GrammarCase, _ gender: Gender) -> String {
        switch self {
        case .definite: kasus.article(gender)
        case .ein:      "ein" + kasus.einEnding(gender)
        case .mein:     "mein" + kasus.einEnding(gender)
        case .kein:     "kein" + kasus.einEnding(gender)
        }
    }

    /// The forms engine's family and stem, so a pick is graded by the same rules as a story blank.
    var kasusFamily: (family: KasusFamily, stem: String) {
        switch self {
        case .definite: (.definite, "")
        case .ein:      (.ein, "ein")
        case .mein:     (.possessive, "mein")
        case .kein:     (.kein, "kein")
        }
    }

    /// The family's forms to pick from. The Genitiv form (des, eines…) joins only when the round
    /// has Genitiv in play; before that it is a form the learner hasn't met.
    func options(includesGenitiv: Bool) -> [String] {
        var forms: [String] = switch self {
        case .definite: ["der", "die", "das", "den", "dem"]
        case .ein:      ["ein", "eine", "einen", "einem", "einer"]
        case .mein:     ["mein", "meine", "meinen", "meinem", "meiner"]
        case .kein:     ["kein", "keine", "keinen", "keinem", "keiner"]
        }
        if includesGenitiv { forms.append(form(.genitiv, .der)) }
        return forms
    }
}

/// A sentence with a blank; `{N}` is the noun. `why` names the case trigger in Kasus-Check terms
/// (preposition, another noun, subject, sein, receiver or Dativ verb, otherwise Akkusativ), in the
/// `KasusRich` markup.
nonisolated struct EndingsFrame: Hashable {
    /// A drill family a frame belongs to beyond the plain Schnellrunde: a variant asks only its
    /// family's frames (the Dativ verbs with their Akkusativ false friends).
    enum Family: Hashable {
        case core
        /// helfen, gehören … and the verbs that only feel like they take the Dativ (besuchen).
        case dativVerb
    }

    let kasus: GrammarCase
    let singular: String
    let plural: String
    let why: String
    var family: Family = .core
    /// The English twin with its own blank („I see ___.“), for the Pronomen-Brücke. Nil where
    /// English has no natural pronoun there („That is he“).
    var englishSingular: String? = nil
    var englishPlural: String? = nil

    static let all: [EndingsFrame] = [
        .init(kasus: .nominativ, singular: "Das ist ___ {N}.", plural: "Das sind ___ {N}.", why: "„*sein*“ links it back to the **subject**, so it stays {nom:Nominativ}"),
        .init(kasus: .nominativ, singular: "Hier kommt ___ {N}.", plural: "Hier kommen ___ {N}.", why: "It's the **subject** of „*kommen*“, so {nom:Nominativ}",
              englishSingular: "Here comes ___.", englishPlural: "Here come ___."),
        .init(kasus: .akkusativ, singular: "Ich sehe ___ {N}.", plural: "Ich sehe ___ {N}.", why: "It's what „*sehen*“ acts on: the **direct object**, so {akk:Akkusativ}",
              englishSingular: "I see ___.", englishPlural: "I see ___."),
        .init(kasus: .akkusativ, singular: "Kennst du ___ {N}?", plural: "Kennst du ___ {N}?", why: "It's what „*kennen*“ acts on: the **direct object**, so {akk:Akkusativ}",
              englishSingular: "Do you know ___?", englishPlural: "Do you know ___?"),
        .init(kasus: .akkusativ, singular: "Wir besuchen ___ {N}.", plural: "Wir besuchen ___ {N}.", why: "It's what „*besuchen*“ acts on, so {akk:Akkusativ}. „*besuchen*“ can feel like it has a receiver, but it takes the {akk:Akkusativ}", family: .dativVerb,
              englishSingular: "We visit ___.", englishPlural: "We visit ___."),
        .init(kasus: .dativ, singular: "Ich helfe ___ {N}.", plural: "Ich helfe ___ {N}.", why: "„*helfen*“ is one of the verbs that always take the {dat:Dativ}", family: .dativVerb,
              englishSingular: "I help ___.", englishPlural: "I help ___."),
        .init(kasus: .dativ, singular: "Wir sprechen mit ___ {N}.", plural: "Wir sprechen mit ___ {N}.", why: "„*mit*“ always takes the {dat:Dativ}",
              englishSingular: "We speak with ___.", englishPlural: "We speak with ___."),
        .init(kasus: .dativ, singular: "Das Buch gehört ___ {N}.", plural: "Das Buch gehört ___ {N}.", why: "„*gehören*“ takes the {dat:Dativ}: the thing owned is the subject, the **owner** is {dat:Dativ}", family: .dativVerb,
              englishSingular: "The book belongs to ___.", englishPlural: "The book belongs to ___."),
        // Dativ-Verben: the verbs that take the Dativ without any „to“, and the ones that only
        // feel like they do.
        .init(kasus: .dativ, singular: "Ich danke ___ {N}.", plural: "Ich danke ___ {N}.", why: "„*danken*“ always takes the {dat:Dativ}: the thanks go **to** someone, even though English says „thank *him*“", family: .dativVerb),
        .init(kasus: .dativ, singular: "Das Essen gefällt ___ {N}.", plural: "Das Essen gefällt ___ {N}.", why: "„*gefallen*“ takes the {dat:Dativ}: the thing liked is the subject, the one who likes it the **receiver**", family: .dativVerb),
        .init(kasus: .dativ, singular: "Der Hund folgt ___ {N}.", plural: "Der Hund folgt ___ {N}.", why: "„*folgen*“ is one of the verbs that always take the {dat:Dativ}", family: .dativVerb),
        .init(kasus: .dativ, singular: "Ich antworte ___ {N}.", plural: "Ich antworte ___ {N}.", why: "„*antworten*“ takes the {dat:Dativ}: the answer goes **to** someone", family: .dativVerb),
        .init(kasus: .dativ, singular: "Wir gratulieren ___ {N}.", plural: "Wir gratulieren ___ {N}.", why: "„*gratulieren*“ always takes the {dat:Dativ}", family: .dativVerb),
        .init(kasus: .dativ, singular: "Die Suppe schmeckt ___ {N}.", plural: "Die Suppe schmeckt ___ {N}.", why: "„*schmecken*“ takes the {dat:Dativ}: the soup is the subject, the one tasting it the **receiver**", family: .dativVerb),
        .init(kasus: .dativ, singular: "Die Jacke passt ___ {N}.", plural: "Die Jacke passt ___ {N}.", why: "„*passen*“ takes the {dat:Dativ}: the jacket is the subject, the wearer the **receiver**", family: .dativVerb),
        .init(kasus: .dativ, singular: "Du fehlst ___ {N}.", plural: "Du fehlst ___ {N}.", why: "„*fehlen*“ takes the {dat:Dativ}: you are the subject, the one missing you the **receiver**", family: .dativVerb),
        .init(kasus: .dativ, singular: "Ich höre ___ {N} zu.", plural: "Ich höre ___ {N} zu.", why: "„*zuhören*“ always takes the {dat:Dativ}", family: .dativVerb),
        .init(kasus: .dativ, singular: "Ich glaube ___ {N}.", plural: "Ich glaube ___ {N}.", why: "„*glauben*“ with a person takes the {dat:Dativ}", family: .dativVerb),
        .init(kasus: .dativ, singular: "Wir vertrauen ___ {N}.", plural: "Wir vertrauen ___ {N}.", why: "„*vertrauen*“ always takes the {dat:Dativ}", family: .dativVerb),
        .init(kasus: .dativ, singular: "Ich begegne ___ {N}.", plural: "Ich begegne ___ {N}.", why: "„*begegnen*“ always takes the {dat:Dativ}", family: .dativVerb),
        .init(kasus: .akkusativ, singular: "Ich frage ___ {N}.", plural: "Ich frage ___ {N}.", why: "It's what „*fragen*“ acts on, so {akk:Akkusativ}. The person gets a question, but „*fragen*“ takes the {akk:Akkusativ}", family: .dativVerb),
        .init(kasus: .akkusativ, singular: "Ich rufe ___ {N} an.", plural: "Ich rufe ___ {N} an.", why: "It's what „*anrufen*“ acts on, so {akk:Akkusativ}. The call reaches someone, but „*anrufen*“ takes the {akk:Akkusativ}", family: .dativVerb),
        .init(kasus: .akkusativ, singular: "Wir brauchen ___ {N}.", plural: "Wir brauchen ___ {N}.", why: "It's what „*brauchen*“ acts on, so {akk:Akkusativ}", family: .dativVerb),
        .init(kasus: .genitiv, singular: "Das ist der Name ___ {N}.", plural: "Das sind die Namen ___ {N}.", why: "It hangs on **another noun** (*der Name*), so {gen:Genitiv}"),
        .init(kasus: .genitiv, singular: "Wegen ___ {N} bleiben wir zu Hause.", plural: "Wegen ___ {N} bleiben wir zu Hause.", why: "„*wegen*“ takes the {gen:Genitiv}"),
    ]
}

nonisolated struct EndingsQuestion: Identifiable, Hashable {
    let id = UUID()
    let frame: EndingsFrame
    let noun: EndingsNoun
    let isPlural: Bool
    let determiner: EndingsDeterminer
    /// The buttons on offer, fixed when the round is built (they depend on the round's cases).
    let options: [String]

    var kasus: GrammarCase { frame.kasus }
    var gender: Gender { isPlural ? .plural : noun.gender }
    var answer: String { determiner.form(kasus, gender) }

    var nounForm: String { noun.form(kasus, isPlural: isPlural) }

    /// The answer as two blocks, d + em, mein + en.
    var answerParts: KasusFormParts {
        let (family, stem) = determiner.kasusFamily
        return KasusForms.parts(family: family, stem: stem, case: kasus, genus: gender)
            ?? KasusFormParts(stem: "", ending: answer)
    }

    /// The stem every option shares: d, ein, mein, kein.
    var stem: String { answerParts.stem }

    /// An option's ending: „dem“ → em, „mein“ → "".
    func ending(of form: String) -> String {
        form.hasPrefix(stem) ? String(form.dropFirst(stem.count)) : form
    }

    func form(ending: String) -> String { stem + ending }

    /// Bau das Wort's buttons: the options as endings, „-em“ and „–“ for none.
    var endingLabels: [String] { options.map { KasusForms.endingLabel(ending(of: $0)) } }

    func form(endingLabel label: String) -> String {
        form(ending: label == "–" ? "" : String(label.drop { $0 == "-" }))
    }

    /// Right case, wrong gender („dem“ in „Ich helfe ___ Frau“), by the rule Einsetzen grades
    /// with, so the coach leaves it out here too. The Nominativ left unchanged („der“ for „dem
    /// Hund“) is a case miss.
    func isGenderSlip(_ pick: String) -> Bool {
        let (family, stem) = determiner.kasusFamily
        return KasusForms.isRightCaseWrongGender(pick: pick, answerCase: kasus, genus: gender,
                                                 family: family, stem: stem)
    }

    /// The sentence split around the blank.
    var parts: (before: String, after: String) {
        let template = (isPlural ? frame.plural : frame.singular)
            .replacingOccurrences(of: "{N}", with: nounForm)
        let pieces = template.components(separatedBy: "___")
        return (pieces.first ?? "", pieces.dropFirst().first ?? "")
    }

    /// Why, in the `KasusRich` markup: the frame's Kasus-Check reason, then the code-word line
    /// with the code letters in their gender colors („Masculine Dativ in „mrmn“ is m: dem.“), and
    /// the noun's own ending where it has one.
    var explanation: String {
        let tag = gender.columnLabel
        var text = "\(frame.why). "
        if determiner != .definite && kasus.einEnding(gender).isEmpty {
            text += "*\(gender.genderName.capitalized)* \(Self.caseWord(kasus)) is one of the spots with **no ending**: {\(tag):\(answer)}."
        } else {
            let letter = kasus.article(gender).suffix(1)
            text += "*\(gender.genderName.capitalized)* \(Self.caseWord(kasus)) in „\(Self.codeWord(kasus))“ is {\(tag):\(letter)}: {\(tag):\(answer)}."
        }
        if isPlural && kasus == .dativ && noun.dativePlural != noun.plural {
            text += " The noun adds **-n** too: *\(noun.plural)*{\(tag):n}."
        }
        if !isPlural && kasus == .genitiv && noun.genitive != noun.singular {
            text += " The noun adds **-\(noun.genitive.dropFirst(noun.singular.count))** too: *\(noun.genitive)*."
        }
        return text
    }

    /// A gender slip's own, softer line: the case was right, only the gender wasn't. The pick
    /// wears the color of the gender it belongs to.
    func slipNote(_ pick: String) -> String {
        let (family, stem) = determiner.kasusFamily
        let tag = gender.columnLabel
        let name = "*\(noun.singular)*"
        let others = KasusForms.gendersOfSlip(pick: pick, kasus: kasus, genus: gender, family: family, stem: stem)
        if let other = others.first {
            // „dem“ is masculine and neuter alike: named both ways, and bold rather than one color.
            let picked = others.count == 1 ? "{\(other.columnLabel):\(pick)}" : "**\(pick)**"
            let genders = others.map(\.genderName).joined(separator: " or ")
            return "Right case, wrong gender: \(picked) is \(genders) \(Self.caseWord(kasus)). \(name) is \(gender.genderName), so {\(tag):\(answer)}."
        }
        return "Right case, wrong gender. \(name) is \(gender.genderName), so {\(tag):\(answer)}."
    }

    /// What the drill says after a first pick: the slip note for a gender slip, the explanation
    /// for everything else.
    func feedback(pick: String) -> String {
        pick != answer && isGenderSlip(pick) ? slipNote(pick) : explanation
    }

    /// The case's name in its case color: `{dat:Dativ}` (`KasusExplanation.caseName`).
    static func caseWord(_ kasus: GrammarCase) -> String { KasusExplanation.caseName(kasus) }

    /// The code word with each letter in its column's gender color, as the table prints it
    /// (`KasusExplanation.codeWord`).
    static func codeWord(_ kasus: GrammarCase) -> String { KasusExplanation.codeWord(kasus) }

    /// How many of `count` questions each case gets. Nominativ is the easy baseline, so it weighs
    /// half as much as the others; `emphasis` (the unit's own case) weighs double on top. Every
    /// case in play gets at least one question, so a mixed round never turns single-case.
    static func quota(cases: [GrammarCase], emphasis: GrammarCase?, count: Int) -> [GrammarCase: Int] {
        let inPlay = GrammarCase.allCases.filter(cases.contains)
        guard !inPlay.isEmpty, count > 0 else { return [:] }
        let weights = inPlay.map { kasus -> Double in
            (kasus == .nominativ ? 1 : 2) + (kasus == emphasis ? 2 : 0)
        }
        let total = weights.reduce(0, +)
        let exact = weights.map { $0 / total * Double(count) }
        var counts = exact.map { max(1, Int($0)) }
        // Largest remainder fills the round; ties go to the later case on the path.
        let byRemainder = inPlay.indices.sorted {
            let a = exact[$0] - exact[$0].rounded(.down), b = exact[$1] - exact[$1].rounded(.down)
            return a == b ? $0 > $1 : a > b
        }
        var next = 0
        while counts.reduce(0, +) < count {
            counts[byRemainder[next % byRemainder.count]] += 1
            next += 1
        }
        // A very short round can overshoot on the one-each floor: trim the biggest share.
        while counts.reduce(0, +) > count,
              let biggest = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[biggest] > 1 {
            counts[biggest] -= 1
        }
        return Dictionary(uniqueKeysWithValues: zip(inPlay, counts))
    }

    /// A round over `cases`, weighted toward `emphasis`, no repeats. One case in, one case out:
    /// only the Nominativ unit asks a single case, since the others always keep earlier ones in.
    static func round(cases: [GrammarCase], emphasis: GrammarCase? = nil, count: Int = 10,
                      family: EndingsFrame.Family? = nil, genders: Set<Gender>? = nil,
                      determiners: [EndingsDeterminer]? = nil, options: [String]? = nil) -> [EndingsQuestion] {
        var rng = SystemRandomNumberGenerator()
        return round(cases: cases, emphasis: emphasis, count: count, family: family, genders: genders,
                     determiners: determiners, options: options, using: &rng)
    }

    /// The same round from a seed, so a test or a screenshot gets the same questions every time
    /// (`KasusSeededRandom`). `genders`, `determiners` and `options` narrow a variant: a confusion
    /// pair asks masculine nouns with the definite article and offers only dem and den.
    static func round(cases: [GrammarCase], emphasis: GrammarCase? = nil, count: Int = 10,
                      family: EndingsFrame.Family? = nil, genders: Set<Gender>? = nil,
                      determiners: [EndingsDeterminer]? = nil, options: [String]? = nil,
                      rng: inout KasusSeededRandom) -> [EndingsQuestion] {
        round(cases: cases, emphasis: emphasis, count: count, family: family, genders: genders,
              determiners: determiners, options: options, using: &rng)
    }

    /// The frames a round draws on: every frame, or a family's. A family that has no frame for a
    /// case drops that case from the round, so a variant must check `coversCases` before it
    /// trusts the quota.
    static func frames(family: EndingsFrame.Family?) -> [EndingsFrame] {
        family.map { family in EndingsFrame.all.filter { $0.family == family } } ?? EndingsFrame.all
    }

    /// Whether `family`'s frames span at least two of `cases` (or the one case of a single-case
    /// unit), so a round over them can't turn single-case.
    static func coversCases(_ cases: [GrammarCase], family: EndingsFrame.Family?) -> Bool {
        let covered = Set(frames(family: family).map(\.kasus)).intersection(cases)
        return cases.count == 1 ? covered.count == 1 : covered.count >= 2
    }

    private static func round<G: RandomNumberGenerator>(cases: [GrammarCase], emphasis: GrammarCase?, count: Int,
                                                        family: EndingsFrame.Family?, genders: Set<Gender>? = nil,
                                                        determiners: [EndingsDeterminer]? = nil, options: [String]? = nil,
                                                        using rng: inout G) -> [EndingsQuestion] {
        let includesGenitiv = cases.contains(.genitiv)
        let pool = frames(family: family)
        let nouns = EndingsNoun.all.filter { genders == nil || genders!.contains($0.gender) }
        let singularAllowed = genders == nil || genders!.contains(where: { $0 != .plural })
        let pluralAllowed = genders == nil || genders!.contains(.plural)
        let families = determiners ?? EndingsDeterminer.allCases
        guard !nouns.isEmpty || pluralAllowed, singularAllowed || pluralAllowed else { return [] }
        var seen = Set<String>()
        var out: [EndingsQuestion] = []
        // Table order, so the same seed always walks the cases the same way.
        let quotas = quota(cases: cases, emphasis: emphasis, count: count)
        for kasus in GrammarCase.allCases {
            guard let share = quotas[kasus] else { continue }
            let frames = pool.filter { $0.kasus == kasus }
            guard !frames.isEmpty else { continue }
            for _ in 0..<share {
                for _ in 0..<50 {
                    let noun = (nouns.isEmpty ? EndingsNoun.all : nouns).randomElement(using: &rng)!
                    let isPlural = !singularAllowed || (pluralAllowed && Int.random(in: 0..<4, using: &rng) == 0)
                    let key = "\(kasus)|\(noun.singular)|\(isPlural)"
                    guard seen.insert(key).inserted else { continue }
                    // ein has no plural, and kein stays out of the Genitiv frames
                    // („wegen keines Hundes“ is German nobody says).
                    let allowed = families.filter { !(isPlural && $0 == .ein) && !(kasus == .genitiv && $0 == .kein) }
                    guard let determiner = allowed.randomElement(using: &rng) else { continue }
                    let offered = options ?? determiner.options(includesGenitiv: includesGenitiv)
                    // A narrowed option row must still hold the answer.
                    guard offered.contains(determiner.form(kasus, isPlural ? .plural : noun.gender)) else { continue }
                    out.append(.init(
                        frame: frames.randomElement(using: &rng)!, noun: noun, isPlural: isPlural,
                        determiner: determiner, options: offered
                    ))
                    break
                }
            }
        }
        return out.shuffled(using: &rng)
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
