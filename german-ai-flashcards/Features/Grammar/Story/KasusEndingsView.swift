//
//  KasusEndingsView.swift
//  german-ai-flashcards
//
//  Endungen, the class worksheet's „Füllen Sie die Lücken mit den richtigen Endungen aus“: the
//  story as numbered sentences with the definite and ein articles cut down to their stem and a
//  gap („D__ Bruder schenkt d__ Schwester ein__ neuen Drucker (m).“). Tap a gap, then an ending
//  button (-er -ie -as -en -em -es, or – -e -en -em -er -es; „–“ is no ending).
//
//    Sofort    each first pick is judged at once with the `KasusFeedback` signal; a right one
//              moves on after 800 ms, a wrong one shows ~~pick~~ answer and why, then Weiter
//    Am Ende   fill every gap freely (tap any gap, change it, tap the chosen ending again to
//              empty it); Prüfen shows every verdict, Lösung zeigen the answers, Noch mal starts
//              over unrecorded
//
//  Four help levels, one control in the options pill, remembered in `kasus.hintLevel`:
//  Lernhilfe (the endings table in the tray with the gap's cell ringed, the gender and case chips
//  above the buttons), Viel Hilfe (the table, the gender chip, the deciding word underlined,
//  fewer buttons), Genus-Hilfe (the gender chip and the „(m)“ tag) and Ohne Hilfe (the Tipp).
//  The level and the mode lock once the round has a pick or a Tipp, until it's finished or
//  started over (`KasusEndingsRound.settingsLocked`). A right gap wears its case color, the
//  gender color stays on its letters. Prüfen with gaps empty (even all of them) asks first.
//  The chips and the ending buttons are pinned with the main button; only the table and the
//  verdict above them scroll when the tray runs out of room.
//
//  The round's state lives in `KasusEndingsPlay`, held by the player; `KasusService` grades.
//

import SwiftUI

// MARK: - State

/// Endungen's state for one story, held by the player so hopping between steps keeps every pick.
struct KasusEndingsPlay {
    var round: KasusEndingsRound?
    /// „Noch mal · gemischt“: every case in play gets gaps, not just the unit's own.
    var mixed = false
    /// The gap the tray is working on.
    var activeGap: Int?
    /// DEBUG `-kasus.debugHint` and `-kasus.debugFeedback`, which win over the stored choices
    /// without overwriting them.
    var hintOverride: KasusHintLevel?
    var modeOverride: KasusFeedbackMode?
    var clock = KasusStepClock()
    /// Rounds already recorded. A round rebuilt in the other feedback mode keeps its id, so it's
    /// never recorded twice.
    var recordedIDs: Set<UUID> = []
    /// The attempt on screen is the recorded one, so Lösung zeigen flags it.
    var attemptRecorded = false
    /// DEBUG prefill: the picks weren't the learner's, so nothing is handed on to be recorded.
    var prefilled = false
    /// Bumped by every new round or attempt, so a pending auto-advance never lands in the next.
    var generation = 0

    /// A round of this story has been recorded: the step bar's ✓.
    var isPlayed: Bool { !recordedIDs.isEmpty }

    /// A fresh round at the stored (or overridden) help level and feedback mode. Recorded when
    /// it's finished, like any new round.
    mutating func start(in playable: KasusPlayableStory, unit: KasusUnit, germanLevel: CEFRLevel) {
        let preferred = hintOverride ?? KasusHintLevel.current(level: germanLevel)
        let hint = KasusService.effectiveHintLevel(preferred, unit: unit, mixed: mixed)
        let mode = modeOverride ?? KasusFeedbackMode.current(for: .fill)
        let fresh = KasusService.endingsRound(in: playable, unit: unit, mixed: mixed, hint: hint, mode: mode)
        round = fresh
        activeGap = fresh.gaps.first?.id
        attemptRecorded = false
        prefilled = false
        generation += 1
        clock.restart()
    }

    /// Noch mal: every gap empty again, the same round, not recorded again.
    mutating func retry() {
        round?.reset()
        activeGap = round?.gaps.first?.id
        attemptRecorded = false
        generation += 1
        clock.resume()
    }

    /// The other feedback mode for the round on screen. Offered before the first pick (the same
    /// round) or once it's finished (a fresh attempt with the same id, not recorded again).
    mutating func switchMode(to mode: KasusFeedbackMode) {
        guard let current = round, current.mode != mode else { return }
        round = KasusEndingsRound(gaps: current.gaps, hint: current.hint, mode: mode, id: current.id)
        activeGap = current.gaps.first?.id
        attemptRecorded = false
        generation += 1
    }

    /// The round to record, once it's finished on its first attempt; nil otherwise (and for a
    /// DEBUG prefill). The clock stops at any finish, a Noch mal's too, so Ergebnis shows a
    /// time that holds still.
    mutating func resultIfFinished(storyID: String, unit: KasusUnit, story: KasusStory) -> KasusRoundResult? {
        guard let current = round, current.isFinished else { return nil }
        clock.pause()
        guard current.attempt == 1, !recordedIDs.contains(current.id) else { return nil }
        recordedIDs.insert(current.id)
        attemptRecorded = true
        let result = KasusService.endingsResult(current, storyID: storyID, unit: unit,
                                                durationSeconds: clock.seconds, story: story)
        return prefilled ? nil : result
    }

    /// Lösung zeigen. Returns the recorded round's id to flag, when the attempt on screen was
    /// already recorded. (In Sofort it can come first: the result then carries it itself.)
    mutating func showAnswers() -> UUID? {
        guard var current = round, !current.answersShown else { return nil }
        let flag = attemptRecorded && !prefilled ? current.id : nil
        current.showAnswers()
        round = current
        return current.answersShown ? flag : nil
    }

    /// Where a gap stands, for the text, the strip and the tray.
    func state(of gap: KasusEndingGap) -> KasusGapState {
        guard let round else { return .empty }
        let pick = round.pick(for: gap.id)
        if let outcome = round.outcome(for: gap.id), let pick {
            // Am Ende keeps the answer back until Lösung zeigen; Sofort shows it with the verdict.
            let answerShown = outcome.isRight || round.mode == .sofort || round.answersShown
            return .graded(pick: pick, outcome: outcome, answerShown: answerShown)
        }
        if round.revealed.contains(gap.id) { return .revealed }
        if round.isChecked { return round.answersShown ? .revealed : .leftEmpty }
        if let pick { return .chosen(pick) }
        return .empty
    }
}

/// One gap's standing.
enum KasusGapState: Hashable {
    case empty
    /// Am Ende, before Prüfen: an ending chosen, not judged yet.
    case chosen(String)
    /// Judged. `answerShown`: the right article shows too (Sofort, a right pick, or after
    /// Lösung zeigen).
    case graded(pick: String, outcome: KasusPickOutcome, answerShown: Bool)
    /// Am Ende: still empty at Prüfen.
    case leftEmpty
    /// Lösung zeigen filled it before it had a pick.
    case revealed
}

// MARK: - View

struct KasusEndingsStepView: View {
    @Binding var play: KasusEndingsPlay
    let playable: KasusPlayableStory
    let unit: KasusUnit
    let germanLevel: CEFRLevel
    let hapticMode: HapticFeedbackMode
    /// How tall the tray's verdict and explanation may grow before they scroll.
    let trayTextCap: CGFloat
    /// How tall the whole tray may grow before it scrolls.
    let trayCap: CGFloat
    let onComplete: (KasusRoundResult) -> Void
    let onAnswersShown: (UUID) -> Void
    let onShowResult: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(KasusHintLevel.storageKey) private var hintRaw = ""
    @AppStorage(KasusFeedbackMode.endingsStorageKey) private var modeRaw = ""
    /// The endings table at Lernhilfe and Viel Hilfe, open or folded. Per viewer, remembered.
    @AppStorage("kasus.endingsTableOpen") private var tableOpen = true

    /// Sofort: a right pick waiting out its 800 ms before moving on, and the task that will.
    @State private var pendingAdvance: Int?
    /// Am Ende: Prüfen with gaps still empty asks first.
    @State private var confirmCheck = false
    @State private var advanceTask: Task<Void, Never>?
    @State private var correctCount = 0
    @State private var wrongCount = 0
    @State private var slipCount = 0
    /// The tray's height, and when the round came on screen, so a fresh round's scroll can wait
    /// for the tray to settle.
    @State private var trayHeight: CGFloat = 0
    @State private var freshSince = Date()

    private var story: KasusStory { playable.story }

    var body: some View {
        exercise
            .onDisappear(perform: cancelAdvance)
        .sensoryFeedback(.success, trigger: correctCount) { old, new in
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
        .sensoryFeedback(.impact(weight: .light), trigger: slipCount) { old, new in
            new > old && hapticMode.playsError
        }
    }

    private var emptyGapsTitle: String {
        let empty = (play.round?.gaps.count ?? 0) - (play.round?.picks.count ?? 0)
        return empty == 1 ? "1 gap is still empty" : "\(empty) gaps are still empty"
    }

    @ViewBuilder
    private var exercise: some View {
        if let round = play.round {
            content(round)
        } else {
            Color.clear
        }
    }

    private func content(_ round: KasusEndingsRound) -> some View {
        ScrollViewReader { proxy in
            storyScroll(round)
                .onChange(of: activeSentence) { _, sentence in
                    guard let sentence else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(sentence, anchor: UnitPoint(x: 0.5, y: 0.25))
                    }
                }
                .task(id: FreshScroll(generation: play.generation, trayHeight: trayHeight.rounded())) {
                    // A fresh round, or coming back to one: the focused gap mustn't sit under the
                    // tray (at Lernhilfe it covers almost half the screen). Its sentence goes
                    // near the tray's top edge, which scrolls no further than needed: a gap
                    // already in view stays put, and so does the instruction above it. After a
                    // beat, and again if the tray settles at another height within the first
                    // second (its content animates in); after that a gap's own tap scrolls it
                    // (`activeSentence`), and a tray that grows later leaves the text alone.
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, Date().timeIntervalSince(freshSince) < 1.2,
                          let sentence = activeSentence else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(sentence, anchor: UnitPoint(x: 0.5, y: 0.92))
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            trayPanel(round)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { trayHeight = $0 }
        }
        .onAppear { freshSince = Date() }
        .onChange(of: play.generation) { freshSince = Date() }
    }

    /// When the fresh-round scroll runs again: a new round, or the tray at a new height.
    private struct FreshScroll: Equatable {
        let generation: Int
        let trayHeight: CGFloat
    }

    private func storyScroll(_ round: KasusEndingsRound) -> some View {
        let gaps = Dictionary(uniqueKeysWithValues: round.gaps.map { ($0.id, $0) })
        let trigger = triggerRange(round)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                KasusStoryHeader(story: story, unit: unit)
                header(round)
                if round.gaps.isEmpty {
                    KasusNoteLine(text: "No gaps in this story at this help level. Try another level in the options.")
                }
                KasusSentenceList(sentences: playable.sentences) { word in
                    chip(word, gaps: gaps, trigger: trigger)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trayPanel(_ round: KasusEndingsRound) -> some View {
        KasusTray(maxHeight: trayCap) {
            tray(round)
        } footer: {
            trayFooter(round)
        }
            .animation(.snappy(duration: 0.25), value: round.picks)
            .animation(.snappy(duration: 0.25), value: play.activeGap)
    }

    private var activeSentence: Int? {
        play.activeGap.flatMap { playable.numbered.sentenceNumber(ofTarget: $0) }
    }

    // MARK: Header

    private func header(_ round: KasusEndingsRound) -> some View {
        let available = KasusService.availableHintLevels(unit: unit, mixed: play.mixed)
        let inProgress = round.settingsLocked
        return VStack(alignment: .leading, spacing: 10) {
            KasusInstruction(german: "„Füll die Lücken mit den richtigen Endungen aus.“", english: english(round))
            HStack(alignment: .top, spacing: 8) {
                Text(hintDescription(round.hint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                KasusOptionsMenu(hintLevels: available.count > 1 ? available : [], hint: round.hint,
                                 hintLocked: inProgress, mode: round.mode, modeLocked: inProgress,
                                 onHint: setHint, onMode: setMode)
            }
        }
    }

    /// "9 gaps in the Dativ. Tap a gap, then its ending: – means no ending."
    private func english(_ round: KasusEndingsRound) -> String {
        guard !round.gaps.isEmpty else { return "Tap a gap, then its ending: – means no ending." }
        let cases = GrammarCase.allCases.filter { kasus in round.gaps.contains { $0.kasus == kasus } }
        let names = cases.map(KasusExplanation.caseName)
        let listed = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : names.first ?? ""
        let count = round.gaps.count == 1 ? "1 gap" : "\(round.gaps.count) gaps"
        return "\(count) in the \(listed). Tap a gap, then its ending: – means no ending."
    }

    private func hintDescription(_ level: KasusHintLevel) -> String {
        switch level {
        case .lern:  "\(level.germanLabel): the table lights up the gap's cell."
        case .viel:  "\(level.germanLabel): the table, the gender, fewer choices."
        case .genus: "\(level.germanLabel): the gender after each noun, as in class."
        case .ohne:  "\(level.germanLabel): Tipp gives one clue at a time."
        }
    }

    private func setHint(_ level: KasusHintLevel) {
        if play.hintOverride != nil {
            play.hintOverride = level
        } else {
            hintRaw = level.rawValue
        }
        cancelAdvance()
        play.start(in: playable, unit: unit, germanLevel: germanLevel)
    }

    private func setMode(_ mode: KasusFeedbackMode) {
        if play.modeOverride != nil {
            play.modeOverride = mode
        } else {
            modeRaw = mode.rawValue
        }
        cancelAdvance()
        play.switchMode(to: mode)
    }

    // MARK: Words

    /// The deciding word to underline for the focused gap: at Lernhilfe and Viel Hilfe, or once
    /// the Tipp has shown it, until the gap is answered. Never on a bare time phrase or a
    /// form-only phrase.
    private func triggerRange(_ round: KasusEndingsRound) -> (paragraph: Int, range: NSRange)? {
        guard let id = play.activeGap, let gap = round.gap(id), let range = gap.target.triggerRange,
              !gap.isBareTimePhrase, !gap.isFormOnly, !round.isChecked,
              round.mode == .amEnde || round.pick(for: id) == nil,
              gap.underlinesTrigger || (round.tipps[id] ?? .none) >= .trigger else { return nil }
        return (gap.target.paragraphIndex, range)
    }

    @ViewBuilder
    private func chip(_ word: KasusWord, gaps: [Int: KasusEndingGap],
                      trigger: (paragraph: Int, range: NSRange)?) -> some View {
        if let index = word.role.targetIndex, let gap = gaps[index] {
            if word.role.part == .determiner {
                gapChip(gap, word: word)
            } else {
                // The rest of a gap's phrase: tapping it focuses the gap; the noun carries the
                // class-style „(m)“ (or sg/pl) where the level shows one.
                let tag = word.role.part == .noun ? nounTag(gap) : nil
                KasusChip(action: { focus(gap.id) }) {
                    KasusWordText.text(word, tag: tag?.text, tagColor: tag?.color ?? .secondary)
                }
                .accessibilityLabel(tag.map { "\(word.text), \($0.text)" } ?? word.text)
            }
        } else {
            let underlined = trigger.map { $0.paragraph == word.paragraphIndex
                && NSIntersectionRange($0.range, word.paragraphRange).length > 0 } ?? false
            KasusChip(style: KasusChipStyle(underline: underlined ? .secondary : nil)) {
                KasusWordText.text(word)
            }
        }
    }

    /// After the noun: „(m)“ in its gender color where the level shows the gender, „(sg)“ or
    /// „(pl)“ at Ohne Hilfe on a noun that reads the same in both.
    private func nounTag(_ gap: KasusEndingGap) -> (text: String, color: Color)? {
        if gap.showsGenderTag { return (gap.genderTag, gap.genus.color) }
        if gap.showsNumberTag { return ("(\(gap.numberTag))", .secondary) }
        return nil
    }

    /// The gap: its stem and a slot the width of the widest ending, so filling it never moves a
    /// line. A wrong pick whose answer shows reads ~~der~~ dem, the one state that widens. A right
    /// one is washed in its case color, like Markieren's: the gender color stays on the letters,
    /// so a right feminine „der“ never sits on red.
    private func gapChip(_ gap: KasusEndingGap, word: KasusWord) -> some View {
        let state = play.state(of: gap)
        let isActive = play.activeGap == gap.id
        var style = KasusChipStyle()
        switch state {
        case .empty, .leftEmpty:
            style.wash = Color.secondary.opacity(0.1)
            if state == .leftEmpty { style.outline = .secondary; style.dashed = true }
        case .chosen:
            style.wash = Color.secondary.opacity(0.1)
        case .graded(_, let outcome, _):
            if outcome.isRight {
                style.wash = gap.kasus.color.opacity(0.2)
                style.badge = .check(gap.kasus.color)
            } else {
                style.wash = Color.gray.opacity(0.14)
                style.badge = outcome.isSlip ? .slip : .cross
            }
        case .revealed:
            style.wash = Color.secondary.opacity(0.1)
            style.outline = .secondary
            style.dashed = true
        }
        if isActive {
            style.outline = appTheme.accent(model: nil)
            style.dashed = false
        }
        return KasusChip(style: style, action: { focus(gap.id) }) {
            gapLabel(gap, word: word, state: state)
        }
        .accessibilityLabel(gapAccessibility(gap, state: state))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint("Pick its ending below")
    }

    @ViewBuilder
    private func gapLabel(_ gap: KasusEndingGap, word: KasusWord, state: KasusGapState) -> some View {
        let genderColor = gap.genus.color
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !word.leading.isEmpty { Text(word.leading) }
            switch state {
            case .graded(let pick, let outcome, true) where !outcome.isRight:
                Text(gap.form(pick))
                    .strikethrough(color: .secondary)
                    .foregroundStyle(.secondary)
                Text("\u{00A0}")
                Text(gap.stem)
                    .foregroundStyle(genderColor)
                slot(gap.answer, color: genderColor, bold: true)
            case .graded(let pick, let outcome, _):
                Text(gap.stem)
                    .foregroundStyle(outcome.isRight ? genderColor : .secondary)
                slot(pick, color: outcome.isRight ? genderColor : .secondary, bold: outcome.isRight,
                     struck: !outcome.isRight)
            case .chosen(let pick):
                Text(gap.stem)
                slot(pick, color: .primary)
            case .revealed:
                Text(gap.stem)
                    .foregroundStyle(genderColor)
                slot(gap.answer, color: genderColor)
            case .empty, .leftEmpty:
                Text(gap.stem)
                slot(nil, color: .secondary)
            }
            if !word.trailing.isEmpty { Text(word.trailing) }
        }
    }

    /// The ending's place after the stem: as wide as „em“, with a line under it like the
    /// worksheet's blank. „–“ for no ending.
    private func slot(_ ending: String?, color: Color, bold: Bool = false, struck: Bool = false) -> some View {
        ZStack(alignment: .leading) {
            Text("em").hidden()
            if let ending {
                Text(ending.isEmpty ? "–" : ending)
                    .fontWeight(bold ? .bold : .regular)
                    .strikethrough(struck, color: .secondary)
                    .foregroundStyle(color)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ending == nil ? Color.secondary.opacity(0.6) : color.opacity(0.7))
                .frame(height: 1.5)
                .offset(y: 1)
        }
    }

    private func gapAccessibility(_ gap: KasusEndingGap, state: KasusGapState) -> String {
        let noun = gap.target.noun
        switch state {
        case .empty:                 return "Gap, \(gap.stem) blank, \(noun)"
        case .chosen(let pick):      return "\(gap.form(pick)) \(noun), not checked yet"
        case .graded(let pick, let outcome, let shown):
            if outcome.isRight { return "\(gap.answerForm) \(noun), right" }
            return shown ? "\(gap.form(pick)), wrong, it's \(gap.answerForm) \(noun)" : "\(gap.form(pick)) \(noun), wrong"
        case .leftEmpty:             return "Gap left empty, \(noun)"
        case .revealed:              return "\(gap.answerForm) \(noun), answer shown"
        }
    }

    // MARK: Actions

    private func focus(_ id: Int) {
        pendingAdvance = nil
        play.activeGap = id
    }

    private func choose(_ ending: String, for gap: KasusEndingGap) {
        guard var round = play.round else { return }
        switch round.mode {
        case .amEnde:
            // Tapping the chosen ending again empties the gap.
            if round.pick(for: gap.id) == ending {
                round.clear(gap.id)
                play.round = round
                return
            }
            round.choose(ending, for: gap.id)
            play.round = round
            // On to the next empty gap, if there is one; the chosen one can still change.
            if let next = nextGap(after: gap.id, where: { round.pick(for: $0) == nil }) {
                play.activeGap = next
            }
        case .sofort:
            guard let outcome = round.choose(ending, for: gap.id) else { return }
            play.round = round
            // Recorded here, right or wrong, so closing from the last explanation still counts it.
            recordIfFinished()
            guard outcome.isRight else {
                // A slip only gets a light tap: it was close, and the header says „Fast“.
                if outcome.isSlip { slipCount += 1 } else { wrongCount += 1 }
                return
            }
            correctCount += 1
            pendingAdvance = gap.id
            let generation = play.generation
            advanceTask?.cancel()
            advanceTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                // Only if nothing moved in the meantime: the same round, the same gap.
                guard !Task.isCancelled, generation == play.generation,
                      pendingAdvance == gap.id, play.activeGap == gap.id else { return }
                pendingAdvance = nil
                advance(from: gap.id)
            }
        }
    }

    /// The next gap after `id` that `open` accepts, wrapping to any earlier one.
    private func nextGap(after id: Int, where open: (Int) -> Bool) -> Int? {
        guard let order = play.round?.gaps.map(\.id) else { return nil }
        let start = (order.firstIndex(of: id) ?? -1) + 1
        return order[start...].first(where: open) ?? order.first(where: { $0 != id && open($0) })
    }

    /// Sofort: the next gap without a pick, or the tray's Ergebnis once there's none.
    private func advance(from id: Int) {
        pendingAdvance = nil
        guard let round = play.round else { return }
        play.activeGap = nextGap(after: id) { round.pick(for: $0) == nil && !round.revealed.contains($0) }
    }

    private func cancelAdvance() {
        advanceTask?.cancel()
        advanceTask = nil
        pendingAdvance = nil
    }

    private func check() {
        guard var round = play.round else { return }
        round.check()
        play.round = round
        play.activeGap = nil
        if round.rightCount == round.gaps.count { correctCount += 1 } else { wrongCount += 1 }
        recordIfFinished()
    }

    private func showAnswers() {
        cancelAdvance()
        let flag = play.showAnswers()
        recordIfFinished()
        if let flag { onAnswersShown(flag) }
        if play.round?.mode == .sofort { play.activeGap = nil }
    }

    private func recordIfFinished() {
        if let result = play.resultIfFinished(storyID: story.id, unit: unit, story: story) {
            onComplete(result)
        }
    }

    private func tipp(_ gap: KasusEndingGap) {
        guard var round = play.round else { return }
        let reached = round.tipps[gap.id] ?? .none
        round.recordTipp(reached.next ?? .answer, for: gap.id)
        play.round = round
    }

    // MARK: Tray

    @ViewBuilder
    private func tray(_ round: KasusEndingsRound) -> some View {
        if round.mode == .amEnde, round.isChecked {
            checkedTray(round)
        } else if let id = play.activeGap, let gap = round.gap(id) {
            gapTray(gap, round: round)
        } else if round.isFinished {
            KasusProgressStrip(marks: marks(round, active: nil))
            Button {
                play.retry()
            } label: {
                twoLine("Noch mal", "Retry")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    /// The step's main button, always in view: Weiter, Prüfen, or Ergebnis. After Prüfen at the
    /// accessibility sizes, Lösung zeigen and Noch mal sit in a row above it.
    @ViewBuilder
    private func trayFooter(_ round: KasusEndingsRound) -> some View {
        if round.mode == .amEnde, round.isChecked {
            if dynamicTypeSize.isAccessibilitySize {
                compactActions(round)
            }
            resultButton
        } else if let id = play.activeGap, let gap = round.gap(id) {
            gapFooter(gap, round: round)
        } else if round.isFinished {
            resultButton
        } else if let first = round.gaps.first(where: { round.pick(for: $0.id) == nil }) {
            Button {
                focus(first.id)
            } label: {
                Text("Weiter")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// One gap, top to bottom: the dots (or the fill count) with the Tipp and Lösung zeigen, the
    /// verdict and why once picked (Sofort), and the table. The gender and case chips and the
    /// ending buttons sit in the pinned footer (`gapFooter`), so a tall table (four cases at
    /// Lernhilfe) scrolls instead of pushing them out of reach.
    @ViewBuilder
    private func gapTray(_ gap: KasusEndingGap, round: KasusEndingsRound) -> some View {
        let state = play.state(of: gap)
        let pick = round.pick(for: gap.id)
        HStack(spacing: 10) {
            if round.mode == .sofort {
                KasusProgressStrip(marks: marks(round, active: gap.id))
            } else {
                let filled = round.picks.count
                Text("\(filled) of \(round.gaps.count) filled")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if gap.hintLevel == .ohne, round.mode == .amEnde || pick == nil {
                tippButton(gap, round: round)
            }
            if round.mode == .sofort, !round.isFinished {
                Button(action: showAnswers) {
                    Label("Lösung", systemImage: "eye")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Lösung zeigen, show every answer")
            }
        }
        .frame(minHeight: 28)

        switch state {
        case .graded(let chosen, let outcome, _) where round.mode == .sofort:
            KasusCappedScroll(maxHeight: trayTextCap) {
                KasusFeedbackHeader(verdict: KasusVerdict(outcome), kasus: gap.kasus)
                    .id(gap.id)
                if !(outcome.isRight && pendingAdvance == gap.id) {
                    Text(kasusRich: outcome.isRight
                         ? KasusService.explanation(for: gap.target, in: story)
                         : KasusService.endingFeedback(for: outcome, ending: chosen, gap: gap, in: story) ?? "")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .revealed:
            KasusCappedScroll(maxHeight: trayTextCap, spacing: 6) {
                Label(KasusRound.answersShownLabel, systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(kasusRich: KasusService.explanation(for: gap.target, in: story))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            if (round.tipps[gap.id] ?? .none) > .none {
                tippReveals(gap, reached: round.tipps[gap.id] ?? .none)
            }
        }

        // The table helps with the choice; once Sofort has judged it, the verdict and why take
        // its room.
        if gap.showsCaseTable, state == .empty || round.mode == .amEnde {
            tablePanel(gap)
        }
    }

    /// Under a gap, pinned: the gender and case chips, the ending buttons, then Weiter (Sofort,
    /// once answered) or Prüfen (Am Ende). The main button's place is kept before Weiter shows
    /// (a hint stands in), so the ending buttons never move under a finger and a quick second
    /// tap can't land on the next button.
    @ViewBuilder
    private func gapFooter(_ gap: KasusEndingGap, round: KasusEndingsRound) -> some View {
        let state = play.state(of: gap)
        let pick = round.pick(for: gap.id)
        if gap.showsGenderChip || gap.showsCaseChip {
            chipsRow(gap)
        }
        if state != .revealed {
            KasusOptionGrid(options: gap.options.map(KasusEndingGap.label), answer: KasusEndingGap.label(gap.answer),
                            kasus: gap.kasus, picked: pick.map(KasusEndingGap.label), graded: round.mode == .sofort,
                            columns: KasusOptionGrid.columns(for: gap.options.map(KasusEndingGap.label)),
                            rowHeight: 46) { label in
                guard let ending = gap.options.first(where: { KasusEndingGap.label($0) == label }) else { return }
                choose(ending, for: gap)
            }
            .id("\(gap.id)-\(round.attempt)-\(round.mode.rawValue)")
        }
        switch round.mode {
        case .sofort:
            if pick != nil || state == .revealed, !(state.isRight && pendingAdvance == gap.id) {
                Button {
                    if round.isFinished { play.activeGap = nil } else { advance(from: gap.id) }
                } label: {
                    Text(round.isFinished ? "Fertig · Done" : "Weiter")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text(pick == nil ? "Tap the ending that fits." : " ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
        case .amEnde:
            Button {
                if round.allFilled { check() } else { confirmCheck = true }
            } label: {
                Text("Prüfen · Check")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // Even with nothing filled: after the question, it's how to give up and see the answers.
            .confirmationDialog(emptyGapsTitle, isPresented: $confirmCheck, titleVisibility: .visible) {
                Button("Prüfen · Check", action: check)
                Button("Weiter ausfüllen · Keep filling", role: .cancel) {}
            } message: {
                Text("An empty gap counts as not answered.")
            }
        }
    }

    /// Am Ende after Prüfen: a tapped gap's verdict (its why once the answers show), the score
    /// and a dot per gap, Lösung zeigen and Noch mal, then Ergebnis.
    @ViewBuilder
    private func checkedTray(_ round: KasusEndingsRound) -> some View {
        if let id = play.activeGap, let gap = round.gap(id) {
            checkedGapNote(gap, round: round)
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(round.rightCount) / \(round.gaps.count)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("richtig")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if play.activeGap == nil {
                    Text("Tap a gap to see why.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            KasusProgressStrip(marks: marks(round, active: nil), showsScore: false)
        }
        .accessibilityElement(children: .combine)
        // At the accessibility sizes these live in the pinned footer (`compactActions`), so a
        // long note above can't scroll them out of sight.
        if !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 10) {
                if !round.answersShown, round.rightCount < round.gaps.count {
                    Button(action: showAnswers) {
                        twoLine("Lösung zeigen", "Show answers")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                Button {
                    play.retry()
                } label: {
                    twoLine("Noch mal", "Retry")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    /// After Prüfen at the accessibility sizes: Lösung zeigen and Noch mal in one row in the
    /// pinned footer.
    private func compactActions(_ round: KasusEndingsRound) -> some View {
        HStack(spacing: 8) {
            if !round.answersShown, round.rightCount < round.gaps.count {
                Button(action: showAnswers) {
                    KasusFooterLabel(title: "Lösung", systemImage: "eye")
                }
                .accessibilityLabel("Lösung zeigen, show answers")
            }
            Button {
                play.retry()
            } label: {
                KasusFooterLabel(title: "Noch mal", systemImage: "arrow.counterclockwise")
            }
            .accessibilityLabel("Noch mal, retry")
        }
        .buttonStyle(.bordered)
        .font(.subheadline.weight(.semibold))
    }

    /// A gap tapped after Prüfen. Before Lösung zeigen a wrong one says only how it was wrong and
    /// in which case, so Noch mal is still a real try; after it, why.
    private func checkedGapNote(_ gap: KasusEndingGap, round: KasusEndingsRound) -> some View {
        let state = play.state(of: gap)
        return KasusCappedScroll(maxHeight: trayTextCap, spacing: 6) {
            switch state {
            case .graded(let chosen, let outcome, let shown):
                KasusFeedbackHeader(verdict: KasusVerdict(outcome), kasus: gap.kasus,
                                    detail: shown ? "„\(gap.answerForm) \(gap.target.noun)“" : nil)
                    .id(gap.id)
                if outcome.isRight || shown {
                    Text(kasusRich: outcome.isRight
                         ? KasusService.explanation(for: gap.target, in: story)
                         : KasusService.endingFeedback(for: outcome, ending: chosen, gap: gap, in: story) ?? "")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(outcome.isSlip
                         ? "Right case, but not this noun's gender or number. Noch mal to try again, or Lösung zeigen for the answer and why."
                         : "Not this case's ending. Noch mal to try again, or Lösung zeigen for the answer and why.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .leftEmpty:
                Label("\(KasusItemOutcome.unanswered.germanLabel) · \(KasusItemOutcome.unanswered.englishLabel)",
                      systemImage: KasusItemOutcome.unanswered.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .revealed:
                Label("\(gap.answerForm) \(gap.target.noun)", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(gap.genus.color)
                Text(kasusRich: KasusService.explanation(for: gap.target, in: story))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            case .empty, .chosen:
                EmptyView()
            }
        }
    }

    private var resultButton: some View {
        Button(action: onShowResult) {
            Text("Ergebnis · Result")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// A secondary button's label: the German on top, the English small under it.
    private func twoLine(_ german: String, _ english: String) -> some View {
        VStack(spacing: 0) {
            Text(german)
                .font(.subheadline.weight(.semibold))
            Text(english)
                .font(.caption2)
                .opacity(0.8)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }

    /// One dot per gap in reading order: its case color once right, a ring once not (or left
    /// empty, or filled by Lösung zeigen), the focus ring on `active`.
    private func marks(_ round: KasusEndingsRound, active: Int?) -> [KasusProgressStrip.Mark] {
        round.gaps.map { gap in
            switch play.state(of: gap) {
            case .graded(_, let outcome, _):
                switch KasusVerdict(outcome) {
                case .right: return .right(gap.kasus)
                case .slip:  return .slip
                case .miss:  return .miss
                }
            case .revealed, .leftEmpty:
                return .miss
            case .empty, .chosen:
                return gap.id == active ? .current : .upcoming
            }
        }
    }

    /// Lernhilfe and Viel Hilfe: the endings table for the cases in play, compact, folding to
    /// one line. Lernhilfe rings the gap's cell.
    private func tablePanel(_ gap: KasusEndingGap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { tableOpen.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "tablecells")
                    Text(tableOpen ? "Endungstabelle" : "Tabelle zeigen · Show the table")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(tableOpen ? 0 : -90))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tableOpen ? "Hide the endings table" : "Show the endings table")
            if tableOpen {
                CaseEndingsTable(cases: unit.casesInPlay, highlightCell: gap.highlightsCell ? gap.cell : nil,
                                 compact: true)
                    .transition(.opacity)
            }
        }
    }

    /// Above the buttons: „Bruder · m“ in its gender color, and at Lernhilfe the case too.
    private func chipsRow(_ gap: KasusEndingGap) -> some View {
        HStack(spacing: 8) {
            if gap.showsGenderChip {
                HStack(spacing: 4) {
                    Image(systemName: gap.genus.symbol)
                        .font(.caption2)
                    Text(gap.genderChip)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(gap.genus.color, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(7), style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(gap.target.noun), \(gap.genus.genderName)")
            }
            if gap.showsCaseChip {
                CaseLabel(kasus: gap.kasus, style: .name)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(gap.kasus.color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: appTheme.innerRadius(7), style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func tippButton(_ gap: KasusEndingGap, round: KasusEndingsRound) -> some View {
        let reached = round.tipps[gap.id] ?? .none
        return Button {
            tipp(gap)
        } label: {
            Label("Tipp", systemImage: "lightbulb")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(reached == .answer || round.isChecked)
    }

    /// What the Tipp has shown so far, in order: the deciding word, the gender, the case, the
    /// article. Showing the case or the article means the pick won't count for the coach.
    private func tippReveals(_ gap: KasusEndingGap, reached: KasusTipp) -> some View {
        HStack(spacing: 8) {
            if reached >= .trigger {
                // A bare time phrase has no deciding word, and neither has a generated story's
                // phrase that only its form proves: the verb next to it would mislead.
                Text(gap.triggerClue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if reached >= .gender {
                GenderTag(gender: gap.genus)
            }
            if reached >= .kasus {
                CaseLabel(kasus: gap.kasus, style: .name)
                    .fontWeight(.semibold)
            }
            if reached >= .answer {
                Text(gap.answerForm)
                    .fontWeight(.bold)
                    .foregroundStyle(gap.genus.color)
            }
        }
        .font(.subheadline)
    }
}

private extension KasusGapState {
    var isRight: Bool {
        if case .graded(_, let outcome, _) = self { return outcome.isRight }
        return false
    }
}
