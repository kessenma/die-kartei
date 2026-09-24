//
//  KasusStoryView.swift
//  german-ai-flashcards
//
//  The story player: Lesen → Finden → Einsetzen → Ergebnis over one validated Kasus story,
//  presented full screen through `ActivityRouter` as `.kasusStory`. The two class exercises on
//  one text:
//
//    Lesen      the paragraphs, an English toggle for each, one comprehension question (unscored)
//    Finden     mark the cases: paint each article + noun phrase with a case brush, then Prüfen
//    Einsetzen  fill in the articles, with the hint ladder (Viel Hilfe · Genus-Hilfe · Ohne Hilfe)
//    Ergebnis   per-case counts, the time, the misses in their sentences, and what to try next
//
//  The text is `KasusText`: one `Text` per paragraph whose styling never moves a line (wash,
//  underline, strikethrough, color). Case labels, chips and explanations live in the bottom tray.
//  Case colors mark cases; gender colors mark only articles and gender tags; nothing is ever
//  red or green for right and wrong.
//
//  `KasusService` does the thinking (blanks, options, grading, explanations). Finden (at its first
//  Prüfen) and Einsetzen (the moment its last gap gets a first pick) each hand their round to
//  `onComplete` once, and `ContentView` passes it to `KasusService.recordRound`: Finden counts
//  for the streak only, Einsetzen can move a case skill.
//

import SwiftUI

/// Where the player opens. Real sessions start at `session.startStep`; previews and the DEBUG
/// `-kasus.debugOpen` argument can also open Finden already checked or at its summary, and
/// Ergebnis after a played round.
enum KasusStoryScreen: String, CaseIterable, Identifiable {
    case read, find, check, summary, fill, result

    var id: String { rawValue }

    var step: KasusStep {
        switch self {
        case .read:                   .lesen
        case .find, .check, .summary: .finden
        case .fill:                   .einsetzen
        case .result:                 .ergebnis
        }
    }
}

/// Time spent on one step, paused while the learner is on another, so Finden and Einsetzen never
/// bank each other's minutes when the step bar hops between them.
private struct StepClock {
    private var banked: TimeInterval = 0
    private var runningSince: Date?

    /// From zero, running.
    mutating func restart() {
        banked = 0
        runningSince = Date()
    }

    mutating func resume() {
        if runningSince == nil { runningSince = Date() }
    }

    mutating func pause() {
        guard let runningSince else { return }
        banked += Date().timeIntervalSince(runningSince)
        self.runningSince = nil
    }

    var seconds: Int {
        max(0, Int(banked + (runningSince.map { Date().timeIntervalSince($0) } ?? 0)))
    }
}

struct KasusStoryView: View {
    let session: KasusSession
    let hapticMode: HapticFeedbackMode
    /// For the hint ladder's default (Genus-Hilfe at A1–A2, Ohne Hilfe from B1). Read only.
    let germanLevel: CEFRLevel
    /// Previews only; real sessions start at `session.startStep`.
    var openAt: KasusStoryScreen? = nil
    /// Called once per scored step with its result.
    var onComplete: (KasusRoundResult) -> Void
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme
    @AppStorage(KasusHintLevel.storageKey) private var hintRaw = ""

    /// Finden's own stages: painting, the checked marks, redoing the misses, the sort grid.
    private enum FindPhase { case painting, checked, retrying, summary }

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

    // Finden
    @State private var findPhase: FindPhase = .painting
    @State private var brush: GrammarCase = .nominativ
    /// Target index → the brush it's painted with.
    @State private var paint: [Int: GrammarCase] = [:]
    /// What the text shows after Prüfen. "Noch mal die Fehler" rewrites the redone ones.
    @State private var marks: [Int: KasusFindMark] = [:]
    /// The first Prüfen, the one that's scored and recorded.
    @State private var findResult: KasusRoundResult?
    /// The phrases open again during "Noch mal die Fehler".
    @State private var retry: Set<Int> = []
    @State private var selectedTarget: Int?
    @State private var note: String?
    @State private var showAllCases = false
    @State private var findClock = StepClock()
    /// DEBUG prefill: the paint wasn't the learner's, so nothing is recorded.
    @State private var findPrefilled = false

    // Einsetzen
    /// DEBUG `-kasus.debugHint`, which wins over the stored level without overwriting it.
    @State private var hintOverride: KasusHintLevel?
    @State private var mixed = false
    @State private var roundHint: KasusHintLevel = .genus
    @State private var blanks: [KasusBlank] = []
    /// Blank id → the first pick. Later taps don't count.
    @State private var picks: [Int: String] = [:]
    /// Blank id → how far the Tipp went before the first pick.
    @State private var tipps: [Int: KasusTipp] = [:]
    @State private var activeBlank: Int?
    /// A right pick waiting out its 600 ms before moving on, and the task that will move on.
    @State private var pendingAdvance: Int?
    @State private var advanceTask: Task<Void, Never>?
    @State private var fillRound = 0
    @State private var fillClock = StepClock()
    @State private var fillPrefilled = false
    /// Set, and handed to `onComplete`, the moment the last open gap gets its first pick.
    @State private var fillResult: KasusRoundResult?

    // Haptics
    @State private var correctCount = 0
    @State private var wrongCount = 0

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        cancelAdvance()
                        onDismiss()
                    } label: {
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
        .onDisappear(perform: cancelAdvance)
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
        .sensoryFeedback(.success, trigger: correctCount) { old, new in
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
        .tint(appTheme.accent(model: nil))
    }

    // MARK: - Steps

    /// Lesen · Finden · Einsetzen, in the navigation bar. Any step can be opened from here; a
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
    }

    private func isPlayed(_ item: KasusStep) -> Bool {
        switch item {
        case .lesen:     questionPick != nil
        case .finden:    findResult != nil
        case .einsetzen: fillResult != nil
        case .ergebnis:  false
        }
    }

    /// Switches steps. A pending auto-advance is dropped, and only the step being shown keeps its
    /// clock running.
    private func go(to target: KasusStep) {
        note = nil
        selectedTarget = nil
        cancelAdvance()
        findClock.pause()
        fillClock.pause()
        switch target {
        case .finden:
            step = .finden
            if findResult == nil { findClock.resume() }
        case .einsetzen, .ergebnis:
            if fillResult != nil {
                step = .ergebnis
            } else {
                if blanks.isEmpty { startFillRound() }
                step = .einsetzen
                fillClock.resume()
            }
        case .lesen:
            step = .lesen
        }
    }

    @ViewBuilder
    private func stepContent(_ playable: KasusPlayableStory) -> some View {
        switch step {
        case .lesen:
            readStep(playable.story)
        case .finden:
            if findPhase == .summary {
                findSummary(playable)
            } else {
                findStep(playable)
            }
        case .einsetzen:
            fillStep(playable)
        case .ergebnis:
            if let fillResult {
                resultStep(fillResult, playable: playable)
            } else {
                fillStep(playable)
            }
        }
    }

    // MARK: - Setup

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        guard let playable = KasusService.prepare(session) else { return }
        self.playable = playable
        mixed = session.mixed
        hintOverride = session.prefill?.hint
        brush = unit.findenBrushes.first ?? .nominativ
        questionOrder = Array(playable.story.question.options.indices).shuffled()

        var screen = openAt
        #if DEBUG
        if screen == nil, session.prefill != nil, case .story(let debugScreen)? = KasusDebugOpen.fromLaunchArguments() {
            screen = debugScreen
        }
        #endif
        step = screen?.step ?? session.startStep
        if step == .finden { findClock.restart() }
        if step == .einsetzen || step == .ergebnis { startFillRound() }
        #if DEBUG
        if let screen { applyDebugPrefill(screen, in: playable) }
        #endif
        // Ergebnis needs a played round; without one, start the round instead.
        if step == .ergebnis, fillResult == nil { step = .einsetzen }
    }

    // MARK: - Shared pieces

    private func titleBlock(_ story: KasusStory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.title)
                .font(.title2.weight(.bold))
            Text("\(story.titleEnglish) · \(story.level) · \(unit.germanTitle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func instruction(_ german: String, _ english: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(german)
                .font(.subheadline.weight(.semibold))
            Text(english)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func targets(in paragraph: Int, _ playable: KasusPlayableStory) -> [KasusLocatedTarget] {
        playable.targets.filter { $0.paragraphIndex == paragraph }
    }

    /// The bottom tray: where case labels, chips, options and explanations live, so the story
    /// text above never has to make room for them.
    private func tray<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if appTheme == .klar {
                Rectangle().fill(.bar).ignoresSafeArea()
            } else {
                appTheme.surface.ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) { Divider() }
    }

    private func noteLine(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

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
                titleBlock(story)
                ForEach(Array(story.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    VStack(alignment: .leading, spacing: 8) {
                        KasusText(segments: [KasusTextSegment(text: paragraph.de, kind: .plain)])
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
                questionCard(story.question)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            tray {
                Button {
                    go(to: .finden)
                } label: {
                    Text("Fälle suchen · Find the cases")
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

    // MARK: - Finden

    private func findStep(_ playable: KasusPlayableStory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock(playable.story)
                instruction(findGerman, findEnglish)
                ForEach(Array(playable.story.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    KasusText(segments: findSegments(index, paragraph.de, playable)) { tap in
                        handleFindTap(tap, playable)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            tray { findTray(playable) }
        }
    }

    /// A one-brush unit marks one case only, and says so: painting every phrase would put the
    /// other cases on the wrong brush.
    private var findGerman: String {
        let brushes = unit.findenBrushes
        if brushes.count == 1, let only = brushes.first {
            return "„Markiere jede Nominalgruppe im \(only.name).“"
        }
        return "„Markiere jede Nominalgruppe mit Artikelwort (der, ein, mein …).“"
    }

    private var findEnglish: String {
        let brushes = unit.findenBrushes
        if brushes.count == 1, let only = brushes.first {
            return "Find every \(only.name) phrase, article + noun, and tap it to mark it."
        }
        return "Find every article + noun phrase, pick its case below, and tap the phrase to mark it."
    }

    /// Finden marks gradable targets only; everything else reads as words. No underline before
    /// Prüfen: every article in an authored story is a target, so the hunt is real.
    private func findSegments(_ index: Int, _ text: String, _ playable: KasusPlayableStory) -> [KasusTextSegment] {
        KasusText.segments(paragraph: text, targets: targets(in: index, playable), linkWords: true) { target in
            guard target.gradable else { return nil }
            return [KasusTextSegment(text: target.surface, kind: .target(target.index), style: findStyle(target))]
        }
    }

    private func findStyle(_ target: KasusLocatedTarget) -> KasusTextStyle {
        if findPhase == .summary, showAllCases {
            return KasusTextStyle(wash: target.kasus.color.opacity(0.26))
        }
        let selected = selectedTarget == target.index
        if let mark = marks[target.index] {
            var style: KasusTextStyle
            switch mark {
            case .right:
                style = KasusTextStyle(wash: target.kasus.color.opacity(0.3))
            case .wrongPick:
                style = KasusTextStyle(foreground: .secondary, wash: Color.gray.opacity(0.18),
                                       strikethrough: .init(pattern: .solid, color: .secondary))
            case .missed:
                style = KasusTextStyle(underline: .init(pattern: .dot, color: target.kasus.color))
            }
            if selected { style.underline = .init(pattern: .solid, color: target.kasus.color) }
            return style
        }
        var style = KasusTextStyle()
        if let painted = paint[target.index] { style.wash = painted.color.opacity(0.2) }
        if selected { style.underline = .init(pattern: .solid, color: .secondary) }
        return style
    }

    private func handleFindTap(_ tap: KasusTap, _ playable: KasusPlayableStory) {
        guard case .target(let index) = tap,
              let target = playable.targets.first(where: { $0.index == index }) else {
            selectedTarget = nil
            note = KasusService.nonTargetNote
            return
        }
        switch findPhase {
        case .painting:
            paintTap(target)
        case .retrying:
            if retry.contains(index) {
                paintTap(target)
            } else {
                note = nil
                selectedTarget = index
            }
        case .checked, .summary:
            note = nil
            selectedTarget = selectedTarget == index ? nil : index
        }
    }

    /// Paint with the selected brush; the same brush again clears it. A case the unit hasn't
    /// reached reads as plain prose and can't be painted.
    private func paintTap(_ target: KasusLocatedTarget) {
        selectedTarget = nil
        guard unit.casesInPlay.contains(target.kasus) else {
            let marking = unit.findenBrushes.map(\.short).joined(separator: ", ")
            note = "\(target.kasus.name) comes later on the path. Here you're marking \(marking)."
            return
        }
        note = nil
        paint[target.index] = paint[target.index] == brush ? nil : brush
    }

    @ViewBuilder
    private func findTray(_ playable: KasusPlayableStory) -> some View {
        switch findPhase {
        case .painting, .retrying:
            if let note { noteLine(note) }
            if let selectedTarget, let target = playable.targets.first(where: { $0.index == selectedTarget }) {
                findExplanation(target, story: playable.story)
            }
            brushRow(playable)
            Button {
                check(playable)
            } label: {
                Text(findPhase == .retrying ? "Prüfen · Check again" : "Prüfen · Check")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(findPhase == .painting && paint.isEmpty)
            if findPhase == .retrying {
                Text("Not scored. Only the phrases you missed are open again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .checked:
            if let note { noteLine(note) }
            if let selectedTarget, let target = playable.targets.first(where: { $0.index == selectedTarget }) {
                findExplanation(target, story: playable.story)
            } else {
                findScoreLine
            }
            HStack(spacing: 10) {
                if marks.values.contains(where: { $0 != .right }) {
                    Button {
                        startRetry()
                    } label: {
                        Text("Noch mal die Fehler")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button {
                    selectedTarget = nil
                    findPhase = .summary
                } label: {
                    Text("Weiter")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .summary:
            if let selectedTarget, let target = playable.targets.first(where: { $0.index == selectedTarget }) {
                findExplanation(target, story: playable.story)
            }
            Button {
                go(to: .einsetzen)
            } label: {
                Text("Weiter: Artikel einsetzen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// One chip per brush in the case's color and symbol, with how many are painted so far out of
    /// how many there are to find.
    private func brushRow(_ playable: KasusPlayableStory) -> some View {
        let counts = KasusService.findCounts(in: playable, unit: unit)
        return HStack(spacing: 8) {
            ForEach(unit.findenBrushes) { kasus in
                let selected = brush == kasus
                let painted = paint.values.filter { $0 == kasus }.count
                Button {
                    brush = kasus
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kasus.symbol)
                        Text(kasus.short)
                            .fontWeight(.semibold)
                        Text("\(painted)/\(counts[kasus] ?? 0)")
                            .monospacedDigit()
                            .opacity(0.85)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .foregroundStyle(selected ? Color.white : kasus.color)
                    .background(selected ? kasus.color : kasus.color.opacity(0.12), in: appTheme.pillShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kasus.name), \(painted) of \(counts[kasus] ?? 0) marked")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .minimumScaleFactor(0.8)
    }

    private var findScoreLine: some View {
        let right = marks.values.filter { $0 == .right }.count
        let missed = marks.values.filter { $0 == .missed }.count
        let wrong = marks.count - right - missed
        var detail: [String] = []
        if missed > 0 { detail.append("\(missed) missed") }
        if wrong > 0 { detail.append("\(wrong) on the wrong case") }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(right) of \(marks.count) right" + (detail.isEmpty ? "" : " · " + detail.joined(separator: " · ")))
                .font(.subheadline.weight(.semibold))
            Text("Tap a phrase to see why it has its case.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The tray's word on one phrase: its true case, what went wrong if anything, and why.
    private func findExplanation(_ target: KasusLocatedTarget, story: KasusStory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("„\(target.surface)“")
                    .fontWeight(.semibold)
                CaseLabel(kasus: target.kasus, style: .name)
                    .fontWeight(.semibold)
                switch marks[target.index] {
                case .wrongPick(let painted)?:
                    Text("not \(painted.name)")
                        .foregroundStyle(.secondary)
                case .missed?:
                    Text("not marked")
                        .foregroundStyle(.secondary)
                case .right?:
                    Image(systemName: "checkmark")
                        .foregroundStyle(target.kasus.color)
                case nil:
                    EmptyView()
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Text(KasusService.explanation(for: target, in: story))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func check(_ playable: KasusPlayableStory) {
        let graded = KasusService.gradeFind(paint: paint, in: playable, unit: unit)
        note = nil
        selectedTarget = nil
        switch findPhase {
        case .painting:
            marks = graded
            findPhase = .checked
            findClock.pause()
            let result = KasusService.findResult(storyID: playable.story.id, unit: unit, marks: graded,
                                                 in: playable, durationSeconds: findClock.seconds)
            findResult = result
            if result.firstTryCount == result.askedCount { correctCount += 1 } else { wrongCount += 1 }
            if !findPrefilled { onComplete(result) }
        case .retrying:
            // Unscored: only the redone phrases change. One left unpainted whose case has no brush
            // is now right by being left alone, so it loses its mark.
            for index in retry { marks[index] = graded[index] }
            retry = []
            findPhase = .checked
        case .checked, .summary:
            break
        }
    }

    /// "Noch mal die Fehler": clear the wrong and missed phrases and let them be painted again.
    private func startRetry() {
        retry = Set(marks.filter { $0.value != .right }.map(\.key))
        for index in retry {
            paint[index] = nil
            marks[index] = nil
        }
        selectedTarget = nil
        note = nil
        findPhase = .retrying
    }

    // MARK: - Finden summary

    private func findSummary(_ playable: KasusPlayableStory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let findResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gefunden · What you marked")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(findResult.firstTryCount) of \(findResult.askedCount)")
                            .font(.largeTitle.weight(.bold))
                    }
                    caseRows(findResult.perCase)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sortiert · By case and gender")
                        .font(.subheadline.weight(.semibold))
                    sortGrid(playable)
                    Text("Same case and gender, same last letter: the code from the endings table.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .themedCard()

                Toggle("Alle Fälle zeigen · Show every case", isOn: $showAllCases)
                    .font(.subheadline)

                ForEach(Array(playable.story.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    KasusText(segments: findSegments(index, paragraph.de, playable)) { tap in
                        handleFindTap(tap, playable)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            tray { findTray(playable) }
        }
    }

    /// The story's phrases sorted into the endings table's layout: case rows, gender columns,
    /// each cell the articles that landed there. Off: the cases Finden asked about. On: every case.
    private func sortGrid(_ playable: KasusPlayableStory) -> some View {
        let brushes = Set(unit.findenBrushes)
        let shown = playable.gradable.filter { showAllCases || brushes.contains($0.kasus) }
        let rows = GrammarCase.allCases.filter { kasus in shown.contains { $0.kasus == kasus } }
        return Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 12) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Gender.allCases) { gender in
                    GenderTag(gender: gender)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(rows) { kasus in
                GridRow(alignment: .top) {
                    CaseLabel(kasus: kasus)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 54, alignment: .leading)
                    ForEach(Gender.allCases) { gender in
                        sortCell(shown.filter { $0.kasus == kasus && $0.genus == gender }, gender: gender)
                    }
                }
            }
        }
    }

    private struct SortEntry: Hashable {
        let form: String
        var count: Int
    }

    /// The articles in one cell, each once with a count, in the gender's color.
    private func sortCell(_ targets: [KasusLocatedTarget], gender: Gender) -> some View {
        var forms: [SortEntry] = []
        for target in targets {
            let form = target.determiner.lowercased()
            if let i = forms.firstIndex(where: { $0.form == form }) {
                forms[i].count += 1
            } else {
                forms.append(SortEntry(form: form, count: 1))
            }
        }
        return VStack(spacing: 2) {
            if forms.isEmpty {
                Text("–")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(forms, id: \.form) { entry in
                    HStack(spacing: 2) {
                        Text(entry.form)
                            .fontWeight(.semibold)
                            .foregroundStyle(gender.color)
                        if entry.count > 1 {
                            Text("×\(entry.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Einsetzen

    private func fillStep(_ playable: KasusPlayableStory) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock(playable.story)
                    instruction("„Setz die Artikel ein.“", fillEnglish)
                    hintControl
                    ForEach(Array(playable.story.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        KasusText(segments: fillSegments(index, paragraph.de, playable)) { tap in
                            if case .blank(let id) = tap, blanks.contains(where: { $0.id == id }) {
                                pendingAdvance = nil
                                activeBlank = id
                            }
                        }
                        .id(index)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: activeParagraph) { _, paragraph in
                guard let paragraph else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(paragraph, anchor: .top) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            tray { fillTray(playable) }
        }
    }

    private var activeParagraph: Int? {
        activeBlank.flatMap { id in blanks.first { $0.id == id }?.target.paragraphIndex }
    }

    private var fillEnglish: String {
        let cases = GrammarCase.allCases.filter { kasus in blanks.contains { $0.kasus == kasus } }
        let named = cases.map(\.name).joined(separator: " and ")
        return "Fill in each gap: \(blanks.count) \(named) articles. Every other article stays as a model."
    }

    /// The hint ladder. Fixed once the first article is picked, so a round is played at one level.
    @ViewBuilder
    private var hintControl: some View {
        let available = KasusService.availableHintLevels(unit: unit, mixed: mixed)
        VStack(alignment: .leading, spacing: 6) {
            if available.count > 1 {
                Picker("Hilfe", selection: hintSelection) {
                    ForEach(available) { level in
                        Text(level.germanLabel).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!picks.isEmpty)
            }
            Text(hintDescription(roundHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hintSelection: Binding<KasusHintLevel> {
        Binding(
            get: { roundHint },
            set: { level in
                if hintOverride != nil {
                    hintOverride = level
                } else {
                    hintRaw = level.rawValue
                }
                startFillRound()
            }
        )
    }

    private func hintDescription(_ level: KasusHintLevel) -> String {
        switch level {
        case .viel:  "\(level.englishLabel): the gender after each noun, the word that decides underlined, and fewer choices."
        case .genus: "\(level.englishLabel): the gender after each noun, like the worksheet in class."
        case .ohne:  "\(level.englishLabel). Tipp shows one clue at a time: the word that decides, the gender, the case."
        }
    }

    /// Blanks in place of their articles, a raised gender tag after the noun where the level
    /// shows one (there from the start, so answering never moves the line), and the deciding word
    /// underlined for the focused blank at Viel Hilfe or once the Tipp has shown it.
    private func fillSegments(_ index: Int, _ text: String, _ playable: KasusPlayableStory) -> [KasusTextSegment] {
        let byID = Dictionary(uniqueKeysWithValues: blanks.map { ($0.id, $0) })
        var trigger: NSRange?
        if let active = activeBlank.flatMap({ byID[$0] }), active.target.paragraphIndex == index,
           picks[active.id] == nil,
           active.underlinesTrigger || (tipps[active.id] ?? .none) >= .trigger {
            trigger = active.target.triggerRange
        }
        return KasusText.segments(
            paragraph: text,
            targets: targets(in: index, playable),
            wordStyle: { range in
                guard let trigger, NSIntersectionRange(trigger, range).length > 0 else { return nil }
                return KasusTextStyle(underline: .init(pattern: .dash, color: .secondary))
            },
            render: { target in
                byID[target.index].map { blankSegments($0, in: text) }
            }
        )
    }

    private func blankSegments(_ blank: KasusBlank, in paragraph: String) -> [KasusTextSegment] {
        let target = blank.target
        let restStart = NSMaxRange(target.determinerRange)
        let rest = (paragraph as NSString).substring(with: NSRange(location: restStart,
                                                                   length: NSMaxRange(target.range) - restStart))
        let isActive = activeBlank == blank.id
        let wash: Color? = isActive ? Color.primary.opacity(0.1) : nil
        var out = answerSegments(blank, kind: .blank(blank.id), wash: wash)
        out.append(KasusTextSegment(text: rest, kind: .blank(blank.id)))
        if blank.showsGenderTag {
            out.append(KasusText.tag(blank.genus.columnLabel, color: blank.genus.color))
        } else if blank.showsNumberTag {
            out.append(KasusText.tag(blank.numberTag, color: .secondary))
        }
        return out
    }

    /// The article slot: the gap, the answer in its gender color, or ~~pick~~ answer.
    private func answerSegments(_ blank: KasusBlank, kind: KasusTextSegment.Kind, wash: Color? = nil) -> [KasusTextSegment] {
        guard let pick = picks[blank.id] else {
            return [KasusTextSegment(text: KasusText.gap(for: blank.options), kind: kind,
                                     style: KasusTextStyle(foreground: .secondary, wash: wash))]
        }
        let color = blank.genus.color
        let answer = KasusTextSegment(text: blank.answer, kind: kind,
                                      style: KasusTextStyle(foreground: color, wash: wash,
                                                            underline: .init(pattern: .solid, color: color)))
        if KasusService.grade(pick, for: blank).isRight { return [answer] }
        return [
            KasusTextSegment(text: pick, kind: kind,
                             style: KasusTextStyle(foreground: .secondary, wash: wash,
                                                   strikethrough: .init(pattern: .solid, color: .secondary))),
            KasusTextSegment(text: " ", kind: kind, style: KasusTextStyle(wash: wash)),
            answer,
        ]
    }

    @ViewBuilder
    private func fillTray(_ playable: KasusPlayableStory) -> some View {
        if let id = activeBlank, let position = blanks.firstIndex(where: { $0.id == id }) {
            let blank = blanks[position]
            if let pick = picks[blank.id] {
                fillFeedback(blank, pick: pick, story: playable.story)
            } else {
                HStack {
                    Text("Lücke \(position + 1) von \(blanks.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if blank.hintLevel == .ohne {
                        tippButton(blank)
                    }
                }
                if (tipps[blank.id] ?? .none) > .none {
                    tippReveals(blank)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                    ForEach(blank.options, id: \.self) { option in
                        Button {
                            pick(option, for: blank)
                        } label: {
                            Text(option)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } else if fillResult != nil {
            Button("Ergebnis · Result") { showResult() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        } else if blanks.isEmpty {
            noteLine("No gaps in this story at this level. Try another help level above.")
        }
    }

    private func tippButton(_ blank: KasusBlank) -> some View {
        let reached = tipps[blank.id] ?? .none
        return Button {
            tipps[blank.id] = reached.next ?? .answer
        } label: {
            Label("Tipp", systemImage: "lightbulb")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(reached == .answer)
    }

    /// What the Tipp has shown so far, in order: the deciding word, the gender, the case, the
    /// article. Showing the case or the article means the pick won't count for the coach.
    private func tippReveals(_ blank: KasusBlank) -> some View {
        let reached = tipps[blank.id] ?? .none
        return HStack(spacing: 8) {
            if reached >= .trigger {
                Text("Look at „\(blank.target.spec.trigger)“")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if reached >= .gender {
                GenderTag(gender: blank.genus)
            }
            if reached >= .kasus {
                CaseLabel(kasus: blank.kasus, style: .name)
                    .fontWeight(.semibold)
            }
            if reached >= .answer {
                Text(blank.answer)
                    .fontWeight(.bold)
                    .foregroundStyle(blank.genus.color)
            }
        }
        .font(.subheadline)
    }

    /// After a pick. Right: the case and a short confirmation while the next gap comes up.
    /// Wrong: the case, the gender-slip note or the full explanation, and Weiter.
    @ViewBuilder
    private func fillFeedback(_ blank: KasusBlank, pick: String, story: KasusStory) -> some View {
        let outcome = KasusService.grade(pick, for: blank)
        HStack(spacing: 6) {
            CaseLabel(kasus: blank.kasus, style: .name)
                .fontWeight(.semibold)
            Text("„\(blank.target.surface)“")
                .foregroundStyle(.secondary)
            if outcome.isRight {
                Image(systemName: "checkmark")
                    .foregroundStyle(blank.kasus.color)
            } else if outcome.isGenderSlip {
                Text("Gender slip")
                    .foregroundStyle(.secondary)
            } else if outcome == .numberSlip {
                Text("Number slip")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

        if outcome.isRight {
            if pendingAdvance != blank.id {
                Text(KasusService.explanation(for: blank.target, in: story))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                advanceButton(from: blank)
            }
        } else {
            Text(KasusService.feedback(for: outcome, pick: pick, target: blank.target, in: story) ?? "")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            advanceButton(from: blank)
        }
    }

    private func advanceButton(from blank: KasusBlank) -> some View {
        let isLast = !blanks.contains { picks[$0.id] == nil }
        return Button {
            advance(from: blank.id)
        } label: {
            Text(isLast ? "Ergebnis · Result" : "Weiter")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func pick(_ option: String, for blank: KasusBlank) {
        guard picks[blank.id] == nil else { return }
        picks[blank.id] = option
        // The round is recorded here, right or wrong, so closing from the last explanation still
        // counts it.
        recordFillIfComplete()
        guard KasusService.grade(option, for: blank).isRight else {
            wrongCount += 1
            return
        }
        correctCount += 1
        pendingAdvance = blank.id
        let round = fillRound
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            // Only if nothing moved in the meantime: still Einsetzen, the same round, the same gap.
            guard !Task.isCancelled, step == .einsetzen, round == fillRound,
                  pendingAdvance == blank.id, activeBlank == blank.id else { return }
            pendingAdvance = nil
            advance(from: blank.id)
        }
    }

    private func cancelAdvance() {
        advanceTask?.cancel()
        advanceTask = nil
        pendingAdvance = nil
    }

    /// The next open gap after this one, wrapping to any left earlier; Ergebnis when none are.
    private func advance(from id: Int) {
        pendingAdvance = nil
        let order = blanks.map(\.id)
        let start = (order.firstIndex(of: id) ?? -1) + 1
        let next = order[start...].first { picks[$0] == nil } ?? order.first { picks[$0] == nil }
        if let next {
            activeBlank = next
        } else {
            showResult()
        }
    }

    private func startFillRound() {
        guard let playable else { return }
        let preferred = hintOverride ?? KasusHintLevel.resolve(stored: hintRaw, level: germanLevel)
        roundHint = KasusService.effectiveHintLevel(preferred, unit: unit, mixed: mixed)
        blanks = KasusService.blanks(in: playable, unit: unit, mixed: mixed, hint: roundHint)
        picks = [:]
        tipps = [:]
        cancelAdvance()
        activeBlank = blanks.first?.id
        fillResult = nil
        fillClock.restart()
        fillPrefilled = false
        fillRound += 1
    }

    /// Once every gap has its first pick: builds the round and hands it to `onComplete`, once.
    private func recordFillIfComplete() {
        guard fillResult == nil, let playable, !blanks.isEmpty,
              blanks.allSatisfy({ picks[$0.id] != nil }) else { return }
        fillClock.pause()
        let result = KasusService.fillResult(storyID: playable.story.id, unit: unit, hint: roundHint,
                                             blanks: blanks, picks: picks, tipps: tipps,
                                             durationSeconds: fillClock.seconds)
        fillResult = result
        if !fillPrefilled { onComplete(result) }
    }

    /// Ergebnis, for a round that's been recorded.
    private func showResult() {
        guard fillResult != nil else { return }
        cancelAdvance()
        activeBlank = nil
        step = .ergebnis
    }

    // MARK: - Ergebnis

    private func resultStep(_ result: KasusRoundResult, playable: KasusPlayableStory) -> some View {
        let misses = blanks.filter { blank in
            picks[blank.id].map { !KasusService.grade($0, for: blank).isRight } ?? false
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ergebnis · Result")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(result.firstTryCount) of \(result.askedCount)")
                        .font(.largeTitle.weight(.bold))
                    Text("right on the first try")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                caseRows(result.perCase)

                HStack(spacing: 14) {
                    Label(timeString(result.durationSeconds), systemImage: "timer")
                    Label(roundHint.germanLabel, systemImage: "lightbulb")
                    if mixed {
                        Label("Gemischt", systemImage: "shuffle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !misses.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Die Fehler · Your misses")
                            .font(.subheadline.weight(.semibold))
                        ForEach(misses) { blank in
                            missRow(blank, story: playable.story)
                        }
                    }
                }

                resultButtons(result)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A miss in its sentence, corrected in place, with why.
    private func missRow(_ blank: KasusBlank, story: KasusStory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KasusText(segments: missSegments(blank, story: story), font: .body)
            if let pick = picks[blank.id] {
                Text(KasusService.feedback(for: KasusService.grade(pick, for: blank), pick: pick,
                                           target: blank.target, in: story) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func missSegments(_ blank: KasusBlank, story: KasusStory) -> [KasusTextSegment] {
        let target = blank.target
        let paragraph = story.paragraphs[target.paragraphIndex].de as NSString
        let sentence = target.sentenceRange
        guard sentence.location <= target.range.location,
              NSMaxRange(target.range) <= NSMaxRange(sentence),
              NSMaxRange(sentence) <= paragraph.length else {
            return answerSegments(blank, kind: .plain)
        }
        let before = paragraph.substring(with: NSRange(location: sentence.location,
                                                       length: target.range.location - sentence.location))
        let restStart = NSMaxRange(target.determinerRange)
        let rest = paragraph.substring(with: NSRange(location: restStart,
                                                     length: NSMaxRange(sentence) - restStart))
        var out = [KasusTextSegment(text: String(before.drop(while: \.isWhitespace)), kind: .plain)]
        out += answerSegments(blank, kind: .plain)
        // The noun keeps its leading space; only what trails the sentence goes.
        let trimmedRest = String(rest.reversed().drop(while: \.isWhitespace).reversed())
        out.append(KasusTextSegment(text: trimmedRest, kind: .plain))
        return out
    }

    @ViewBuilder
    private func resultButtons(_ result: KasusRoundResult) -> some View {
        let harder = KasusService.offersHarder(result) ? result.hintLevel?.harder : nil
        let mixedDiffers = KasusService.blankCases(unit: unit, mixed: true, hint: roundHint)
            != KasusService.blankCases(unit: unit, mixed: false, hint: roundHint)
        VStack(spacing: 10) {
            if let harder {
                Button {
                    if hintOverride != nil { hintOverride = harder } else { hintRaw = harder.rawValue }
                    playAgain(mixed: mixed)
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
            if mixedDiffers {
                Button {
                    playAgain(mixed: true)
                } label: {
                    VStack(spacing: 2) {
                        Text("Noch mal · gemischt")
                        Text(mixedSubtitle)
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if harder == nil && !mixedDiffers {
                Button {
                    playAgain(mixed: mixed)
                } label: {
                    Text("Noch mal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button("Fertig", action: onDismiss)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    /// Which cases a gemischt round blanks at this level: „Akkusativ and Dativ gaps“. Below Ohne
    /// Hilfe that leaves the Nominativ out.
    private var mixedSubtitle: String {
        let cases = GrammarCase.allCases
            .filter(KasusService.blankCases(unit: unit, mixed: true, hint: roundHint).contains)
            .map(\.name)
        let listed = cases.count > 1
            ? cases.dropLast().joined(separator: ", ") + " and " + (cases.last ?? "")
            : cases.first ?? ""
        return "\(listed) gaps"
    }

    private func playAgain(mixed: Bool) {
        self.mixed = mixed
        startFillRound()
        step = .einsetzen
    }

    // MARK: - DEBUG prefill

    #if DEBUG
    /// Fills a screen for `-kasus.debugOpen` and previews, so a simulator that can't tap can still
    /// show painted, checked and answered states. Never recorded: the answers aren't the learner's.
    private func applyDebugPrefill(_ screen: KasusStoryScreen, in playable: KasusPlayableStory) {
        let needsAnswers: Set<KasusStoryScreen> = [.check, .summary, .result]
        guard let answers = session.prefill?.answers ?? (needsAnswers.contains(screen) ? .mixed : nil) else { return }
        switch screen {
        case .read:
            break
        case .find, .check, .summary:
            paint = KasusService.debugPaint(in: playable, unit: unit, answers: answers)
            findPrefilled = true
            guard screen != .find else { return }
            check(playable)
            if screen == .summary {
                findPhase = .summary
            } else {
                // The first miss in reading order, so the tray and the text agree run to run.
                selectedTarget = marks.filter { $0.value != .right }.keys.min()
            }
        case .fill, .result:
            let all = KasusService.debugPicks(for: blanks, answers: answers)
            let answered = screen == .result ? blanks : Array(blanks.dropLast(3))
            for blank in answered { picks[blank.id] = all[blank.id] }
            fillPrefilled = true
            if screen == .result {
                recordFillIfComplete()
                showResult()
            } else {
                // Land on the last wrong pick, so the tray shows its explanation.
                let lastWrong = answered.last { blank in
                    picks[blank.id].map { !KasusService.grade($0, for: blank).isRight } ?? false
                }
                activeBlank = lastWrong?.id ?? blanks.first { picks[$0.id] == nil }?.id
            }
        }
    }
    #endif
}

// MARK: - DEBUG launch argument

#if DEBUG
/// `-kasus.debugOpen hub|unit:<unit>|read|find|check|summary|fill|result`: the Grammatik screens
/// sit several taps deep and this simulator can't tap. The player screens open the bundled Dativ
/// story, prefilled from `-kasus.debugAnswers right|mixed` and `-kasus.debugHint viel|genus|ohne`
/// (check, summary and result fall back to mixed answers, since they need some).
enum KasusDebugOpen: Identifiable, Hashable {
    case hub
    case unit(KasusUnit)
    case story(KasusStoryScreen)

    var id: String {
        switch self {
        case .hub:                "hub"
        case .unit(let unit):     "unit:\(unit.rawValue)"
        case .story(let screen):  screen.rawValue
        }
    }

    init?(argument raw: String) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.lowercased() == "hub" {
            self = .hub
        } else if value.lowercased().hasPrefix("unit:") {
            let name = value.dropFirst("unit:".count).lowercased()
            guard let unit = KasusUnit.allCases.first(where: { $0.rawValue.lowercased() == name }) else { return nil }
            self = .unit(unit)
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
    /// knows to read the screen from the launch argument.
    static func session(for screen: KasusStoryScreen) -> KasusSession? {
        guard let story = KasusStoryBank.bundled.stories.first, let unit = story.unit else { return nil }
        return KasusSession(storyID: story.id, unit: unit, startStep: screen.step,
                            prefill: KasusPrefill.fromLaunchArguments() ?? KasusPrefill())
    }
}
#endif

// MARK: - Previews

private func previewPlayer(_ screen: KasusStoryScreen, answers: KasusPrefill.Answers? = .mixed,
                           hint: KasusHintLevel? = .genus) -> some View {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            KasusStoryView(
                session: KasusSession(storyID: "ks-dat-a2-schluessel", unit: .dativ, startStep: screen.step,
                                      prefill: KasusPrefill(answers: answers, hint: hint)),
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
#Preview("Finden · 4 themes") { previewPlayer(.find) }
#Preview("Finden geprüft · 4 themes") { previewPlayer(.check) }
#Preview("Finden sortiert · 4 themes") { previewPlayer(.summary) }
#Preview("Einsetzen · 4 themes") { previewPlayer(.fill) }
#Preview("Einsetzen Ohne Hilfe · 4 themes") { previewPlayer(.fill, hint: .ohne) }
#Preview("Ergebnis · 4 themes") { previewPlayer(.result) }
