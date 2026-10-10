//
//  ReflexivForms.swift
//  german-ai-flashcards
//
//  The reflexive topic's tables, written by hand: the pronouns by person and case, the subjects,
//  the verbs with their present forms, what case they put the person in, and the objects each
//  verb naturally takes. The app has no conjugation table of its own (only participles in
//  past_tense_verbs.json), so this is the gate's source of truth for a verb form, and the
//  planner's source for the German it writes offline. A verb that isn't here can't be bundled.
//
//  Also the explanation every reflexive answer gets (`ReflexivExplanation`), derived from the
//  item's facts in the `KasusRich` markup and never stored, so a rule change rewrites every
//  explanation at once.
//

import Foundation

// MARK: - Pronouns

nonisolated enum ReflexivPronoun {
    /// mich / mir · dich / dir · sich · uns · euch · sich. Nil for a case the pronoun has no form in.
    static func form(person: Int, number: GrammarNumber, kasus: GrammarCase) -> String? {
        switch (person, number, kasus) {
        case (1, .sg, .akkusativ): "mich"
        case (1, .sg, .dativ):     "mir"
        case (2, .sg, .akkusativ): "dich"
        case (2, .sg, .dativ):     "dir"
        case (3, _, .akkusativ), (3, _, .dativ): "sich"
        case (1, .pl, .akkusativ), (1, .pl, .dativ): "uns"
        case (2, .pl, .akkusativ), (2, .pl, .dativ): "euch"
        default: nil
        }
    }

    static let all: Set<String> = ["mich", "mir", "dich", "dir", "sich", "uns", "euch"]

    /// The persons a form stands for (sich: every third person; uns: the first plural).
    static func persons(of form: String) -> [(person: Int, number: GrammarNumber)] {
        switch form.lowercased() {
        case "mich", "mir": [(1, .sg)]
        case "dich", "dir": [(2, .sg)]
        case "sich":        [(3, .sg), (3, .pl)]
        case "uns":         [(1, .pl)]
        case "euch":        [(2, .pl)]
        default:            []
        }
    }

    /// The same person in the other case: mich ↔ mir, dich ↔ dir. Nil where one form serves both.
    static func otherCase(of form: String) -> String? {
        switch form.lowercased() {
        case "mich": "mir"
        case "mir":  "mich"
        case "dich": "dir"
        case "dir":  "dich"
        default:     nil
        }
    }

    /// The case a form shows on its own; nil for sich, uns and euch, which look the same in both.
    static func visibleCase(of form: String) -> GrammarCase? {
        switch form.lowercased() {
        case "mich", "dich": .akkusativ
        case "mir", "dir":   .dativ
        default:             nil
        }
    }
}

// MARK: - Subjects

/// A subject the planner writes and the gate accepts, with its English for the templated twin.
nonisolated struct ReflexivSubject: Hashable {
    let text: String
    let person: Int
    let number: GrammarNumber
    let en: String
    /// my · your · his · her · our · your · their
    let possessive: String
    /// myself · yourself · himself · herself · ourselves · yourselves · themselves
    let reflexive: String

    static let all: [ReflexivSubject] = [
        ReflexivSubject(text: "Ich", person: 1, number: .sg, en: "I", possessive: "my", reflexive: "myself"),
        ReflexivSubject(text: "Du", person: 2, number: .sg, en: "You", possessive: "your", reflexive: "yourself"),
        ReflexivSubject(text: "Er", person: 3, number: .sg, en: "He", possessive: "his", reflexive: "himself"),
        ReflexivSubject(text: "Sie", person: 3, number: .sg, en: "She", possessive: "her", reflexive: "herself"),
        ReflexivSubject(text: "Wir", person: 1, number: .pl, en: "We", possessive: "our", reflexive: "ourselves"),
        ReflexivSubject(text: "Ihr", person: 2, number: .pl, en: "You", possessive: "your", reflexive: "yourselves"),
        ReflexivSubject(text: "Sie", person: 3, number: .pl, en: "They", possessive: "their", reflexive: "themselves"),
    ]

    /// The table row an item's subject names, when its text, person and number agree.
    static func matching(_ subject: GapSubject) -> ReflexivSubject? {
        let text = subject.text.lowercased()
        return all.first { row in
            guard row.person == subject.person, row.number == subject.number else { return false }
            return row.text.lowercased() == text
        }
    }

    /// „1st person singular“, for an explanation.
    static func label(person: Int, number: GrammarNumber) -> String {
        let ordinal = ["1st", "2nd", "3rd"][max(0, min(2, person - 1))]
        return "\(ordinal) person \(number == .sg ? "singular" : "plural")"
    }
}

// MARK: - Objects

/// A thing a verb naturally takes as its second object, in the Akkusativ with its article.
nonisolated struct ReflexivObject: Hashable {
    let text: String
    let lemma: String
    let genus: Gender
    let number: GrammarNumber
    /// The English noun without a possessive („hands“), or with its article where the English
    /// has one („a book“).
    let en: String
    /// The English twin says „my hands“ (true) or „a book“ (false).
    var possessed = true

    static let haende = ReflexivObject(text: "die Hände", lemma: "Hand", genus: .die, number: .pl, en: "hands")
    static let haare = ReflexivObject(text: "die Haare", lemma: "Haar", genus: .das, number: .pl, en: "hair")
    static let gesicht = ReflexivObject(text: "das Gesicht", lemma: "Gesicht", genus: .das, number: .sg, en: "face")
    static let zaehne = ReflexivObject(text: "die Zähne", lemma: "Zahn", genus: .der, number: .pl, en: "teeth")
    static let nase = ReflexivObject(text: "die Nase", lemma: "Nase", genus: .die, number: .sg, en: "nose")
    static let beine = ReflexivObject(text: "die Beine", lemma: "Bein", genus: .das, number: .pl, en: "legs")
    static let bart = ReflexivObject(text: "den Bart", lemma: "Bart", genus: .der, number: .sg, en: "beard")
    static let jacke = ReflexivObject(text: "die Jacke", lemma: "Jacke", genus: .die, number: .sg, en: "jacket")
    static let schuhe = ReflexivObject(text: "die Schuhe", lemma: "Schuh", genus: .der, number: .pl, en: "shoes")
    static let mantel = ReflexivObject(text: "den Mantel", lemma: "Mantel", genus: .der, number: .sg, en: "coat")
    static let arm = ReflexivObject(text: "den Arm", lemma: "Arm", genus: .der, number: .sg, en: "arm")
    static let knie = ReflexivObject(text: "das Knie", lemma: "Knie", genus: .das, number: .sg, en: "knee")
    static let buch = ReflexivObject(text: "ein Buch", lemma: "Buch", genus: .das, number: .sg, en: "a book", possessed: false)
    static let auto = ReflexivObject(text: "ein Auto", lemma: "Auto", genus: .das, number: .sg, en: "a car", possessed: false)
    static let kaffee = ReflexivObject(text: "einen Kaffee", lemma: "Kaffee", genus: .der, number: .sg, en: "a coffee", possessed: false)
    static let nummer = ReflexivObject(text: "die Nummer", lemma: "Nummer", genus: .die, number: .sg, en: "the number", possessed: false)
    static let namen = ReflexivObject(text: "den Namen", lemma: "Name", genus: .der, number: .sg, en: "the name", possessed: false)
    static let adresse = ReflexivObject(text: "die Adresse", lemma: "Adresse", genus: .die, number: .sg, en: "the address", possessed: false)
    static let film = ReflexivObject(text: "den Film", lemma: "Film", genus: .der, number: .sg, en: "the film", possessed: false)
    static let foto = ReflexivObject(text: "das Foto", lemma: "Foto", genus: .das, number: .sg, en: "the photo", possessed: false)
    static let bild = ReflexivObject(text: "das Bild", lemma: "Bild", genus: .das, number: .sg, en: "the picture", possessed: false)
    static let reise = ReflexivObject(text: "eine Reise", lemma: "Reise", genus: .die, number: .sg, en: "a trip", possessed: false)
    static let antwort = ReflexivObject(text: "die Antwort", lemma: "Antwort", genus: .die, number: .sg, en: "the answer", possessed: false)
    static let plan = ReflexivObject(text: "einen Plan", lemma: "Plan", genus: .der, number: .sg, en: "a plan", possessed: false)
    static let stadt = ReflexivObject(text: "die Stadt", lemma: "Stadt", genus: .die, number: .sg, en: "the city", possessed: false)
    static let haus = ReflexivObject(text: "das Haus", lemma: "Haus", genus: .das, number: .sg, en: "the house", possessed: false)
}

// MARK: - Verbs

/// The English of a verb, by person and by the case the German shows.
nonisolated struct ReflexivEnglish: Hashable {
    let base: String
    let third: String
    /// The Akkusativ reading: `{S}` subject, `{V}` verb, `{B}` am / are / is, `{R}` myself …, `{O}` the object.
    let akk: String?
    /// The Dativ reading: `{P}` the possessive (my hands) or `{O}` the object as written.
    let dat: String?
}

/// A fixed phrase after the pronoun that rounds the sentence off („am Wochenende“), with its
/// English. Never asked, never read into; the gate takes it verbatim.
nonisolated struct ReflexivTail: Hashable {
    let de: String
    let en: String
}

nonisolated struct ReflexivVerb: Hashable {
    /// The infinitive without „sich“.
    let lemma: String
    /// A separable prefix, written last.
    var prefix: String? = nil
    let takes: ReflexivTakes
    /// Present forms: ich · du · er/sie/es · wir · ihr · sie.
    let forms: [String]
    let en: ReflexivEnglish
    /// The second objects the verb naturally takes (none for an always-Akkusativ verb).
    var objects: [ReflexivObject] = []
    /// Tails for the Akkusativ reading of an always-Akkusativ verb („Ich beeile mich heute“). A
    /// verb that takes either case gets none: a phrase after the pronoun could read as the second
    /// object the lesson talks about.
    var tails: [ReflexivTail] = []
    /// The subject numbers the verb takes. A reciprocal verb (sich treffen) needs a plural
    /// subject: „Ich treffe mich im Park“ is missing its „mit …“.
    var numbers: Set<GrammarNumber> = [.sg, .pl]

    /// The finite form for a subject.
    func form(person: Int, number: GrammarNumber) -> String? {
        let index: Int
        switch (person, number) {
        case (1, .sg): index = 0
        case (2, .sg): index = 1
        case (3, .sg): index = 2
        case (1, .pl): index = 3
        case (2, .pl): index = 4
        case (3, .pl): index = 5
        default:       return nil
        }
        return forms.indices.contains(index) ? forms[index] : nil
    }

    /// „sich waschen“, „sich anziehen“ (the lemma already carries its prefix).
    var infinitive: String { "sich " + lemma }

    static func named(_ lemma: String) -> ReflexivVerb? {
        table.first { $0.lemma == lemma }
    }

    private static func regular(_ stem: String) -> [String] {
        // An e before -st/-t after t, d and a consonant + n (du leistest, er trocknet).
        let e = ["t", "d", "chn", "ckn", "ffn", "gn"].contains(where: stem.hasSuffix) ? "e" : ""
        let s = stem.hasSuffix("s") || stem.hasSuffix("z") || stem.hasSuffix("ß") || stem.hasSuffix("x") ? "t" : "st"
        return [stem + "e", stem + e + s, stem + e + "t", stem + "en", stem + e + "t", stem + "en"]
    }

    static let table: [ReflexivVerb] = [
        // Both: the person alone, or a thing with the person as receiver.
        ReflexivVerb(lemma: "waschen", takes: .both, forms: ["wasche", "wäschst", "wäscht", "waschen", "wascht", "waschen"],
                     en: ReflexivEnglish(base: "wash", third: "washes", akk: "{S} {V} {R}.", dat: "{S} {V} {P} {O}."),
                     objects: [.haende, .haare, .gesicht]),
        ReflexivVerb(lemma: "kämmen", takes: .both, forms: regular("kämm"),
                     en: ReflexivEnglish(base: "comb", third: "combs", akk: "{S} {V} {P} hair.", dat: "{S} {V} {P} {O}."),
                     objects: [.haare]),
        ReflexivVerb(lemma: "rasieren", takes: .both, forms: regular("rasier"),
                     en: ReflexivEnglish(base: "shave", third: "shaves", akk: "{S} {V}.", dat: "{S} {V} {P} {O}."),
                     objects: [.beine, .gesicht]),
        ReflexivVerb(lemma: "putzen", takes: .both, forms: regular("putz"),
                     en: ReflexivEnglish(base: "brush", third: "brushes", akk: nil, dat: "{S} {V} {P} {O}."),
                     objects: [.zaehne]),
        ReflexivVerb(lemma: "abtrocknen", prefix: "ab", takes: .both, forms: regular("trockn"),
                     en: ReflexivEnglish(base: "dry", third: "dries", akk: "{S} {V} {R} off.", dat: "{S} {V} {P} {O}."),
                     objects: [.haende, .haare]),
        ReflexivVerb(lemma: "anziehen", prefix: "an", takes: .both, forms: regular("zieh"),
                     en: ReflexivEnglish(base: "get dressed", third: "gets dressed", akk: "{S} {V}.", dat: "{S} {V:put|puts} on {P} {O}."),
                     objects: [.jacke, .schuhe, .mantel]),
        ReflexivVerb(lemma: "ausziehen", prefix: "aus", takes: .both, forms: regular("zieh"),
                     en: ReflexivEnglish(base: "get undressed", third: "gets undressed", akk: "{S} {V}.", dat: "{S} {V:take|takes} off {P} {O}."),
                     objects: [.jacke, .schuhe, .mantel]),
        ReflexivVerb(lemma: "verletzen", takes: .both, forms: regular("verletz"),
                     en: ReflexivEnglish(base: "hurt", third: "hurts", akk: "{S} {V} {R}.", dat: "{S} {V} {P} {O}."),
                     objects: [.arm, .knie]),
        ReflexivVerb(lemma: "vorstellen", prefix: "vor", takes: .both, forms: regular("stell"),
                     en: ReflexivEnglish(base: "introduce", third: "introduces", akk: "{S} {V} {R}.", dat: "{S} {V:imagine|imagines} {O}."),
                     objects: [.stadt, .haus]),
        // Dativ only: a thing is the Akkusativ object, the person the receiver.
        ReflexivVerb(lemma: "merken", takes: .dat, forms: regular("merk"),
                     en: ReflexivEnglish(base: "remember", third: "remembers", akk: nil, dat: "{S} {V} {O}."),
                     objects: [.nummer, .namen, .adresse]),
        ReflexivVerb(lemma: "kaufen", takes: .dat, forms: regular("kauf"),
                     en: ReflexivEnglish(base: "buy", third: "buys", akk: nil, dat: "{S} {V} {R} {O}."),
                     objects: [.buch, .auto, .kaffee]),
        ReflexivVerb(lemma: "ansehen", prefix: "an", takes: .dat, forms: ["sehe", "siehst", "sieht", "sehen", "seht", "sehen"],
                     en: ReflexivEnglish(base: "look at", third: "looks at", akk: nil, dat: "{S} {V} {O}."),
                     objects: [.foto, .bild]),
        ReflexivVerb(lemma: "leisten", takes: .dat, forms: regular("leist"),
                     en: ReflexivEnglish(base: "afford", third: "affords", akk: nil, dat: "{S} can afford {O}."),
                     objects: [.auto, .reise]),
        ReflexivVerb(lemma: "überlegen", takes: .dat, forms: regular("überleg"),
                     en: ReflexivEnglish(base: "think", third: "thinks", akk: nil, dat: "{S} {V} about {O}."),
                     objects: [.antwort, .plan]),
        // Akkusativ only: the person is the only object.
        ReflexivVerb(lemma: "beeilen", takes: .akk, forms: regular("beeil"),
                     en: ReflexivEnglish(base: "hurry", third: "hurries", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "heute", en: "today"), ReflexivTail(de: "jetzt", en: "now")]),
        ReflexivVerb(lemma: "erholen", takes: .akk, forms: regular("erhol"),
                     en: ReflexivEnglish(base: "rest", third: "rests", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "am Wochenende", en: "at the weekend"), ReflexivTail(de: "im Urlaub", en: "on holiday")]),
        ReflexivVerb(lemma: "setzen", takes: .akk, forms: regular("setz"),
                     en: ReflexivEnglish(base: "sit down", third: "sits down", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "auf den Stuhl", en: "on the chair"), ReflexivTail(de: "ans Fenster", en: "by the window")]),
        ReflexivVerb(lemma: "freuen", takes: .akk, forms: regular("freu"),
                     en: ReflexivEnglish(base: "look forward", third: "looks forward", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "auf die Ferien", en: "to the holidays"), ReflexivTail(de: "auf das Wochenende", en: "to the weekend")]),
        ReflexivVerb(lemma: "ärgern", takes: .akk, forms: ["ärgere", "ärgerst", "ärgert", "ärgern", "ärgert", "ärgern"],
                     en: ReflexivEnglish(base: "get annoyed", third: "gets annoyed", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "über den Lärm", en: "about the noise"), ReflexivTail(de: "über das Wetter", en: "about the weather")]),
        ReflexivVerb(lemma: "erinnern", takes: .akk, forms: ["erinnere", "erinnerst", "erinnert", "erinnern", "erinnert", "erinnern"],
                     en: ReflexivEnglish(base: "remember", third: "remembers", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "an den Sommer", en: "the summer"), ReflexivTail(de: "an die Reise", en: "the trip")]),
        ReflexivVerb(lemma: "interessieren", takes: .akk, forms: regular("interessier"),
                     en: ReflexivEnglish(base: "interested", third: "interested", akk: "{S} {B} interested.", dat: nil),
                     tails: [ReflexivTail(de: "für Musik", en: "in music"), ReflexivTail(de: "für Fußball", en: "in football")]),
        ReflexivVerb(lemma: "entschuldigen", takes: .akk, forms: regular("entschuldig"),
                     en: ReflexivEnglish(base: "apologise", third: "apologises", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "beim Lehrer", en: "to the teacher"), ReflexivTail(de: "bei der Nachbarin", en: "to the neighbour")]),
        ReflexivVerb(lemma: "umziehen", prefix: "um", takes: .akk, forms: regular("zieh"),
                     en: ReflexivEnglish(base: "get changed", third: "gets changed", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "schnell", en: "quickly")]),
        ReflexivVerb(lemma: "duschen", takes: .akk, forms: regular("dusch"),
                     en: ReflexivEnglish(base: "shower", third: "showers", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "am Morgen", en: "in the morning"), ReflexivTail(de: "nach dem Sport", en: "after sport")]),
        ReflexivVerb(lemma: "fühlen", takes: .akk, forms: regular("fühl"),
                     en: ReflexivEnglish(base: "feel", third: "feels", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "gut", en: "good"), ReflexivTail(de: "müde", en: "tired")]),
        ReflexivVerb(lemma: "treffen", takes: .akk, forms: ["treffe", "triffst", "trifft", "treffen", "trefft", "treffen"],
                     en: ReflexivEnglish(base: "meet", third: "meets", akk: "{S} {V}.", dat: nil),
                     tails: [ReflexivTail(de: "im Park", en: "in the park"), ReflexivTail(de: "um sieben", en: "at seven")],
                     numbers: [.pl]),
    ]
}

// MARK: - Explanations

/// Why the answer is what it is, derived from the item's facts. In the `KasusRich` markup.
nonisolated enum ReflexivExplanation {

    /// The case line: why this pronoun's case.
    static func caseLine(_ item: GapChoiceItem) -> String {
        let answer = item.gaps.first?.answer ?? ""
        let verb = ReflexivVerb.named(item.verb.lemma)
        let infinitive = verb?.infinitive ?? "sich \(item.verb.lemma)"
        switch (item.verb.takes, item.secondObject) {
        case (.akk, _):
            return "„*\(infinitive)*“ is always reflexive: the person is its only object, so it takes the {akk:Akkusativ} → {akk:\(answer)}."
        case (.dat, let object?):
            return "„*sich etwas \(item.verb.lemma)*“ keeps the thing („*\(object.text)*“) in the {akk:Akkusativ}; the person is the receiver → {dat:Dativ} {dat:\(answer)}."
        case (.dat, nil):
            return "„*sich etwas \(item.verb.lemma)*“ puts the person in the {dat:Dativ} → {dat:\(answer)}."
        case (.both, nil):
            return "No second object follows „*\(item.verb.form)*“: the person is the object itself → {akk:Akkusativ} {akk:\(answer)}."
        case (.both, let object?):
            return "A second object follows („*\(object.text)*“) and takes the {akk:Akkusativ}; the person moves to the {dat:Dativ} → {dat:\(answer)}."
        }
    }

    /// The person line: why this pronoun's person.
    static func personLine(_ item: GapChoiceItem) -> String {
        let answer = item.gaps.first?.answer ?? ""
        let tag = item.kasus == .dativ ? "dat" : "akk"
        return "The subject is „*\(item.subject.text)*“ (\(ReflexivSubject.label(person: item.subject.person, number: item.subject.number))), so the pronoun is {\(tag):\(answer)}."
    }

    /// The explanation for the answer: the case rule, and the person where the round asks it.
    static func why(_ item: GapChoiceItem) -> String {
        switch item.focus {
        case .person: personLine(item) + " " + caseLine(item)
        default:      caseLine(item)
        }
    }

    /// The feedback for a pick, right or wrong.
    static func feedback(_ item: GapChoiceItem, pick: String) -> String {
        let answer = item.gaps.first?.answer ?? ""
        if pick.lowercased() == answer.lowercased() { return why(item) }
        if ReflexivPronoun.otherCase(of: answer)?.lowercased() == pick.lowercased() {
            return "„*\(pick)*“ is the right person but the wrong case. " + caseLine(item)
        }
        return "„*\(pick)*“ belongs to another person. " + personLine(item) + " " + caseLine(item)
    }
}
