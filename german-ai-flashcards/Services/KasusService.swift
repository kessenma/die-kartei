//
//  KasusService.swift
//  german-ai-flashcards
//
//  Everything between a validated Kasus story and the screens that play it, mirroring
//  `PrepositionService`'s shape (a stateless enum over the caller's `ModelContext`):
//
//    sessions      what `.kasusStory` launches: a story, its unit, gemischt or not, where to start
//    blanks        which articles Einsetzen hides, and the buttons each one offers
//    grading       first pick only; the right case for another gender is a gender slip
//    recording     `recordRound`: streak + time, one `KasusRound`, and the coach's case skills
//    progress      which steps are done, keyed on (storyID, unit, step), never on a display string
//    the path      `KasusPath.next`: the hub's "Weiter" row
//
//  The coach only hears about answers that were the learner's own work. Finden is recognition
//  and never moves a skill; Viel Hilfe never does; at Genus-Hilfe only masculine targets count
//  (the f/n/pl Akkusativ forms equal the tag); at Ohne Hilfe everything counts unless the Tipp
//  showed the case or the answer, or showed the gender of an f/n/pl Akkusativ. The Schnellrunde
//  names each noun with its article, so its f/n/pl Akkusativ answers are left out the same way.
//  Slips (right case, wrong gender or number) say nothing about the case, so they're left out,
//  and a case needs `minItemsPerCase` such answers before its skill moves at all. Nominativ has
//  no skill, so it only ever counts for the streak. The same precedent as
//  `PrepositionAnswerOutcome.scaffolded`.
//

import Foundation
import SwiftData

// MARK: - Hint level

/// The Einsetzen hint ladder. One segmented control, remembered in `kasus.hintLevel`.
enum KasusHintLevel: String, CaseIterable, Identifiable {
    /// The gender tag, the trigger underlined, and only the noun's own gender on the buttons.
    case viel
    /// The m/f/n/pl tag after the noun; the whole family on the buttons.
    case genus
    /// Nothing shown. A Tipp button reveals trigger → gender → case → answer.
    case ohne

    var id: String { rawValue }

    /// `@AppStorage` key. Empty (never set) means "follow the learner's level".
    static let storageKey = "kasus.hintLevel"

    var germanLabel: String {
        switch self {
        case .viel:  "Viel Hilfe"
        case .genus: "Genus-Hilfe"
        case .ohne:  "Ohne Hilfe"
        }
    }

    var englishLabel: String {
        switch self {
        case .viel:  "Lots of help"
        case .genus: "Gender shown"
        case .ohne:  "No hints"
        }
    }

    /// Genus-Hilfe at A1–A2, Ohne Hilfe from B1. Read from the level anchor, never written back.
    static func defaultLevel(for level: CEFRLevel) -> KasusHintLevel {
        switch level {
        case .a1, .a2:          .genus
        case .b1, .b2, .c1:     .ohne
        }
    }

    /// The stored choice, or the level's default when there is none. For a view holding
    /// `@AppStorage(KasusHintLevel.storageKey) var raw = ""`.
    static func resolve(stored raw: String, level: CEFRLevel) -> KasusHintLevel {
        KasusHintLevel(rawValue: raw) ?? defaultLevel(for: level)
    }

    static func current(level: CEFRLevel, defaults: UserDefaults = .standard) -> KasusHintLevel {
        resolve(stored: defaults.string(forKey: storageKey) ?? "", level: level)
    }

    /// "Noch mal · eine Stufe schwerer". Nil at the top.
    var harder: KasusHintLevel? {
        switch self {
        case .viel:  .genus
        case .genus: .ohne
        case .ohne:  nil
        }
    }
}

// MARK: - Steps and sessions

/// The story player's screens, in order. Only Finden and Einsetzen are scored.
enum KasusStep: String, CaseIterable, Identifiable {
    case lesen, finden, einsetzen, ergebnis

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .lesen:     "Lesen"
        case .finden:    "Finden"
        case .einsetzen: "Einsetzen"
        case .ergebnis:  "Ergebnis"
        }
    }

    var englishLabel: String {
        switch self {
        case .lesen:     "Read"
        case .finden:    "Mark the cases"
        case .einsetzen: "Fill in the articles"
        case .ergebnis:  "Result"
        }
    }

    /// What the step records as, if it records at all.
    var roundStep: KasusRoundStep? {
        switch self {
        case .finden:           .find
        case .einsetzen:        .fill
        case .lesen, .ergebnis: nil
        }
    }
}

/// The payload for launching a story via `Activity.kasusStory`.
struct KasusSession: Identifiable {
    let id = UUID()
    let storyID: String
    /// The unit the story is played in; what its rounds are filed under.
    let unit: KasusUnit
    /// "Noch mal · gemischt": Einsetzen blanks every case in play, not just the unit's own.
    var mixed: Bool = false
    var startStep: KasusStep = .lesen
    /// Set only by the DEBUG launch arguments, so a simulator that can't tap can still show a
    /// filled-in screen. Nil in every real session.
    var prefill: KasusPrefill? = nil

    var story: KasusStory? { KasusStoryBank.bundled.story(id: storyID) }
}

/// Answers and a hint level to start a screen with, for screenshots. DEBUG launch arguments only.
struct KasusPrefill: Hashable {
    enum Answers: String, Hashable {
        /// Every mark and every blank right.
        case right
        /// Roughly one in three wrong: gender slips where the form allows one, case misses,
        /// wrong brushes and misses in Finden.
        case mixed
    }

    var answers: Answers?
    var hint: KasusHintLevel?

    #if DEBUG
    /// `-kasus.debugAnswers right|mixed` and `-kasus.debugHint viel|genus|ohne`. Nil when neither
    /// is set.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> KasusPrefill? {
        let answers = defaults.string(forKey: "kasus.debugAnswers").flatMap { Answers(rawValue: $0.lowercased()) }
        let hint = defaults.string(forKey: "kasus.debugHint").flatMap { KasusHintLevel(rawValue: $0.lowercased()) }
        guard answers != nil || hint != nil else { return nil }
        return KasusPrefill(answers: answers, hint: hint)
    }
    #endif
}

/// A story validated once for a session: the located targets every step renders.
struct KasusPlayableStory {
    let story: KasusStory
    let report: KasusReport

    /// Every target found in the text, in reading order.
    var targets: [KasusLocatedTarget] { report.located }
    /// The ones Finden may mark and score.
    var gradable: [KasusLocatedTarget] { report.located.filter(\.gradable) }
}

// MARK: - Einsetzen blanks

/// One Einsetzen blank: a target's determiner, the buttons for it, and what the hint level shows.
struct KasusBlank: Identifiable, Hashable {
    let target: KasusLocatedTarget
    let hintLevel: KasusHintLevel
    /// The buttons, in the endings table's order and capitalised like the word they replace
    /// („Der“ at a sentence start). The answer is always among them.
    let options: [String]

    var id: Int { target.index }
    var kasus: GrammarCase { target.kasus }
    var genus: Gender { target.genus }
    /// The determiner as written. Grade with `KasusService.grade(_:for:)`, which ignores case.
    var answer: String { target.answer }

    /// Viel Hilfe and Genus-Hilfe: the raised m/f/n/pl tag after the noun, in `Gender.color`.
    var showsGenderTag: Bool { hintLevel != .ohne }
    /// Viel Hilfe: the trigger gets an underline (`target.triggerRange`).
    var underlinesTrigger: Bool { hintLevel == .viel }
    /// Ohne Hilfe, for a noun that reads the same in the plural (Schlüssel): a sg/pl tag, since
    /// the article is the only thing that would otherwise say which.
    var showsNumberTag: Bool { hintLevel == .ohne && target.numberAmbiguous }
    var numberTag: String { genus == .plural ? "pl" : "sg" }
}

/// How far the Ohne Hilfe Tipp button went before the first pick.
enum KasusTipp: Int, CaseIterable, Comparable, Hashable {
    case none, trigger, gender, kasus, answer

    static func < (a: KasusTipp, b: KasusTipp) -> Bool { a.rawValue < b.rawValue }

    /// The next thing a tap reveals. Nil once the answer is showing.
    var next: KasusTipp? { KasusTipp(rawValue: rawValue + 1) }

    /// Showing the case (or the answer) makes the pick scaffolded. The trigger and the gender
    /// don't: they leave the case for the learner to work out.
    var revealsCase: Bool { self >= .kasus }
}

/// What a first pick was.
enum KasusPickOutcome: Hashable {
    case right
    /// The right case for another singular gender („dem“ for „der“ in „in ___ Tasche“). Carries
    /// the gender whose form was picked, when there is one. A form the noun's own gender takes in
    /// another case („der“ for „dem Boden“) is a case miss, never a slip.
    case genderSlip(Gender?)
    /// The right case in the plural, on a noun that reads the same in the plural („die“ for
    /// „den“ in „nimmt ___ Schlüssel“).
    case numberSlip
    case caseMiss

    var isRight: Bool { self == .right }
    var isGenderSlip: Bool {
        if case .genderSlip = self { return true }
        return false
    }
    /// Right case, wrong gender or number: it says nothing about the case.
    var isSlip: Bool { isGenderSlip || self == .numberSlip }
}

// MARK: - Finden marks

/// A gradable target after Prüfen.
enum KasusFindMark: Hashable {
    /// Painted with its own case's brush.
    case right
    /// Painted with another brush, or painted at all when its case has no brush in this unit
    /// (so painting everything never scores 100%).
    case wrongPick(painted: GrammarCase)
    /// Its case has a brush, and it wasn't painted.
    case missed
}

// MARK: - Round results

/// One answer, as `recordRound` needs it.
struct KasusItemResult: Hashable {
    let kasus: GrammarCase
    let genus: Gender
    /// Right on the first pick (Einsetzen, Schnellrunde) or painted with the right brush (Finden).
    let firstTry: Bool
    /// Right case, wrong gender (or wrong number on a noun like Schlüssel). Practice for the
    /// streak, but it says nothing about the case.
    var slip: Bool = false
    /// How far the Tipp went before the first pick (Ohne Hilfe only).
    var tipp: KasusTipp = .none
    /// The story target, for "misses in their sentences". Nil for Schnellrunde items.
    var targetIndex: Int? = nil
}

/// A finished Finden, Einsetzen or Schnellrunde, handed to `KasusService.recordRound`.
struct KasusRoundResult {
    /// The story's id, or `KasusService.quickRoundID(for:)` for a Schnellrunde.
    let storyID: String
    let unit: KasusUnit
    let step: KasusRoundStep
    /// Einsetzen only.
    var hintLevel: KasusHintLevel? = nil
    let items: [KasusItemResult]
    let durationSeconds: Int
    /// Finden only: how many phrases were painted. The unpainted ones are in `items` (as missed)
    /// for the score, but nobody answered them.
    var paintedCount: Int? = nil

    var askedCount: Int { items.count }
    /// What the streak and XP count: every answer, but in Finden only the painted phrases.
    var answeredCount: Int { paintedCount ?? items.count }
    var firstTryCount: Int { items.filter(\.firstTry).count }
    var score: Double { items.isEmpty ? 0 : Double(firstTryCount) / Double(items.count) }

    var perCase: [GrammarCase: KasusRound.CaseTally] {
        items.reduce(into: [:]) { tally, item in
            tally[item.kasus, default: .init()].asked += 1
            if item.firstTry { tally[item.kasus, default: .init()].firstTry += 1 }
        }
    }
}

/// One `applyDrillResult` call `recordRound` made.
struct KasusSkillMove: Hashable {
    let focus: GrammarFocus
    let correct: Int
    let total: Int
}

// MARK: - Service

enum KasusService {

    /// A case needs at least this many answers that count before its coach skill moves, so one
    /// lucky or unlucky Genitiv can't swing it.
    static let minItemsPerCase = 3

    /// Ergebnis offers "Noch mal · eine Stufe schwerer" at or above this first-try share.
    static let harderThreshold = 0.8

    /// Finden's note for a tap on a word that isn't a target. Always true, whatever was tapped.
    static let nonTargetNote = "Only article + noun phrases count here: der, ein, mein, kein … with their noun."

    /// The storyID a Schnellrunde is filed under: "quick-dativ".
    static func quickRoundID(for unit: KasusUnit) -> String {
        "quick-\(unit.rawValue)"
    }

    // MARK: Preparing a story

    /// Validates the story once for a session. A few milliseconds; the Goethe map is built on
    /// first use.
    static func prepare(_ story: KasusStory) -> KasusPlayableStory {
        prepare(story, lexicon: AppKasusLexicon())
    }

    static func prepare(_ story: KasusStory, lexicon: some KasusLexicon) -> KasusPlayableStory {
        KasusPlayableStory(story: story,
                           report: KasusValidator.validate(story, source: story.source, lexicon: lexicon))
    }

    static func prepare(_ session: KasusSession) -> KasusPlayableStory? {
        session.story.map { prepare($0) }
    }

    // MARK: Finden

    /// How many targets each brush has to find: the instruction's count per brush.
    static func findCounts(in playable: KasusPlayableStory, unit: KasusUnit) -> [GrammarCase: Int] {
        let brushes = Set(unit.findenBrushes)
        return playable.gradable.reduce(into: [:]) { counts, target in
            if brushes.contains(target.kasus) { counts[target.kasus, default: 0] += 1 }
        }
    }

    /// Prüfen. `paint` maps a target index to the brush it was painted with. Targets whose case
    /// has no brush and weren't painted aren't part of the check, so they get no mark.
    static func gradeFind(paint: [Int: GrammarCase], in playable: KasusPlayableStory,
                          unit: KasusUnit) -> [Int: KasusFindMark] {
        let brushes = Set(unit.findenBrushes)
        var marks: [Int: KasusFindMark] = [:]
        for target in playable.gradable {
            let painted = paint[target.index]
            if brushes.contains(target.kasus) {
                if let painted {
                    marks[target.index] = painted == target.kasus ? .right : .wrongPick(painted: painted)
                } else {
                    marks[target.index] = .missed
                }
            } else if let painted {
                marks[target.index] = .wrongPick(painted: painted)
            }
        }
        return marks
    }

    /// Finden's round, for `recordRound`. Every marked target is one item under its true case;
    /// only the painted ones count as answered.
    static func findResult(storyID: String, unit: KasusUnit, marks: [Int: KasusFindMark],
                           in playable: KasusPlayableStory, durationSeconds: Int) -> KasusRoundResult {
        let items = playable.gradable.compactMap { target -> KasusItemResult? in
            guard let mark = marks[target.index] else { return nil }
            return KasusItemResult(kasus: target.kasus, genus: target.genus, firstTry: mark == .right,
                                   targetIndex: target.index)
        }
        return KasusRoundResult(storyID: storyID, unit: unit, step: .find, items: items,
                                durationSeconds: durationSeconds,
                                paintedCount: marks.values.filter { $0 != .missed }.count)
    }

    // MARK: Einsetzen

    /// The cases Einsetzen blanks. The unit's own case, or every case in play when gemischt (and
    /// for Alle Fälle, which has no single case). Nominativ only at Ohne Hilfe: with a gender tag
    /// showing, the Nominativ form *is* the tag.
    static func blankCases(unit: KasusUnit, mixed: Bool, hint: KasusHintLevel) -> Set<GrammarCase> {
        var cases: Set<GrammarCase>
        if !mixed, let focus = unit.focusCase {
            cases = [focus]
        } else {
            cases = Set(unit.casesInPlay)
        }
        if hint != .ohne { cases.remove(.nominativ) }
        return cases
    }

    /// The hint level Einsetzen actually runs at. Only the Nominativ unit (not gemischt) changes
    /// it: its blanks are all Nominativ, which only Ohne Hilfe may ask, so it runs there.
    static func effectiveHintLevel(_ preferred: KasusHintLevel, unit: KasusUnit, mixed: Bool) -> KasusHintLevel {
        blankCases(unit: unit, mixed: mixed, hint: preferred).isEmpty ? .ohne : preferred
    }

    /// The levels worth offering in the segmented control for this unit.
    static func availableHintLevels(unit: KasusUnit, mixed: Bool) -> [KasusHintLevel] {
        KasusHintLevel.allCases.filter { !blankCases(unit: unit, mixed: mixed, hint: $0).isEmpty }
    }

    /// Einsetzen's blanks, in reading order. Every other article stays visible as a model.
    /// Only blankable targets with a parsed determiner: pronouns and contractions never.
    static func blanks(in playable: KasusPlayableStory, unit: KasusUnit, mixed: Bool,
                       hint: KasusHintLevel) -> [KasusBlank] {
        let cases = blankCases(unit: unit, mixed: mixed, hint: hint)
        let includeGenitive = unit.casesInPlay.contains(.genitiv)
        return playable.targets
            .filter { $0.blankable && $0.parsed != nil && cases.contains($0.kasus) }
            .map { target in
                KasusBlank(target: target, hintLevel: hint,
                           options: options(for: target, hint: hint, includeGenitive: includeGenitive))
            }
    }

    static func blanks(in playable: KasusPlayableStory, session: KasusSession,
                       hint: KasusHintLevel) -> [KasusBlank] {
        blanks(in: playable, unit: session.unit, mixed: session.mixed, hint: hint)
    }

    /// The buttons for one blank. Viel Hilfe: the noun's own gender through the cases in play,
    /// plus one other-gender form when that leaves fewer than three. Genus-Hilfe and Ohne Hilfe:
    /// the whole family, des/eines only once Genitiv is in play. Always in table order, so the
    /// answer's place never gives it away.
    static func options(for target: KasusLocatedTarget, hint: KasusHintLevel, includeGenitive: Bool) -> [String] {
        guard let parsed = target.parsed else { return [] }
        let full = KasusForms.fullFamilyOptions(family: parsed.family, stem: parsed.stem,
                                                includeGenitive: includeGenitive)
        var forms: [String]
        switch hint {
        case .viel:
            let viel = KasusForms.vielHilfeOptions(answer: target.answer, family: parsed.family,
                                                   stem: parsed.stem, genus: target.genus,
                                                   includeGenitive: includeGenitive)
            forms = full.filter(viel.contains) + viel.filter { !full.contains($0) }
        case .genus, .ohne:
            forms = full
        }
        let answer = target.answer.lowercased()
        if !forms.contains(answer) { forms.append(answer) }
        return forms.map { KasusForms.matchingCapitalization($0, like: target.determiner) }
    }

    // MARK: Grading

    /// First pick only, ignoring case. A wrong pick that is the right case for another singular
    /// gender is a gender slip, and the plural of the right case on a noun like Schlüssel is a
    /// number slip; neither is a case miss. Anything the noun's own gender takes in another case
    /// is a case miss.
    static func grade(_ pick: String, for target: KasusLocatedTarget) -> KasusPickOutcome {
        if pick.caseInsensitiveCompare(target.answer) == .orderedSame { return .right }
        guard let parsed = target.parsed else { return .caseMiss }
        if target.numberAmbiguous,
           KasusForms.isRightCaseWrongNumber(pick: pick, answerCase: target.kasus, genus: target.genus,
                                             family: parsed.family, stem: parsed.stem) {
            return .numberSlip
        }
        if KasusForms.isRightCaseWrongGender(pick: pick, answerCase: target.kasus, genus: target.genus,
                                             family: parsed.family, stem: parsed.stem) {
            return .genderSlip(KasusForms.genderOfSlip(pick: pick, kasus: target.kasus, genus: target.genus,
                                                       family: parsed.family, stem: parsed.stem))
        }
        return .caseMiss
    }

    static func grade(_ pick: String, for blank: KasusBlank) -> KasusPickOutcome {
        grade(pick, for: blank.target)
    }

    /// Einsetzen's round, for `recordRound`. `picks` holds each blank's first pick; a blank with
    /// no pick is left out. `tipps` is how far the Tipp went on each (Ohne Hilfe).
    static func fillResult(storyID: String, unit: KasusUnit, hint: KasusHintLevel, blanks: [KasusBlank],
                           picks: [Int: String], tipps: [Int: KasusTipp] = [:],
                           durationSeconds: Int) -> KasusRoundResult {
        let items = blanks.compactMap { blank -> KasusItemResult? in
            guard let pick = picks[blank.id] else { return nil }
            let outcome = grade(pick, for: blank)
            return KasusItemResult(kasus: blank.kasus, genus: blank.genus, firstTry: outcome.isRight,
                                   slip: outcome.isSlip, tipp: tipps[blank.id] ?? .none,
                                   targetIndex: blank.id)
        }
        return KasusRoundResult(storyID: storyID, unit: unit, step: .fill, hintLevel: hint, items: items,
                                durationSeconds: durationSeconds)
    }

    /// A Schnellrunde, for `recordRound`. The drill never shows the case, but it names the noun
    /// with its article, so `countsTowardSkill` leaves its f/n/pl Akkusativ answers out.
    static func quickResult(unit: KasusUnit, items: [KasusItemResult], durationSeconds: Int) -> KasusRoundResult {
        KasusRoundResult(storyID: quickRoundID(for: unit), unit: unit, step: .quick, items: items,
                         durationSeconds: durationSeconds)
    }

    /// Whether Ergebnis offers "eine Stufe schwerer".
    static func offersHarder(_ result: KasusRoundResult) -> Bool {
        result.step == .fill && result.hintLevel?.harder != nil && result.score >= harderThreshold
    }

    // MARK: Explanations

    /// The why behind a target's case, in Kasus-Check order, ending on the code-word letter.
    static func explanation(for target: KasusLocatedTarget, in story: KasusStory) -> String {
        KasusExplanation.explanation(for: target, in: story)
    }

    /// What Einsetzen says after a wrong first pick: the slip note for a gender or number slip,
    /// the full explanation for a case miss.
    static func feedback(for outcome: KasusPickOutcome, pick: String, target: KasusLocatedTarget,
                         in story: KasusStory) -> String? {
        switch outcome {
        case .right:
            return nil
        case .genderSlip:
            return KasusExplanation.genderSlipNote(pick: pick, answer: target.answer, genus: target.genus,
                                                   kasus: target.kasus)
        case .numberSlip:
            return KasusExplanation.numberSlipNote(pick: pick, answer: target.answer, kasus: target.kasus,
                                                   noun: target.noun)
        case .caseMiss:
            return explanation(for: target, in: story)
        }
    }

    /// Finden's note for a target only its role decides („By its form, seine could be …“).
    static func ambiguityNote(for target: KasusLocatedTarget) -> String? {
        KasusExplanation.ambiguityNote(for: target)
    }

    // MARK: Recording

    /// Whether one answer may move the coach's case skill. See the header for the rules.
    static func countsTowardSkill(_ item: KasusItemResult, step: KasusRoundStep, hint: KasusHintLevel?) -> Bool {
        guard item.kasus.focus != nil, !item.slip else { return false }
        // The f/n/pl Akkusativ is the dictionary form (die Katze · die Katze), so once the gender
        // is on screen, so is the answer.
        let genderGivesItAway = item.kasus == .akkusativ && item.genus != .der
        switch step {
        case .find:
            return false
        case .quick:
            // The drill names the noun with its article („Noun: die Katze“).
            return !genderGivesItAway
        case .fill:
            switch hint {
            case .viel?, nil: return false
            case .genus?:     return item.genus == .der
            case .ohne?:      return !item.tipp.revealsCase && !(item.tipp >= .gender && genderGivesItAway)
            }
        }
    }

    /// The `applyDrillResult` calls a result earns: one per case, over the answers that count,
    /// only for a case with at least `minItemsPerCase` of them. In table order.
    static func skillMoves(for result: KasusRoundResult) -> [KasusSkillMove] {
        let counting = result.items.filter { countsTowardSkill($0, step: result.step, hint: result.hintLevel) }
        return GrammarCase.allCases.compactMap { kasus in
            guard let focus = kasus.focus else { return nil }
            let rows = counting.filter { $0.kasus == kasus }
            guard rows.count >= minItemsPerCase else { return nil }
            return KasusSkillMove(focus: focus, correct: rows.filter(\.firstTry).count, total: rows.count)
        }
    }

    /// Fold one finished step in: the streak, time and XP (every answer is practice, however much
    /// help was on screen; in Finden only the painted phrases were answered), one `KasusRound` for
    /// the calendar and the step marks, and the coach's case skills from the answers that count.
    /// Returns the skill moves it made.
    @discardableResult
    static func recordRound(_ result: KasusRoundResult, in context: ModelContext) -> [KasusSkillMove] {
        guard !result.items.isEmpty else { return [] }

        StudyLogService.record(.grammar(result.answeredCount), seconds: result.durationSeconds, in: context)

        context.insert(KasusRound(
            storyID: result.storyID,
            unitRaw: result.unit.rawValue,
            stepRaw: result.step.rawValue,
            hintLevelRaw: result.hintLevel?.rawValue ?? "",
            askedCount: result.askedCount,
            firstTryCount: result.firstTryCount,
            durationSeconds: result.durationSeconds,
            perCase: result.perCase
        ))

        let moves = skillMoves(for: result)
        for move in moves {
            LearnerMemoryService.applyDrillResult(focus: move.focus, correct: move.correct,
                                                  total: move.total, in: context)
        }

        try? context.save()
        return moves
    }

    // MARK: Progress

    static func progress(in context: ModelContext) -> KasusProgress {
        KasusProgress(rounds: (try? context.fetch(FetchDescriptor<KasusRound>())) ?? [])
    }

    // MARK: DEBUG

    #if DEBUG
    /// First picks for `-kasus.debugAnswers`: all right, or about one in three wrong (a gender
    /// slip where the form has one, otherwise a case miss).
    static func debugPicks(for blanks: [KasusBlank], answers: KasusPrefill.Answers) -> [Int: String] {
        var picks: [Int: String] = [:]
        for (i, blank) in blanks.enumerated() {
            guard answers == .mixed, i % 3 == 1 else {
                picks[blank.id] = blank.answer
                continue
            }
            let wrong = blank.options.filter { grade($0, for: blank) != .right }
            let slip = wrong.first { grade($0, for: blank).isSlip }
            let miss = wrong.first { grade($0, for: blank) == .caseMiss }
            picks[blank.id] = (i % 2 == 1 ? slip ?? miss : miss ?? slip) ?? blank.answer
        }
        return picks
    }

    /// Paint for `-kasus.debugAnswers` in Finden: every brush-case target right, or with one in
    /// four missed and one in five on the wrong brush.
    static func debugPaint(in playable: KasusPlayableStory, unit: KasusUnit,
                           answers: KasusPrefill.Answers) -> [Int: GrammarCase] {
        let brushes = unit.findenBrushes
        var paint: [Int: GrammarCase] = [:]
        for (i, target) in playable.gradable.filter({ brushes.contains($0.kasus) }).enumerated() {
            if answers == .mixed, i % 4 == 3 { continue }
            if answers == .mixed, i % 5 == 2, let other = brushes.first(where: { $0 != target.kasus }) {
                paint[target.index] = other
            } else {
                paint[target.index] = target.kasus
            }
        }
        return paint
    }

    /// `-kasus.debugVerify 1`, after the validator's report: the service rules on the bundled
    /// Dativ story (blanks per hint level, options, grading) and `KasusPath.next` over synthetic
    /// history. Nothing is written; the rounds and the profile are never inserted.
    static func debugServiceReport() -> [String] {
        var lines: [String] = []
        var failures = 0
        func check(_ label: String, _ actual: String, _ expected: String) {
            let ok = actual == expected
            if !ok { failures += 1 }
            lines.append("  \(ok ? "PASS" : "FAIL")  \(label): \(actual)\(ok ? "" : " (expected \(expected))")")
        }
        func tally(_ blanks: [KasusBlank]) -> String {
            let counts = blanks.reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
            return GrammarCase.allCases.compactMap { kasus in counts[kasus].map { "\(kasus.short) \($0)" } }
                .joined(separator: " · ")
        }

        let bank = KasusStoryBank.bundled
        guard let story = bank.story(id: "ks-dat-a2-schluessel") else {
            return ["Service: the bundled Dativ story is missing", "1 FAILED"]
        }
        let playable = prepare(story)
        lines.append("Service · \(story.id)")

        check("blanks Viel Hilfe", tally(blanks(in: playable, unit: .dativ, mixed: false, hint: .viel)), "Dat 9")
        check("blanks Genus-Hilfe", tally(blanks(in: playable, unit: .dativ, mixed: false, hint: .genus)), "Dat 9")
        check("blanks Ohne Hilfe", tally(blanks(in: playable, unit: .dativ, mixed: false, hint: .ohne)), "Dat 9")
        check("blanks gemischt, Genus-Hilfe", tally(blanks(in: playable, unit: .dativ, mixed: true, hint: .genus)), "Akk 11 · Dat 9")
        check("blanks gemischt, Ohne Hilfe", tally(blanks(in: playable, unit: .dativ, mixed: true, hint: .ohne)), "Nom 6 · Akk 11 · Dat 9")
        check("Nominativ unit's hint levels", availableHintLevels(unit: .nominativ, mixed: false).map(\.rawValue).joined(separator: ", "), "ohne")

        let ohne = blanks(in: playable, unit: .dativ, mixed: true, hint: .ohne)
        lines.append("  sg/pl tags at Ohne Hilfe: " + ohne.filter(\.showsNumberTag).map { "\($0.target.surface) (\($0.numberTag))" }.joined(separator: ", "))
        func graded(_ pick: String, _ blank: KasusBlank) -> String {
            switch grade(pick, for: blank) {
            case .right:                 "right"
            case .genderSlip(let other): "gender slip (\(other?.columnLabel ?? "?"))"
            case .numberSlip:            "number slip"
            case .caseMiss:              "case miss"
            }
        }
        if let boden = ohne.first(where: { $0.target.noun == "Boden" }) {
            for hint in KasusHintLevel.allCases {
                let options = self.options(for: boden.target, hint: hint, includeGenitive: false)
                lines.append("  options „\(boden.target.surface)“ \(hint.germanLabel): \(options.joined(separator: " · "))")
            }
            check("grade „dem“ on „dem Boden“", graded("dem", boden), "right")
            check("grade „Dem“ on „dem Boden“", graded("Dem", boden), "right")
            // The Nominativ left unchanged is a case miss, even though „der“ is also feminine Dativ.
            check("grade „der“ on „dem Boden“", graded("der", boden), "case miss")
            check("grade „den“ on „dem Boden“", graded("den", boden), "case miss")
            // Böden: the plural differs, and a Dativ plural would add -n anyway.
            check("sg/pl tag on „dem Boden“", boden.showsNumberTag ? "shown" : "none", "none")
        } else {
            failures += 1
            lines.append("  FAIL  no „dem Boden“ blank")
        }
        if let tasche = ohne.first(where: { $0.target.surface == "der Tasche" }) {
            check("grade „dem“ on „der Tasche“", graded("dem", tasche), "gender slip (m)")
            check("grade „die“ on „der Tasche“", graded("die", tasche), "case miss")
            lines.append("  gender slip note: " + (feedback(for: grade("dem", for: tasche), pick: "dem", target: tasche.target, in: story) ?? ""))
        } else {
            failures += 1
            lines.append("  FAIL  no „der Tasche“ blank")
        }
        if let key = ohne.first(where: { $0.target.surface == "den Schlüssel" }) {
            check("sg/pl tag on „den Schlüssel“", key.showsNumberTag ? "shown" : "none", "shown")
            check("grade „die“ on „den Schlüssel“", graded("die", key), "number slip")
            check("grade „der“ on „den Schlüssel“", graded("der", key), "case miss")
            check("grade „das“ on „den Schlüssel“", graded("das", key), "gender slip (n)")
            lines.append("  number slip note: " + (feedback(for: grade("die", for: key), pick: "die", target: key.target, in: story) ?? ""))
        } else {
            failures += 1
            lines.append("  FAIL  no „den Schlüssel“ blank")
        }
        if let key = ohne.first(where: { $0.target.surface == "dem Schlüssel" }) {
            check("sg/pl tag on „dem Schlüssel“ (Dativ plural adds -n)", key.showsNumberTag ? "shown" : "none", "none")
        }
        if let first = ohne.first(where: { $0.target.determiner.first?.isUppercase == true }) {
            lines.append("  capitalised „\(first.target.surface)“: \(first.options.joined(separator: " · "))")
        }

        check("hint default A1", KasusHintLevel.defaultLevel(for: .a1).rawValue, "genus")
        check("hint default A2", KasusHintLevel.defaultLevel(for: .a2).rawValue, "genus")
        check("hint default B1", KasusHintLevel.defaultLevel(for: .b1).rawValue, "ohne")

        // KasusPath over synthetic, never-inserted history.
        func played(_ steps: [(String, KasusUnit, KasusRoundStep)], daysAgo: Double = 1) -> [KasusRound] {
            steps.map { KasusRound(storyID: $0.0, unitRaw: $0.1.rawValue, stepRaw: $0.2.rawValue,
                                   askedCount: 1, firstTryCount: 1, durationSeconds: 0,
                                   date: Date().addingTimeInterval(-daysAgo * 86_400)) }
        }
        func describe(_ hero: KasusHero) -> String { "\(hero.unit.rawValue) · \(hero.subtitle)" }
        let none: [KasusRound] = []
        check("hero A1, nothing played", describe(KasusPath.next(profile: nil, level: .a1, rounds: none, bank: bank)),
              "dativ · „\(story.title)“ · Lesen")
        let findOnly = played([(story.id, .dativ, .find)])
        check("hero B1, Finden played", describe(KasusPath.next(profile: nil, level: .b1, rounds: findOnly, bank: bank)),
              "dativ · „\(story.title)“ · Einsetzen")
        // Akkusativ has no story yet, so its Schnellrunde is the first unfinished step from A2.
        check("hero A2, Finden played", describe(KasusPath.next(profile: nil, level: .a2, rounds: findOnly, bank: bank)),
              "akkusativ · Schnellrunde · Nom + Akk")
        let storyDone = played([(story.id, .dativ, .find), (story.id, .dativ, .fill)])
        check("hero A2, story done", describe(KasusPath.next(profile: nil, level: .a2, rounds: storyDone, bank: bank)),
              "akkusativ · Schnellrunde · Nom + Akk")
        check("hero B1, story done", describe(KasusPath.next(profile: nil, level: .b1, rounds: storyDone, bank: bank)),
              "dativ · Schnellrunde · Nom + Akk + Dat")
        let everything = storyDone + played(KasusUnit.allCases.map { (quickRoundID(for: $0), $0, .quick) })
        check("hero B1, all done", describe(KasusPath.next(profile: nil, level: .b1, rounds: everything, bank: bank)),
              "dativ · Wiederholen · „\(story.title)“")
        let shaky = LearnerProfile()
        shaky.grammar = [GrammarFocus.dativ.rawValue: GrammarSkill(struggle: 0.6, lastSeen: Date(), samples: [])]
        check("hero, Dativ shaky, all done", describe(KasusPath.next(profile: shaky, level: .b1, rounds: everything, bank: bank)),
              "dativ · „\(story.title)“ · Einsetzen")

        lines.append(failures == 0 ? "Service ALL OK" : "Service \(failures) FAILED")
        return lines
    }

    /// The storyID the record check files its rounds under. No real story or unit key, so a kept
    /// run never marks a step done or changes the hub's pick.
    static let debugVerifyStoryID = "debug-verify-record"

    /// `-kasus.debugVerifyRecord 1`: runs `recordRound` on synthetic rounds in the live store and
    /// checks each one against the rules: every round adds its answered items to today's
    /// `grammarExercises` and one `KasusRound`, and only the last two may move a case skill.
    /// Afterwards the coach's skills, the rounds and the day's count are put back, unless the
    /// argument is `keep`. Returns printable lines; the caller adds the prefix.
    static func debugVerifyRecord(in context: ModelContext, keep: Bool) -> [String] {
        let profile = LearnerMemoryService.profile(in: context)
        let savedGrammar = profile.grammar
        let dayStart = Calendar.current.startOfDay(for: Date())
        let watched: [GrammarFocus] = [.akkusativ, .dativ, .genitiv]

        func grammarExercises() -> Int {
            let day = (try? context.fetch(FetchDescriptor<StudyDay>(
                predicate: #Predicate<StudyDay> { $0.dayStart == dayStart }
            )))?.first
            return day?.grammarExercises ?? 0
        }
        func roundCount() -> Int { (try? context.fetchCount(FetchDescriptor<KasusRound>())) ?? 0 }
        func struggle(_ focus: GrammarFocus) -> Double? { profile.grammar[focus.rawValue]?.struggle }
        func show(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }
        func item(_ kasus: GrammarCase, _ genus: Gender, _ right: Bool,
                  slip: Bool = false, tipp: KasusTipp = .none) -> KasusItemResult {
            KasusItemResult(kasus: kasus, genus: genus, firstTry: right, slip: slip, tipp: tipp)
        }
        func round(_ step: KasusRoundStep, _ unit: KasusUnit, _ hint: KasusHintLevel?,
                   _ items: [KasusItemResult], painted: Int? = nil) -> KasusRoundResult {
            KasusRoundResult(storyID: debugVerifyStoryID, unit: unit, step: step, hintLevel: hint,
                             items: items, durationSeconds: 0, paintedCount: painted)
        }
        // The two rounds that should move a skill push it whichever way it has room to go, so the
        // change always shows: all wrong raises struggle, all right lowers it.
        let datRight = (struggle(.dativ) ?? 0) >= 0.8
        let akkRight = (struggle(.akkusativ) ?? 0) >= 0.8

        let scenarios: [(name: String, result: KasusRoundResult, moves: Set<GrammarFocus>)] = [
            ("Viel Hilfe · 5 Akk m, all wrong (scaffolded)",
             round(.fill, .akkusativ, .viel, Array(repeating: item(.akkusativ, .der, false), count: 5)), []),
            ("Ohne Hilfe · 2 Dat, both wrong (under 3)",
             round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .die, false), count: 2)), []),
            ("Genus-Hilfe · 5 Akk f/n/pl, all wrong (the tag gives them away)",
             round(.fill, .akkusativ, .genus, [.die, .das, .plural, .die, .das].map { item(.akkusativ, $0, false) }), []),
            ("Ohne Hilfe · 4 Akk m, Tipp showed the case or answer, all wrong",
             round(.fill, .akkusativ, .ohne, [KasusTipp.kasus, .answer, .kasus, .answer].map {
                 item(.akkusativ, .der, false, tipp: $0)
             }), []),
            ("Ohne Hilfe · 4 Dat gender slips",
             round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .die, false, slip: true), count: 4)), []),
            ("Ohne Hilfe · 4 Akk f/n/pl, Tipp showed the gender, all wrong (the tag gives them away)",
             round(.fill, .akkusativ, .ohne, [.die, .das, .plural, .die].map {
                 item(.akkusativ, $0, false, tipp: .gender)
             }), []),
            ("Schnellrunde · 6 Nom, all wrong (Nominativ has no skill)",
             round(.quick, .nominativ, nil, Array(repeating: item(.nominativ, .der, false), count: 6)), []),
            ("Schnellrunde · 4 Akk f/n/pl, all wrong (the header names the article)",
             round(.quick, .akkusativ, nil, [.die, .das, .plural, .die].map { item(.akkusativ, $0, false) }), []),
            ("Schnellrunde · 4 Dat gender slips",
             round(.quick, .dativ, nil, Array(repeating: item(.dativ, .die, false, slip: true), count: 4)), []),
            ("Finden · 6 Akk + 6 Dat marked, 5 painted, all wrong (recognition only; 5 answered)",
             round(.find, .dativ, nil, Array(repeating: item(.akkusativ, .der, false), count: 6)
                   + Array(repeating: item(.dativ, .der, false), count: 6), painted: 5), []),
            ("Ohne Hilfe · 4 Dat \(datRight ? "right" : "wrong") + 2 Nom → moves Dativ",
             round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .die, datRight), count: 4)
                   + Array(repeating: item(.nominativ, .die, false), count: 2)), [.dativ]),
            ("Genus-Hilfe · 3 Akk m \(akkRight ? "right" : "wrong") + 3 Akk f → moves Akkusativ (m only, exactly 3)",
             round(.fill, .akkusativ, .genus, Array(repeating: item(.akkusativ, .der, akkRight), count: 3)
                   + Array(repeating: item(.akkusativ, .die, !akkRight), count: 3)), [.akkusativ]),
        ]

        var lines: [String] = []
        var failures = 0
        var asked = 0
        for (i, scenario) in scenarios.enumerated() {
            let exercisesBefore = grammarExercises(), roundsBefore = roundCount()
            let before: [GrammarFocus: Double] = watched.reduce(into: [:]) { $0[$1] = struggle($1) }

            let moves = recordRound(scenario.result, in: context)
            asked += scenario.result.answeredCount

            let exercisesDelta = grammarExercises() - exercisesBefore
            let roundsDelta = roundCount() - roundsBefore
            var problems: [String] = []
            if exercisesDelta != scenario.result.answeredCount {
                problems.append("grammarExercises +\(exercisesDelta), expected +\(scenario.result.answeredCount)")
            }
            if roundsDelta != 1 { problems.append("KasusRound +\(roundsDelta), expected +1") }
            let called = Set(moves.map(\.focus))
            if called != scenario.moves {
                problems.append("applyDrillResult for [\(called.map(\.rawValue).sorted().joined(separator: ", "))]")
            }
            var skills: [String] = []
            for focus in watched {
                let after = struggle(focus)
                let moved = after != before[focus]
                skills.append("\(focus.rawValue.prefix(3)) \(show(before[focus]))→\(show(after))")
                if moved != scenario.moves.contains(focus) {
                    problems.append("\(focus.rawValue) \(moved ? "moved" : "didn't move")")
                }
            }
            if profile.grammar.keys.contains(GrammarCase.nominativ.rawValue) {
                problems.append("a nominativ skill key exists")
            }
            failures += problems.isEmpty ? 0 : 1
            lines.append("#\(i + 1) \(scenario.name)")
            lines.append("   grammarExercises +\(exercisesDelta) · KasusRound +\(roundsDelta) · "
                         + skills.joined(separator: " · ") + " · "
                         + (problems.isEmpty ? "PASS" : "FAIL: " + problems.joined(separator: "; ")))
        }
        lines.append(failures == 0 ? "ALL OK · \(scenarios.count) rounds" : "\(failures) of \(scenarios.count) FAILED")

        if keep {
            lines.append("kept: \(scenarios.count) rounds under \(debugVerifyStoryID), +\(asked) grammarExercises, the skill changes")
        } else {
            profile.grammar = savedGrammar
            let debugID = debugVerifyStoryID
            let rounds = (try? context.fetch(FetchDescriptor<KasusRound>(
                predicate: #Predicate<KasusRound> { $0.storyID == debugID }
            ))) ?? []
            for row in rounds { context.delete(row) }
            if let day = (try? context.fetch(FetchDescriptor<StudyDay>(
                predicate: #Predicate<StudyDay> { $0.dayStart == dayStart }
            )))?.first {
                day.grammarExercises = max(0, day.grammarExercises - asked)
            }
            try? context.save()
            lines.append("restored: coach skills, \(rounds.count) rounds removed, grammarExercises −\(asked)")
        }
        return lines
    }
    #endif
}

// MARK: - Progress

/// Which steps are done and when each was last played, read from `KasusRound` history. Keyed on
/// (storyID, unit, step), never on a display string. Played at all counts as done: the marks say
/// "you've been here", and the Ergebnis is where the score lives.
struct KasusProgress {
    private struct Key: Hashable {
        let storyID: String
        let unitRaw: String
        let stepRaw: String
    }

    private var latest: [Key: Date] = [:]

    init(rounds: [KasusRound]) {
        for round in rounds {
            let key = Key(storyID: round.storyID, unitRaw: round.unitRaw, stepRaw: round.stepRaw)
            if let seen = latest[key], seen >= round.date { continue }
            latest[key] = round.date
        }
    }

    func isDone(storyID: String, unit: KasusUnit, step: KasusRoundStep) -> Bool {
        lastPlayed(storyID: storyID, unit: unit, step: step) != nil
    }

    func lastPlayed(storyID: String, unit: KasusUnit, step: KasusRoundStep) -> Date? {
        latest[Key(storyID: storyID, unitRaw: unit.rawValue, stepRaw: step.rawValue)]
    }

    /// The last Finden or Einsetzen of a story. Nil when it was never played.
    func lastPlayed(storyID: String, unit: KasusUnit) -> Date? {
        [KasusRoundStep.find, .fill].compactMap { lastPlayed(storyID: storyID, unit: unit, step: $0) }.max()
    }

    func isDone(_ story: KasusStory, step: KasusRoundStep) -> Bool {
        guard let unit = story.unit else { return false }
        return isDone(storyID: story.id, unit: unit, step: step)
    }

    func lastPlayed(_ story: KasusStory) -> Date? {
        guard let unit = story.unit else { return nil }
        return lastPlayed(storyID: story.id, unit: unit)
    }

    /// Finden and Einsetzen both played: the story's dot fills.
    func isFinished(_ story: KasusStory) -> Bool {
        isDone(story, step: .find) && isDone(story, step: .fill)
    }

    func quickRoundDone(_ unit: KasusUnit) -> Bool {
        isDone(storyID: KasusService.quickRoundID(for: unit), unit: unit, step: .quick)
    }
}

// MARK: - The path

/// The hub's "Weiter · Up next" row. Derived on every render, never stored.
struct KasusHero: Hashable {
    enum Action: Hashable {
        /// Play a story, starting at this step.
        case story(storyID: String, step: KasusStep)
        /// The unit's Schnellrunde.
        case quickRound
    }

    enum Reason: Hashable {
        /// Rule 1: the coach counts this case as shaky.
        case shaky(GrammarFocus)
        /// Rule 2: a story not played yet.
        case newStory
        /// Rule 3: the first unfinished step from the start unit on.
        case nextStep
        /// Rule 4: everything's done; the story played longest ago.
        case review
    }

    let unit: KasusUnit
    let action: Action
    let reason: Reason
    /// The story's title, for a story action.
    let storyTitle: String?

    var storyID: String? {
        if case .story(let id, _) = action { return id }
        return nil
    }

    var step: KasusStep? {
        if case .story(_, let step) = action { return step }
        return nil
    }

    /// „Der verlorene Schlüssel“ · Einsetzen, Wiederholen · „Der verlorene Schlüssel“, or
    /// Schnellrunde · Nom + Akk + Dat.
    var subtitle: String {
        switch action {
        case .story(_, let step):
            let title = "„\(storyTitle ?? unit.germanTitle)“"
            return reason == .review ? "Wiederholen · \(title)" : "\(title) · \(step.germanLabel)"
        case .quickRound:
            return "Schnellrunde · \(unit.casesInPlay.map(\.short).joined(separator: " + "))"
        }
    }

    /// What to launch for a story action.
    var storySession: KasusSession? {
        guard case .story(let id, let step) = action else { return nil }
        return KasusSession(storyID: id, unit: unit, startStep: step)
    }

    /// What to launch for a Schnellrunde action.
    var quickRoundSession: CaseEndingsSession { CaseEndingsSession(unit: unit) }
}

enum KasusPath {

    /// Where to pick up, first rule that fits:
    ///   1. a shaky akk/dat/gen case whose unit has a story → that unit's least-recently-played
    ///      story (Lesen if it was never played, else Einsetzen, the step that moves the skill);
    ///   2. an unplayed story, the start unit's first;
    ///   3. the first unfinished step from the start unit on (Finden, Einsetzen, Schnellrunde);
    ///   4. the story played longest ago, "Wiederholen".
    /// The start unit comes from the learner's level (A1 → Nominativ, A2 → Akkusativ,
    /// B1+ → Dativ); nothing is ever written back.
    static func next(profile: LearnerProfile?, level: CEFRLevel, rounds: [KasusRound],
                     bank: KasusStoryBank) -> KasusHero {
        let progress = KasusProgress(rounds: rounds)
        let start = KasusUnit.start(for: level)
        let path = Array(KasusUnit.allCases.drop { $0 != start })

        func hero(_ story: KasusStory, _ unit: KasusUnit, _ step: KasusStep, _ reason: KasusHero.Reason) -> KasusHero {
            KasusHero(unit: unit, action: .story(storyID: story.id, step: step), reason: reason,
                      storyTitle: story.title)
        }

        // 1. A shaky case with a story.
        for focus in LearnerMemoryService.shakyFocuses(profile) {
            guard let unit = KasusUnit.allCases.first(where: { $0.focus == focus }) else { continue }
            let stories = bank.stories(for: unit)
            guard let story = stories.min(by: {
                (progress.lastPlayed($0) ?? .distantPast) < (progress.lastPlayed($1) ?? .distantPast)
            }) else { continue }
            let step: KasusStep = progress.lastPlayed(story) == nil ? .lesen : .einsetzen
            return hero(story, unit, step, .shaky(focus))
        }

        // 2. An unplayed story, from the start unit on, then any earlier one.
        let unitOrder = path + KasusUnit.allCases.filter { !path.contains($0) }
        for unit in unitOrder {
            if let story = bank.stories(for: unit).first(where: { progress.lastPlayed($0) == nil }) {
                return hero(story, unit, .lesen, .newStory)
            }
        }

        // 3. The first unfinished step from the start unit on.
        for unit in path {
            for story in bank.stories(for: unit) {
                if !progress.isDone(story, step: .find) { return hero(story, unit, .finden, .nextStep) }
                if !progress.isDone(story, step: .fill) { return hero(story, unit, .einsetzen, .nextStep) }
            }
            if !progress.quickRoundDone(unit) {
                return KasusHero(unit: unit, action: .quickRound, reason: .nextStep, storyTitle: nil)
            }
        }

        // 4. The story played longest ago.
        let played = bank.stories.compactMap { story in progress.lastPlayed(story).map { (story, $0) } }
        if let oldest = played.min(by: { $0.1 < $1.1 })?.0, let unit = oldest.unit {
            return hero(oldest, unit, .lesen, .review)
        }
        return KasusHero(unit: start, action: .quickRound, reason: .review, storyTitle: nil)
    }
}
