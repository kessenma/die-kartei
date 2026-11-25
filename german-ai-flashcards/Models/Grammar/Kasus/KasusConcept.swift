//
//  KasusConcept.swift
//  german-ai-flashcards
//
//  Verstehen · Understand: the concept exercises on each unit of the case path, which teach what
//  a case *is* before the stories ask for its endings.
//
//    Rollen            tap a phrase, name its role: the Kasus-Check step that decides it
//    Wer macht was?    who does what when only the ending tells („Den Hund jagt die Katze“), and
//                      „Gleich oder anders?“ on a pair that moved a block (the Umstellprobe)
//    Die Probe         swap in *der Mann* to read an article that could be two cases
//
//  Every item is a mini-story in the bundled stories' format (`KasusStory`: one or two sentences,
//  targets with reason and trigger), so the validator is its answer key, `KasusExplanation`
//  explains it and the word chips come from `KasusMarking`. Roles are never authored: a target's
//  role is read off its reason and its preposition (`KasusRole.init(target:)`), in the
//  Kasus-Check's own order. What a kind needs beyond the story (the question, which phrase to
//  swap) sits next to it in `KasusConceptItem.Detail`; the rest is derived at load into
//  `KasusConceptFacts`, which also lists what is wrong with an item (`problems`).
//
//  Foundation only, so `training/kasus_cli` compiles it next to the validator.
//

import Foundation

// MARK: - Kinds and exercises

/// One item's shape. Two kinds play in the same exercise (`exercise`).
nonisolated enum KasusConceptKind: String, Codable, CaseIterable, Hashable {
    /// A sentence whose phrases get a role each.
    case roles
    /// One sentence, „Wer …?“, two phrases to pick from.
    case whoDoesWhat
    /// Two sentences, „Gleich oder anders?“.
    case sameMeaning
    /// One sentence with an ambiguous phrase: which form of the masculine test noun fits?
    case probe

    var exercise: KasusConceptExercise {
        switch self {
        case .roles:                      .roles
        case .whoDoesWhat, .sameMeaning:  .wer
        case .probe:                      .probe
        }
    }
}

/// The three Verstehen exercises, each one row on a unit screen and one `KasusRoundStep`. What a
/// row shows and how a round files come from the registry (`kind.meta`, `KasusRoundStep.swift`);
/// what stays here is the item side: which item kinds play in the exercise and how many items a
/// unit needs before it offers it.
nonisolated enum KasusConceptExercise: String, CaseIterable, Identifiable, Hashable {
    case roles, wer, probe

    var id: String { rawValue }

    /// The exercise's kind in the registry.
    var kind: KasusDrillKind {
        switch self {
        case .roles: .roles
        case .wer:   .wer
        case .probe: .probe
        }
    }

    /// What a finished round records as.
    var roundStep: KasusRoundStep { kind.step }

    init?(step: KasusRoundStep) {
        guard let exercise = Self.allCases.first(where: { $0.roundStep == step }) else { return nil }
        self = exercise
    }

    /// The item kinds that play in this exercise.
    var kinds: [KasusConceptKind] {
        KasusConceptKind.allCases.filter { $0.exercise == self }
    }

    var germanTitle: String { kind.meta.germanTitle }
    var englishTitle: String { kind.meta.englishTitle }
    /// One line for the unit screen's row.
    var blurb: String { kind.meta.blurb }
    var symbol: String { kind.meta.symbol }
    /// The drawing a launcher row announces the exercise with.
    var art: GrammarTaskArt { kind.meta.art }
    /// Items per round. Rollen asks every phrase of its items, so eight sentences are about
    /// eighteen roles.
    var roundSize: Int { kind.meta.roundSize }
    /// About how long a round takes, for the hub's hero line.
    var minutes: Int { kind.meta.minutes }

    /// Fewer items than this in a unit, and the unit doesn't offer the exercise. A property of
    /// the item bank, not of the kind.
    var minimumItems: Int {
        switch self {
        case .roles: 4
        case .wer:   6
        case .probe: 4
        }
    }
}

// MARK: - Roles

/// How Rollen asks: the Kasus-Check one question at a time (Ja / Nein), or the role chips at once.
nonisolated enum KasusRolesMode: String, CaseIterable, Identifiable, Hashable {
    /// „Schritt für Schritt“: the six questions in order; the first Ja decides.
    case schritt
    /// „Direkt“: every role in play as a chip.
    case direkt

    var id: String { rawValue }

    /// `@AppStorage` key. Empty (never set) means Schritt für Schritt.
    static let storageKey = "kasus.rolesMode"

    var germanLabel: String {
        switch self {
        case .schritt: "Schritt für Schritt"
        case .direkt:  "Direkt"
        }
    }

    var englishLabel: String {
        switch self {
        case .schritt: "One question at a time"
        case .direkt:  "Pick the role"
        }
    }

    static func resolve(stored raw: String) -> KasusRolesMode {
        KasusRolesMode(rawValue: raw) ?? .schritt
    }
}

/// A phrase's job in the sentence, which is the Kasus-Check step that decides its case. The chips
/// Rollen shows and the questions Schritt für Schritt asks, in the Check's order.
nonisolated enum KasusRole: String, CaseIterable, Identifiable, Hashable {
    /// 1. A preposition in front decides.
    case praeposition
    /// 2. Hangs on another noun: whose, of what → Genitiv.
    case gehoertZu
    /// 3. The subject: whoever does the verb → Nominativ.
    case subjekt
    /// 4. What sein/werden/bleiben/heißen equates with the subject → Nominativ.
    case gleichSubjekt
    /// 5. The receiver, or the partner of a Dativ verb → Dativ.
    case empfaenger
    /// 6. None of the above: the direct object → Akkusativ.
    case direktesObjekt

    var id: String { rawValue }

    /// The Kasus-Check step, 1 to 6.
    var checkStep: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    var germanLabel: String {
        switch self {
        case .praeposition:   "Präposition"
        case .gehoertZu:      "Gehört zu"
        case .subjekt:        "Subjekt"
        case .gleichSubjekt:  "= Subjekt"
        case .empfaenger:     "Empfänger"
        case .direktesObjekt: "Direktes Objekt"
        }
    }

    var englishLabel: String {
        switch self {
        case .praeposition:   "the preposition decides"
        case .gehoertZu:      "whose · of"
        case .subjekt:        "the doer"
        case .gleichSubjekt:  "after sein"
        case .empfaenger:     "the receiver · a Dativ verb"
        case .direktesObjekt: "done-to"
        }
    }

    /// The English-speaker's handle on the role, in the `KasusRich` markup: the question word and
    /// the English pronoun that shows the same job. Only here do wer/wen/wem/wessen appear; the
    /// Kasus-Check, not the question test, decides.
    var bridge: String {
        switch self {
        case .praeposition:   "*für, mit, wegen* …"
        case .gehoertZu:      "*wessen?* · whose, 's"
        case .subjekt:        "*wer?* · I, he, who"
        case .gleichSubjekt:  "*wer?* · he **is** he, not him"
        case .empfaenger:     "*wem?* · to me, to him"
        case .direktesObjekt: "*wen?* · me, him, whom"
        }
    }

    /// Schritt für Schritt's question for this step, German then English.
    var question: (de: String, en: String) {
        switch self {
        case .praeposition:   ("Steht eine **Präposition** davor?", "Is there a preposition in front?")
        case .gehoertZu:      ("Hängt es an einem **anderen Nomen**?", "Does it hang on another noun: whose, of what?")
        case .subjekt:        ("Ist es das **Subjekt**?", "Is it the subject, the one doing the verb?")
        case .gleichSubjekt:  ("Setzt *sein, werden, bleiben* oder *heißen* es mit dem Subjekt **gleich**?", "Does sein, werden, bleiben or heißen equate it with the subject?")
        case .empfaenger:     ("Ist es der **Empfänger**, oder steht ein **Dativ-Verb**?", "Is it the receiver, or is the verb a Dativ verb like helfen?")
        case .direktesObjekt: ("**Nichts** davon?", "None of the above?")
        }
    }

    var symbol: String {
        switch self {
        case .praeposition:   "arrow.right.to.line"
        case .gehoertZu:      GrammarCase.genitiv.symbol
        case .subjekt:        GrammarCase.nominativ.symbol
        case .gleichSubjekt:  GrammarCase.nominativ.symbol
        case .empfaenger:     GrammarCase.dativ.symbol
        case .direktesObjekt: GrammarCase.akkusativ.symbol
        }
    }

    /// The case the role always means. Nil for a preposition, which decides on its own.
    var fixedCase: GrammarCase? {
        switch self {
        case .praeposition:                   nil
        case .gehoertZu:                      .genitiv
        case .subjekt, .gleichSubjekt:        .nominativ
        case .empfaenger:                     .dativ
        case .direktesObjekt:                 .akkusativ
        }
    }

    /// What the role reveals once picked: its own case, or the one the preposition takes.
    func revealedCase(for target: KasusLocatedTarget) -> GrammarCase {
        fixedCase ?? target.kasus
    }

    /// The role a located target has, read the way the Kasus-Check reads it: a preposition in
    /// front wins over everything (so a two-way or prepositional object phrase is `praeposition`),
    /// then the reason. Nil for a phrase no step names: a bare time phrase, a harvested phrase, or
    /// a preposition reason whose preposition wasn't found. Such a phrase is shown plain and never
    /// asked.
    init?(target: KasusLocatedTarget) {
        if target.preposition != nil {
            self = .praeposition
            return
        }
        switch target.spec.reason {
        case .subject:                                  self = .subjekt
        case .predicate:                                self = .gleichSubjekt
        case .object:                                   self = .direktesObjekt
        case .recipient, .dativeVerb, .dativeOther:     self = .empfaenger
        case .attribute:                                self = .gehoertZu
        case .time, .preposition, .prepObject, .wechselWo, .wechselWohin, .inferred:
            return nil
        }
    }

    /// The roles in play for a unit, in Kasus-Check order: the steps whose case the unit has met.
    /// Nominativ: Subjekt and = Subjekt. Akkusativ adds Präposition and Direktes Objekt; Dativ
    /// adds Empfänger; Genitiv and Alle Fälle have all six.
    @MainActor
    static func chips(for unit: KasusUnit) -> [KasusRole] {
        let cases = Set(unit.casesInPlay)
        return allCases.filter { role in
            switch role {
            case .praeposition:            cases.contains(.akkusativ)
            case .gehoertZu:               cases.contains(.genitiv)
            case .subjekt, .gleichSubjekt: true
            case .empfaenger:              cases.contains(.dativ)
            case .direktesObjekt:          cases.contains(.akkusativ)
            }
        }
    }

    /// The questions Schritt für Schritt asks for a unit: the chips in play except the last,
    /// „Nichts davon“, which is what's left when every question got a Nein.
    @MainActor
    static func walkSteps(for unit: KasusUnit) -> [KasusRole] {
        chips(for: unit).filter { $0 != .direktesObjekt }
    }

    /// The preposition chip's small line for a unit: the prepositions it has met.
    @MainActor
    static func prepositionBridge(for unit: KasusUnit) -> String {
        switch unit {
        case .nominativ, .akkusativ: "*für, durch, ohne, um* …"
        case .dativ:                 "*für, mit, aus, zu* …"
        case .genitiv, .alleFaelle:  "*für, mit, wegen* …"
        }
    }
}

// MARK: - The Probe's test noun

/// The masculine noun the Probe swaps in: the one gender whose article shows every case.
nonisolated enum KasusProbeNoun: String, Codable, CaseIterable, Hashable {
    case mann = "Mann"
    case hund = "Hund"
    case lehrer = "Lehrer"
    case vater = "Vater"

    var genitive: String {
        switch self {
        case .mann:   "Mannes"
        case .hund:   "Hundes"
        case .lehrer: "Lehrers"
        case .vater:  "Vaters"
        }
    }

    /// The noun as it stands after the article in this case.
    func noun(_ kasus: GrammarCase) -> String {
        kasus == .genitiv ? genitive : rawValue
    }

    /// „dem Mann“, „des Mannes“: the form the learner picks.
    func form(_ kasus: GrammarCase) -> String {
        "\(kasus.article(.der)) \(noun(kasus))"
    }

    /// The buttons, in table order; des Mannes only once the Genitiv is in play.
    func options(includeGenitive: Bool) -> [String] {
        let cases: [GrammarCase] = includeGenitive ? GrammarCase.allCases : [.nominativ, .akkusativ, .dativ]
        return cases.map(form)
    }

    /// „der Mann“, for an instruction.
    var dictionaryForm: String { form(.nominativ) }
}

// MARK: - Items

nonisolated struct KasusConceptFile: Decodable {
    let version: Int
    let items: [KasusConceptItem]
}

/// One item of `Resources/kasus_concepts.json`: a mini-story plus what its kind needs. The JSON is
/// one flat object (the story's fields next to the kind's), decoded into the story the validator
/// reads and the detail the exercise reads. The story-only fields (title, question, reviewed)
/// are filled with blanks, so an item is a `KasusStory` everywhere the player needs one.
nonisolated struct KasusConceptItem: Identifiable, Hashable, Decodable {
    let id: String
    let kind: KasusConceptKind
    let story: KasusStory
    let detail: Detail
    /// The phrase in the English line, by target index („the woman“), so the English twin can
    /// wear the same case color. Optional per target.
    let english: [Int: String]
    /// Wer …?: a picture per reading, keyed by the target that is the doer in it (a
    /// `kasus3d-*` scene asset). With both options covered, the item is answered by tapping the
    /// picture that fits instead of a phrase.
    let pictures: [Int: String]

    nonisolated enum Detail: Hashable {
        /// Rollen: the targets to ask, or nil for every target whose role is a chip in the unit.
        case roles(ask: [Int]?)
        /// Wer …?: the question, the two phrases (target indices, reading order), the doer.
        case whoDoesWhat(question: Prompt, options: [Int], answer: Int)
        /// Two paragraphs: do they mean the same?
        case sameMeaning(same: Bool)
        /// The phrase to swap (a target index) and the noun to swap in.
        case probe(target: Int, noun: KasusProbeNoun)
    }

    nonisolated struct Prompt: Hashable, Decodable {
        let de: String
        let en: String
    }

    init(id: String, kind: KasusConceptKind, story: KasusStory, detail: Detail, english: [Int: String] = [:],
         pictures: [Int: String] = [:]) {
        self.id = id
        self.kind = kind
        self.story = story
        self.detail = detail
        self.english = english
        self.pictures = pictures
    }

    var unitRaw: String { story.unitRaw }
    var level: String { story.level }

    enum CodingKeys: String, CodingKey {
        case id, unit, level, source, kind, paragraphs, targets, notTargets
        case ask, question, options, answer, same, probe, pictures
    }

    /// A target's extra key, read beside the validator's spec.
    private nonisolated struct TargetExtras: Decodable {
        let en: String?
    }

    private nonisolated struct ProbeSpec: Decodable {
        let target: Int
        let noun: KasusProbeNoun
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(KasusConceptKind.self, forKey: .kind)
        let targets = try container.decode([KasusTargetSpec].self, forKey: .targets)
        let extras = try container.decode([TargetExtras].self, forKey: .targets)
        english = Dictionary(uniqueKeysWithValues: extras.enumerated().compactMap { index, extra in
            extra.en.map { (index, $0) }
        })
        let pictureKeys = try container.decodeIfPresent([String: String].self, forKey: .pictures) ?? [:]
        var pictures: [Int: String] = [:]
        for (key, asset) in pictureKeys {
            guard let index = Int(key) else {
                throw DecodingError.dataCorruptedError(forKey: .pictures, in: container,
                                                       debugDescription: "picture key \(key) is no target index")
            }
            pictures[index] = asset
        }
        self.pictures = pictures
        let paragraphs = try container.decode([KasusStory.Paragraph].self, forKey: .paragraphs)
        story = KasusStory(
            id: id,
            unitRaw: try container.decode(String.self, forKey: .unit),
            level: try container.decode(String.self, forKey: .level),
            source: try container.decodeIfPresent(KasusStorySource.self, forKey: .source) ?? .authored,
            reviewed: .init(by: "", date: ""),
            title: id,
            titleEnglish: "",
            question: .init(de: "", en: "", options: [], answer: 0),
            paragraphs: paragraphs,
            targets: targets,
            notTargets: try container.decodeIfPresent([KasusNotTarget].self, forKey: .notTargets) ?? []
        )
        switch kind {
        case .roles:
            detail = .roles(ask: try container.decodeIfPresent([Int].self, forKey: .ask))
        case .whoDoesWhat:
            detail = .whoDoesWhat(
                question: try container.decode(Prompt.self, forKey: .question),
                options: try container.decode([Int].self, forKey: .options),
                answer: try container.decode(Int.self, forKey: .answer)
            )
        case .sameMeaning:
            detail = .sameMeaning(same: try container.decode(Bool.self, forKey: .same))
        case .probe:
            let probe = try container.decode(ProbeSpec.self, forKey: .probe)
            detail = .probe(target: probe.target, noun: probe.noun)
        }
    }
}

@MainActor
extension KasusConceptItem {
    /// Nil for an unknown raw value.
    var unit: KasusUnit? { KasusUnit(rawValue: unitRaw) }
}

// MARK: - Facts

/// What an item is for playing, derived from the validator's located targets: each target's role,
/// which targets a round asks, the phrase whose form decides a Wer item, and whether a Probe
/// phrase is really ambiguous. `problems` lists what makes the item unplayable; the DEBUG loader
/// asserts it empty, the tests check it, and `-kasus.debugVerify` prints it.
nonisolated struct KasusConceptFacts: Hashable {
    /// The role of every located target that has one, by target index.
    let roles: [Int: KasusRole]
    /// Rollen: the targets to ask, in reading order.
    let asked: [Int]
    /// Wer …?: the option whose form or preposition decides the reading. Same meaning: the clue
    /// of each paragraph, in order.
    let clues: [Int]
    /// Wer …?: the sentence's first phrase is not the doer (object first).
    let isOVS: Bool
    /// The subject target of each paragraph, in order, where one is found.
    let subjects: [Int]
    let problems: [String]

    var clue: Int? { clues.first }
    var isPlayable: Bool { problems.isEmpty }

    /// Reads the facts off the validator's targets. `unit` says which roles are in play.
    @MainActor
    static func derive(_ item: KasusConceptItem, unit: KasusUnit, located: [KasusLocatedTarget]) -> KasusConceptFacts {
        var problems: [String] = []
        if located.count != item.story.targets.count {
            problems.append("\(item.story.targets.count - located.count) target(s) not located")
        }
        let byIndex = Dictionary(uniqueKeysWithValues: located.map { ($0.index, $0) })
        var roles: [Int: KasusRole] = [:]
        for target in located {
            if let role = KasusRole(target: target) { roles[target.index] = role }
        }
        let subjects = located.filter { $0.spec.reason == .subject }.map(\.index)
        func decides(_ target: KasusLocatedTarget) -> Bool {
            target.gradable && (target.proof == .form || target.proof == .preposition)
        }
        /// The first located phrase of a paragraph, by position.
        func firstPhrase(in paragraph: Int) -> KasusLocatedTarget? {
            located.filter { $0.paragraphIndex == paragraph }.min { $0.range.location < $1.range.location }
        }

        var asked: [Int] = []
        var clues: [Int] = []
        var isOVS = false

        switch item.detail {
        case .roles(let ask):
            let chips = Set(KasusRole.chips(for: unit))
            let wanted = ask ?? located.map(\.index)
            for index in wanted {
                guard let target = byIndex[index] else {
                    problems.append("ask #\(index + 1) is no target")
                    continue
                }
                guard target.gradable else { continue }
                guard let role = roles[index] else {
                    if ask != nil { problems.append("#\(index + 1) „\(target.surface)“ has no role to ask") }
                    continue
                }
                if chips.contains(role) { asked.append(index) }
                else if ask != nil { problems.append("#\(index + 1) „\(target.surface)“ is \(role.rawValue), not in play for \(unit.rawValue)") }
            }
            asked.sort { (byIndex[$0]?.range.location ?? 0) < (byIndex[$1]?.range.location ?? 0) }
            if asked.isEmpty { problems.append("no phrase to ask") }

        case .whoDoesWhat(_, let options, let answer):
            guard options.count == 2, Set(options).count == 2, options.contains(answer) else {
                problems.append("options must be two targets, one of them the answer")
                break
            }
            guard let doer = byIndex[answer], options.allSatisfy({ byIndex[$0] != nil }) else {
                problems.append("an option is no located target")
                break
            }
            if doer.spec.reason != .subject { problems.append("the answer „\(doer.surface)“ is not the subject") }
            if let clue = options.first(where: { byIndex[$0].map(decides) == true && $0 != answer })
                ?? options.first(where: { byIndex[$0].map(decides) == true }) {
                clues = [clue]
            } else {
                problems.append("neither phrase is proven by its form: nothing but word order decides")
            }
            if let first = firstPhrase(in: doer.paragraphIndex) { isOVS = first.index != answer }
            if !item.pictures.isEmpty, Set(item.pictures.keys) != Set(options) {
                problems.append("pictures must cover exactly the two options")
            }
            if Set(item.pictures.values).count != item.pictures.count {
                problems.append("each reading needs its own picture")
            }

        case .sameMeaning(let same):
            if !item.pictures.isEmpty { problems.append("only a Wer …? item takes pictures") }
            guard item.story.paragraphs.count == 2 else {
                problems.append("same-meaning needs exactly two sentences")
                break
            }
            // Who does what in each sentence: the doer and the verb's partners (done-to, receiver,
            // Dativ partner) with their nouns. An Umstellprobe keeps this set and moves the
            // blocks; an attribute („des Lehrers“) rides along with its noun.
            var signatures: [Set<String>] = []
            for paragraph in 0..<2 {
                let here = located.filter { $0.paragraphIndex == paragraph }
                guard let clue = here.first(where: decides) else {
                    problems.append("sentence \(paragraph + 1) has no phrase proven by its form")
                    continue
                }
                clues.append(clue.index)
                guard here.contains(where: { $0.spec.reason == .subject }) else {
                    problems.append("sentence \(paragraph + 1) has no subject target")
                    continue
                }
                let roles: [KasusReason] = [.subject, .object, .recipient, .dativeVerb]
                signatures.append(Set(here.filter { roles.contains($0.spec.reason) }
                    .map { "\($0.spec.reason.rawValue):\($0.spec.lemma)" }))
            }
            if signatures.count == 2, (signatures[0] == signatures[1]) != same {
                problems.append("same = \(same), but the roles read \(signatures[0].sorted()) and \(signatures[1].sorted())")
            }

        case .probe(let index, let noun):
            guard let target = byIndex[index] else {
                problems.append("probe target #\(index + 1) is no located target")
                break
            }
            if target.kind != .article || target.parsed == nil { problems.append("„\(target.surface)“ is no article phrase") }
            if target.genus == .der { problems.append("„\(target.surface)“ is masculine: nothing to swap") }
            if target.candidates.count < 2 { problems.append("„\(target.surface)“ already shows its case") }
            if !target.gradable { problems.append("„\(target.surface)“ can't be graded") }
            _ = noun
        }

        return KasusConceptFacts(roles: roles, asked: asked, clues: clues, isOVS: isOVS,
                                 subjects: subjects, problems: problems)
    }
}
