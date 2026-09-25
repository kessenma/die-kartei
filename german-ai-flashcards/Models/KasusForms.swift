//
//  KasusForms.swift
//  german-ai-flashcards
//
//  The forms engine behind the Kasus stories: which article family a word belongs to, which cases
//  a determiner can stand for with a given gender, the answer options the fill-in step offers, and
//  the curated word lists the validator and the explanations lean on (n-nouns, plural-only nouns,
//  Dativ verbs, the liegen/legen pairs, copulas, contractions, the pronouns that show their case).
//
//  Every form is read off `GrammarCase.article(_:)` and `einEnding(_:)` (GrammarPalette.swift),
//  so the endings table, the drill and the story checks can never disagree. Foundation only.
//

import Foundation

// MARK: - Determiners

/// The article words a Kasus target can start with.
nonisolated enum KasusFamily: String, CaseIterable, Hashable {
    case definite     // der, die, das, den, dem, des
    case ein          // ein, eine, einen … and no plural
    case kein         // kein, keine, keinen …
    case possessive   // mein, dein, sein, ihr, unser, euer (and formal Ihr)
    case derWord      // dieser, jeder, welcher: the definite article's endings on a stem; jeder has no plural
}

/// A determiner token taken apart. `stem` is the base word the table hangs endings on ("ein",
/// "kein", "mein" … "euer", "dies", "jed", "welch"), empty for the definite article; `ending` is
/// what follows it ("en" in "einen"), or the whole word for the definite article. `word` is the
/// token lowercased.
nonisolated struct KasusDeterminer: Hashable {
    let family: KasusFamily
    let stem: String
    let ending: String
    let word: String
}

nonisolated enum KasusForms {

    static let definiteForms: Set<String> = ["der", "die", "das", "den", "dem", "des"]

    /// The possessive bases. euer drops its second e before an ending (eure, euren …); the
    /// colloquial unsre/unsren/unserm are not parsed, so a story lists them as notTargets.
    static let possessiveStems = ["mein", "dein", "sein", "ihr", "unser", "euer"]

    /// The der-word bases: dieser, jeder, welcher. They always carry an ending, the definite
    /// article's last letters (dies-er like d-er, dies-em like d-em), so the bare stem never parses.
    static let derWordStems = ["dies", "jed", "welch"]

    /// Every ending an ein-word can carry, including none.
    private static let einWordEndings: Set<String> = ["", "e", "en", "em", "er", "es"]

    /// Reads a token as a determiner, ignoring case ("Der", "SEINEN", "Diesem"). Nil when it
    /// belongs to none of the families.
    static func parseDeterminer(_ token: String) -> KasusDeterminer? {
        let word = token.lowercased()
        if definiteForms.contains(word) {
            return KasusDeterminer(family: .definite, stem: "", ending: word, word: word)
        }
        let bases: [(KasusFamily, String)] = [(.ein, "ein"), (.kein, "kein")]
            + possessiveStems.map { (.possessive, $0) }
        for (family, stem) in bases {
            if stem == "euer" {
                if word == "euer" { return KasusDeterminer(family: family, stem: stem, ending: "", word: word) }
                guard word.hasPrefix("eur") else { continue }
                let ending = String(word.dropFirst(3))
                guard !ending.isEmpty, einWordEndings.contains(ending) else { continue }
                return KasusDeterminer(family: family, stem: stem, ending: ending, word: word)
            }
            guard word.hasPrefix(stem) else { continue }
            let ending = String(word.dropFirst(stem.count))
            guard einWordEndings.contains(ending) else { continue }
            return KasusDeterminer(family: family, stem: stem, ending: ending, word: word)
        }
        for stem in derWordStems where word.hasPrefix(stem) {
            let ending = String(word.dropFirst(stem.count))
            guard !ending.isEmpty, einWordEndings.contains(ending) else { continue }
            return KasusDeterminer(family: .derWord, stem: stem, ending: ending, word: word)
        }
        return nil
    }

    /// A der-word's ending in one cell: the definite article's, minus its d („der“ → -er,
    /// „dem“ → -em, „die“ → -e, „das“ and „des“ → -es).
    static func derWordEnding(case kasus: GrammarCase, genus: Gender) -> String {
        switch kasus.article(genus) {
        case "die":          "e"
        case "das", "des":   "es"
        case let article:    String(article.dropFirst())   // der → er, den → en, dem → em
        }
    }

    /// The table form for one cell, lowercased. Nil for ein and jeder in the plural: „eine
    /// Kinder“ and „jede Kinder“ are not German, so those cells are empty rather than borrowed
    /// from kein or alle.
    static func form(family: KasusFamily, stem: String, case kasus: GrammarCase, genus: Gender) -> String? {
        switch family {
        case .definite:
            return kasus.article(genus)
        case .derWord:
            let base = stem.isEmpty ? "dies" : stem.lowercased()
            if base == "jed" && genus == .plural { return nil }
            return base + derWordEnding(case: kasus, genus: genus)
        case .ein, .kein, .possessive:
            if family == .ein && genus == .plural { return nil }
            let base = stem.isEmpty ? (family == .kein ? "kein" : "ein") : stem.lowercased()
            let ending = kasus.einEnding(genus)
            if base == "euer" && !ending.isEmpty { return "eur" + ending }
            return base + ending
        }
    }

    static func form(_ determiner: KasusDeterminer, case kasus: GrammarCase, genus: Gender) -> String? {
        form(family: determiner.family, stem: determiner.stem, case: kasus, genus: genus)
    }

    /// Every case this determiner can be with this gender: the table read backwards. „der“ with a
    /// feminine noun is {Dativ, Genitiv}; „eine“ with a plural noun is ∅.
    static func compatibleCases(determiner: String, genus: Gender) -> Set<GrammarCase> {
        guard let parsed = parseDeterminer(determiner) else { return [] }
        return compatibleCases(parsed, genus: genus)
    }

    static func compatibleCases(_ determiner: KasusDeterminer, genus: Gender) -> Set<GrammarCase> {
        Set(GrammarCase.allCases.filter { form(determiner, case: $0, genus: genus) == determiner.word })
    }

    /// Capitalises a table form to match the word it replaces, so a sentence-initial blank offers
    /// „Der“ rather than „der“.
    static func matchingCapitalization(_ form: String, like surface: String) -> String {
        guard let first = surface.first, first.isUppercase else { return form }
        return form.prefix(1).uppercased() + form.dropFirst()
    }

    // MARK: - Answer options

    /// The whole family as a teacher's table lists it: der · die · das · den · dem (· des), or
    /// ein · eine · einen · einem · einer (· eines). Genitiv-only forms join once Genitiv is in play.
    static func fullFamilyOptions(family: KasusFamily, stem: String, includeGenitive: Bool) -> [String] {
        let cases = GrammarCase.allCases.filter { includeGenitive || $0 != .genitiv }
        var seen = Set<String>()
        var options: [String] = []
        for kasus in cases {
            for genus in Gender.allCases {
                guard let form = form(family: family, stem: stem, case: kasus, genus: genus),
                      seen.insert(form).inserted else { continue }
                options.append(form)
            }
        }
        return options
    }

    /// Viel Hilfe: the noun's own gender through the cases in play (2–4 distinct forms). When that
    /// leaves fewer than three, one plausible other-gender form joins so it is never a coin flip:
    /// the masculine Dativ for feminine and plural (die · der · dem), the masculine Akkusativ for
    /// neuter (das · dem · den).
    static func vielHilfeOptions(answer: String, family: KasusFamily, stem: String, genus: Gender,
                                 includeGenitive: Bool) -> [String] {
        let cases = GrammarCase.allCases.filter { includeGenitive || $0 != .genitiv }
        var options: [String] = []
        for kasus in cases {
            guard let form = form(family: family, stem: stem, case: kasus, genus: genus),
                  !options.contains(form) else { continue }
            options.append(form)
        }
        let wanted = answer.lowercased()
        if !options.contains(wanted) { options.append(wanted) }
        if options.count < 3 {
            let extraCase: GrammarCase = genus == .das ? .akkusativ : .dativ
            if let extra = form(family: family, stem: stem, case: extraCase, genus: .der),
               !options.contains(extra) {
                options.append(extra)
            }
        }
        return options
    }

    /// True when `pick` is the right case for another singular gender: „dem“ for „der“ in
    /// „in ___ Tasche“. That is a gender slip, and it doesn't count as a case miss. Never a slip:
    ///   - a form the noun's own gender takes in some case. „der“ for „dem“ in „auf ___ Boden“ is
    ///     the Nominativ left unchanged, the classic case miss, even though „der“ is also the
    ///     feminine Dativ; so is „ein“ for „einen“;
    ///   - a plural form (den for dem stays a case miss: it is also the masculine Akkusativ);
    ///   - any pick for a plural answer, since the noun shows its number.
    static func isRightCaseWrongGender(pick: String, answerCase: GrammarCase, genus: Gender,
                                       family: KasusFamily, stem: String) -> Bool {
        guard genus != .plural else { return false }
        let picked = pick.lowercased()
        let ownForms = GrammarCase.allCases.compactMap { form(family: family, stem: stem, case: $0, genus: genus) }
        guard !ownForms.contains(picked) else { return false }
        return [Gender.der, .die, .das].contains { other in
            other != genus && form(family: family, stem: stem, case: answerCase, genus: other) == picked
        }
    }

    /// True when `pick` is the answer's case in the other number: „die“ for „den“ in „nimmt ___
    /// Schlüssel“, or for a plural answer the singular („den“ for „für die Nachbarn“, given the
    /// lemma's `singularGenus`). Only meaningful for a noun that reads the same in both numbers
    /// (the caller checks), where it is a number slip rather than a case miss.
    static func isRightCaseWrongNumber(pick: String, answerCase: GrammarCase, genus: Gender,
                                       singularGenus: Gender? = nil,
                                       family: KasusFamily, stem: String) -> Bool {
        let picked = pick.lowercased()
        let answer = form(family: family, stem: stem, case: answerCase, genus: genus)
        guard genus != .plural else {
            guard let singularGenus, singularGenus != .plural,
                  let singular = form(family: family, stem: stem, case: answerCase, genus: singularGenus)
            else { return false }
            return picked == singular && picked != answer
        }
        guard let plural = form(family: family, stem: stem, case: answerCase, genus: .plural) else { return false }
        return picked == plural && picked != answer
    }

    /// The other singular gender whose form in `kasus` is `pick`, for the gender-slip note.
    static func genderOfSlip(pick: String, kasus: GrammarCase, genus: Gender,
                             family: KasusFamily, stem: String) -> Gender? {
        gendersOfSlip(pick: pick, kasus: kasus, genus: genus, family: family, stem: stem).first
    }

    /// Every other singular gender whose form in `kasus` is `pick`: „dem“ in the Dativ is
    /// masculine and neuter alike, so a note shouldn't call it masculine only.
    static func gendersOfSlip(pick: String, kasus: GrammarCase, genus: Gender,
                              family: KasusFamily, stem: String) -> [Gender] {
        let picked = pick.lowercased()
        return [Gender.der, .die, .das].filter { other in
            other != genus && form(family: family, stem: stem, case: kasus, genus: other) == picked
        }
    }

    // MARK: - Nouns

    /// Whether the plural may look exactly like the singular (der Schlüssel · die Schlüssel), so a
    /// bare noun can't tell the number. A Goethe plural marker wins: "-" means the same, any other
    /// marker means it differs. Without one, masculine and neuter nouns in -er, -el, -en, -chen and
    /// -lein usually keep their form, unless the plural only adds an umlaut (der Boden · die Böden).
    static func mightBeSameInPlural(lemma: String, genus: Gender?, goethePlural: String?) -> Bool {
        if let marker = goethePlural?.trimmingCharacters(in: .whitespaces), !marker.isEmpty {
            return marker == "-"
        }
        guard genus == nil || genus == .der || genus == .das else { return false }
        guard !umlautPlurals.contains(where: { $0.caseInsensitiveCompare(lemma) == .orderedSame }) else { return false }
        let lower = lemma.lowercased()
        return ["er", "el", "en", "chen", "lein"].contains { lower.hasSuffix($0) }
    }

    /// Masculine and neuter nouns in -er, -el and -en whose plural is the umlaut alone, for when
    /// no Goethe row gives a marker.
    static let umlautPlurals: Set<String> = [
        "Apfel", "Boden", "Bruder", "Faden", "Garten", "Graben", "Hafen", "Hammer", "Kasten",
        "Kloster", "Laden", "Magen", "Mantel", "Nagel", "Ofen", "Sattel", "Schaden", "Vater", "Vogel",
    ]

    /// The plural a Goethe marker spells out: "-e" on Hund is Hunde, "¨-er" on Haus is Häuser,
    /// "-" keeps the word, "only pl." is the lemma itself, and a whole word ("Konten") is the
    /// plural as written. Nil for "only sg." and anything unreadable. The lists write the umlaut
    /// mark as the escape "¨", so both spellings are read.
    static func expectedPlural(lemma: String, marker: String?) -> String? {
        guard var mark = marker?.trimmingCharacters(in: .whitespaces), !mark.isEmpty else { return nil }
        mark = mark.replacingOccurrences(of: "\\u00a8", with: "¨")
        switch mark {
        case "only pl.": return lemma
        case "only sg.": return nil
        default:         break
        }
        var base = lemma
        if mark.hasPrefix("¨") {
            guard let umlauted = umlauted(lemma) else { return nil }
            base = umlauted
            mark.removeFirst()
        }
        guard mark.hasPrefix("-") else {
            // A whole word (Konten, Firmen); never after an umlaut mark.
            return base == lemma && mark.first?.isUppercase == true ? mark : nil
        }
        return base + mark.dropFirst()
    }

    /// The word with its last a, o or u umlauted, and „au“ as „äu“: Boden → Böden, Haus → Häus.
    /// Nil when there is nothing to umlaut.
    static func umlauted(_ word: String) -> String? {
        var letters = Array(word)
        guard let last = letters.lastIndex(where: { "aouAOU".contains($0) }) else { return nil }
        let at = letters[last] == "u" && last > 0 && "aA".contains(letters[last - 1]) ? last - 1 : last
        let umlaut: [Character: Character] = ["a": "ä", "o": "ö", "u": "ü", "A": "Ä", "O": "Ö", "U": "Ü"]
        guard let replacement = umlaut[letters[at]] else { return nil }
        letters[at] = replacement
        return String(letters)
    }

    /// Masculine n-nouns: -(e)n everywhere outside the Nominativ singular (den Jungen, dem Herrn,
    /// des Namens).
    static let nDeklination: Set<String> = [
        "Junge", "Mensch", "Student", "Kollege", "Nachbar", "Herr", "Kunde", "Tourist", "Polizist",
        "Name", "Präsident", "Affe", "Löwe", "Bär", "Held", "Soldat", "Journalist", "Architekt",
        "Planet", "Automat", "Bauer", "Gedanke", "Glaube", "Wille", "Friede", "Buchstabe",
    ]

    static func isNDeklination(_ lemma: String) -> Bool {
        nDeklination.contains { $0.caseInsensitiveCompare(lemma) == .orderedSame }
    }

    /// The Name-type nouns: the n-noun ending, plus -s in the Genitiv (des Namens, des
    /// Gedankens). Das Herz follows them in the neuter (dem Herzen, des Herzens).
    static let mixedDeclension: Set<String> = [
        "Name", "Gedanke", "Glaube", "Wille", "Friede", "Buchstabe", "Funke", "Same", "Herz",
    ]

    static func isMixedDeclension(_ lemma: String) -> Bool {
        mixedDeclension.contains { $0.caseInsensitiveCompare(lemma) == .orderedSame }
    }

    /// What an n-noun adds outside the Nominativ singular: -n after -e and -er and on Herr and
    /// Nachbar (den Jungen, dem Herrn), -en otherwise (den Studenten). The Name-type nouns add -s
    /// on top in the Genitiv (des Namens), and only they do: „des Studentens“ is wrong.
    static func nDeklinationEnding(lemma: String, kasus: GrammarCase) -> String {
        let lower = lemma.lowercased()
        let short = lower.hasSuffix("e") || lower.hasSuffix("er") || ["herr", "nachbar"].contains(lower)
        let ending = short ? "n" : "en"
        return kasus == .genitiv && isMixedDeclension(lemma) ? ending + "s" : ending
    }

    /// Whether an n-noun reads the same here in both numbers: „den Nachbarn“ (one neighbour) is
    /// also the plural „die Nachbarn“, „des Nachbarn“ also „der Nachbarn“. Outside the Nominativ
    /// the singular's -(e)n is the plural's, except on Herr (Herrn · Herren) and in a Name-type
    /// Genitiv (des Namens · der Namen). `noun` is the form in the text, either number.
    static func nNounReadsAsPlural(noun: String, lemma: String, kasus: GrammarCase) -> Bool {
        guard isNDeklination(lemma), kasus != .nominativ,
              lemma.caseInsensitiveCompare("Herr") != .orderedSame,
              kasus != .genitiv || !isMixedDeclension(lemma) else { return false }
        let plural = lemma + nDeklinationEnding(lemma: lemma, kasus: .akkusativ)
        return noun.caseInsensitiveCompare(plural) == .orderedSame
    }

    /// Whether `noun` is a masculine or neuter Genitiv singular of `lemma`: -s or -es (des Sofas,
    /// des Hundes), -es or -ses after s, ß, x and z (des Hauses, des Busses), -ens for das Herz.
    static func isGenitiveSingular(_ noun: String, of lemma: String) -> Bool {
        let lowerNoun = noun.lowercased(), lowerLemma = lemma.lowercased()
        guard lowerNoun.hasPrefix(lowerLemma) else { return false }
        let ending = String(lowerNoun.dropFirst(lowerLemma.count))
        if isMixedDeclension(lemma) { return ending == nDeklinationEnding(lemma: lemma, kasus: .genitiv) }
        let sibilant = ["s", "ß", "x", "z"].contains { lowerLemma.hasSuffix($0) }
        return (sibilant ? ["es", "ses"] : ["s", "es"]).contains(ending)
    }

    /// Nouns that only exist in the plural. Checked before any dictionary: Wiktionary files some
    /// of them with a singular gender. Not Lebensmittel: „das Lebensmittel“ is standard German,
    /// just rarer than the plural.
    static let pluraliaTantum: Set<String> = ["Leute", "Eltern", "Ferien", "Kosten", "Geschwister"]

    static func isPluraleTantum(_ lemma: String) -> Bool {
        pluraliaTantum.contains { $0.caseInsensitiveCompare(lemma) == .orderedSame }
    }

    /// Nouns with two accepted genders; either one passes the gender check.
    static let dualGender: [String: Set<Gender>] = [
        "Virus": [.der, .das],
        "Joghurt": [.der, .das],
        "Keks": [.der, .das],
    ]

    static func dualGenders(of lemma: String) -> Set<Gender>? {
        dualGender.first { $0.key.caseInsensitiveCompare(lemma) == .orderedSame }?.value
    }

    /// Nouns made from adjectives (der Deutsche, des Deutschen). They decline like adjectives, so
    /// the Genitiv -s rule skips them.
    static let adjectivalNouns: Set<String> = [
        "Deutsche", "Bekannte", "Verwandte", "Erwachsene", "Angestellte", "Beamte", "Kranke",
        "Jugendliche", "Reisende", "Vorsitzende", "Fremde", "Obdachlose",
    ]

    static func isAdjectivalNoun(_ lemma: String) -> Bool {
        adjectivalNouns.contains { $0.caseInsensitiveCompare(lemma) == .orderedSame }
    }

    // MARK: - Verbs

    /// Verbs that always take a Dativ object, with the forms a story is likely to use. The
    /// separable zuhören is listed both joined and split ("hört zu").
    static let dativeVerbs: [String: [String]] = [
        "helfen":      ["helfe", "hilfst", "hilft", "helfen", "helft", "half", "halfst", "halfen", "halft", "geholfen", "hilf"],
        "danken":      ["danke", "dankst", "dankt", "danken", "dankte", "danktest", "dankten", "gedankt"],
        "gefallen":    ["gefalle", "gefällst", "gefällt", "gefallen", "gefallt", "gefiel", "gefielst", "gefielen", "gefielt"],
        "gehören":     ["gehöre", "gehörst", "gehört", "gehören", "gehörte", "gehörtest", "gehörten"],
        "antworten":   ["antworte", "antwortest", "antwortet", "antworten", "antwortete", "antworteten", "geantwortet"],
        "gratulieren": ["gratuliere", "gratulierst", "gratuliert", "gratulieren", "gratulierte", "gratulierten"],
        "schmecken":   ["schmecke", "schmeckst", "schmeckt", "schmecken", "schmeckte", "schmeckten", "geschmeckt"],
        "passen":      ["passe", "passt", "passen", "passte", "passten", "gepasst"],
        "fehlen":      ["fehle", "fehlst", "fehlt", "fehlen", "fehlte", "fehlten", "gefehlt"],
        "folgen":      ["folge", "folgst", "folgt", "folgen", "folgte", "folgten", "gefolgt"],
        "glauben":     ["glaube", "glaubst", "glaubt", "glauben", "glaubte", "glaubten", "geglaubt"],
        "vertrauen":   ["vertraue", "vertraust", "vertraut", "vertrauen", "vertraute", "vertrauten"],
        "zuhören":     ["zuhöre", "zuhörst", "zuhört", "zuhören", "zuhörte", "zuhörten", "zugehört",
                        "höre zu", "hörst zu", "hört zu", "hören zu", "hörte zu", "hörten zu"],
    ]

    /// The Dativ verb a trigger is a form of ("gefällt" → "gefallen"), ignoring case.
    static func dativeVerbLemma(for trigger: String) -> String? {
        let wanted = trigger.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return dativeVerbs.first { $0.key == wanted || $0.value.contains(wanted) }?.key
    }

    /// With these three the thing is the subject and the person is Dativ: „Der Ball gefällt dem Hund.“
    static let reversedRoleVerbs: Set<String> = ["gefallen", "gehören", "schmecken"]

    /// How a two-way preposition's verb decides it: a position verb answers Wo? (Dativ), a
    /// placement verb answers Wohin? (Akkusativ).
    nonisolated enum WechselVerbKind: Hashable {
        case position     // liegen, stehen, sitzen, hängen (hing) → Dativ
        case placement    // legen, stellen, setzen, hängen (hängte) → Akkusativ
    }

    /// Fixed position/placement forms → (kind, infinitive). The present of hängen (hängt) is both,
    /// so only its unambiguous forms are listed.
    static let wechselVerbForms: [String: (kind: WechselVerbKind, lemma: String)] = {
        var map: [String: (kind: WechselVerbKind, lemma: String)] = [:]
        let table: [(WechselVerbKind, String, [String])] = [
            (.position, "liegen", ["liege", "liegst", "liegt", "liegen", "lag", "lagst", "lagen", "lagt", "gelegen"]),
            (.position, "stehen", ["stehe", "stehst", "steht", "stehen", "stand", "standst", "standen", "standet", "gestanden"]),
            (.position, "sitzen", ["sitze", "sitzt", "sitzen", "saß", "saßt", "saßen", "gesessen"]),
            (.position, "hängen", ["hing", "hingst", "hingen", "hingt", "gehangen"]),
            (.placement, "legen", ["lege", "legst", "legt", "legen", "legte", "legtest", "legten", "legtet", "gelegt"]),
            (.placement, "stellen", ["stelle", "stellst", "stellt", "stellen", "stellte", "stelltest", "stellten", "stelltet", "gestellt"]),
            (.placement, "setzen", ["setze", "setzt", "setzen", "setzte", "setztest", "setzten", "setztet", "gesetzt"]),
            (.placement, "hängen", ["hängte", "hängtest", "hängten", "hängtet", "gehängt"]),
        ]
        for (kind, lemma, forms) in table {
            for form in forms { map[form] = (kind, lemma) }
        }
        return map
    }()

    /// Motion verbs. With a two-way preposition they usually mean Wohin?, but „im Park laufen“ is
    /// Wo?, so they only ever raise a warning.
    static let motionVerbForms: Set<String> = [
        "gehe", "gehst", "geht", "gehen", "ging", "gingen", "gegangen",
        "fahre", "fährst", "fährt", "fahren", "fuhr", "fuhren", "gefahren",
        "laufe", "läufst", "läuft", "laufen", "lief", "liefen", "gelaufen",
        "komme", "kommst", "kommt", "kommen", "kam", "kamen", "gekommen",
        "fliege", "fliegst", "fliegt", "fliegen", "flog", "flogen", "geflogen",
        "springe", "springst", "springt", "springen", "sprang", "sprangen", "gesprungen",
        "renne", "rennst", "rennt", "rennen", "rannte", "rannten", "gerannt",
        "werfe", "wirfst", "wirft", "werfen", "warf", "warfen", "geworfen",
        "bringe", "bringst", "bringt", "bringen", "brachte", "brachten", "gebracht",
        "steige", "steigst", "steigt", "steigen", "stieg", "stiegen", "gestiegen",
        "falle", "fällst", "fällt", "fallen", "fiel", "fielen",
    ]

    /// sein, werden, bleiben and heißen, whose other noun stays Nominativ when they are the main
    /// verb („Das ist der Hund“).
    static let copulaForms: Set<String> = [
        "bin", "bist", "ist", "sind", "seid", "sein", "war", "warst", "waren", "wart",
        "sei", "seist", "wäre", "wärst", "wären", "wärt", "gewesen",
        "werde", "wirst", "wird", "werden", "werdet", "wurde", "wurdest", "wurden", "wurdet",
        "würde", "würdest", "würden", "würdet", "geworden",
        "bleibe", "bleibst", "bleibt", "bleiben", "blieb", "bliebst", "blieben", "bliebt", "geblieben",
        "heiße", "heißt", "heißen", "hieß", "hießt", "hießen", "geheißen",
    ]

    // MARK: - Prepositions

    /// Prepositions that double as conjunctions or zu-infinitive openers („um dem Hund zu helfen“,
    /// „seit die Mutter da ist“). They force their case only when the target's reason is
    /// `preposition`, or its trigger names them („seit dem Morgen“ as a time).
    static let softPrepositions: Set<String> = ["bis", "während", "seit", "um", "ohne", "statt", "anstatt", "außer"]

    /// Prepositions that may follow their noun („den Fluss entlang“, „dem Bahnhof gegenüber“).
    static let postpositions: Set<String> = ["nach", "gegenüber", "entlang", "wegen"]

    /// A preposition trigger may reach back across one of these plus a noun phrase
    /// („mit dem Hund und der Katze“).
    static let coordinators: Set<String> = ["und", "oder"]

    /// entlang takes the Akkusativ after its noun and the Dativ or Genitiv before it. It is never a
    /// two-way Wo/Wohin preposition, whatever prepositions.json files it under.
    static func entlangCases(after: Bool) -> Set<GrammarCase> {
        after ? [.akkusativ] : [.dativ, .genitiv]
    }

    /// Preposition + article contractions → (preposition, article), the ones prepositions.json
    /// lists plus hinters/überm/unterm/vors. A contraction target („im Garten“) is spot-only: it
    /// can be marked in Finden, never blanked. An idiom („am besten“, „zum Glück“) is a notTarget.
    static let contractions: [String: (preposition: String, article: String)] = [
        "am": ("an", "dem"), "ans": ("an", "das"), "aufs": ("auf", "das"), "beim": ("bei", "dem"),
        "durchs": ("durch", "das"), "fürs": ("für", "das"), "hinterm": ("hinter", "dem"),
        "hinters": ("hinter", "das"), "im": ("in", "dem"), "ins": ("in", "das"),
        "übers": ("über", "das"), "überm": ("über", "dem"), "ums": ("um", "das"),
        "unterm": ("unter", "dem"), "unters": ("unter", "das"), "vom": ("von", "dem"),
        "vorm": ("vor", "dem"), "vors": ("vor", "das"), "zum": ("zu", "dem"), "zur": ("zu", "der"),
    ]

    /// The contraction a token is, ignoring case („Im“ → in + dem). Nil for anything else.
    static func contraction(_ token: String) -> (preposition: String, article: String)? {
        contractions[token.lowercased()]
    }

    // MARK: - Pronouns

    /// The personal pronouns whose form alone shows the case: mich, dich, ihn are Akkusativ; mir,
    /// dir, ihm Dativ. uns, euch, sie, es and ihr read the same in two cases (or double as an
    /// article), so they stay plain text. A pronoun target is spot-only, like a contraction.
    static let caseVisiblePronouns: [String: KasusPronoun] = [
        "mich": KasusPronoun(word: "mich", kasus: .akkusativ, nominative: "ich", genders: nil),
        "dich": KasusPronoun(word: "dich", kasus: .akkusativ, nominative: "du", genders: nil),
        "ihn":  KasusPronoun(word: "ihn", kasus: .akkusativ, nominative: "er", genders: [.der]),
        "mir":  KasusPronoun(word: "mir", kasus: .dativ, nominative: "ich", genders: nil),
        "dir":  KasusPronoun(word: "dir", kasus: .dativ, nominative: "du", genders: nil),
        "ihm":  KasusPronoun(word: "ihm", kasus: .dativ, nominative: "er", genders: [.der, .das]),
    ]

    /// The case-visible pronoun a token is, ignoring case („Mir“). Nil for anything else.
    static func pronoun(_ token: String) -> KasusPronoun? {
        caseVisiblePronouns[token.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}

/// A personal pronoun whose form shows its case (`KasusForms.caseVisiblePronouns`).
nonisolated struct KasusPronoun: Hashable {
    /// Lowercased: "mir".
    let word: String
    let kasus: GrammarCase
    /// The Nominativ it comes from: ich, du, er (ihm is er or es; the table says er).
    let nominative: String
    /// The genders it can stand for. Nil for the ich and du forms, which have none.
    let genders: Set<Gender>?

    /// The same person in the other case: mich ↔ mir, dich ↔ dir, ihn ↔ ihm.
    var otherCase: String {
        switch word {
        case "mich": "mir"
        case "mir":  "mich"
        case "dich": "dir"
        case "dir":  "dich"
        case "ihn":  "ihm"
        default:     "ihn"
        }
    }
}
