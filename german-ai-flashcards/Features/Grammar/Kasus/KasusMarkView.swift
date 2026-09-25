//
//  KasusMarkView.swift
//  german-ai-flashcards
//
//  Markieren, the class worksheet's „Markiere alle Wörter im Dativ“: the story as numbered
//  sentences, every word a chip, one case per round. Tap every word in the asked case (the
//  article, any adjective, the noun), then Prüfen. The score is the sheet's: right minus wrong,
//  out of the words to find („6 / 10“), so marking everything scores low.
//
//    Am Ende   tap to mark and unmark freely; Prüfen shows every verdict at once
//    Sofort    each tap is judged at once with the `KasusFeedback` signal; Fertig shows the misses
//
//  After Prüfen: right = ✓ on a wash in the case color, wrong = a grey ✗ and struck through,
//  missed = a dashed outline in the case color. Never green or red. A tap on any word shows why
//  in the tray (`KasusService.markNote`). „Lösung zeigen“ shows the missed words (scrolling the
//  first one above the tray) and flags the recorded round; „Noch mal“ starts over unrecorded (with „Alle Fälle“ off again); „Nächster
//  Fall“ asks the unit's next case as a round of its own. Prüfen with nothing marked asks first
//  and records a round that answered nothing, which is how to give up and see the answers. At
//  the accessibility sizes the secondary actions sit in the pinned footer, under any note.
//  Recognition only: it counts for the streak, never for the coach.
//
//  The round's state lives in `KasusMarkPlay`, held by the player, so hopping to Lesen or
//  Endungen and back keeps every mark.
//

import SwiftUI

// MARK: - State

/// Markieren's state for one story, held by the player.
struct KasusMarkPlay {
    /// The cases this story asks, in the unit's order (`KasusService.markCases`).
    var cases: [GrammarCase] = []
    var caseIndex = 0
    var round: KasusMarkRound?
    /// The word the tray talks about: after Prüfen, the one tapped; in Sofort, the last tap.
    var selectedWord: Int?
    /// Sofort: what the last tap was, for the tray's header.
    var lastVerdict: KasusMarkVerdict?
    /// „Alle Fälle“: every target word washed in its own case's color.
    var showAllCases = false
    var clock = KasusStepClock()
    /// Rounds already recorded. A round rebuilt in the other feedback mode keeps its id, so it's
    /// never recorded twice.
    var recordedIDs: Set<UUID> = []
    /// The attempt on screen is the recorded one, so Lösung zeigen flags it.
    var attemptRecorded = false
    /// DEBUG prefill: the marks weren't the learner's, so nothing is handed on to be recorded.
    var prefilled = false
    /// DEBUG `-kasus.debugFeedback`, which wins over the stored mode without overwriting it.
    var modeOverride: KasusFeedbackMode?

    var nextCase: GrammarCase? { cases.indices.contains(caseIndex + 1) ? cases[caseIndex + 1] : nil }
    /// A round of this story has been recorded: the step bar's ✓.
    var isPlayed: Bool { !recordedIDs.isEmpty }

    /// The first case's round.
    mutating func start(in playable: KasusPlayableStory, unit: KasusUnit, mode: KasusFeedbackMode) {
        cases = KasusService.markCases(in: playable, unit: unit)
        startCase(0, in: playable, mode: mode)
    }

    /// A fresh round for `cases[index]`: „Nächster Fall“, recorded on its own.
    mutating func startCase(_ index: Int, in playable: KasusPlayableStory, mode: KasusFeedbackMode) {
        selectedWord = nil
        lastVerdict = nil
        showAllCases = false
        attemptRecorded = false
        prefilled = false
        guard cases.indices.contains(index) else {
            round = nil
            return
        }
        caseIndex = index
        round = KasusService.markRound(cases[index], in: playable, mode: mode)
        clock.restart()
    }

    /// Noch mal: the marks cleared, the same round, not recorded again. „Alle Fälle“ goes off, or
    /// the fresh attempt would open with every answer colored in.
    mutating func retry() {
        round?.reset()
        selectedWord = nil
        lastVerdict = nil
        showAllCases = false
        attemptRecorded = false
        clock.resume()
    }

    /// The other feedback mode for the round on screen. Offered before the first mark (the same
    /// round) or after Prüfen (a fresh attempt with the same id, so it isn't recorded again).
    mutating func switchMode(to mode: KasusFeedbackMode, in playable: KasusPlayableStory) {
        guard let current = round, current.mode != mode else { return }
        round = KasusMarkRound(kasus: current.kasus, text: playable.numbered, mode: mode, id: current.id)
        selectedWord = nil
        lastVerdict = nil
        showAllCases = false
        attemptRecorded = false
    }

    /// Prüfen (Am Ende) or Fertig (Sofort). Returns the round to record on its first check, nil
    /// after that (and for a DEBUG prefill).
    mutating func check(storyID: String, unit: KasusUnit, in playable: KasusPlayableStory) -> KasusRoundResult? {
        guard var current = round, !current.isChecked else { return nil }
        current.check()
        round = current
        clock.pause()
        selectedWord = nil
        lastVerdict = nil
        guard current.attempt == 1, !recordedIDs.contains(current.id) else { return nil }
        recordedIDs.insert(current.id)
        attemptRecorded = true
        let result = KasusService.markResult(current, storyID: storyID, unit: unit, in: playable,
                                             durationSeconds: clock.seconds)
        return prefilled ? nil : result
    }

    /// Lösung zeigen. Returns the recorded round's id to flag, when the attempt on screen is it.
    mutating func showAnswers() -> UUID? {
        guard var current = round, current.isChecked, !current.answersShown else { return nil }
        current.showAnswers()
        round = current
        selectedWord = nil
        return attemptRecorded && !prefilled ? current.id : nil
    }
}

// MARK: - View

struct KasusMarkStepView: View {
    @Binding var play: KasusMarkPlay
    let playable: KasusPlayableStory
    let unit: KasusUnit
    let hapticMode: HapticFeedbackMode
    /// How tall the tray's explanation may grow before it scrolls.
    let trayTextCap: CGFloat
    /// How tall the whole tray may grow before it scrolls.
    let trayCap: CGFloat
    let onComplete: (KasusRoundResult) -> Void
    let onAnswersShown: (UUID) -> Void
    /// „Weiter: Endungen“, after the last case.
    let onFinished: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(KasusFeedbackMode.markStorageKey) private var storedModeRaw = ""
    @State private var correctCount = 0
    @State private var wrongCount = 0
    /// Prüfen with nothing marked asks first: it's how to give up and see the answers.
    @State private var confirmEmptyCheck = false

    private var story: KasusStory { playable.story }

    private var currentMode: KasusFeedbackMode {
        play.modeOverride ?? KasusFeedbackMode.resolve(stored: storedModeRaw, default: KasusFeedbackMode.markDefault)
    }

    var body: some View {
        Group {
            if let round = play.round {
                content(round)
            } else {
                ContentUnavailableView("Nichts zu markieren · Nothing to mark", systemImage: "highlighter",
                                       description: Text("This story has no words to mark in this unit."))
            }
        }
        .sensoryFeedback(.success, trigger: correctCount) { old, new in
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
    }

    private func content(_ round: KasusMarkRound) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    KasusStoryHeader(story: story, unit: unit)
                    header(round)
                    KasusSentenceList(sentences: playable.sentences) { word in
                        chip(word, round)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task {
                // Opening on a word the tray already talks about (coming back to the step, a
                // DEBUG screen): its sentence goes just above the tray, like Endungen's focused
                // gap, so the note and its ringed word are on screen together. With no word
                // picked but the answers showing, the first shown answer does. A word already in
                // view stays put. After a beat, once the tray has its height.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let sentence = play.selectedWord.flatMap { playable.numbered.word($0)?.sentenceNumber }
                    ?? firstShownSentence(round)
                guard let sentence else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(sentence, anchor: UnitPoint(x: 0.5, y: 0.92))
                }
            }
            .onChange(of: round.answersShown) { _, shown in
                // Lösung zeigen: bring the first answer it showed above the tray.
                guard shown, let sentence = firstShownSentence(round) else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(sentence, anchor: UnitPoint(x: 0.5, y: 0.92))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            KasusTray(maxHeight: trayCap) {
                tray(round)
            } footer: {
                trayFooter(round)
            }
                .animation(.snappy(duration: 0.25), value: round.isChecked)
        }
    }

    // MARK: Header

    private func header(_ round: KasusMarkRound) -> some View {
        let (german, english) = KasusMarking.instruction(for: round.kasus,
                                                         countsPronouns: playable.numbered.countsPronouns)
        return VStack(alignment: .leading, spacing: 10) {
            KasusInstruction(german: german, english: english)
            HStack(spacing: 8) {
                if play.cases.count > 1 {
                    caseSteps
                }
                Spacer(minLength: 0)
                KasusOptionsMenu(mode: round.mode, modeLocked: !round.marked.isEmpty && !round.isChecked,
                                 onMode: setMode)
            }
        }
    }

    /// Dat › Akk › Nom: the cases this story asks, the current one filled, the done ones ticked.
    /// „Fall 2 von 3“ where the row doesn't fit.
    private var caseSteps: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(play.cases.enumerated()), id: \.offset) { index, kasus in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    caseStep(kasus, index: index)
                }
            }
            Text("Fall \(play.caseIndex + 1) von \(play.cases.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Case \(play.caseIndex + 1) of \(play.cases.count): \(play.cases.map(\.name).joined(separator: ", "))")
    }

    private func caseStep(_ kasus: GrammarCase, index: Int) -> some View {
        let current = index == play.caseIndex
        return HStack(spacing: 3) {
            if index < play.caseIndex {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
            Text(kasus.short)
                .font(.caption.weight(.semibold))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(current ? Color(.systemBackground) : kasus.color)
        .background(current ? kasus.color : kasus.color.opacity(0.12), in: Capsule())
    }

    // MARK: Words

    /// The sentence of the first word Lösung zeigen showed. Nil before it, or with nothing missed.
    private func firstShownSentence(_ round: KasusMarkRound) -> Int? {
        guard round.answersShown else { return nil }
        return playable.numbered.words.first { round.verdict(for: $0.id) == .shown }?.sentenceNumber
    }

    private func chip(_ word: KasusWord, _ round: KasusMarkRound) -> some View {
        let verdict = round.verdict(for: word.id)
        let style = chipStyle(word, round, verdict)
        return KasusChip(style: style, action: { tap(word) }) {
            KasusWordText.text(word, foreground: style.foreground, strikethrough: style.strikethrough)
        }
        .animation(.easeOut(duration: 0.2), value: verdict)
        .accessibilityLabel(word.text)
        .accessibilityValue(accessibilityValue(word, round, verdict))
        .accessibilityAddTraits(round.marked.contains(word.id) ? .isSelected : [])
    }

    private func chipStyle(_ word: KasusWord, _ round: KasusMarkRound, _ verdict: KasusMarkVerdict?) -> KasusChipStyle {
        let color = round.kasus.color
        var style = KasusChipStyle()
        switch verdict {
        case .right?:
            style.wash = color.opacity(0.3)
            style.badge = .check(color)
        case .wrong?:
            style.wash = Color.gray.opacity(0.16)
            style.foreground = .secondary
            style.strikethrough = true
            style.badge = .cross
        case .missed?:
            style.outline = color
            style.dashed = true
        case .shown?:
            style.outline = color
            style.dashed = true
            style.wash = color.opacity(0.14)
            style.foreground = color
        case .notCounted?:
            style.wash = Color.gray.opacity(0.12)
        case nil:
            if round.marked.contains(word.id) { style.wash = color.opacity(0.22) }
        }
        // „Alle Fälle“: every phrase in its own case's color, the verdicts kept on top. Only
        // once checked: before that it would be the answer key.
        if play.showAllCases, round.isChecked, let index = word.role.targetIndex,
           let kasus = playable.target(index)?.kasus {
            style.wash = kasus.color.opacity(verdict == .wrong ? 0.18 : 0.28)
        }
        style.selected = play.selectedWord == word.id && (round.isChecked || round.mode == .sofort)
        return style
    }

    private func accessibilityValue(_ word: KasusWord, _ round: KasusMarkRound, _ verdict: KasusMarkVerdict?) -> String {
        switch verdict {
        case .right?:      "Marked, right"
        case .wrong?:      "Marked, wrong"
        case .missed?:     "Missed"
        case .shown?:      "Missed, shown"
        case .notCounted?: "Marked, not counted"
        case nil:          round.marked.contains(word.id) ? "Marked" : ""
        }
    }

    // MARK: Actions

    private func tap(_ word: KasusWord) {
        guard var round = play.round else { return }
        if round.isChecked {
            play.selectedWord = play.selectedWord == word.id ? nil : word.id
            return
        }
        switch round.mode {
        case .amEnde:
            round.tap(word.id)
            play.round = round
            play.selectedWord = nil
        case .sofort:
            // A word already judged just shows its verdict again.
            guard !round.marked.contains(word.id) else {
                play.selectedWord = word.id
                play.lastVerdict = round.verdict(for: word.id)
                return
            }
            let verdict = round.tap(word.id)
            play.round = round
            play.selectedWord = word.id
            play.lastVerdict = verdict
            switch verdict {
            case .right?: correctCount += 1
            case .wrong?: wrongCount += 1
            default:      break
            }
        }
    }

    private func check() {
        let isAmEnde = play.round?.mode == .amEnde
        let result = play.check(storyID: story.id, unit: unit, in: playable)
        // No buzz for giving up with nothing marked.
        if isAmEnde, let score = play.round?.score, score.right + score.wrong > 0 {
            if score.points == score.caseWords { correctCount += 1 } else { wrongCount += 1 }
        }
        if let result { onComplete(result) }
    }

    private func showAnswers() {
        if let id = play.showAnswers() { onAnswersShown(id) }
    }

    private func setMode(_ mode: KasusFeedbackMode) {
        if play.modeOverride != nil {
            play.modeOverride = mode
        } else {
            storedModeRaw = mode.rawValue
        }
        play.switchMode(to: mode, in: playable)
    }

    private func nextCase() {
        play.startCase(play.caseIndex + 1, in: playable, mode: currentMode)
    }

    // MARK: Tray

    @ViewBuilder
    private func tray(_ round: KasusMarkRound) -> some View {
        if round.isChecked {
            if let id = play.selectedWord {
                wordNote(id, round)
            }
            scoreRow(round)
            // At the accessibility sizes these live in the pinned footer (`compactActions`).
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    if !round.answersShown, round.score.missed > 0 {
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
        } else if round.mode == .sofort {
            sofortFeedback(round)
            counter(round)
        } else {
            if round.marked.isEmpty {
                Text("Tap a word to mark it, tap it again to unmark it. Prüfen when you're done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            counter(round)
        }
    }

    /// The step's main button, always in view: Prüfen, Fertig, then Nächster Fall or Endungen.
    /// Prüfen with nothing marked asks first, so giving up to see the answers is one tap away.
    @ViewBuilder
    private func trayFooter(_ round: KasusMarkRound) -> some View {
        if round.isChecked {
            if dynamicTypeSize.isAccessibilitySize {
                compactActions(round)
            }
            nextButton
        } else {
            let title = round.mode == .sofort ? "Fertig · Done" : "Prüfen · Check"
            Button {
                if round.marked.isEmpty { confirmEmptyCheck = true } else { check() }
            } label: {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .confirmationDialog("Nothing is marked yet", isPresented: $confirmEmptyCheck, titleVisibility: .visible) {
                Button(title, action: check)
                Button("Weiter markieren · Keep marking", role: .cancel) {}
            } message: {
                Text("Every word to find counts as missed, and you'll see where they were.")
            }
        }
    }

    /// After Prüfen at the accessibility sizes: Alle Fälle, Lösung zeigen and Noch mal in one row
    /// in the pinned footer, so a long note in the tray can't scroll them away.
    private func compactActions(_ round: KasusMarkRound) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: $play.showAllCases) {
                KasusFooterLabel(title: "Alle Fälle", systemImage: "square.3.layers.3d")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Alle Fälle zeigen, show every case")
            if !round.answersShown, round.score.missed > 0 {
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

    /// „5 marked · 10 to find“, or in Sofort „4 richtig · 1 falsch · 10 to find“.
    private func counter(_ round: KasusMarkRound) -> some View {
        let score = round.score
        return HStack(spacing: 6) {
            if round.mode == .sofort {
                Label("\(score.right)", systemImage: "checkmark")
                    .foregroundStyle(round.kasus.color)
                Label("\(score.wrong)", systemImage: "xmark")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(round.marked.count) marked")
                    .fontWeight(.semibold)
            }
            Text("· \(score.caseWords) words to find")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.subheadline.monospacedDigit())
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    /// Sofort, before Fertig: what the last tap was. Right shows only the verdict (it would give
    /// away the rest of the phrase); wrong says why; a word that never counts says so and stays
    /// unmarked.
    @ViewBuilder
    private func sofortFeedback(_ round: KasusMarkRound) -> some View {
        if let id = play.selectedWord, let word = playable.numbered.word(id), let verdict = play.lastVerdict {
            switch verdict {
            case .right:
                KasusFeedbackHeader(verdict: .right, kasus: round.kasus, detail: "„\(word.text)“")
                    .id(id)
            case .wrong:
                KasusCappedScroll(maxHeight: trayTextCap, spacing: 6) {
                    KasusFeedbackHeader(verdict: .miss, kasus: word.role.kasus, detail: "„\(word.text)“")
                        .id(id)
                    Text(kasusRich: sofortWhy(word, round))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .notCounted:
                KasusNoteLine(text: KasusService.markNote(for: id, in: round, playable: playable) ?? "")
            case .missed, .shown:
                EmptyView()
            }
        } else {
            Text("Each tap is checked right away. Fertig when you've found them all.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A wrong tap's why. An ordinary word gets a line that doesn't name the phrase it decides,
    /// which is still there to be found.
    private func sofortWhy(_ word: KasusWord, _ round: KasusMarkRound) -> String {
        if word.role == .plain {
            return "„\(word.text)“ isn't part of a phrase in the \(KasusExplanation.caseName(round.kasus)). Only the article, any adjective and the noun are marked."
        }
        return KasusService.markNote(for: word.id, in: round, playable: playable) ?? ""
    }

    /// After Prüfen: „6 / 10“, the counts, and the „Alle Fälle“ switch. The counts drop under
    /// the score where one line can't hold them.
    private func scoreRow(_ round: KasusMarkRound) -> some View {
        let score = round.score
        let points = HStack(alignment: .firstTextBaseline, spacing: 5) {
            if score.points == score.caseWords {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(round.kasus.color)
            }
            Text(score.scoreLabel)
                .monospacedDigit()
        }
        .font(.title2.weight(.bold))
        .fixedSize()
        let counts = Text(score.countsLabel)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        return VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    points
                    counts.lineLimit(1).fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    points
                    counts.fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            // At the accessibility sizes the switch is in the pinned footer (`compactActions`).
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text(play.selectedWord == nil ? "Tap a word to see why." : "Tap it again to close.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Toggle(isOn: $play.showAllCases) {
                        Label("Alle Fälle", systemImage: "square.3.layers.3d")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .accessibilityLabel("Alle Fälle zeigen, show every case")
                }
            }
        }
    }

    /// „Nächster Fall · Next case“ while the unit has more, then on to Endungen.
    @ViewBuilder
    private var nextButton: some View {
        if let next = play.nextCase {
            Button(action: nextCase) {
                Text("Nächster Fall · \(next.name)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Nächster Fall, next case: \(next.name)")
        } else {
            Button(action: onFinished) {
                Text("Weiter: Endungen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// A tapped word after Prüfen: the phrase, its verdict, and why.
    private func wordNote(_ id: Int, _ round: KasusMarkRound) -> some View {
        let word = playable.numbered.word(id)
        let phrase = word?.role.targetIndex.flatMap { playable.target($0)?.surface } ?? word?.text ?? ""
        let note = KasusService.markNote(for: id, in: round, playable: playable) ?? ""
        return KasusCappedScroll(maxHeight: trayTextCap, spacing: 6) {
            HStack(spacing: 8) {
                Text("„\(phrase)“")
                    .fontWeight(.semibold)
                verdictTag(round.verdict(for: id), word: word, round: round)
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if !note.isEmpty {
                Text(kasusRich: note)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(id)
    }

    @ViewBuilder
    private func verdictTag(_ verdict: KasusMarkVerdict?, word: KasusWord?, round: KasusMarkRound) -> some View {
        switch verdict {
        case .right?:
            Label("Richtig", systemImage: "checkmark")
                .foregroundStyle(round.kasus.color)
        case .wrong?:
            Label("Falsch markiert", systemImage: "xmark")
                .foregroundStyle(.secondary)
        case .missed?, .shown?:
            Label("Übersehen", systemImage: "circle.dashed")
                .foregroundStyle(round.kasus.color)
        case .notCounted?:
            Text("Nicht gezählt · Not counted")
                .foregroundStyle(.secondary)
        case nil:
            if let kasus = word?.role.kasus {
                CaseLabel(kasus: kasus, style: .name)
            }
        }
    }
}
