//
//  KasusRoundStep.swift
//  german-ai-flashcards
//
//  The registry of grammar exercise types. Every scored step the Grammatik path records is one
//  `KasusRoundStep` raw value (stored in `KasusRound.stepRaw`, synced as a string, never renamed),
//  and every fact the app needs about a step lives in its `KasusDrillMeta`: how it is titled,
//  filed, offered, counted and whether its answers may move the coach. Verlauf, the calendar, the
//  round detail, the hub, the unit screens, the recording rail, the debug launch arguments and
//  the seeder all read the meta, so adding an exercise type is one case and one meta row here,
//  plus a module that plays it.
//
//  `KasusDrillKind` is the subset of steps the drill shell plays (not the story worksheets or a
//  read lesson). It has no raw values of its own: its `rawValue` is its step's, so
//  `-kasus.debugOpen <kind>:<topic>` parses through `KasusRoundStep(rawValue:)` and the two can
//  never drift apart (the way the kasus-cli stub once did).
//
//  Foundation only and `nonisolated`: compiled into training/kasus_cli next to the item types.
//

import Foundation

/// Which exercise a `KasusRound` records. The raw values are stored; never rename one. A build
/// that doesn't know a step reads the round with `step == nil` and shows a plain row.
nonisolated enum KasusRoundStep: String, Codable, CaseIterable {
    /// Markieren: mark every word in one case (before it, Finden's brush sorting). Counts for the
    /// streak only.
    case find
    /// Endungen: fill in the article endings (before it, Einsetzen's whole articles).
    case fill
    /// Schnellrunde: the endings drill for one unit.
    case quick
    /// Bau das Wort: the Schnellrunde's sentences, answered with ending blocks (d + em) instead
    /// of whole articles. Graded like the Schnellrunde; extra practice, so it never marks a unit
    /// done.
    case build
    /// Verstehen · Rollen: name each phrase's role (the Kasus-Check step). Counts for the streak
    /// only, like Markieren.
    case roles
    /// Verstehen · Wer macht was?: who does what when only the ending tells (structured input),
    /// and „Gleich oder anders?“. Counts for the streak only.
    case wer
    /// Verstehen · Die Probe: swap in *der Mann* to read an ambiguous article. Production, so it
    /// may move the coach like the Schnellrunde.
    case probe
    /// Verstehen · Lektion: the unit's lesson was read through. Asked 0, answered 0; banks the
    /// time only, and no list shows it.
    case lesson
    /// Blitzrunde: the Schnellrunde against the clock, misses reviewed at the end. Never evidence.
    case blitz
    /// Verwechslungs-Paar: ten sentences on the two forms a learner mixes up (dem vs den). Never
    /// evidence: two options are practice.
    case pair
    /// Dativ-Verben: the Schnellrunde's frames on the verbs that take the Dativ, with the
    /// Akkusativ false friends mixed in.
    case dativVerbs = "dativverben"
    /// Finde den Fehler: one ending in the sentence is wrong; tap it, then pick the fix.
    case fehler
    /// Reflexivverben · Akkusativ oder Dativ?: mich or mir, by the person and whether a second
    /// object follows.
    case reflexCase = "reflexcase"
    /// Reflexivverben · Die richtige Person: sich, dich or uns, following the subject, in one case.
    case reflexPerson = "reflexperson"
    /// Pronomen-Brücke: he/him → er/ihn → der/den on the same frames.
    case bridge
    /// Welche Frage?: which of wer/wen/wem/wessen the ringed part of an English sentence answers.
    /// Recognition on a translation, so it never moves the coach.
    case frage
    /// Die englische Falle: the same question where the English reading points at the wrong case
    /// (a Dativ verb, an inverter, a preposition that doesn't transfer).
    case englischeFalle = "englischefalle"
    /// Finde den Fall: the question is given, the learner taps the phrase that answers it.
    case findeFall = "findefall"
    /// Die Tabelle: the article chart as a board, its forms dragged into their cells.
    case tabelle

    var germanLabel: String { meta.germanTitle }

    /// The name the step had before Markieren and Endungen, for rounds recorded then.
    var legacyGermanLabel: String { meta.legacyGermanTitle ?? meta.germanTitle }

    /// The Verstehen exercises and the lesson, whose rounds file under `concept-<unit>-<step>`.
    var isConcept: Bool { meta.filing == .concept || meta.filing == .lesson }
}

// MARK: - Meta

/// Everything the app knows about an exercise type, in one place.
nonisolated struct KasusDrillMeta: Hashable {
    /// Where a step's rounds file and how its rows are titled.
    enum Filing: Hashable {
        /// A story's worksheet (Markieren, Endungen): filed under the story's id, titled by the
        /// story.
        case story
        /// A unit's own drill with no story (Schnellrunde, Bau das Wort, …): filed under
        /// `<step>-<topic>` (the Schnellrunde keeps its `quick-<unit>`), titled „Step · Unit“.
        case topicDrill
        /// A Verstehen exercise: `concept-<topic>-<step>`, titled „Step · Unit“.
        case concept
        /// A read lesson: `concept-<topic>-lesson`; never listed.
        case lesson
    }

    /// Whether an answer may move the coach's skill (`KasusService.countsTowardSkill`). The
    /// guards that hold for every step (answered, not a slip, a case with a focus) are applied
    /// before the policy is read.
    enum CoachPolicy: Hashable {
        /// Recognition: the role, the reading, a marked word, a timed pick. Streak only.
        case never
        /// Production whose screen shows nothing of the answer (Die Probe's test noun, a reflexive
        /// pronoun).
        case production
        /// Production where the noun is named with its article („Noun: die Katze“), so an
        /// f/n/pl Akkusativ gives itself away and is left out.
        case productionUnlessGenderShown
        /// Endungen: by help level (Lernhilfe and Viel Hilfe never, Genus-Hilfe masculine only,
        /// Ohne Hilfe unless the Tipp showed too much).
        case hintLadder
    }

    /// Which section of a unit or topic screen offers the exercise.
    enum Placement: Hashable {
        /// Inside the story player; never a row of its own.
        case story
        /// Verstehen · Understand.
        case verstehen
        /// Üben · Practice (the Schnellrunde's section).
        case ueben
        /// Unused since the Weitere-Bereiche reorg: hub rows come from `GrammarArea.rows`, not a
        /// placement. Kept for a future registry-driven room mapping.
        case tool
        /// Not offered anywhere yet (a kind whose module isn't built).
        case hidden
    }

    /// „Sätze“ / "sentences": what the round's count is a count of, in Verlauf (German) and the
    /// calendar's day detail (English).
    struct CountNoun: Hashable {
        let de: String
        let en: String
    }

    /// A German label with its English.
    struct LabelPair: Hashable {
        let de: String
        let en: String
    }

    /// „Schnellrunde“: the title on every surface.
    let germanTitle: String
    /// "Quick round": the English after the dot on a row.
    let englishTitle: String
    /// The name the step had before it was renamed (Finden, Einsetzen), for rounds recorded then.
    var legacyGermanTitle: String? = nil
    /// One line for a unit screen's row.
    let blurb: String
    /// An SF Symbol. For the dense, retrospective surfaces: Verlauf, the calendar, a round's
    /// detail, the drill shell's empty state. A launcher row shows `art` instead.
    let symbol: String
    /// The drawing a launcher row announces the exercise with (`GrammarTaskArt`). No default: a new
    /// step must choose a task shape, and choosing one another step already uses is a statement
    /// that the two ask the same thing (`GrammarTaskArtTests` pins which shares are intended).
    let art: GrammarTaskArt
    /// About how long a round takes.
    let minutes: Int
    /// Items per round; 0 where the round sizes itself (a story's words, a timed round).
    let roundSize: Int
    let countNoun: CountNoun
    let filing: Filing
    let coachPolicy: CoachPolicy
    let placement: Placement
    /// The step's rounds fill the unit's own dot on the hub (the Schnellrunde only; Bau das Wort
    /// is extra practice). Verstehen kinds fill the Verstehen dot by their placement.
    var marksUnitDone = false
    /// The pick is a form (an article, an ending, a pronoun): the round detail strikes it through
    /// in the sentence, and the confusion analysis may read it. False where the pick is a role or
    /// a reading.
    var pickIsForm = true
    /// The round detail's reason when a round of this step never moves the coach, after the
    /// step's label („Rollen · Dativ is for understanding the roles, so it never moves the coach.“).
    var coachNote: String? = nil
    /// Per-step wording of an outcome in the round history, where the default labels would
    /// mislead (a `wrongPick` in Rollen is another role, in a reflexive drill another person).
    var outcomeLabels: [KasusItemOutcome: LabelPair] = [:]
    /// How many counting answers a focus needs before the coach moves. Three per case for the
    /// case drills; six for a drill whose buttons are few enough to guess.
    var minItemsPerFocus = 3
    /// The round summary prints each case's code word (the endings drills).
    var summaryShowsCodeWord = false
    /// The question-mark menu may pin the endings table over the round. Off for a timed round,
    /// where the pinned table would show the answer.
    var allowsReference = true
    /// A round may ask one case only (person agreement, where the case is given and the skill is
    /// the person). Every case drill past the Nominativ unit mixes two.
    var singleCaseAllowed = false

    /// The `KasusRound.storyID` a round of this step files under for `topicKey` (a `KasusUnit`
    /// raw value, or a topic's key): `quick-dativ`, `build-dativ`, `concept-dativ-roles`,
    /// `concept-dativ-lesson`, `blitz-dativ`, `reflexcase-reflexiv`. Never changes for a shipped
    /// step. A story step files under its story's id instead and returns an empty string.
    func roundID(topicKey: String, step: KasusRoundStep) -> String {
        switch filing {
        case .story:      return ""
        case .topicDrill: return "\(step.rawValue)-\(topicKey)"
        case .concept:    return "\(KasusDrillMeta.conceptPrefix)\(topicKey)-\(step.rawValue)"
        case .lesson:     return "\(KasusDrillMeta.conceptPrefix)\(topicKey)-\(KasusRoundStep.lesson.rawValue)"
        }
    }

    /// Every Verstehen round and read lesson files under this prefix.
    static let conceptPrefix = "concept-"
}

extension KasusRoundStep {
    /// The step's meta. One row per step; adding a step means adding its row here.
    nonisolated var meta: KasusDrillMeta {
        switch self {
        case .find:
            KasusDrillMeta(germanTitle: "Markieren", englishTitle: "Mark the case", legacyGermanTitle: "Finden",
                           blurb: "Tap every word in the case", symbol: "highlighter",
                           art: .markWords, minutes: 6, roundSize: 0,
                           countNoun: .init(de: "Wörter", en: "words"), filing: .story, coachPolicy: .never,
                           placement: .story, pickIsForm: false,
                           coachNote: "is for spotting cases, so it never moves the coach.")
        case .fill:
            KasusDrillMeta(germanTitle: "Endungen", englishTitle: "Endings", legacyGermanTitle: "Einsetzen",
                           blurb: "Fill in the article endings", symbol: "character.cursor.ibeam",
                           art: .endingGap, minutes: 4, roundSize: 0,
                           countNoun: .init(de: "Endungen", en: "endings"), filing: .story, coachPolicy: .hintLadder,
                           placement: .story)
        case .quick:
            KasusDrillMeta(germanTitle: "Schnellrunde", englishTitle: "Quick round",
                           blurb: "Pick the article that fits the sentence", symbol: "character.cursor.ibeam",
                           art: .wordGap,
                           minutes: 3, roundSize: 10, countNoun: .init(de: "Sätze", en: "sentences"),
                           filing: .topicDrill, coachPolicy: .productionUnlessGenderShown, placement: .ueben,
                           marksUnitDone: true, summaryShowsCodeWord: true)
        case .build:
            KasusDrillMeta(germanTitle: "Bau das Wort", englishTitle: "Build the word",
                           blurb: "The same sentences, the ending snapped onto the stem in 3D", symbol: "cube.fill",
                           art: .snapEnding,
                           minutes: 3, roundSize: 10, countNoun: .init(de: "Wörter", en: "words"),
                           filing: .topicDrill, coachPolicy: .productionUnlessGenderShown, placement: .ueben,
                           summaryShowsCodeWord: true)
        case .roles:
            KasusDrillMeta(germanTitle: "Rollen", englishTitle: "Who does what?",
                           blurb: "Name each phrase's job: the doer, the done-to, the receiver …", symbol: "tag.fill",
                           art: .tagPhrases,
                           minutes: 4, roundSize: 8, countNoun: .init(de: "Rollen", en: "roles"),
                           filing: .concept, coachPolicy: .never, placement: .verstehen, pickIsForm: false,
                           coachNote: "is for understanding the roles, so it never moves the coach.",
                           outcomeLabels: [.wrongPick: .init(de: "Andere Rolle", en: "Another role")])
        case .wer:
            KasusDrillMeta(germanTitle: "Wer macht was?", englishTitle: "Only the ending tells",
                           blurb: "Read who does what when the word order doesn't say", symbol: "person.2.fill",
                           art: .twoReadings,
                           minutes: 3, roundSize: 10, countNoun: .init(de: "Sätze", en: "sentences"),
                           filing: .concept, coachPolicy: .never, placement: .verstehen, pickIsForm: false,
                           coachNote: "is for understanding the roles, so it never moves the coach.",
                           outcomeLabels: [.wrongPick: .init(de: "Anders gelesen", en: "Read the other way")])
        case .probe:
            KasusDrillMeta(germanTitle: "Die Probe", englishTitle: "Swap in der Mann",
                           blurb: "Read an article that could be two cases", symbol: "arrow.2.squarepath",
                           art: .swapInPlace,
                           minutes: 3, roundSize: 8, countNoun: .init(de: "Formen", en: "swaps"),
                           filing: .concept, coachPolicy: .production, placement: .verstehen)
        case .lesson:
            KasusDrillMeta(germanTitle: "Lektion", englishTitle: "The idea",
                           blurb: "What this case is, in English and German", symbol: "lightbulb.fill",
                           art: .ideaCard,
                           minutes: 2, roundSize: 0, countNoun: .init(de: "gelesen", en: "cards"),
                           filing: .lesson, coachPolicy: .never, placement: .verstehen, pickIsForm: false)
        case .blitz:
            KasusDrillMeta(germanTitle: "Blitzrunde", englishTitle: "Speed round",
                           blurb: "Sixty seconds, as many sentences as you can; the misses wait for the end",
                           symbol: "bolt.fill",
                           art: .beatTheClock, minutes: 1, roundSize: 0, countNoun: .init(de: "Sätze", en: "sentences"),
                           filing: .topicDrill, coachPolicy: .never, placement: .ueben,
                           coachNote: "is a speed round, so it never moves the coach", allowsReference: false)
        case .pair:
            KasusDrillMeta(germanTitle: "Verwechslungs-Paar", englishTitle: "Confusion pair",
                           blurb: "The two forms you mix up, ten sentences", symbol: "arrow.left.arrow.right",
                           art: .pickOfTwo,
                           minutes: 2, roundSize: 10, countNoun: .init(de: "Sätze", en: "sentences"),
                           filing: .topicDrill, coachPolicy: .never, placement: .hidden)
        case .dativVerbs:
            KasusDrillMeta(germanTitle: "Dativ-Verben", englishTitle: "The verb decides",
                           blurb: "helfen, danken, gefallen … and the verbs that only feel like them",
                           symbol: "hand.raised.fill", art: .verbDecides, minutes: 3, roundSize: 10,
                           countNoun: .init(de: "Sätze", en: "sentences"), filing: .topicDrill,
                           coachPolicy: .productionUnlessGenderShown, placement: .ueben, summaryShowsCodeWord: true)
        case .fehler:
            KasusDrillMeta(germanTitle: "Finde den Fehler", englishTitle: "Find the mistake",
                           blurb: "One ending is wrong: tap it, then fix it", symbol: "exclamationmark.magnifyingglass",
                           art: .spotTheOddOne,
                           minutes: 3, roundSize: 8, countNoun: .init(de: "Sätze", en: "sentences"),
                           filing: .topicDrill, coachPolicy: .productionUnlessGenderShown, placement: .ueben,
                           coachNote: "moves the coach only for a mistake you found yourself",
                           outcomeLabels: [.wrongPick: .init(de: "Übersehen", en: "Missed the word")])
        case .reflexCase:
            KasusDrillMeta(germanTitle: "Akkusativ oder Dativ?", englishTitle: "mich or mir?",
                           blurb: "Which reflexive pronoun fits: the person, and whether a second object follows",
                           symbol: "arrow.uturn.backward.circle.fill",
                           art: .pickOfTwo, minutes: 3, roundSize: 10,
                           countNoun: .init(de: "Sätze", en: "sentences"), filing: .topicDrill,
                           coachPolicy: .production, placement: .hidden,
                           outcomeLabels: [.wrongPick: .init(de: "Andere Person", en: "Another person"),
                                           .caseMiss: .init(de: "Falscher Fall", en: "Wrong case")],
                           minItemsPerFocus: 6)
        case .reflexPerson:
            KasusDrillMeta(germanTitle: "Die richtige Person", englishTitle: "The right person",
                           blurb: "sich, dich or uns: the pronoun follows the subject",
                           symbol: "person.fill.checkmark", art: .followTheSubject, minutes: 2, roundSize: 10,
                           countNoun: .init(de: "Sätze", en: "sentences"), filing: .topicDrill,
                           coachPolicy: .production, placement: .hidden,
                           outcomeLabels: [.wrongPick: .init(de: "Andere Person", en: "Another person"),
                                           .caseMiss: .init(de: "Falscher Fall", en: "Wrong case")],
                           minItemsPerFocus: 6, singleCaseAllowed: true)
        case .bridge:
            KasusDrillMeta(germanTitle: "Pronomen-Brücke", englishTitle: "Pronoun bridge",
                           blurb: "You already say him, not he: German does the same to every noun",
                           symbol: "point.topleft.down.to.point.bottomright.curvepath",
                           art: .threeStepChain, minutes: 3, roundSize: 8,
                           countNoun: .init(de: "Sätze", en: "sentences"), filing: .topicDrill,
                           coachPolicy: .never, placement: .verstehen,
                           coachNote: "is recognition of a job you already feel in English, so it never moves the coach")
        case .frage:
            KasusDrillMeta(germanTitle: "Welche Frage?", englishTitle: "Which question?",
                           blurb: "Which of the four questions the marked part answers",
                           symbol: "questionmark.bubble",
                           art: .ringOneSpan, minutes: 4, roundSize: 10,
                           countNoun: .init(de: "Sätze", en: "sentences"), filing: .topicDrill,
                           coachPolicy: .never, placement: .tool, pickIsForm: false,
                           coachNote: "is recognition on an English sentence, so it never moves the coach",
                           outcomeLabels: [.wrongPick: .init(de: "Andere Frage", en: "Another question")])
        case .englischeFalle:
            KasusDrillMeta(germanTitle: "Die englische Falle", englishTitle: "Where English lies",
                           blurb: "Where your English points at the wrong case",
                           symbol: "exclamationmark.triangle.fill",
                           art: .forkedPath, minutes: 3, roundSize: 8,
                           countNoun: .init(de: "Sätze", en: "sentences"), filing: .topicDrill,
                           coachPolicy: .never, placement: .tool, pickIsForm: false,
                           coachNote: "is recognition on an English sentence, so it never moves the coach",
                           outcomeLabels: [.wrongPick: .init(de: "Andere Frage", en: "Another question")])
        case .tabelle:
            KasusDrillMeta(germanTitle: "Die Tabelle", englishTitle: "Fill the table",
                           blurb: "Drag every article into its cell of the chart",
                           symbol: "tablecells.badge.ellipsis",
                           art: .fillTheGrid, minutes: 4, roundSize: ArticleTableRound.cellCount,
                           countNoun: .init(de: "Felder", en: "cells"),
                           filing: .topicDrill, coachPolicy: .never, placement: .tool,
                           coachNote: "is built from a closed set of tiles, so it never moves the coach",
                           outcomeLabels: [.wrongPick: .init(de: "Falsches Feld", en: "Another cell")],
                           summaryShowsCodeWord: true, allowsReference: false)
        case .findeFall:
            KasusDrillMeta(germanTitle: "Finde den Fall", englishTitle: "Find the case",
                           blurb: "The question is given: tap the part that answers it",
                           symbol: "hand.tap.fill",
                           art: .pickThePhrase, minutes: 3, roundSize: 8,
                           countNoun: .init(de: "Sätze", en: "sentences"), filing: .topicDrill,
                           coachPolicy: .never, placement: .tool, pickIsForm: false,
                           coachNote: "is recognition on an English sentence, so it never moves the coach",
                           outcomeLabels: [.wrongPick: .init(de: "Anderer Teil", en: "Another part")])
        }
    }

    /// The round id for this step in `topicKey` (`KasusDrillMeta.roundID`).
    nonisolated func roundID(topicKey: String) -> String { meta.roundID(topicKey: topicKey, step: self) }
}

// MARK: - Kinds

/// The steps the drill shell plays: everything but a story's worksheets and a read lesson. The
/// raw value is the step's, derived, never a second copy.
nonisolated enum KasusDrillKind: CaseIterable, Hashable, Identifiable {
    case quick, build, roles, wer, probe
    case blitz, pair, dativVerbs, fehler, reflexCase, reflexPerson, bridge
    case frage, englischeFalle, findeFall
    case tabelle

    /// The step a round of this kind records as.
    var step: KasusRoundStep {
        switch self {
        case .quick:        .quick
        case .build:        .build
        case .roles:        .roles
        case .wer:          .wer
        case .probe:        .probe
        case .blitz:        .blitz
        case .pair:         .pair
        case .dativVerbs:   .dativVerbs
        case .fehler:       .fehler
        case .reflexCase:   .reflexCase
        case .reflexPerson: .reflexPerson
        case .bridge:       .bridge
        case .frage:          .frage
        case .englischeFalle: .englischeFalle
        case .findeFall:      .findeFall
        case .tabelle:        .tabelle
        }
    }

    init?(step: KasusRoundStep) {
        guard let kind = Self.allCases.first(where: { $0.step == step }) else { return nil }
        self = kind
    }

    /// The step's raw value („quick“, „reflexcase“): what `-kasus.debugOpen <kind>:<topic>` reads.
    var rawValue: String { step.rawValue }

    init?(rawValue: String) {
        guard let step = KasusRoundStep(rawValue: rawValue), let kind = Self(step: step) else { return nil }
        self = kind
    }

    var id: String { rawValue }

    var meta: KasusDrillMeta { step.meta }
}
