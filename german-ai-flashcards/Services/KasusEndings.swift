//
//  KasusEndings.swift
//  german-ai-flashcards
//
//  Endungen, the class worksheet's „Füllen Sie die Lücken mit den richtigen Endungen aus“: a
//  story's definite and ein articles become a stem and a gap („D__ Bruder schenkt d__ Schwester
//  ein__ neuen Drucker“), and the buttons are the endings: -er -ie -as -en -em -es for the
//  definite article, – -e -en -em -er -es for ein ("–" is no ending). Possessives, kein and
//  dieser stay written out for now, and so do the adjective and noun endings.
//
//    gaps       which articles become gaps (the same rules as the old Einsetzen's blanks: the
//               unit's case, every case in play when gemischt, the Nominativ only at Ohne Hilfe,
//               restricted to the two families), the stem as written, the buttons per hint level,
//               and what each level shows (table, highlighted cell, chips, tags)
//    grading    the chosen ending goes back on its stem („d“ + „em“ = „dem“) and is graded the
//               way whole articles were: right, case miss, gender slip, number slip
//    the round  `KasusEndingsRound`: the picks, Prüfen, Lösung zeigen and Noch mal, per feedback
//               mode, and the result `recordRound` stores
//
//  Counting: Lernhilfe and Viel Hilfe never move the coach, Genus-Hilfe only masculine gaps, Ohne
//  Hilfe unless the Tipp showed the case or the answer, and a gap Lösung zeigen filled never
//  (`KasusService.countsTowardSkill`).
//

import Foundation

// MARK: - Families

/// The article families Endungen turns into gaps.
nonisolated enum KasusEndingFamily: String, CaseIterable, Hashable {
    /// der, die, das, den, dem, des: the stem is the d, the ending the rest (-er, -ie, -as …).
    case definite
    /// ein, eine, einen, einem, einer, eines: the stem is ein, the ending what follows, maybe none.
    case ein

    /// Nil for kein, the possessives and dieser/jeder/welcher, which stay written out.
    init?(_ family: KasusFamily) {
        switch family {
        case .definite: self = .definite
        case .ein:      self = .ein
        case .kein, .possessive, .derWord: return nil
        }
    }

    /// The stem, lowercased: "d" or "ein".
    var stem: String { self == .definite ? "d" : "ein" }

    /// Every button, in the endings table's order: -er -ie -as -en -em (-es), or – -e -en -em -er
    /// (-es). The Genitiv's -es only once Genitiv is in play.
    func endings(includeGenitive: Bool) -> [String] {
        let family: KasusFamily = self == .definite ? .definite : .ein
        return KasusForms.fullFamilyOptions(family: family, stem: stem, includeGenitive: includeGenitive)
            .map(ending(of:))
    }

    /// A whole form's ending: "dem" → "em", "einen" → "en", "ein" → "".
    func ending(of form: String) -> String {
        String(form.lowercased().dropFirst(stem.count))
    }
}

/// A cell of the endings table (`CaseEndingsTable`): the case row and the gender column.
nonisolated struct KasusTableCell: Hashable {
    let kasus: GrammarCase
    let genus: Gender
}

// MARK: - Gaps

/// One Endungen gap: a target's article as its stem plus a gap, the ending buttons, and what the
/// hint level shows around it.
struct KasusEndingGap: Identifiable, Hashable {
    let target: KasusLocatedTarget
    let hintLevel: KasusHintLevel
    let family: KasusEndingFamily
    /// The stem as the text writes it: „D“ at a sentence start, „d“, „Ein“, „ein“.
    let stem: String
    /// The right ending, lowercased; "" for an ein-word with no ending.
    let answer: String
    /// The ending buttons, in table order. The answer is always among them.
    let options: [String]

    var id: Int { target.index }
    var kasus: GrammarCase { target.kasus }
    var genus: Gender { target.genus }

    /// „D__“, „ein__“: the gap before it's filled.
    var gapText: String { stem + "__" }
    /// The article with `ending` on the stem, as the text would write it: „Dem“, „ein“.
    func form(_ ending: String) -> String { stem + ending }
    /// The right article, as written.
    var answerForm: String { form(answer) }

    /// A button's label: „-em“, or „–“ for no ending.
    nonisolated static func label(_ ending: String) -> String { ending.isEmpty ? "–" : "-" + ending }

    /// Where the answer sits in the endings table: Lernhilfe highlights this cell (case row ×
    /// gender column), whose article and ein ending are the answer.
    var cell: KasusTableCell { KasusTableCell(kasus: kasus, genus: genus) }

    // What the hint level shows.

    /// Lernhilfe and Viel Hilfe: the endings table for the cases in play, in the exercise.
    var showsCaseTable: Bool { hintLevel.showsCaseTable }
    /// Lernhilfe: the table's `cell` is highlighted.
    var highlightsCell: Bool { hintLevel == .lern }
    /// Lernhilfe, Viel Hilfe and Genus-Hilfe: the „Bruder · m“ chip above the buttons, and the
    /// class-style „(m)“ tag after the noun in the text, both in `Gender.color`.
    var showsGenderChip: Bool { hintLevel != .ohne }
    var showsGenderTag: Bool { hintLevel != .ohne }
    /// Lernhilfe: the case chip („Dativ“) next to the gender chip.
    var showsCaseChip: Bool { hintLevel == .lern }
    /// „Bruder · m“: the noun as written and its column label.
    var genderChip: String { "\(target.noun) · \(genus.columnLabel)" }
    /// „(m)“, as the class sheet writes the gender after the noun.
    var genderTag: String { "(\(genus.columnLabel))" }
    /// Lernhilfe and Viel Hilfe: the trigger is underlined (`target.triggerRange`), except on a
    /// bare time phrase, where the verb next to it isn't what decides.
    var underlinesTrigger: Bool { hintLevel.showsCaseTable && !isBareTimePhrase && !isFormOnly }
    /// A time phrase with no preposition („jeden Tag“).
    var isBareTimePhrase: Bool { target.spec.reason == .time && target.preposition == nil }
    /// A generated story's unplanned phrase with no preposition in front: only the article's form
    /// shows the case, so there is no word to underline or point the Tipp at.
    var isFormOnly: Bool { target.spec.reason == .inferred && target.preposition == nil }
    /// The Tipp's first clue: the deciding word, or what to look at when there is none.
    var triggerClue: String {
        if isBareTimePhrase { return "A time phrase: wann? wie oft?" }
        if isFormOnly { return "Find the verb. Ask wer?, wen?, wem? or wessen?" }
        return "Look at „\(target.spec.trigger)“"
    }
    /// Ohne Hilfe, on a noun that reads the same in the plural (Schlüssel): a sg/pl tag.
    var showsNumberTag: Bool { hintLevel == .ohne && target.numberAmbiguous }
    var numberTag: String { genus == .plural ? "pl" : "sg" }
}

// MARK: - The round

/// One Endungen round: the gaps at one hint level, the picks, and where the round is. Value type,
/// so a view can hold it in `@State` and call its mutating methods.
///
/// Sofort: each gap's first pick is graded and locked (`choose` returns the grade for the
/// `KasusFeedback` signal); the round is finished, and recorded, once every gap has a pick or was
/// filled by Lösung zeigen. Am Ende: picks can change until `check()` (Prüfen), which grades them
/// all and is when the round is recorded; `showAnswers()` (Lösung zeigen) then fills in every gap
/// that isn't right, and `reset()` (Noch mal) starts over unrecorded.
struct KasusEndingsRound: Identifiable, Hashable {
    /// Kept through Noch mal, so Lösung zeigen finds the recorded round
    /// (`KasusService.markAnswersShown(roundID:in:)`).
    let id: UUID
    let gaps: [KasusEndingGap]
    let hint: KasusHintLevel
    let mode: KasusFeedbackMode

    /// Gap id → the chosen ending ("" is „–“). Sofort: the first pick. Am Ende: the latest.
    private(set) var picks: [Int: String] = [:]
    /// Gap id → how far the Ohne Hilfe Tipp went before the gap's (first) pick.
    private(set) var tipps: [Int: KasusTipp] = [:]
    /// Am Ende: Prüfen has been tapped.
    private(set) var isChecked = false
    /// Lösung zeigen has been tapped.
    private(set) var answersShown = false
    /// Gaps Lösung zeigen filled before they had a pick. Never counted.
    private(set) var revealed: Set<Int> = []
    /// 1 until the first Noch mal. Only the first attempt is recorded.
    private(set) var attempt = 1

    init(gaps: [KasusEndingGap], hint: KasusHintLevel, mode: KasusFeedbackMode, id: UUID = UUID()) {
        self.id = id
        self.gaps = gaps
        self.hint = hint
        self.mode = mode
    }

    func gap(_ id: Int) -> KasusEndingGap? {
        gaps.first { $0.id == id }
    }

    func pick(for id: Int) -> String? {
        picks[id]
    }

    /// A tap on an ending button.
    ///   - Sofort, a gap without a pick: graded and locked; returns the grade.
    ///   - Am Ende, before Prüfen: sets or replaces the gap's pick; nothing is judged yet, so nil.
    ///   - Anything else (a picked gap in Sofort, after Prüfen, a gap Lösung zeigen filled): nil.
    @discardableResult
    mutating func choose(_ ending: String, for id: Int) -> KasusPickOutcome? {
        guard let gap = gap(id), !revealed.contains(id), !isChecked else { return nil }
        switch mode {
        case .sofort:
            guard picks[id] == nil else { return nil }
            picks[id] = ending
            return KasusService.grade(ending: ending, for: gap)
        case .amEnde:
            picks[id] = ending
            return nil
        }
    }

    /// Am Ende, before Prüfen: empties a gap again.
    mutating func clear(_ id: Int) {
        guard mode == .amEnde, !isChecked else { return }
        picks[id] = nil
    }

    /// The Tipp went one step further on a gap. Only before the gap's pick counts (Sofort) or
    /// before Prüfen (Am Ende), and it never goes back.
    mutating func recordTipp(_ tipp: KasusTipp, for id: Int) {
        guard !isChecked, mode == .amEnde || picks[id] == nil else { return }
        tipps[id] = max(tipps[id] ?? .none, tipp)
    }

    /// Every gap has a pick: Am Ende's Prüfen is ready.
    var allFilled: Bool { gaps.allSatisfy { picks[$0.id] != nil } }

    /// The help level and the feedback mode stay put while the round is under way: a pick made,
    /// or a Tipp taken, and not finished. Changing either rebuilds the round, which would forget
    /// a Tipp and let the answer it showed count as the learner's own.
    var settingsLocked: Bool { (!picks.isEmpty || !tipps.isEmpty) && !isFinished }

    /// Am Ende's Prüfen: every pick shows its grade; a gap still empty is recorded as left empty.
    mutating func check() {
        guard mode == .amEnde else { return }
        isChecked = true
    }

    /// Lösung zeigen: every gap that isn't right shows its answer. In Sofort it can come at any
    /// time, and the gaps not picked yet are filled (and never counted); in Am Ende only after
    /// Prüfen.
    mutating func showAnswers() {
        guard mode == .sofort || isChecked else { return }
        answersShown = true
        for gap in gaps where picks[gap.id] == nil { revealed.insert(gap.id) }
    }

    /// Noch mal: every gap empty again, the next attempt (not recorded).
    mutating func reset() {
        picks = [:]
        tipps = [:]
        isChecked = false
        answersShown = false
        revealed = []
        attempt += 1
    }

    /// The grade a gap shows now: Sofort once it has its pick, Am Ende after Prüfen. Nil before
    /// that, and for a gap with no pick.
    func outcome(for id: Int) -> KasusPickOutcome? {
        guard let gap = gap(id), let ending = picks[id], mode == .sofort || isChecked else { return nil }
        return KasusService.grade(ending: ending, for: gap)
    }

    /// The right article shows in the gap: a right pick, a wrong one once it's graded (as
    /// ~~pick~~ answer), or any gap after Lösung zeigen.
    func showsAnswer(for id: Int) -> Bool {
        answersShown || outcome(for: id) != nil
    }

    /// Ready to record: Am Ende after Prüfen; Sofort once every gap has a pick or was filled by
    /// Lösung zeigen.
    var isFinished: Bool {
        switch mode {
        case .amEnde: isChecked
        case .sofort: gaps.allSatisfy { picks[$0.id] != nil || revealed.contains($0.id) }
        }
    }

    /// Picks graded right so far (only the ones that show a grade).
    var rightCount: Int { gaps.filter { outcome(for: $0.id)?.isRight == true }.count }
}

// MARK: - Service

extension KasusService {

    /// Endungen's gaps, in reading order: the same cases the old Einsetzen blanked
    /// (`blankCases`: the unit's case, every case in play when gemischt, the Nominativ only at
    /// Ohne Hilfe), but only definite and ein articles. Every other article stays written out.
    static func endingGaps(in playable: KasusPlayableStory, unit: KasusUnit, mixed: Bool,
                           hint: KasusHintLevel) -> [KasusEndingGap] {
        let cases = blankCases(unit: unit, mixed: mixed, hint: hint)
        let includeGenitive = unit.casesInPlay.contains(.genitiv)
        return playable.targets.compactMap { target in
            guard target.blankable, cases.contains(target.kasus) else { return nil }
            return endingGap(for: target, hint: hint, includeGenitive: includeGenitive)
        }
    }

    /// One target as a gap. Nil unless it is a definite or ein article.
    static func endingGap(for target: KasusLocatedTarget, hint: KasusHintLevel,
                          includeGenitive: Bool) -> KasusEndingGap? {
        guard let parsed = target.parsed, let family = KasusEndingFamily(parsed.family),
              target.determiner.count >= family.stem.count else { return nil }
        let stem = String(target.determiner.prefix(family.stem.count))
        return KasusEndingGap(target: target, hintLevel: hint, family: family, stem: stem,
                              answer: family.ending(of: target.determiner),
                              options: endingOptions(for: target, hint: hint, includeGenitive: includeGenitive))
    }

    /// The ending buttons, in table order. Lernhilfe and Viel Hilfe: the noun's own gender
    /// through the cases in play, padded to three with one other form (the same set as the old
    /// Viel Hilfe's articles). Genus-Hilfe and Ohne Hilfe: the whole row, -es only once Genitiv is
    /// in play. Empty for anything that isn't a definite or ein article.
    static func endingOptions(for target: KasusLocatedTarget, hint: KasusHintLevel,
                              includeGenitive: Bool) -> [String] {
        guard let parsed = target.parsed, let family = KasusEndingFamily(parsed.family) else { return [] }
        let full = family.endings(includeGenitive: includeGenitive)
        var endings: [String]
        if hint.showsCaseTable {
            let viel = KasusForms.vielHilfeOptions(answer: target.answer, family: parsed.family, stem: parsed.stem,
                                                   genus: target.genus, includeGenitive: includeGenitive)
                .map(family.ending(of:))
            endings = full.filter(viel.contains) + viel.filter { !full.contains($0) }
        } else {
            endings = full
        }
        let answer = family.ending(of: target.determiner)
        if !endings.contains(answer) { endings.append(answer) }
        return endings
    }

    /// Grades a chosen ending by putting it back on its stem („d“ + „em“) and grading the whole
    /// article: right, case miss, gender slip or number slip, exactly as before.
    static func grade(ending: String, for gap: KasusEndingGap) -> KasusPickOutcome {
        grade(gap.family.stem + ending.lowercased(), for: gap.target)
    }

    /// What Endungen says after a wrong pick: the slip note for a slip, the explanation for a
    /// case miss. Nil for a right pick.
    static func endingFeedback(for outcome: KasusPickOutcome, ending: String, gap: KasusEndingGap,
                               in story: KasusStory) -> String? {
        feedback(for: outcome, pick: gap.family.stem + ending.lowercased(), target: gap.target, in: story)
    }

    /// Endungen's round, for `recordRound`: when `round.isFinished` on the first attempt (Am Ende
    /// at Prüfen, Sofort at the last pick or Lösung zeigen). One item per gap: its graded pick
    /// (stored as the whole article, „dem“, so the history reads like before), `revealed` for a
    /// gap Lösung zeigen filled, `unanswered` for one left empty at Prüfen. `story` gives each
    /// its sentence; nil looks the id up in the bundled bank.
    static func endingsResult(_ round: KasusEndingsRound, storyID: String, unit: KasusUnit,
                              durationSeconds: Int, story: KasusStory? = nil) -> KasusRoundResult {
        let story = story ?? KasusStoryBank.bundled.story(id: storyID)
        let items = round.gaps.map { gap -> KasusItemResult in
            let tipp = round.tipps[gap.id] ?? .none
            if let ending = round.picks[gap.id] {
                let outcome = grade(ending: ending, for: gap)
                let record = story.map { story -> KasusRoundItem in
                    var record = KasusRoundItem.story(
                        gap.target, in: story, pick: gap.form(ending), outcome: outcome.itemOutcome,
                        explanation: endingFeedback(for: outcome, ending: ending, gap: gap, in: story)
                            ?? explanation(for: gap.target, in: story))
                    if round.answersShown, !outcome.isRight { record.revealed = true }
                    return record
                }
                return KasusItemResult(kasus: gap.kasus, genus: gap.genus, firstTry: outcome.isRight,
                                       slip: outcome.isSlip, tipp: tipp, targetIndex: gap.id, record: record)
            }
            let wasRevealed = round.revealed.contains(gap.id)
            let record = story.map { story -> KasusRoundItem in
                var record = KasusRoundItem.story(gap.target, in: story, pick: nil,
                                                  outcome: wasRevealed ? .revealed : .unanswered,
                                                  explanation: explanation(for: gap.target, in: story))
                if wasRevealed { record.revealed = true }
                return record
            }
            return KasusItemResult(kasus: gap.kasus, genus: gap.genus, firstTry: false, tipp: tipp,
                                   targetIndex: gap.id, record: record,
                                   revealed: wasRevealed, unanswered: !wasRevealed)
        }
        return KasusRoundResult(storyID: storyID, unit: unit, step: .fill, hintLevel: round.hint, items: items,
                                durationSeconds: durationSeconds, feedbackMode: round.mode,
                                revealedAnswers: round.answersShown, id: round.id)
    }

    /// A fresh Endungen round.
    static func endingsRound(in playable: KasusPlayableStory, unit: KasusUnit, mixed: Bool,
                             hint: KasusHintLevel, mode: KasusFeedbackMode) -> KasusEndingsRound {
        KasusEndingsRound(gaps: endingGaps(in: playable, unit: unit, mixed: mixed, hint: hint), hint: hint, mode: mode)
    }
}
