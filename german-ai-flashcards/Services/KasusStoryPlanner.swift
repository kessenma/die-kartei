//
//  KasusStoryPlanner.swift
//  german-ai-flashcards
//
//  Plans the phrases a tutor-written Kasus story must contain (Phase 3). Pure and seeded: the same
//  unit, level, seed and lexicon always give the same plan, so a Lab run can be repeated and a
//  stored plan explains its story.
//
//  Every planned phrase is one the validator can prove, and it uses a definite or an ein article,
//  the only two Endungen blanks:
//    Nominativ   der/ein + masculine as the subject of a planned verb, in the third person
//                („der Hund schläft“; the prompt shows the verb conjugated)
//    Akkusativ   den/einen + masculine with a transitive verb; a fixed Akkusativ preposition;
//                auf/unter/neben + a placement verb (Wohin?)
//    Dativ       dem/einem with a Dativ verb or a receiver verb; a fixed Dativ preposition (never
//                an article it would contract with: zum, zur, vom, beim, im, am); auf/unter/neben
//                + a position verb (Wo?)
//    Genitiv     wegen/trotz + a curated Genitiv noun
//  Nouns are Goethe nouns at or below the level (plus the learner's own, when given) whose gender
//  the lexicon verifies; n-nouns, dual-gender and plural-only nouns are skipped. Verbs above the
//  level are skipped too. Kinship and mass nouns take only the definite article („der Bruder“,
//  „wegen des Regens“), and each two-way pair names the furniture it goes with (sitzen on seats,
//  stehen on surfaces). At least three phrases of the unit's case (two of each for Alle Fälle once
//  there is room); the Nominativ unit plans mostly subjects. With the memory saver on, the level
//  is capped at A2 and the plan at six.
//
//  The verb frames and noun pools live in `Resources/kasus_triggers.json`.
//

import Foundation

// MARK: - Seeded randomness

/// SplitMix64: small, fast, and the same sequence on every device and OS, which the standard
/// library's generator doesn't promise.
nonisolated struct KasusSeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< n; 0 when n ≤ 1.
    mutating func int(below n: Int) -> Int {
        n <= 1 ? 0 : Int(next() % UInt64(n))
    }

    mutating func chance(_ p: Double) -> Bool {
        Double(next() >> 11) / Double(UInt64(1) << 53) < p
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        items.isEmpty ? nil : items[int(below: items.count)]
    }

    /// Fisher–Yates with this generator, so the order is part of the seed's promise.
    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(i, int(below: i + 1))
        }
        return result
    }
}

// MARK: - The trigger file

/// `Resources/kasus_triggers.json`, decoded.
nonisolated struct KasusTriggerBank: Decodable {
    let version: Int
    let genre: String
    let topics: [String]
    /// Nouns that never take ein: kinship („der Bruder“; „ein Bruder“ reads odd and invites „mein
    /// Bruder“) and mass nouns („wegen eines Regens“).
    let definiteOnly: [String]?
    /// Category → Goethe nouns („people“, „things“, „furniture“ …).
    let nouns: [String: [String]]
    let subjectVerbs: [Verb]
    let objectVerbs: [Verb]
    /// Forms come from `KasusForms.dativeVerbs`, the list the validator and explanations use.
    let dativeVerbs: [Verb]
    let recipientVerbs: [Verb]
    let prepositions: [Preposition]
    let wechsel: Wechsel
    let genitive: Genitive

    nonisolated struct Verb: Decodable, Hashable {
        let lemma: String
        /// Noun categories that fit the verb's slot.
        let nouns: [String]
        /// A subject verb: only the third-person singular forms, the one the prompt shows first.
        let forms: [String]?
        /// A subject verb's Partizip II and its helper („hat“ or „ist“).
        let participle: String?
        let aux: String?
    }

    nonisolated struct Preposition: Decodable, Hashable {
        let word: String
        let caseRaw: String
        let nouns: [String]
        /// Only einem/einer after it: zu + dem/der would contract (zum, zur).
        let einOnly: Bool?
        /// Only the definite article: „um den Tisch“, „nach dem Essen“ („nach einem Unterricht“
        /// isn't how anyone says it).
        let definiteOnly: Bool?

        enum CodingKeys: String, CodingKey { case word, caseRaw = "case", nouns, einOnly, definiteOnly }
    }

    nonisolated struct Wechsel: Decodable, Hashable {
        let pairs: [Pair]
    }

    /// A position verb and its placement partner (liegen/legen, stehen/stellen, sitzen/setzen),
    /// with the noun categories each two-way preposition takes with them: a cup stands on a
    /// shelf, a person sits on a chair.
    nonisolated struct Pair: Decodable, Hashable {
        let position: String
        let placement: String
        /// What the prompt names for the placement verb when it isn't the bare infinitive
        /// („sich setzen“).
        let placementVerb: String?
        /// Two-way preposition → noun categories.
        let prepositions: [String: [String]]
    }

    nonisolated struct Genitive: Decodable, Hashable {
        let prepositions: [String]
        let nouns: [GenitiveNoun]
    }

    /// A noun that fits „wegen …“ / „trotz …“, with its Genitiv singular for m/n („Regens“).
    nonisolated struct GenitiveNoun: Decodable, Hashable {
        let lemma: String
        let genitive: String?
    }

    private static var cache: KasusTriggerBank?

    /// The bundled file, decoded once. A DEBUG build asserts when it's missing or malformed.
    @MainActor
    static var bundled: KasusTriggerBank {
        if let cache { return cache }
        let bank: KasusTriggerBank
        if let url = Bundle.main.url(forResource: "kasus_triggers", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(KasusTriggerBank.self, from: data) {
            bank = decoded
        } else {
            assertionFailure("kasus_triggers.json is missing or doesn't decode")
            bank = KasusTriggerBank(version: 0, genre: "Alltag", topics: ["Ein Tag zu Hause"], definiteOnly: nil,
                                    nouns: [:], subjectVerbs: [], objectVerbs: [], dativeVerbs: [], recipientVerbs: [],
                                    prepositions: [], wechsel: .init(pairs: []),
                                    genitive: .init(prepositions: [], nouns: []))
        }
        cache = bank
        return bank
    }
}

// MARK: - Nouns

/// A noun the planner may use: a verified singular gender, at or below the story's level.
nonisolated struct KasusPlannerNoun: Hashable {
    let lemma: String
    let genus: Gender
}

// MARK: - The planner

@MainActor
enum KasusStoryPlanner {

    /// The word lists stop at B1, so a story never plans above it.
    static let maxLevel: CEFRLevel = .b1
    /// With the memory saver on: shorter stories (fewer tokens, a smaller KV cache).
    static let governedMaxLevel: CEFRLevel = .a2
    static let governedMaxPhrases = 6
    /// A phrase uses the definite article this often; the ein article otherwise.
    static let definiteShare = 0.65

    /// Preposition + article pairs German writes as one word (zum, zur, vom, beim, im, am, ins,
    /// ans), so a planned phrase never has them: the model would write the contraction instead.
    /// „von der Oma“, „bei der Oma“ stay apart, so they are fine.
    static func contracts(_ preposition: String, _ determiner: String) -> Bool {
        switch determiner.lowercased() {
        case "dem": ["zu", "von", "bei", "in", "an"].contains(preposition)
        case "der": preposition == "zu"
        case "das": ["in", "an"].contains(preposition)
        default:    false
        }
    }

    /// The modals and werden, third person singular: with one of them in the sentence, a
    /// subject's verb may stand in the infinitive („Der Hund will schlafen“).
    static let subjectModals = ["kann", "konnte", "will", "wollte", "muss", "musste", "soll", "sollte",
                                "darf", "durfte", "möchte", "mag", "wird", "würde"]

    /// Every form that counts as a subject verb in the sentence: its third-person singular
    /// forms, its participle with the helper („hat gelacht“), modal or werden + infinitive
    /// („kann lachen“), „zu lachen“. The infinitive alone never does: „Der Bruder lachen laut.“
    static func subjectForms(_ verb: KasusTriggerBank.Verb) -> [String] {
        var forms = (verb.forms ?? []).map { $0.lowercased() }
        if let participle = verb.participle?.lowercased() {
            let helpers = verb.aux == "ist" ? ["ist", "war"] : ["hat", "hatte"]
            forms += helpers.map { "\($0) \(participle)" }
        }
        forms += subjectModals.map { "\($0) \(verb.lemma)" }
        forms.append("zu \(verb.lemma)")
        return forms
    }

    /// The unit's own level label, as a starting point.
    static func defaultLevel(for unit: KasusUnit) -> CEFRLevel {
        switch unit {
        case .nominativ, .akkusativ: .a1
        case .dativ:                 .a2
        case .genitiv, .alleFaelle:  .b1
        }
    }

    /// The level a plan is written at: never above B1, never above A2 with the memory saver on.
    static func effectiveLevel(_ level: CEFRLevel, governed: Bool) -> CEFRLevel {
        let cap = governed ? governedMaxLevel : maxLevel
        return rank(level) > rank(cap) ? cap : level
    }

    /// How many phrases a plan has: A1 5–6, A2 6–7, B1 7–8; Alle Fälle always 8, so it can hold two
    /// of each case. At most 6 with the memory saver on.
    static func phraseCountRange(unit: KasusUnit, level: CEFRLevel, governed: Bool) -> ClosedRange<Int> {
        var range: ClosedRange<Int> = switch level {
        case .a1:             5...6
        case .a2:             6...7
        case .b1, .b2, .c1:   7...8
        }
        if unit == .alleFaelle { range = 8...8 }
        if governed { range = min(range.lowerBound, governedMaxPhrases)...min(range.upperBound, governedMaxPhrases) }
        return range
    }

    /// The case of each phrase to plan, in order. At least three of the unit's case; Nominativ is
    /// mostly subjects with one object to tell them apart; Genitiv and Alle Fälle fill the rest
    /// round robin through the other cases.
    static func caseQuota(unit: KasusUnit, count: Int) -> [GrammarCase] {
        switch unit {
        case .nominativ:
            return Array(repeating: .nominativ, count: max(3, count - 1)) + [.akkusativ]
        case .akkusativ:
            return Array(repeating: .akkusativ, count: max(3, count - 1)) + [.nominativ]
        case .dativ:
            return Array(repeating: .dativ, count: max(3, count - 2)) + [.akkusativ, .nominativ]
        case .genitiv:
            let gen = count >= 8 ? 4 : 3
            let rest: [GrammarCase] = [.dativ, .akkusativ, .nominativ]
            return Array(repeating: .genitiv, count: gen) + (0..<max(0, count - gen)).map { rest[$0 % rest.count] }
        case .alleFaelle:
            let order: [GrammarCase] = [.genitiv, .dativ, .akkusativ, .nominativ]
            return (0..<count).map { order[$0 % order.count] }
        }
    }

    /// The Goethe level a noun is introduced at, or nil when no list has it.
    static func goetheLevel(_ lemma: String) -> CEFRLevel? {
        GoetheVocabService.index[lemma].map { CEFRLevel(rawValue: $0.lowestLevel.rawValue) ?? .b1 }
    }

    /// A plan for `unit` at `level`. Contract B plans no phrases, only the topic.
    static func plan(unit: KasusUnit, level: CEFRLevel, seed: UInt64, governed: Bool,
                     contract: KasusContract = .planned, learnerNouns: [String] = [],
                     lexicon: (any KasusLexicon)? = nil,
                     bank: KasusTriggerBank? = nil,
                     levelOf: ((String) -> CEFRLevel?)? = nil) -> KasusStoryPlan {
        let lexicon = lexicon ?? AppKasusLexicon()
        let bank = bank ?? .bundled
        let levelOf = levelOf ?? { goetheLevel($0) }
        var rng = KasusSeededRandom(seed: seed)
        let level = effectiveLevel(level, governed: governed)
        let topic = rng.pick(bank.topics) ?? "Ein Tag zu Hause"
        let genre = StoryGenre(rawValue: bank.genre)?.rawValue ?? StoryGenre.alltag.rawValue
        guard contract == .planned else {
            return KasusStoryPlan(unitRaw: unit.rawValue, level: level.rawValue, seed: seed, governed: governed,
                                  contract: contract, topic: topic, genreRaw: genre, phrases: [])
        }

        let atLevel = { (word: String) in levelOf(word).map { rank($0) <= rank(level) } == true }
        let genitiveAtLevel = Set(bank.genitive.nouns.map(\.lemma).filter(atLevel))
        var builder = Builder(bank: bank, pool: nounPool(bank: bank, level: level, learnerNouns: learnerNouns,
                                                          lexicon: lexicon, levelOf: levelOf),
                              genitiveAtLevel: genitiveAtLevel, verbAtLevel: atLevel, lexicon: lexicon, rng: rng)
        let range = phraseCountRange(unit: unit, level: level, governed: governed)
        let count = range.lowerBound + builder.rng.int(below: range.count)
        let quota = builder.rng.shuffled(caseQuota(unit: unit, count: count))
        var phrases: [KasusPlannedPhrase] = []
        for kasus in quota {
            if let phrase = builder.phrase(for: kasus, id: phrases.count) { phrases.append(phrase) }
        }
        return KasusStoryPlan(unitRaw: unit.rawValue, level: level.rawValue, seed: seed, governed: governed,
                              contract: contract, topic: topic, genreRaw: genre, phrases: phrases)
    }

    // MARK: Noun pool

    /// Category → usable nouns, in the file's order. The learner's own nouns join „things“.
    static func nounPool(bank: KasusTriggerBank, level: CEFRLevel, learnerNouns: [String],
                         lexicon: any KasusLexicon, levelOf: (String) -> CEFRLevel?) -> [String: [KasusPlannerNoun]] {
        var cache: [String: KasusPlannerNoun?] = [:]
        func usable(_ lemma: String, checkLevel: Bool) -> KasusPlannerNoun? {
            if let cached = cache[lemma] { return cached }
            var result: KasusPlannerNoun?
            let levelOK = !checkLevel || levelOf(lemma).map { rank($0) <= rank(level) } == true
            if levelOK, !KasusForms.isNDeklination(lemma), KasusForms.dualGenders(of: lemma) == nil,
               !KasusForms.isPluraleTantum(lemma), !KasusForms.isAdjectivalNoun(lemma),
               case .verified(let genus) = lexicon.gender(forLemma: lemma), genus != .plural {
                result = KasusPlannerNoun(lemma: lemma, genus: genus)
            }
            cache[lemma] = result
            return result
        }
        var pool: [String: [KasusPlannerNoun]] = [:]
        for (category, lemmas) in bank.nouns {
            pool[category] = lemmas.compactMap { usable($0, checkLevel: true) }
        }
        let learner = learnerNouns
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.first?.isUppercase == true && !$0.contains(" ") }
            .compactMap { usable($0, checkLevel: false) }
        if !learner.isEmpty {
            pool["things", default: []] += learner.filter { noun in !(pool["things"] ?? []).contains(noun) }
        }
        return pool
    }

    static func rank(_ level: CEFRLevel) -> Int {
        CEFRLevel.allCases.firstIndex(of: level) ?? 0
    }

    // MARK: Building phrases

    private struct Builder {
        let bank: KasusTriggerBank
        let pool: [String: [KasusPlannerNoun]]
        /// The curated Genitiv nouns at or below the level.
        let genitiveAtLevel: Set<String>
        /// A verb is at or below the level (a verb no Goethe list has is never used).
        let verbAtLevel: (String) -> Bool
        let definiteOnly: Set<String>
        let lexicon: any KasusLexicon
        var rng: KasusSeededRandom
        var usedNouns: Set<String> = []
        var frameUse: [KasusFrameKind: Int] = [:]
        var verbUse: [String: Int] = [:]

        init(bank: KasusTriggerBank, pool: [String: [KasusPlannerNoun]], genitiveAtLevel: Set<String>,
             verbAtLevel: @escaping (String) -> Bool, lexicon: any KasusLexicon, rng: KasusSeededRandom) {
            self.bank = bank
            self.pool = pool
            self.genitiveAtLevel = genitiveAtLevel
            self.verbAtLevel = verbAtLevel
            self.definiteOnly = Set(bank.definiteOnly ?? [])
            self.lexicon = lexicon
            self.rng = rng
        }

        /// The article families a noun may take here: both, unless the noun (kinship, mass) or
        /// the preposition allows only one.
        func families(for lemma: String, einOnly: Bool = false, definiteOnly: Bool = false) -> [KasusFamily] {
            let definite = !einOnly
            let ein = !definiteOnly && !self.definiteOnly.contains(lemma)
            return (definite ? [.definite] : []) + (ein ? [.ein] : [])
        }

        /// One of `allowed`: the seed's pick when both are, so a noun's constraint doesn't shift
        /// the rest of the plan. Nil when none is.
        mutating func family(from allowed: [KasusFamily]) -> KasusFamily? {
            let roll = definite()
            if allowed.count > 1 { return roll ? .definite : .ein }
            return allowed.first
        }

        /// The frames that can carry a case, least used first (ties broken by the seed).
        mutating func frames(for kasus: GrammarCase) -> [KasusFrameKind] {
            let kinds: [KasusFrameKind] = switch kasus {
            case .nominativ: [.subject]
            case .akkusativ: [.object, .preposition, .wechselWohin]
            case .dativ:     [.dativeVerb, .recipient, .preposition, .wechselWo]
            case .genitiv:   [.genitivePreposition]
            }
            let shuffled = rng.shuffled(kinds)
            return shuffled.sorted { frameUse[$0, default: 0] < frameUse[$1, default: 0] }
        }

        mutating func phrase(for kasus: GrammarCase, id: Int) -> KasusPlannedPhrase? {
            for frame in frames(for: kasus) {
                let built: KasusPlannedPhrase? = switch frame {
                case .subject:             verbFrame(.subject, verbs: bank.subjectVerbs, genders: [.der], id: id)
                case .object:              verbFrame(.object, verbs: bank.objectVerbs, genders: [.der], id: id)
                case .dativeVerb:          verbFrame(.dativeVerb, verbs: bank.dativeVerbs, genders: [.der, .das], id: id)
                case .recipient:           verbFrame(.recipient, verbs: bank.recipientVerbs, genders: [.der, .das], id: id)
                case .preposition:         prepositionFrame(kasus, id: id)
                case .wechselWo:           wechselFrame(wo: true, id: id)
                case .wechselWohin:        wechselFrame(wo: false, id: id)
                case .genitivePreposition: genitiveFrame(id: id)
                }
                if let built {
                    frameUse[frame, default: 0] += 1
                    usedNouns.insert(built.lemma)
                    if let verb = built.verb { verbUse[verb, default: 0] += 1 }
                    return built
                }
            }
            return nil
        }

        /// Unused nouns of these categories and genders, in pool order.
        func nouns(_ categories: [String], genders: Set<Gender>) -> [KasusPlannerNoun] {
            var seen = Set<String>()
            return categories.flatMap { pool[$0] ?? [] }.filter { noun in
                genders.contains(noun.genus) && !usedNouns.contains(noun.lemma) && seen.insert(noun.lemma).inserted
            }
        }

        /// Verbs least used first, ties broken by the seed.
        mutating func ordered(_ verbs: [KasusTriggerBank.Verb]) -> [KasusTriggerBank.Verb] {
            rng.shuffled(verbs).sorted { verbUse[$0.lemma, default: 0] < verbUse[$1.lemma, default: 0] }
        }

        mutating func definite() -> Bool { rng.chance(KasusStoryPlanner.definiteShare) }

        /// subject, object, dativeVerb, recipient: a determiner fixed by the frame + a noun of the
        /// verb's categories. A subject's verb counts only in the third person singular.
        mutating func verbFrame(_ frame: KasusFrameKind, verbs: [KasusTriggerBank.Verb], genders: Set<Gender>,
                                id: Int) -> KasusPlannedPhrase? {
            let kasus: GrammarCase = switch frame {
            case .subject:  .nominativ
            case .object:   .akkusativ
            default:        .dativ
            }
            for verb in ordered(verbs) where verbAtLevel(verb.lemma) {
                let forms: [String] = switch frame {
                case .dativeVerb: KasusForms.dativeVerbs[verb.lemma] ?? []
                case .subject:    KasusStoryPlanner.subjectForms(verb)
                default:          verb.forms ?? []
                }
                guard !forms.isEmpty, let noun = rng.pick(nouns(verb.nouns, genders: genders)),
                      let family = family(from: families(for: noun.lemma)) else { continue }
                guard let determiner = KasusForms.form(family: family, stem: family == .ein ? "ein" : "",
                                                       case: kasus, genus: noun.genus),
                      KasusForms.compatibleCases(determiner: determiner, genus: noun.genus) == [kasus]
                else { continue }
                let phrase = "\(determiner) \(noun.lemma)"
                return KasusPlannedPhrase(id: id, frame: frame, expression: phrase, phrase: phrase,
                                          caseRaw: kasus.rawValue, genusRaw: noun.genus.columnLabel,
                                          lemma: noun.lemma, preposition: nil, verb: verb.lemma,
                                          verbForms: forms.map { $0.lowercased() },
                                          verbShown: frame == .subject ? verb.forms?.first : nil)
            }
            return nil
        }

        /// The determiner a preposition + noun would take in this case with one of `allowed`, or
        /// nil when it would contract or wouldn't prove the case.
        func determiner(_ family: KasusFamily, case kasus: GrammarCase, noun: KasusPlannerNoun,
                        after word: String, governed: Set<GrammarCase>) -> String? {
            guard let determiner = KasusForms.form(family: family, stem: family == .ein ? "ein" : "",
                                                   case: kasus, genus: noun.genus),
                  !KasusStoryPlanner.contracts(word, determiner),
                  KasusForms.compatibleCases(determiner: determiner, genus: noun.genus).intersection(governed) == [kasus]
            else { return nil }
            return determiner
        }

        /// The families that give a usable determiner for this noun after `word`.
        func usableFamilies(_ noun: KasusPlannerNoun, case kasus: GrammarCase, after word: String,
                            governed: Set<GrammarCase>, einOnly: Bool = false, definiteOnly: Bool = false) -> [KasusFamily] {
            families(for: noun.lemma, einOnly: einOnly, definiteOnly: definiteOnly).filter {
                determiner($0, case: kasus, noun: noun, after: word, governed: governed) != nil
            }
        }

        /// A fixed-case preposition + article + noun, where the form and the preposition together
        /// leave exactly the planned case.
        mutating func prepositionFrame(_ kasus: GrammarCase, id: Int) -> KasusPlannedPhrase? {
            let candidates = bank.prepositions.filter { $0.caseRaw == kasus.rawValue }
            for preposition in rng.shuffled(candidates) {
                let word = preposition.word.lowercased()
                guard let governed = lexicon.prepositionCases(word), governed == [kasus] else { continue }
                let einOnly = preposition.einOnly == true, definiteOnly = preposition.definiteOnly == true
                let fitting = nouns(preposition.nouns, genders: [.der, .die, .das]).filter {
                    !usableFamilies($0, case: kasus, after: word, governed: governed,
                                    einOnly: einOnly, definiteOnly: definiteOnly).isEmpty
                }
                guard let noun = rng.pick(fitting),
                      let family = family(from: usableFamilies(noun, case: kasus, after: word, governed: governed,
                                                               einOnly: einOnly, definiteOnly: definiteOnly)),
                      let determiner = determiner(family, case: kasus, noun: noun, after: word, governed: governed)
                else { continue }
                let phrase = "\(determiner) \(noun.lemma)"
                return KasusPlannedPhrase(id: id, frame: .preposition, expression: "\(word) \(phrase)", phrase: phrase,
                                          caseRaw: kasus.rawValue, genusRaw: noun.genus.columnLabel,
                                          lemma: noun.lemma, preposition: word, verb: nil, verbForms: [])
            }
            return nil
        }

        /// auf/unter/neben + a piece of furniture that goes with the pair's verbs, with the
        /// position verb (Wo? → Dativ) or its placement partner (Wohin? → Akkusativ) as the hint.
        mutating func wechselFrame(wo: Bool, id: Int) -> KasusPlannedPhrase? {
            let kasus: GrammarCase = wo ? .dativ : .akkusativ
            let kind: KasusForms.WechselVerbKind = wo ? .position : .placement
            let forms = KasusForms.wechselVerbForms.filter { $0.value.kind == kind }.map(\.key).sorted()
            let pairs = bank.wechsel.pairs.filter { verbAtLevel(wo ? $0.position : $0.placement) }
            guard let pair = rng.pick(pairs), !forms.isEmpty else { return nil }
            // Sorted first: a dictionary's order isn't part of the seed's promise.
            for word in rng.shuffled(pair.prepositions.keys.sorted()) {
                let categories = pair.prepositions[word] ?? []
                guard lexicon.isTwoWay(word), let governed = lexicon.prepositionCases(word) else { continue }
                let fitting = nouns(categories, genders: [.der, .die, .das]).filter {
                    !usableFamilies($0, case: kasus, after: word, governed: governed).isEmpty
                }
                guard let noun = rng.pick(fitting),
                      let family = family(from: usableFamilies(noun, case: kasus, after: word, governed: governed)),
                      let determiner = determiner(family, case: kasus, noun: noun, after: word, governed: governed)
                else { continue }
                let phrase = "\(determiner) \(noun.lemma)"
                return KasusPlannedPhrase(id: id, frame: wo ? .wechselWo : .wechselWohin,
                                          expression: "\(word) \(phrase)", phrase: phrase,
                                          caseRaw: kasus.rawValue, genusRaw: noun.genus.columnLabel,
                                          lemma: noun.lemma, preposition: word,
                                          verb: wo ? pair.position : (pair.placementVerb ?? pair.placement),
                                          verbForms: forms)
            }
            return nil
        }

        /// wegen/trotz + a curated noun: des/eines + the noun's -(e)s form, der/einer + a feminine
        /// noun. Nouns above the level are used only when none at or below it is left.
        mutating func genitiveFrame(id: Int) -> KasusPlannedPhrase? {
            guard let word = rng.pick(bank.genitive.prepositions)?.lowercased(),
                  let governed = lexicon.prepositionCases(word), governed.contains(.genitiv) else { return nil }
            let atLevel = bank.genitive.nouns.filter { genitiveAtLevel.contains($0.lemma) }
            let all = bank.genitive.nouns
            for entries in [atLevel, all] {
                for entry in rng.shuffled(entries) where !usedNouns.contains(entry.lemma) {
                    guard !KasusForms.isNDeklination(entry.lemma),
                          case .verified(let genus) = lexicon.gender(forLemma: entry.lemma), genus != .plural,
                          let family = family(from: families(for: entry.lemma))
                    else { continue }
                    guard let determiner = KasusForms.form(family: family, stem: family == .ein ? "ein" : "",
                                                           case: .genitiv, genus: genus) else { continue }
                    let noun: String
                    if genus == .die {
                        noun = entry.lemma
                    } else {
                        guard let genitive = entry.genitive,
                              KasusForms.isGenitiveSingular(genitive, of: entry.lemma) else { continue }
                        noun = genitive
                    }
                    guard KasusForms.compatibleCases(determiner: determiner, genus: genus)
                            .intersection(governed) == [.genitiv] else { continue }
                    let phrase = "\(determiner) \(noun)"
                    return KasusPlannedPhrase(id: id, frame: .genitivePreposition, expression: "\(word) \(phrase)",
                                              phrase: phrase, caseRaw: GrammarCase.genitiv.rawValue,
                                              genusRaw: genus.columnLabel, lemma: entry.lemma, preposition: word,
                                              verb: nil, verbForms: [])
                }
            }
            return nil
        }
    }
}
