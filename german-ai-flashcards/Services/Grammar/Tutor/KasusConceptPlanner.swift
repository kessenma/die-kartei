//
//  KasusConceptPlanner.swift
//  german-ai-flashcards
//
//  Seeded plans for one tutor-written Verstehen item each (`KasusConceptPlan`): the app picks the
//  verb, the nouns, their articles and roles, and (for Wer) which phrase opens the sentence; the
//  tutor only writes the sentence. Every plan also comes with a template sentence written without
//  any model, which is the baseline the tutors are measured against and a safe fallback.
//
//    Wer      subject + one partner on ONE verb that works both ways round („Den Hund jagt die
//             Katze“ / „Der Hund jagt die Katze“ both make sense), so only the ending can say who
//             does what. One phrase is a form-proven masculine (der/den/dem), the clue; the other
//             an ambiguous f/n one. Half the plans are object-first.
//    Rollen   subject + verb + one or two partners from the roles in play for the unit
//             (`KasusRole.chips`): an object, a receiver, a Dativ-verb partner, a preposition.
//    Probe    a phrase whose article could be two cases (die/das + f/n, der + f), in a role the
//             app picked, next to a form-proven subject wherever the role would otherwise be a
//             guess.
//
//  Nouns come from `Resources/kasus_triggers.json`, kept the way `KasusStoryPlanner` keeps them:
//  a verified singular gender, no n-nouns, no dual-gender nouns, at or below the level (relaxed to
//  B1 when a pool would be too small). Deterministic for a seed (`KasusSeededRandom`).
//

import Foundation

@MainActor
enum KasusConceptPlanner {

    /// A verb that reads both ways round with two living things, for Wer and Probe. Not in
    /// kasus_triggers.json, whose object verbs mostly take things.
    struct TwoWayVerb {
        let lemma: String
        let caseRaw: String           // the partner's case
        let shown: String             // third person singular present
        let forms: [String]
        let subjects: [String]        // noun categories
        let partners: [String]
    }

    static let akkusativVerbs: [TwoWayVerb] = [
        .init(lemma: "jagen", caseRaw: "akkusativ", shown: "jagt", forms: ["jagt", "jagte"],
              subjects: ["pets"], partners: ["pets"]),
        .init(lemma: "sehen", caseRaw: "akkusativ", shown: "sieht", forms: ["sieht", "sah"],
              subjects: ["people", "pets"], partners: ["people", "pets"]),
        .init(lemma: "suchen", caseRaw: "akkusativ", shown: "sucht", forms: ["sucht", "suchte"],
              subjects: ["people", "pets"], partners: ["people", "pets"]),
        .init(lemma: "finden", caseRaw: "akkusativ", shown: "findet", forms: ["findet", "fand"],
              subjects: ["people", "pets"], partners: ["people", "pets"]),
        .init(lemma: "rufen", caseRaw: "akkusativ", shown: "ruft", forms: ["ruft", "rief"],
              subjects: ["people"], partners: ["people", "pets"]),
        .init(lemma: "fragen", caseRaw: "akkusativ", shown: "fragt", forms: ["fragt", "fragte"],
              subjects: ["people"], partners: ["people"]),
        .init(lemma: "besuchen", caseRaw: "akkusativ", shown: "besucht", forms: ["besucht", "besuchte"],
              subjects: ["people"], partners: ["people"]),
        .init(lemma: "kennen", caseRaw: "akkusativ", shown: "kennt", forms: ["kennt", "kannte"],
              subjects: ["people"], partners: ["people", "pets"]),
    ]

    static let dativVerbs: [TwoWayVerb] = [
        .init(lemma: "helfen", caseRaw: "dativ", shown: "hilft", forms: ["hilft", "half"],
              subjects: ["people"], partners: ["people", "pets"]),
        .init(lemma: "danken", caseRaw: "dativ", shown: "dankt", forms: ["dankt", "dankte"],
              subjects: ["people"], partners: ["people"]),
        .init(lemma: "antworten", caseRaw: "dativ", shown: "antwortet", forms: ["antwortet", "antwortete"],
              subjects: ["people"], partners: ["people"]),
        .init(lemma: "folgen", caseRaw: "dativ", shown: "folgt", forms: ["folgt", "folgte"],
              subjects: ["people", "pets"], partners: ["people", "pets"]),
        .init(lemma: "gratulieren", caseRaw: "dativ", shown: "gratuliert", forms: ["gratuliert", "gratulierte"],
              subjects: ["people"], partners: ["people"]),
    ]

    /// The exercises a unit's plans can be for; Nominativ has only Rollen, as in the bundle.
    static func kinds(for unit: KasusUnit) -> [KasusConceptKind] {
        unit == .nominativ ? [.roles] : [.roles, .whoDoesWhat, .probe]
    }

    // MARK: Planning

    static func plan(kind: KasusConceptKind, unit: KasusUnit, seed: UInt64,
                     level: CEFRLevel? = nil, bank: KasusTriggerBank? = nil,
                     lexicon: some KasusLexicon = AppKasusLexicon()) -> KasusConceptPlan? {
        let bank = bank ?? .bundled
        let level = level ?? KasusStoryPlanner.defaultLevel(for: unit)
        var builder = Builder(bank: bank, lexicon: lexicon, level: level,
                              rng: KasusSeededRandom(seed: seed &* 0x9E37_79B9 &+ 17 &+ UInt64(KasusUnit.allCases.firstIndex(of: unit) ?? 0) &* 0x51_7CC1))
        // At most one phrase whose article fits several cases (a preposition decides its own):
        // with two, only word order would say who is who, and the check refuses the item. A draw
        // with two is drawn again from the same generator, so a seed still gives one plan.
        var built: Built?
        for _ in 0..<8 {
            let draw: Built?
            switch kind {
            case .whoDoesWhat: draw = builder.wer(unit)
            case .roles:       draw = builder.rollen(unit)
            case .probe:       draw = builder.probe(unit)
            case .sameMeaning: return nil
            }
            if let draw, draw.phrases.filter({ $0.preposition == nil && !$0.isAttribute && !Builder.formProves($0.kasus, $0.genus) }).count <= 1 {
                built = draw
                break
            }
        }
        guard let built else { return nil }
        return KasusConceptPlan(kindRaw: kind.rawValue, unitRaw: unit.rawValue, level: level.rawValue, seed: seed,
                                phrases: built.phrases, verbLemma: built.verb.lemma, verbForms: built.verb.forms,
                                verbShown: built.verb.shown, firstPhrase: built.first, probePhrase: built.probe,
                                template: built.template)
    }

    /// `count` distinct plans for an exercise, seeds `from`, `from + 1` …, skipping seeds that plan
    /// nothing or repeat an earlier plan's template.
    static func plans(kind: KasusConceptKind, unit: KasusUnit, from: UInt64, count: Int,
                      lexicon: some KasusLexicon = AppKasusLexicon()) -> [KasusConceptPlan] {
        var out: [KasusConceptPlan] = []
        var seen = Set<String>()
        var seed = from
        while out.count < count, seed < from + UInt64(count * 20) {
            if let plan = plan(kind: kind, unit: unit, seed: seed, lexicon: lexicon), seen.insert(plan.template).inserted {
                out.append(plan)
            }
            seed += 1
        }
        return out
    }

    struct Verb {
        let lemma: String
        let shown: String
        let forms: [String]
    }

    struct Built {
        let phrases: [KasusConceptPlannedPhrase]
        let verb: Verb
        var first: Int? = nil
        var probe: Int? = nil
        let template: String
    }

    struct Noun: Hashable {
        let lemma: String
        let genus: Gender
    }

    struct Builder {
        let bank: KasusTriggerBank
        let lexicon: any KasusLexicon
        let level: CEFRLevel
        var rng: KasusSeededRandom
        private var used: Set<String> = []

        init(bank: KasusTriggerBank, lexicon: any KasusLexicon, level: CEFRLevel, rng: KasusSeededRandom) {
            self.bank = bank
            self.lexicon = lexicon
            self.level = level
            self.rng = rng
        }

        // MARK: Nouns

        /// Usable nouns of these categories and genders, at or below the level (relaxed to B1 when
        /// fewer than three are left), never one already in the plan.
        mutating func nouns(_ categories: [String], genders: Set<Gender>) -> [Noun] {
            func pool(maxLevel: CEFRLevel) -> [Noun] {
                var seen = Set<String>()
                return categories.flatMap { bank.nouns[$0] ?? [] }.compactMap { lemma -> Noun? in
                    guard seen.insert(lemma).inserted, !used.contains(lemma), !Self.neverPlanned.contains(lemma),
                          !KasusForms.isNDeklination(lemma), KasusForms.dualGenders(of: lemma) == nil,
                          case .verified(let genus) = lexicon.gender(forLemma: lemma), genus != .plural,
                          genders.contains(genus) else { return nil }
                    if let at = KasusStoryPlanner.goetheLevel(lemma), rank(at) > rank(maxLevel) { return nil }
                    return Noun(lemma: lemma, genus: genus)
                }
            }
            let strict = pool(maxLevel: level)
            return strict.count >= 3 ? strict : pool(maxLevel: .b1)
        }

        mutating func pick(_ categories: [String], genders: Set<Gender>) -> Noun? {
            guard let noun = rng.pick(nouns(categories, genders: genders)) else { return nil }
            used.insert(noun.lemma)
            return noun
        }

        /// Wine and beer (a child would end up drinking them), and the baby (it ended up thanked,
        /// congratulated and asked; „das Kind“ covers a child).
        static let neverPlanned: Set<String> = ["Wein", "Bier", "Baby"]
        /// Nouns that are never the doer or a receiver of an errand („Das Baby kocht“, „schickt dem
        /// Baby einen Brief“); they can still be helped, visited, found.
        static let neverDoers: Set<String> = ["Baby"]

        /// A noun to do the verb: the same as `pick`, without the baby.
        mutating func pickDoer(_ categories: [String], genders: Set<Gender>) -> Noun? {
            guard let noun = rng.pick(nouns(categories, genders: genders).filter { !Self.neverDoers.contains($0.lemma) }) else { return nil }
            used.insert(noun.lemma)
            return noun
        }

        /// A noun from a frame's own short list (a curated object such as „die Jacke“).
        mutating func pickLemma(_ lemmas: [String], genders: Set<Gender> = [.der, .die, .das]) -> Noun? {
            let usable = lemmas.compactMap { lemma -> Noun? in
                guard !used.contains(lemma), case .verified(let g) = lexicon.gender(forLemma: lemma), genders.contains(g) else { return nil }
                return Noun(lemma: lemma, genus: g)
            }
            guard let noun = rng.pick(usable) else { return nil }
            used.insert(noun.lemma)
            return noun
        }

        /// Jobs, for „ist ein Lehrer“; everyone else in the people pool is family or a role.
        static let jobs: Set<String> = ["Lehrer", "Lehrerin", "Arzt", "Ärztin", "Kellner", "Kellnerin", "Verkäufer",
                                        "Verkäuferin", "Fahrer", "Chef", "Chefin", "Schüler", "Schülerin"]

        mutating func pickFamily(genders: Set<Gender>) -> Noun? {
            guard let noun = rng.pick(nouns(["people"], genders: genders).filter { !Self.jobs.contains($0.lemma) }) else { return nil }
            used.insert(noun.lemma)
            return noun
        }

        mutating func pickJob(genus: Gender) -> Noun? {
            guard let noun = rng.pick(nouns(["people"], genders: [genus]).filter { Self.jobs.contains($0.lemma) }) else { return nil }
            used.insert(noun.lemma)
            return noun
        }

        private func rank(_ level: CEFRLevel) -> Int { CEFRLevel.allCases.firstIndex(of: level) ?? 0 }

        // MARK: Phrases

        func phrase(_ noun: Noun, _ kasus: GrammarCase, _ reason: KasusReason, ein: Bool = false,
                    preposition: String? = nil) -> KasusConceptPlannedPhrase {
            let article = ein && noun.genus != .plural ? "ein" + kasus.einEnding(noun.genus) : kasus.article(noun.genus)
            var surface = noun.lemma
            if kasus == .genitiv, noun.genus == .der || noun.genus == .das {
                surface = bank.genitive.nouns.first { $0.lemma == noun.lemma }?.genitive
                    ?? Self.esGenitive[noun.lemma] ?? noun.lemma + "s"
            }
            return KasusConceptPlannedPhrase(phrase: "\(article) \(surface)", caseRaw: kasus.rawValue,
                                             genusRaw: noun.genus.columnLabel, lemma: noun.lemma,
                                             reasonRaw: reason.rawValue, preposition: preposition)
        }

        /// Whether a definite form leaves only one case for this gender.
        static func formProves(_ kasus: GrammarCase, _ genus: Gender) -> Bool {
            KasusForms.compatibleCases(determiner: kasus.article(genus), genus: genus).count == 1
        }

        static func sentence(_ parts: [String]) -> String {
            let text = parts.joined(separator: " ")
            return text.prefix(1).uppercased() + text.dropFirst() + "."
        }

        static func verb(_ v: TwoWayVerb) -> Verb { Verb(lemma: v.lemma, shown: v.shown, forms: v.forms) }

        // MARK: Wer

        mutating func wer(_ unit: KasusUnit) -> Built? {
            let verbs: [TwoWayVerb] = switch unit {
            case .akkusativ: KasusConceptPlanner.akkusativVerbs
            case .dativ:     KasusConceptPlanner.dativVerbs
            default:         KasusConceptPlanner.akkusativVerbs + KasusConceptPlanner.dativVerbs
            }
            guard let v = rng.pick(verbs) else { return nil }
            let partnerCase = GrammarCase(rawValue: v.caseRaw) ?? .akkusativ
            let partnerReason: KasusReason = partnerCase == .dativ ? .dativeVerb : .object
            // The clue: the subject as a masculine „der“, or the partner as „den“/„dem“. The other
            // phrase is the ambiguous one (die/das; for a Dativ partner, der + feminine).
            let clueOnSubject = rng.chance(0.5)
            let subjectGenders: Set<Gender> = clueOnSubject ? [.der] : [.die, .das]
            let partnerGenders: Set<Gender> = clueOnSubject
                ? (partnerCase == .dativ ? [.die] : [.die, .das])
                : (partnerCase == .dativ ? [.der, .das] : [.der])
            guard let s = pickDoer(v.subjects, genders: subjectGenders),
                  let o = pick(v.partners, genders: partnerGenders) else { return nil }
            let subject = phrase(s, .nominativ, .subject)
            let partner = phrase(o, partnerCase, partnerReason)
            let objectFirst = rng.chance(0.5)
            var phrases = [subject, partner]
            // The Genitiv unit hangs a Genitiv on one of the two: „Den Hund des Lehrers jagt die Katze.“
            if unit == .genitiv {
                let head = rng.int(below: 2)
                guard let attribute = attribute(to: head, of: head == 0 ? s.lemma : o.lemma) else { return nil }
                phrases.append(attribute)
            }
            let full = { (i: Int) in ([phrases[i].phrase] + phrases.filter { $0.head == i }.map(\.phrase)).joined(separator: " ") }
            let template = objectFirst
                ? Self.sentence([full(1), v.shown, full(0)])
                : Self.sentence([full(0), v.shown, full(1)])
            return Built(phrases: phrases, verb: Self.verb(v), first: objectFirst ? 1 : 0, template: template)
        }

        // MARK: Rollen

        mutating func rollen(_ unit: KasusUnit) -> Built? {
            switch unit {
            case .nominativ:
                if rng.chance(0.5) {
                    // „Die Frau ist eine Lehrerin.“
                    guard let s = pickFamily(genders: [.der, .die]),
                          let p = pickJob(genus: s.genus) else { return nil }
                    let subject = phrase(s, .nominativ, .subject)
                    let predicate = phrase(p, .nominativ, .predicate, ein: true)
                    return Built(phrases: [subject, predicate], verb: Verb(lemma: "sein", shown: "ist", forms: ["ist", "war"]),
                                 template: Self.sentence([subject.phrase, "ist", predicate.phrase]))
                }
                guard let v = rng.pick(bank.subjectVerbs), let s = pickDoer(v.nouns, genders: [.der, .die, .das]) else { return nil }
                let subject = phrase(s, .nominativ, .subject)
                let shown = v.forms?.first ?? v.lemma
                return Built(phrases: [subject], verb: Verb(lemma: v.lemma, shown: shown, forms: v.forms ?? [shown]),
                             template: Self.sentence([subject.phrase, shown]))
            case .akkusativ:
                return objectSentence(extra: rng.chance(0.5) ? "akkusativ" : nil)
            case .dativ:
                return rng.chance(0.6) ? giving(extra: nil) : partnerSentence(extraDativ: true)
            case .genitiv:
                return rng.chance(0.5) ? attributeSentence(feminine: false) : reasonSentence(transitive: rng.chance(0.6))
            case .alleFaelle:
                return rng.chance(0.5) ? givingWithReason() : giving(extra: "akkusativ")
            }
        }

        /// „Die Frau kauft einen Kuchen (für den Opa / wegen des Regens).“ Food and drinks only with
        /// der/die/das („trinkt eine Milch“ isn't German); an Akkusativ extra is always „für“ + a person.
        mutating func objectSentence(extra: String?) -> Built? {
            // „für den Opa“ reads naturally after getting something, not after „sieht“ or „isst“.
            let verbs = bank.objectVerbs.filter { (!$0.nouns.contains("people") || $0.nouns.count > 1)
                && (extra != "akkusativ" || Self.forSomeoneVerbs.contains($0.lemma)) }
            guard let v = rng.pick(verbs), let s = pickDoer(["people"], genders: [.der, .die, .das]),
                  let category = rng.pick(v.nouns.filter { $0 != "people" }),
                  let o = pick([category], genders: [.der, .die, .das]) else { return nil }
            let verb = Self.thirdPerson(v)
            let subject = phrase(s, .nominativ, .subject)
            let countable = !["food", "drinks"].contains(category)
            let object = phrase(o, .akkusativ, .object, ein: countable && rng.chance(0.4))
            var phrases = [subject, object]
            var parts = [subject.phrase, verb.shown, object.phrase]
            if let extra, let p = prepositionPhrase(extra) {
                phrases.append(p)
                parts.append(p.expression)
            }
            return Built(phrases: phrases, verb: verb, template: Self.sentence(parts))
        }

        /// „Der Vater gibt der Tochter einen Ball (wegen des Regens).“ Only verbs that hand a thing
        /// over (erklären/erzählen take a story, not a ball).
        static let handingVerbs: Set<String> = ["geben", "schenken", "bringen", "schicken", "zeigen"]

        static let forSomeoneVerbs: Set<String> = ["kaufen", "holen", "suchen", "finden", "brauchen", "nehmen"]
        /// „gibt dem Kellner einen Schlüssel für den Fahrer“: handing a thing on to someone else.
        /// Not „zeigt … für“ or „schenkt … für“.
        static let passingOnVerbs: Set<String> = ["geben", "bringen", "schicken"]

        mutating func giving(extra: String?) -> Built? {
            let verbs = bank.recipientVerbs.filter {
                Self.handingVerbs.contains($0.lemma) && (extra != "akkusativ" || Self.passingOnVerbs.contains($0.lemma))
            }
            guard let v = rng.pick(verbs),
                  let s = pickDoer(["people"], genders: [.der, .die, .das]),
                  let r = pickDoer(["people"], genders: [.der, .die, .das]),
                  let o = pick(["things"], genders: [.der, .die, .das]) else { return nil }
            let verb = Self.thirdPerson(v)
            let subject = phrase(s, .nominativ, .subject)
            let receiver = phrase(r, .dativ, .recipient)
            let object = phrase(o, .akkusativ, .object, ein: true)
            var phrases = [subject, receiver, object]
            var parts = [subject.phrase, verb.shown, receiver.phrase, object.phrase]
            if let extra, let p = prepositionPhrase(extra) {
                phrases.append(p)
                parts.append(p.expression)
            }
            return Built(phrases: phrases, verb: verb, template: Self.sentence(parts))
        }

        /// „Das Kind hilft dem Opa (mit dem Koffer).“
        mutating func partnerSentence(extraDativ: Bool) -> Built? {
            guard let v = rng.pick(KasusConceptPlanner.dativVerbs),
                  let s = pickDoer(v.subjects, genders: [.der, .die, .das]),
                  let o = pick(v.partners, genders: [.der, .die, .das]) else { return nil }
            let subject = phrase(s, .nominativ, .subject)
            let partner = phrase(o, .dativ, .dativeVerb)
            var phrases = [subject, partner]
            var parts = [subject.phrase, v.shown, partner.phrase]
            if extraDativ, v.lemma == "helfen", let p = prepositionPhrase("dativ") {
                phrases.append(p)
                parts.append(p.expression)
            }
            return Built(phrases: phrases, verb: Self.verb(v), template: Self.sentence(parts))
        }

        /// A fixed-case preposition phrase of that case: „für den Hund“, „mit dem Ball“,
        /// „wegen des Regens“. Never one that would contract (zum, im, beim …).
        mutating func prepositionPhrase(_ caseRaw: String) -> KasusConceptPlannedPhrase? {
            if caseRaw == "genitiv" {
                guard let word = rng.pick(bank.genitive.prepositions) else { return nil }
                let lemmas = bank.genitive.nouns.map(\.lemma)
                let candidates = lemmas.compactMap { lemma -> Noun? in
                    guard !used.contains(lemma), case .verified(let g) = lexicon.gender(forLemma: lemma), g != .plural else { return nil }
                    return Noun(lemma: lemma, genus: g)
                }
                guard let n = rng.pick(candidates) else { return nil }
                used.insert(n.lemma)
                return phrase(n, .genitiv, .preposition, preposition: word)
            }
            // „für den Opa“ (who it's for), „mit dem Handy“ (helping with): the pairings that read
            // naturally after any verb here. „ohne die Jacke“ after „sieht den Hund“ doesn't.
            let word = caseRaw == "akkusativ" ? "für" : "mit"
            let categories = caseRaw == "akkusativ" ? ["people"] : ["things"]
            guard let p = bank.prepositions.first(where: { $0.word == word && $0.caseRaw == caseRaw }),
                  let n = pick(categories, genders: [.der, .die, .das]) else { return nil }
            let kasus = GrammarCase(rawValue: caseRaw) ?? .akkusativ
            let built = phrase(n, kasus, .preposition, preposition: p.word)
            guard !KasusStoryPlanner.contracts(p.word, kasus.article(n.genus)) else { return nil }
            return built
        }

        // MARK: Probe

        mutating func probe(_ unit: KasusUnit) -> Built? {
            let which: String = switch unit {
            case .akkusativ: "akkusativ"
            case .dativ:     "dativ"
            case .genitiv:   ["genitiv", "dativ", "akkusativ"][rng.int(below: 3)]
            default:         ["genitiv", "dativ", "akkusativ"][rng.int(below: 3)]
            }
            switch which {
            case "akkusativ":
                // „Der Opa sieht die Katze.“ A masculine subject, so only the partner can be the object.
                guard let v = rng.pick(KasusConceptPlanner.akkusativVerbs),
                      let s = pickDoer(v.subjects, genders: [.der]),
                      let o = pick(v.partners, genders: [.die, .das]) else { return nil }
                let subject = phrase(s, .nominativ, .subject)
                let object = phrase(o, .akkusativ, .object)
                return Built(phrases: [subject, object], verb: Self.verb(v), probe: 1,
                             template: Self.sentence([subject.phrase, v.shown, object.phrase]))
            case "dativ":
                // „Das Kind hilft der Oma.“ der + feminine can't be a subject.
                guard let v = rng.pick(KasusConceptPlanner.dativVerbs),
                      let s = pickDoer(v.subjects, genders: [.der]),
                      let o = pick(v.partners, genders: [.die]) else { return nil }
                let subject = phrase(s, .nominativ, .subject)
                let partner = phrase(o, .dativ, .dativeVerb)
                return Built(phrases: [subject, partner], verb: Self.verb(v), probe: 1,
                             template: Self.sentence([subject.phrase, v.shown, partner.phrase]))
            default:
                if rng.chance(0.5) {
                    // „Der Hund der Lehrerin schläft.“ der + feminine behind a noun: Dativ or
                    // Genitiv by the article alone; „des Mannes“ shows it's the Genitiv.
                    guard var built = attributeSentence(feminine: true) else { return nil }
                    built.probe = built.phrases.firstIndex(where: \.isAttribute)
                    return built
                }
                // „Der Vater bleibt wegen der Krankheit zu Hause.“ The preposition decides; the
                // article alone could be Dativ or Genitiv. A reason that fits the verb.
                guard let s = pickDoer(["people"], genders: [.der, .das]),
                      let (frame, word, reasonNoun) = pickReason(Self.intransitiveReasons, feminine: true) else { return nil }
                let subject = phrase(s, .nominativ, .subject)
                let reason = phrase(reasonNoun, .genitiv, .preposition, preposition: word)
                return Built(phrases: [subject, reason], verb: frame.verb, probe: 1,
                             template: Self.sentence([subject.phrase, frame.verb.shown, reason.expression]))
            }
        }

        // MARK: Genitiv attributes („der Hund des Lehrers“)

        /// One-syllable masculine and neuter nouns take -es: „des Mannes“, not „des Manns“.
        static let esGenitive: [String: String] = ["Mann": "Mannes", "Kind": "Kindes", "Freund": "Freundes",
                                                   "Arzt": "Arztes", "Gast": "Gastes", "Hund": "Hundes",
                                                   "Sohn": "Sohnes", "Pferd": "Pferdes"]

        static let adults = ["Lehrer", "Lehrerin", "Nachbarin", "Chef", "Chefin", "Arzt", "Ärztin", "Kellner",
                             "Kellnerin", "Verkäufer", "Verkäuferin", "Fahrer", "Kollegin", "Onkel", "Tante", "Mann", "Frau"]
        static let children = ["Kind", "Mädchen", "Sohn", "Tochter", "Schüler", "Schülerin"]

        /// Whose a head can plausibly be: a pet anyone's, a child an adult's, a teacher a
        /// child's, a doctor a patient's („die Ärztin des Opas“). A head not listed takes no
        /// attribute („das Mädchen der Kollegin“, „die Mutter des Bruders“ read wrong).
        static let possessors: [String: [String]] = {
            var table: [String: [String]] = [:]
            let anyone = adults + children + ["Mutter", "Vater", "Oma", "Opa", "Freund", "Freundin"]
            for pet in ["Hund", "Katze", "Vogel", "Pferd"] { table[pet] = anyone }
            for child in ["Sohn", "Tochter", "Kind"] { table[child] = adults + ["Freund", "Freundin"] }
            for sibling in ["Bruder", "Schwester"] { table[sibling] = adults + ["Kind", "Mädchen", "Schüler", "Schülerin", "Freund", "Freundin"] }
            for friend in ["Freund", "Freundin"] {
                table[friend] = ["Tochter", "Sohn", "Schwester", "Bruder", "Lehrerin", "Nachbarin", "Kollegin", "Chef", "Mädchen", "Schüler", "Schülerin"]
            }
            table["Mann"] = ["Nachbarin", "Lehrerin", "Chefin", "Ärztin", "Tante", "Kollegin"]
            table["Frau"] = ["Lehrer", "Chef", "Arzt", "Onkel", "Kellner", "Fahrer"]
            for teacher in ["Lehrer", "Lehrerin"] { table[teacher] = children }
            for doctor in ["Arzt", "Ärztin"] { table[doctor] = ["Opa", "Oma", "Kind", "Mutter", "Vater", "Mädchen"] }
            for boss in ["Chef", "Chefin"] {
                table[boss] = ["Mutter", "Vater", "Kellner", "Kellnerin", "Verkäufer", "Verkäuferin", "Fahrer", "Kollegin", "Frau", "Mann"]
            }
            for parent in ["Mutter", "Vater"] { table[parent] = ["Kind", "Mädchen", "Schüler", "Schülerin", "Freund", "Freundin"] }
            for grand in ["Opa", "Oma"] { table[grand] = ["Kind", "Mädchen", "Sohn", "Tochter", "Schüler", "Schülerin"] }
            for relative in ["Onkel", "Tante"] { table[relative] = ["Kind", "Mädchen", "Sohn", "Tochter", "Freund", "Freundin"] }
            table["Kollegin"] = ["Mutter", "Vater", "Ärztin", "Lehrer", "Chefin"]
            for pupil in ["Schüler", "Schülerin"] { table[pupil] = ["Lehrer", "Lehrerin"] }
            table["Gast"] = ["Chef", "Chefin", "Nachbarin", "Kellner"]
            table["Fahrer"] = ["Chef", "Chefin"]
            return table
        }()

        /// Whose: someone the head belongs to. `feminine` for a Probe (der + feminine could be
        /// Dativ). A thing („den Schlüssel“) can be anyone's; a person or pet only someone in
        /// `possessors`.
        mutating func attribute(to head: Int, of headLemma: String, feminine: Bool = false) -> KasusConceptPlannedPhrase? {
            let genders: Set<Gender> = feminine ? [.die] : [.der, .die, .das]
            let n: Noun?
            if let allowed = Self.possessors[headLemma] {
                n = pickLemma(allowed, genders: genders)
            } else if bank.nouns["people"]?.contains(headLemma) == true {
                n = nil
            } else {
                n = pickLemma(Self.adults + ["Mutter", "Vater", "Oma", "Opa", "Freund", "Freundin"], genders: genders)
            }
            guard let n else { return nil }
            var attribute = phrase(n, .genitiv, .attribute)
            attribute.head = head
            return attribute
        }

        /// Things that belong to someone, with a verb that fits: „sucht den Schlüssel der Mutter“.
        static let ownedThings: [(verb: Verb, objects: [String])] = [
            (v("suchen", "sucht", "suchte"), ["Schlüssel", "Handy", "Brille", "Uhr", "Tasche"]),
            (v("finden", "findet", "fand"), ["Schlüssel", "Handy", "Brille", "Tasche", "Ball"]),
            (v("nehmen", "nimmt", "nahm"), ["Tasche", "Jacke", "Koffer", "Rucksack"]),
            (v("tragen", "trägt", "trug"), ["Koffer", "Rucksack", "Tasche"]),
            (v("lesen", "liest", "las"), ["Brief", "Buch", "Zeitung"]),
            (v("holen", "holt", "holte"), ["Koffer", "Jacke", "Tasche"]),
            (v("sehen", "sieht", "sah"), ["Hund", "Katze", "Pferd"]),
        ]
        /// Heads that do something themselves: a pet or a relative of someone („Der Sohn des Lehrers spielt“).
        static let ownedDoers = ["Hund", "Katze", "Vogel", "Pferd", "Sohn", "Tochter", "Bruder", "Schwester", "Freund", "Freundin"]
        static let ownedDoerVerbs = [v("schlafen", "schläft", "schlief"), v("spielen", "spielt", "spielte"),
                                     v("warten", "wartet", "wartete")]

        /// Rollen or Probe with a Genitiv attribute: on the object („Der Vater sucht den Schlüssel
        /// der Mutter.“) or on the subject („Der Hund des Lehrers schläft.“). `feminine`: the
        /// attribute is der + feminine, and the other phrases are proven by form.
        mutating func attributeSentence(feminine: Bool) -> Built? {
            if rng.chance(0.5) {
                guard let frame = rng.pick(Self.ownedThings),
                      let s = pickDoer(["people"], genders: feminine ? [.der] : [.der, .die, .das]),
                      let o = pickLemma(frame.objects) else { return nil }
                let subject = phrase(s, .nominativ, .subject)
                let object = phrase(o, .akkusativ, .object)
                guard let attribute = attribute(to: 1, of: o.lemma, feminine: feminine) else { return nil }
                return Built(phrases: [subject, object, attribute], verb: frame.verb,
                             template: Self.sentence([subject.phrase, frame.verb.shown, object.phrase, attribute.phrase]))
            }
            guard let verb = rng.pick(Self.ownedDoerVerbs),
                  let s = pickLemma(Self.ownedDoers, genders: feminine ? [.der, .das] : [.der, .die, .das]) else { return nil }
            let subject = phrase(s, .nominativ, .subject)
            guard let attribute = attribute(to: 0, of: s.lemma, feminine: feminine) else { return nil }
            return Built(phrases: [subject, attribute], verb: verb,
                         template: Self.sentence([subject.phrase, attribute.phrase, verb.shown]))
        }

        // MARK: Reasons (wegen / trotz)

        /// A verb with the reasons that make sense for it, so a Genitiv phrase is never random
        /// („sieht eine Gabel trotz des Sturms“ was). `objects`: what the verb takes, if anything.
        struct ReasonFrame {
            let verb: Verb
            var objects: [String] = []
            var wegen: [String] = []
            var trotz: [String] = []
        }

        static func v(_ lemma: String, _ present: String, _ past: String) -> Verb {
            Verb(lemma: lemma, shown: present, forms: [present, past])
        }

        /// „Der Vater kommt wegen des Staus spät.“ „Das Kind spielt trotz des Regens draußen.“
        static let intransitiveReasons: [ReasonFrame] = [
            .init(verb: v("warten", "wartet", "wartete"), wegen: ["Stau", "Verspätung", "Unfall", "Streik", "Baustelle", "Regen"]),
            .init(verb: v("kommen", "kommt", "kam"), wegen: ["Stau", "Verspätung", "Streik", "Unfall", "Baustelle", "Termin"],
                  trotz: ["Regen", "Schnee", "Sturm", "Erkältung", "Kälte", "Krankheit"]),
            .init(verb: v("bleiben", "bleibt", "blieb"), wegen: ["Regen", "Sturm", "Schnee", "Kälte", "Hitze", "Krankheit", "Erkältung", "Fieber", "Streik", "Gewitter"]),
            .init(verb: v("schlafen", "schläft", "schlief"), wegen: ["Lärm", "Hitze", "Gewitter", "Fieber", "Baustelle"],
                  trotz: ["Lärm", "Gewitter", "Hitze"]),
            .init(verb: v("arbeiten", "arbeitet", "arbeitete"), wegen: ["Termin", "Verspätung", "Prüfung"],
                  trotz: ["Erkältung", "Fieber", "Krankheit", "Hitze"]),
            .init(verb: v("spielen", "spielt", "spielte"), wegen: ["Regen", "Hitze", "Sturm", "Gewitter"],
                  trotz: ["Regen", "Kälte", "Wind", "Schnee"]),
            .init(verb: v("fahren", "fährt", "fuhr"), wegen: ["Termin", "Verspätung"], trotz: ["Schnee", "Regen", "Nebel", "Sturm", "Stau"]),
            .init(verb: v("lernen", "lernt", "lernte"), wegen: ["Prüfung"], trotz: ["Lärm", "Hitze", "Erkältung"]),
            .init(verb: v("singen", "singt", "sang"), trotz: ["Erkältung", "Regen"]),
            .init(verb: v("weinen", "weint", "weinte"), wegen: ["Gewitter", "Lärm", "Fieber", "Prüfung"]),
        ]

        /// „Die Oma nimmt wegen der Kälte eine Jacke.“ „Der Schüler liest trotz des Lärms ein Buch.“
        static let objectReasons: [ReasonFrame] = [
            .init(verb: v("nehmen", "nimmt", "nahm"), objects: ["Jacke", "Mantel", "Mütze", "Decke"], wegen: ["Kälte", "Wind", "Regen", "Schnee"]),
            .init(verb: v("tragen", "trägt", "trug"), objects: ["Mantel", "Pullover", "Jacke", "Mütze"], wegen: ["Kälte", "Wind", "Schnee"],
                  trotz: ["Hitze"]),
            .init(verb: v("brauchen", "braucht", "brauchte"), objects: ["Jacke", "Mantel", "Decke", "Mütze"], wegen: ["Kälte", "Schnee", "Wind"]),
            .init(verb: v("kaufen", "kauft", "kaufte"), objects: ["Mütze", "Decke", "Jacke"], wegen: ["Kälte", "Schnee"]),
            .init(verb: v("holen", "holt", "holte"), objects: ["Decke"], wegen: ["Kälte"]),
            .init(verb: v("holen", "holt", "holte"), objects: ["Kerze", "Lampe"], wegen: ["Gewitter", "Sturm"]),
            .init(verb: v("trinken", "trinkt", "trank"), objects: ["Kaffee"], wegen: ["Prüfung", "Arbeit", "Termin"]),
            .init(verb: v("essen", "isst", "aß"), objects: ["Suppe"], wegen: ["Erkältung", "Kälte", "Krankheit", "Fieber"]),
            .init(verb: v("lesen", "liest", "las"), objects: ["Buch", "Zeitung", "Heft"], trotz: ["Lärm", "Hitze"]),
            .init(verb: v("lesen", "liest", "las"), objects: ["Buch", "Heft"], wegen: ["Prüfung"]),
            .init(verb: v("suchen", "sucht", "suchte"), objects: ["Schlüssel", "Ticket", "Handy"], wegen: ["Termin"]),
        ]

        /// „Der Vater bringt der Oma wegen der Erkältung eine Suppe.“ The verb's er-form comes from
        /// the triggers file.
        static let givingReasons: [(verb: String, objects: [String], wegen: [String], trotz: [String])] = [
            ("bringen", ["Decke", "Jacke", "Mütze", "Mantel"], ["Kälte", "Wind", "Schnee", "Regen"], []),
            ("geben", ["Decke", "Jacke", "Mütze", "Mantel"], ["Kälte", "Wind", "Schnee", "Regen"], []),
            ("bringen", ["Suppe"], ["Erkältung", "Krankheit", "Fieber"], []),
            ("geben", ["Flasche"], ["Hitze"], []),
            ("schenken", ["Buch", "Heft"], ["Prüfung"], []),
            ("zeigen", ["Karte"], ["Stau", "Baustelle", "Unfall"], []),
            ("schicken", ["Brief", "Karte", "Paket"], [], ["Streik"]),
        ]

        /// A frame, a preposition and a reason noun from it, never one already in the plan;
        /// `feminine` for a Probe, whose der + feminine could be Dativ or Genitiv.
        mutating func pickReason(_ frames: [ReasonFrame], feminine: Bool = false) -> (ReasonFrame, String, Noun)? {
            var options: [(ReasonFrame, String, Noun)] = []
            for frame in frames {
                for (word, lemmas) in [("wegen", frame.wegen), ("trotz", frame.trotz)] {
                    for lemma in lemmas where !used.contains(lemma) {
                        guard case .verified(let g) = lexicon.gender(forLemma: lemma), g != .plural,
                              !feminine || g == .die else { continue }
                        options.append((frame, word, Noun(lemma: lemma, genus: g)))
                    }
                }
            }
            guard let choice = rng.pick(options) else { return nil }
            used.insert(choice.2.lemma)
            return choice
        }

        /// Rollen with a Genitiv: „Der Opa bleibt wegen des Regens.“ or „Die Oma nimmt wegen der
        /// Kälte eine Jacke.“
        mutating func reasonSentence(transitive: Bool) -> Built? {
            guard let s = pickDoer(["people"], genders: [.der, .die, .das]),
                  let (frame, word, reasonNoun) = pickReason(transitive ? Self.objectReasons : Self.intransitiveReasons) else { return nil }
            let subject = phrase(s, .nominativ, .subject)
            let reason = phrase(reasonNoun, .genitiv, .preposition, preposition: word)
            guard transitive else {
                return Built(phrases: [subject, reason], verb: frame.verb,
                             template: Self.sentence([subject.phrase, frame.verb.shown, reason.expression]))
            }
            guard let o = pickLemma(frame.objects) else { return nil }
            let object = phrase(o, .akkusativ, .object, ein: rng.chance(0.7))
            return Built(phrases: [subject, object, reason], verb: frame.verb,
                         template: Self.sentence([subject.phrase, frame.verb.shown, reason.expression, object.phrase]))
        }

        /// Alle Fälle with a Genitiv: „Der Vater bringt der Oma wegen der Erkältung eine Suppe.“
        mutating func givingWithReason() -> Built? {
            guard let entry = rng.pick(Self.givingReasons),
                  let tv = bank.recipientVerbs.first(where: { $0.lemma == entry.verb }) else { return nil }
            let frame = ReasonFrame(verb: Self.thirdPerson(tv), objects: entry.objects, wegen: entry.wegen, trotz: entry.trotz)
            guard let s = pickDoer(["people"], genders: [.der, .die, .das]),
                  let r = pickDoer(["people"], genders: [.der, .die, .das]),
                  let (_, word, reasonNoun) = pickReason([frame]),
                  let o = pickLemma(frame.objects) else { return nil }
            let subject = phrase(s, .nominativ, .subject)
            let receiver = phrase(r, .dativ, .recipient)
            let object = phrase(o, .akkusativ, .object, ein: true)
            let reason = phrase(reasonNoun, .genitiv, .preposition, preposition: word)
            return Built(phrases: [subject, receiver, object, reason], verb: frame.verb,
                         template: Self.sentence([subject.phrase, frame.verb.shown, receiver.phrase, reason.expression, object.phrase]))
        }

        /// The er/sie/es forms of a triggers-file verb, present and simple past („isst“, „aß“).
        /// Its forms list ich, du, er … first; when du and er share a form („isst“) it is listed once.
        static func thirdPerson(_ v: KasusTriggerBank.Verb) -> Verb {
            let forms = v.forms ?? []
            guard forms.count >= 3 else { return Verb(lemma: v.lemma, shown: forms.first ?? v.lemma, forms: forms.isEmpty ? [v.lemma] : forms) }
            let present = forms[2] == v.lemma ? forms[1] : forms[2]
            let stem = v.lemma.hasSuffix("en") ? String(v.lemma.dropLast(2)) : String(v.lemma.dropLast())
            let lemmaAt = forms.firstIndex(of: v.lemma) ?? 2
            let past = forms[(lemmaAt + 1)...].first { f in
                f != stem + "t" && f != stem + "et" && !f.hasSuffix("st") && !f.hasSuffix("en") && !f.hasPrefix("ge") && f != present
            }
            return Verb(lemma: v.lemma, shown: present, forms: [present] + (past.map { [$0] } ?? []))
        }
    }
}
