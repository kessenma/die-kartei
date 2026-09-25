//
//  KasusStoryView.swift
//  german-ai-flashcards
//
//  The story player: Lesen → Markieren → Endungen → Ergebnis over one validated Kasus story,
//  presented full screen through `ActivityRouter` as `.kasusStory`. The two class worksheets on
//  one text:
//
//    Lesen      the paragraphs, an English toggle for each, one comprehension question (unscored);
//               a tutor-written story has neither yet, so Lesen shows only its text
//    Markieren  mark every word in one case, the numbered sentences as chips (`KasusMarkView`)
//    Endungen   fill in the article endings on their stems, with four help levels
//               (`KasusEndingsView`)
//    Ergebnis   per-case counts, the time, the misses in their sentences, and what to try next
//
//  Both exercises show the story as numbered sentences (`KasusSentences`) and judge either after
//  each answer („Sofort“) or at Prüfen („Am Ende“), each remembering its own choice. Case colors
//  mark cases; gender colors mark only articles and gender tags; nothing is ever red or green
//  for right and wrong. The right/wrong signal is `KasusFeedback`, the same one the Schnellrunde
//  gives, and every explanation renders through `Text(kasusRich:)`.
//
//  This view holds each exercise's state (`KasusMarkPlay`, `KasusEndingsPlay`), so the step bar
//  can hop between them without losing a mark. `KasusService` does the thinking. Each round is
//  handed to `onComplete` once, on its first attempt (Markieren at Prüfen or Fertig, Endungen
//  when its last gap is answered or at Prüfen), and `ContentView` passes it to
//  `KasusService.recordRound`: Markieren counts for the streak only, Endungen can move a case
//  skill. Lösung zeigen after that goes to `onAnswersShown`, which flags the same round.
//

import SwiftUI

/// Where the player opens. Real sessions start at `session.startStep`; previews and the DEBUG
/// `-kasus.debugOpen` argument can also open Markieren checked or with its answers shown,
/// Endungen checked (Am Ende), and Ergebnis after a played round.
enum KasusStoryScreen: String, CaseIterable, Identifiable {
    case read
    case mark
    case markChecked = "mark-checked"
    case markRevealed = "mark-revealed"
    case fill
    case fillChecked = "fill-checked"
    case result

    var id: String { rawValue }

    var step: KasusStep {
        switch self {
        case .read:                                .lesen
        case .mark, .markChecked, .markRevealed:   .finden
        case .fill, .fillChecked:                  .einsetzen
        case .result:                              .ergebnis
        }
    }
}

struct KasusStoryView: View {
    let session: KasusSession
    let hapticMode: HapticFeedbackMode
    /// For the hint ladder's default (Genus-Hilfe at A1–A2, Ohne Hilfe from B1). Read only.
    let germanLevel: CEFRLevel
    /// Previews only; real sessions start at `session.startStep`.
    var openAt: KasusStoryScreen? = nil
    /// Called once per scored round with its result.
    var onComplete: (KasusRoundResult) -> Void
    /// Lösung zeigen on a round that was already handed to `onComplete`: its result's id.
    var onAnswersShown: (UUID) -> Void = { _ in }
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(KasusHintLevel.storageKey) private var hintRaw = ""

    /// Validated once, on appear: the init runs on every re-render of the cover.
    @State private var playable: KasusPlayableStory?
    @State private var didSetUp = false
    @State private var step: KasusStep = .lesen
    @State private var showKasusCheck = false

    // Lesen
    @State private var showEnglish: Set<Int> = []
    /// The question's options in the order shown, shuffled once so the answer isn't always first.
    @State private var questionOrder: [Int] = []
    @State private var questionPick: Int?
    /// A story without a question (a tutor-written one) counts Lesen as read once it's left.
    @State private var leftLesen = false

    @State private var markPlay = KasusMarkPlay()
    @State private var endingsPlay = KasusEndingsPlay()

    /// The step's height, which caps how tall the tray's explanation may grow before it scrolls.
    @State private var stepHeight: CGFloat = 0

    private var unit: KasusUnit { session.unit }

    var body: some View {
        NavigationStack {
            Group {
                if let playable {
                    stepContent(playable)
                } else if didSetUp {
                    ContentUnavailableView("Geschichte nicht gefunden · Story not found",
                                           systemImage: "book.closed")
                } else {
                    Color.clear
                }
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { stepHeight = $0 }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    if playable != nil { stepBar }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showKasusCheck = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Der Kasus-Check")
                }
            }
        }
        .onAppear(perform: setUp)
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
        .tint(appTheme.accent(model: nil))
    }

    // MARK: - Steps

    /// Lesen · Markieren · Endungen, in the navigation bar. Any step can be opened from here; a
    /// checkmark means it's been played.
    private var stepBar: some View {
        HStack(spacing: 2) {
            ForEach([KasusStep.lesen, .finden, .einsetzen]) { item in
                let current = step == item || (item == .einsetzen && step == .ergebnis)
                Button {
                    go(to: item)
                } label: {
                    HStack(spacing: 3) {
                        if isPlayed(item) {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                        }
                        Text(item.germanLabel)
                            .font(.caption.weight(current ? .semibold : .regular))
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(current ? Color.primary : Color.secondary)
                    .background(current ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear),
                                in: appTheme.pillShape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(current ? .isSelected : [])
            }
        }
        .minimumScaleFactor(0.8)
        // A navigation bar stops growing at the larger sizes; so does this, or „Markieren“ turns
        // into „Marki…“ on a small phone.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func isPlayed(_ item: KasusStep) -> Bool {
        switch item {
        case .lesen:     playable?.story.hasQuestion == false ? leftLesen : questionPick != nil
        case .finden:    markPlay.isPlayed
        case .einsetzen: endingsPlay.isPlayed
        case .ergebnis:  false
        }
    }

    /// Switches steps, starting an exercise the first time it's opened. Only the step being
    /// shown keeps its clock running.
    private func go(to target: KasusStep) {
        guard let playable else { return }
        markPlay.clock.pause()
        endingsPlay.clock.pause()
        if target != .lesen { leftLesen = true }
        switch target {
        case .lesen:
            step = .lesen
        case .finden:
            if markPlay.round == nil {
                markPlay.start(in: playable, unit: unit, mode: markMode)
            } else if markPlay.round?.isChecked == false {
                markPlay.clock.resume()
            }
            step = .finden
        case .einsetzen:
            if endingsPlay.round == nil {
                endingsPlay.start(in: playable, unit: unit, germanLevel: germanLevel)
            } else if endingsPlay.round?.isFinished == false {
                endingsPlay.clock.resume()
            }
            step = .einsetzen
        case .ergebnis:
            step = endingsPlay.round?.isFinished == true ? .ergebnis : .einsetzen
        }
    }

    private var markMode: KasusFeedbackMode {
        markPlay.modeOverride ?? KasusFeedbackMode.current(for: .find)
    }

    /// How tall the tray's verdict and explanation may grow before they scroll: about a third of
    /// the step (a fifth at the accessibility sizes), so the story keeps some room and the
    /// buttons stay on screen.
    private var trayTextCap: CGFloat {
        guard stepHeight > 0 else { return .infinity }
        return max(90, stepHeight * (dynamicTypeSize.isAccessibilitySize ? 0.2 : 0.3))
    }

    /// How tall the tray's content may grow before it scrolls (its main button, and Endungen's
    /// chips and ending buttons, stay pinned under it): two fifths of the step, which only the
    /// largest text sizes, or a four-case table on a small phone, reach.
    private var trayCap: CGFloat { stepHeight > 0 ? max(200, stepHeight * 0.4) : .infinity }

    @ViewBuilder
    private func stepContent(_ playable: KasusPlayableStory) -> some View {
        switch step {
        case .lesen:
            readStep(playable.story)
        case .finden:
            KasusMarkStepView(play: $markPlay, playable: playable, unit: unit, hapticMode: hapticMode,
                              trayTextCap: trayTextCap, trayCap: trayCap, onComplete: onComplete,
                              onAnswersShown: onAnswersShown, onFinished: { go(to: .einsetzen) })
        case .einsetzen:
            endingsStep(playable)
        case .ergebnis:
            if let round = endingsPlay.round, round.isFinished {
                resultStep(round, playable: playable)
            } else {
                endingsStep(playable)
            }
        }
    }

    private func endingsStep(_ playable: KasusPlayableStory) -> some View {
        KasusEndingsStepView(play: $endingsPlay, playable: playable, unit: unit, germanLevel: germanLevel,
                             hapticMode: hapticMode, trayTextCap: trayTextCap, trayCap: trayCap,
                             onComplete: onComplete,
                             onAnswersShown: onAnswersShown, onShowResult: {
                                 endingsPlay.clock.pause()
                                 step = .ergebnis
                             })
    }

    // MARK: - Setup

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        guard let playable = KasusService.prepare(session) else { return }
        self.playable = playable
        questionOrder = Array(playable.story.question.options.indices).shuffled()
        markPlay.modeOverride = session.prefill?.feedback
        endingsPlay.modeOverride = session.prefill?.feedback
        endingsPlay.hintOverride = session.prefill?.hint
        endingsPlay.mixed = session.mixed

        var screen = openAt
        #if DEBUG
        if screen == nil, session.prefill != nil, case .story(let debugScreen)? = KasusDebugOpen.fromLaunchArguments() {
            screen = debugScreen
        }
        // Checking is Am Ende's, so that screen opens in it whatever is stored.
        if screen == .fillChecked { endingsPlay.modeOverride = .amEnde }
        #endif
        step = screen?.step ?? session.startStep
        if step != .lesen { leftLesen = true }
        if step == .finden { markPlay.start(in: playable, unit: unit, mode: markMode) }
        if step == .einsetzen || step == .ergebnis {
            endingsPlay.start(in: playable, unit: unit, germanLevel: germanLevel)
        }
        #if DEBUG
        if let screen { applyDebugPrefill(screen, in: playable) }
        #endif
        // Ergebnis needs a finished round; without one, start the round instead.
        if step == .ergebnis, endingsPlay.round?.isFinished != true { step = .einsetzen }
    }

    // MARK: - Shared pieces

    /// The code word with each letter in its column's gender color, as the endings table shows it.
    private func codeWord(_ kasus: GrammarCase) -> Text {
        var out = AttributedString()
        for (letter, gender) in zip(kasus.code, Gender.allCases) {
            var run = AttributedString(String(letter))
            run.foregroundColor = gender.color
            out += run
        }
        return Text(out)
    }

    /// First-try counts per case, in table order: the Schnellrunde summary's shape.
    private func caseRows(_ perCase: [GrammarCase: KasusRound.CaseTally]) -> some View {
        VStack(spacing: 10) {
            ForEach(GrammarCase.allCases) { kasus in
                if let tally = perCase[kasus], tally.asked > 0 {
                    HStack {
                        CaseLabel(kasus: kasus, style: .name)
                            .frame(width: 130, alignment: .leading)
                        codeWord(kasus)
                            .font(.headline.weight(.heavy))
                        Spacer()
                        Text("\(tally.firstTry) / \(tally.asked)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    // MARK: - Lesen

    private func readStep(_ story: KasusStory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                KasusStoryHeader(story: story, unit: unit)
                ForEach(Array(story.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    VStack(alignment: .leading, spacing: 8) {
                        KasusText(segments: [KasusTextSegment(text: paragraph.de, kind: .plain)])
                        // A tutor-written story has no English yet: no toggle to an empty line.
                        if !paragraph.en.isEmpty {
                            if showEnglish.contains(index) {
                                Text(paragraph.en)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Button(showEnglish.contains(index) ? "Hide English" : "Show English") {
                                if showEnglish.contains(index) {
                                    showEnglish.remove(index)
                                } else {
                                    showEnglish.insert(index)
                                }
                            }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.borderless)
                        }
                    }
                }
                if story.hasQuestion {
                    questionCard(story.question)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            KasusTray {
                Button {
                    go(to: .finden)
                } label: {
                    Text("Markieren · Mark the case")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    /// One question about what happened. Not scored: it's there so the story is read as a story
    /// before it becomes an exercise.
    private func questionCard(_ question: KasusStory.Question) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Frage · Question")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(question.de)
                .font(.headline)
            Text(question.en)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(questionOrder.filter(question.options.indices.contains), id: \.self) { index in
                questionOption(question.options[index], index: index, answer: question.answer)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    private func questionOption(_ option: String, index: Int, answer: Int) -> some View {
        let answered = questionPick != nil
        let isAnswer = index == answer
        let missed = answered && questionPick == index && !isAnswer
        return Button {
            questionPick = index
        } label: {
            HStack(spacing: 8) {
                Text(option)
                    .strikethrough(missed)
                    .foregroundStyle(missed ? Color.secondary : Color.primary)
                Spacer(minLength: 8)
                if answered && isAnswer {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous)
                    .fill(answered && isAnswer ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(Color.secondary.opacity(0.08)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    // MARK: - Ergebnis

    /// Endungen's result, for the round on screen (a Noch mal shows its own picks; what was
    /// recorded is the first attempt). In Am Ende the misses keep their answers back until
    /// Lösung zeigen, the same as in the exercise.
    private func resultStep(_ round: KasusEndingsRound, playable: KasusPlayableStory) -> some View {
        let result = KasusService.endingsResult(round, storyID: playable.story.id, unit: unit,
                                                durationSeconds: endingsPlay.clock.seconds, story: playable.story)
        let misses = round.gaps.filter { round.outcome(for: $0.id)?.isRight != true }
        let answersShow = round.mode == .sofort || round.answersShown
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ergebnis · Result")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    // „5 / 8 richtig“, as the tray says it after Prüfen.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(result.firstTryCount) / \(result.askedCount)")
                            .font(.largeTitle.weight(.bold))
                            .monospacedDigit()
                        Text("richtig")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text(round.mode == .sofort ? "Right on the first try" : "Right at Prüfen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                KasusProgressStrip(marks: resultMarks(round), showsScore: false)

                caseRows(result.perCase)

                HStack(spacing: 14) {
                    Label(timeString(result.durationSeconds), systemImage: "timer")
                    Label(round.hint.germanLabel, systemImage: "lightbulb")
                    Label(round.mode.germanLabel, systemImage: round.mode == .sofort ? "bolt" : "checklist")
                    if endingsPlay.mixed {
                        Label("Gemischt", systemImage: "shuffle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                if round.answersShown {
                    Label(KasusRound.answersShownLabel, systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !misses.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Die Fehler · Your misses")
                            .font(.subheadline.weight(.semibold))
                        if !answersShow {
                            HStack(spacing: 10) {
                                Text("The answers stay hidden until you ask for them.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Button("Lösung zeigen") {
                                    if let id = endingsPlay.showAnswers() { onAnswersShown(id) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        ForEach(misses) { gap in
                            missRow(gap, round: round, story: playable.story, showsAnswer: answersShow)
                        }
                    }
                }

                resultButtons(result, round: round)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultMarks(_ round: KasusEndingsRound) -> [KasusProgressStrip.Mark] {
        round.gaps.map { gap in
            guard let outcome = round.outcome(for: gap.id) else { return .miss }
            switch KasusVerdict(outcome) {
            case .right: return .right(gap.kasus)
            case .slip:  return .slip
            case .miss:  return .miss
            }
        }
    }

    /// A miss in its sentence, ~~pick~~ answer (or ~~pick~~ d__ while the answer is hidden),
    /// with why once the answers show.
    private func missRow(_ gap: KasusEndingGap, round: KasusEndingsRound, story: KasusStory,
                         showsAnswer: Bool) -> some View {
        let pick = round.pick(for: gap.id)
        let why: String? = if !showsAnswer {
            nil
        } else if let pick {
            KasusService.endingFeedback(for: KasusService.grade(ending: pick, for: gap), ending: pick, gap: gap, in: story)
        } else {
            KasusService.explanation(for: gap.target, in: story)
        }
        return VStack(alignment: .leading, spacing: 6) {
            if let number = playable?.numbered.sentenceNumber(ofTarget: gap.id) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(number).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(missSentence(gap, pick: pick, showsAnswer: showsAnswer, sentence: number))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
            }
            if pick == nil {
                Text(round.revealed.contains(gap.id) ? KasusRound.answersShownLabel : "Leer · Left empty")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let why {
                Text(kasusRich: why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func missSentence(_ gap: KasusEndingGap, pick: String?, showsAnswer: Bool, sentence number: Int) -> AttributedString {
        guard let sentence = playable?.numbered.sentence(number) else { return AttributedString(gap.target.surface) }
        var out = AttributedString()
        for (i, word) in sentence.words.enumerated() {
            if i > 0 { out += AttributedString(" ") }
            guard word.role.targetIndex == gap.id, word.role.part == .determiner else {
                out += AttributedString(word.display)
                continue
            }
            out += AttributedString(word.leading)
            if let pick {
                var struck = AttributedString(gap.form(pick))
                struck.strikethroughStyle = .single
                struck.foregroundColor = .secondary
                out += struck + AttributedString(" ")
            }
            var answer = AttributedString(showsAnswer ? gap.answerForm : gap.gapText)
            if showsAnswer {
                answer.foregroundColor = gap.genus.color
                answer.inlinePresentationIntent = .stronglyEmphasized
                answer.underlineStyle = Text.LineStyle(pattern: .solid, color: gap.kasus.color)
            } else {
                answer.foregroundColor = .secondary
            }
            out += answer + AttributedString(word.trailing)
        }
        return out
    }

    @ViewBuilder
    private func resultButtons(_ result: KasusRoundResult, round: KasusEndingsRound) -> some View {
        let harder = KasusService.offersHarder(result) ? result.hintLevel?.harder : nil
        let mixedDiffers = KasusService.blankCases(unit: unit, mixed: true, hint: round.hint)
            != KasusService.blankCases(unit: unit, mixed: false, hint: round.hint)
        VStack(spacing: 10) {
            if let harder {
                Button {
                    if endingsPlay.hintOverride != nil { endingsPlay.hintOverride = harder } else { hintRaw = harder.rawValue }
                    playAgain(mixed: endingsPlay.mixed)
                } label: {
                    VStack(spacing: 2) {
                        Text("Noch mal · eine Stufe schwerer")
                        Text(harder.germanLabel)
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if mixedDiffers, !endingsPlay.mixed {
                Button {
                    playAgain(mixed: true)
                } label: {
                    VStack(spacing: 2) {
                        Text("Noch mal · gemischt")
                        Text(mixedSubtitle(round.hint))
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button {
                // The same gaps again, unrecorded, like the exercise's own Noch mal.
                endingsPlay.retry()
                step = .einsetzen
            } label: {
                Text("Noch mal · Retry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button("Fertig", action: onDismiss)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    /// Which cases a gemischt round asks at this level: „Akkusativ and Dativ gaps“. Below Ohne
    /// Hilfe that leaves the Nominativ out.
    private func mixedSubtitle(_ hint: KasusHintLevel) -> String {
        let cases = GrammarCase.allCases
            .filter(KasusService.blankCases(unit: unit, mixed: true, hint: hint).contains)
            .map(\.name)
        let listed = cases.count > 1
            ? cases.dropLast().joined(separator: ", ") + " and " + (cases.last ?? "")
            : cases.first ?? ""
        return "\(listed) gaps"
    }

    /// A new round (another level, or gemischt): recorded when it's finished.
    private func playAgain(mixed: Bool) {
        guard let playable else { return }
        endingsPlay.mixed = mixed
        endingsPlay.start(in: playable, unit: unit, germanLevel: germanLevel)
        step = .einsetzen
    }

    // MARK: - DEBUG prefill

    #if DEBUG
    /// Fills a screen for `-kasus.debugOpen` and previews, so a simulator that can't tap can still
    /// show marked, checked and answered states. Never recorded: the answers aren't the learner's.
    private func applyDebugPrefill(_ screen: KasusStoryScreen, in playable: KasusPlayableStory) {
        let needsAnswers: Set<KasusStoryScreen> = [.markChecked, .markRevealed, .fillChecked, .result]
        let answers = session.prefill?.answers ?? (needsAnswers.contains(screen) ? .mixed : nil)
        switch screen {
        case .read:
            break
        case .mark, .markChecked, .markRevealed:
            guard var round = markPlay.round else { return }
            markPlay.prefilled = true
            var last: (id: Int, verdict: KasusMarkVerdict?)?
            if let answers {
                for id in KasusService.debugMarks(for: round, answers: answers) {
                    last = (id, round.tap(id))
                }
            }
            markPlay.round = round
            if screen == .mark {
                if round.mode == .sofort, let last {
                    markPlay.selectedWord = last.id
                    markPlay.lastVerdict = last.verdict
                }
                return
            }
            _ = markPlay.check(storyID: playable.story.id, unit: unit, in: playable)
            if screen == .markRevealed {
                _ = markPlay.showAnswers()
            } else if let checked = markPlay.round {
                // The first wrong mark in reading order, so the tray and the text agree run to run.
                markPlay.selectedWord = checked.marked.sorted().first { checked.verdict(for: $0) == .wrong }
            }
        case .fill, .fillChecked, .result:
            guard var round = endingsPlay.round else { return }
            if let answers {
                let picks = KasusService.debugEndingPicks(for: round.gaps, answers: answers)
                let answered: ArraySlice<KasusEndingGap> = switch screen {
                case .fill:        round.gaps.dropLast(3)
                case .fillChecked: round.gaps.dropLast(1)
                default:           round.gaps[...]
                }
                for gap in answered {
                    if let ending = picks[gap.id] { round.choose(ending, for: gap.id) }
                }
            }
            switch screen {
            case .fill:
                // Land on the last wrong pick, so the tray shows its explanation, else the first
                // empty gap.
                let lastWrong = round.gaps.last { round.outcome(for: $0.id).map { !$0.isRight } ?? false }
                endingsPlay.activeGap = lastWrong?.id ?? round.gaps.first { round.pick(for: $0.id) == nil }?.id
            case .fillChecked:
                round.check()
                endingsPlay.activeGap = nil
            default:
                round.check()
                endingsPlay.activeGap = nil
                step = .ergebnis
            }
            endingsPlay.round = round
            endingsPlay.prefilled = true
            _ = endingsPlay.resultIfFinished(storyID: playable.story.id, unit: unit, story: playable.story)
        }
    }
    #endif
}

// MARK: - DEBUG launch argument

#if DEBUG
/// `-kasus.debugOpen hub|unit:<unit>|quick:<unit>|read|mark|mark-checked|mark-revealed|fill|
/// fill-checked|result`: the Grammatik screens sit several taps deep and this simulator can't
/// tap. The player screens open the bundled Dativ story (or `-kasus.debugStory <id>`),
/// prefilled from `-kasus.debugAnswers right|mixed`, `-kasus.debugHint lern|viel|genus|ohne` and
/// `-kasus.debugFeedback sofort|amEnde` (mark-checked, mark-revealed, fill-checked and result
/// fall back to mixed answers, since they need some; fill-checked always runs Am Ende).
/// `quick:<unit>` opens that unit's Schnellrunde, prefilled from `-kasus.debugAnswers` and
/// `-kasus.debugQuickState right|wrong|slip|done`.
enum KasusDebugOpen: Identifiable, Hashable {
    case hub
    case unit(KasusUnit)
    case quick(KasusUnit)
    case story(KasusStoryScreen)

    var id: String {
        switch self {
        case .hub:                "hub"
        case .unit(let unit):     "unit:\(unit.rawValue)"
        case .quick(let unit):    "quick:\(unit.rawValue)"
        case .story(let screen):  screen.rawValue
        }
    }

    init?(argument raw: String) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        func unitNamed(after prefix: String) -> KasusUnit? {
            let name = value.dropFirst(prefix.count).lowercased()
            return KasusUnit.allCases.first { $0.rawValue.lowercased() == name }
        }
        if value.lowercased() == "hub" {
            self = .hub
        } else if value.lowercased().hasPrefix("unit:") {
            guard let unit = unitNamed(after: "unit:") else { return nil }
            self = .unit(unit)
        } else if value.lowercased().hasPrefix("quick:") {
            guard let unit = unitNamed(after: "quick:") else { return nil }
            self = .quick(unit)
        } else if let screen = KasusStoryScreen(rawValue: value.lowercased()) {
            self = .story(screen)
        } else {
            return nil
        }
    }

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> KasusDebugOpen? {
        defaults.string(forKey: "kasus.debugOpen").flatMap { KasusDebugOpen(argument: $0) }
    }

    /// The session a player screen launches. Its prefill is never nil, which is how the player
    /// knows to read the screen from the launch argument. `-kasus.debugStory <id>` picks another
    /// bundled story than the first.
    static func session(for screen: KasusStoryScreen) -> KasusSession? {
        let stories = KasusStoryBank.bundled.stories
        let wanted = UserDefaults.standard.string(forKey: "kasus.debugStory")
        let picked = wanted.flatMap { id in stories.first { $0.id == id } } ?? stories.first
        guard let story = picked, let unit = story.unit else { return nil }
        return KasusSession(storyID: story.id, unit: unit, startStep: screen.step,
                            prefill: KasusPrefill.fromLaunchArguments() ?? KasusPrefill())
    }

    /// The Schnellrunde `quick:<unit>` launches, with a prefill so the drill reads its state from
    /// the launch arguments.
    static func quickSession(for unit: KasusUnit) -> CaseEndingsSession {
        CaseEndingsSession(unit: unit, prefill: KasusPrefill.fromLaunchArguments() ?? KasusPrefill())
    }
}
#endif

// MARK: - Previews

private func previewPlayer(_ screen: KasusStoryScreen, answers: KasusPrefill.Answers? = .mixed,
                           hint: KasusHintLevel? = .genus, feedback: KasusFeedbackMode? = nil) -> some View {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            KasusStoryView(
                session: KasusSession(storyID: "ks-dat-a2-schluessel", unit: .dativ, startStep: screen.step,
                                      prefill: KasusPrefill(answers: answers, hint: hint, feedback: feedback)),
                hapticMode: .all,
                germanLevel: .a2,
                openAt: screen,
                onComplete: { _ in },
                onDismiss: {}
            )
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}

#Preview("Lesen · 4 themes") { previewPlayer(.read, answers: nil) }
#Preview("Markieren · 4 themes") { previewPlayer(.mark) }
#Preview("Markieren Sofort · 4 themes") { previewPlayer(.mark, feedback: .sofort) }
#Preview("Markieren geprüft · 4 themes") { previewPlayer(.markChecked) }
#Preview("Markieren Lösung · 4 themes") { previewPlayer(.markRevealed) }
#Preview("Endungen Lernhilfe · 4 themes") { previewPlayer(.fill, answers: nil, hint: .lern) }
#Preview("Endungen Viel Hilfe · 4 themes") { previewPlayer(.fill, hint: .viel) }
#Preview("Endungen Ohne Hilfe · 4 themes") { previewPlayer(.fill, hint: .ohne) }
#Preview("Endungen geprüft · 4 themes") { previewPlayer(.fillChecked) }
#Preview("Ergebnis · 4 themes") { previewPlayer(.result) }
