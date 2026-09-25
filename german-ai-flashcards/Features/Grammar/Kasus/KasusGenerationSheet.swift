//
//  KasusGenerationSheet.swift
//  german-ai-flashcards
//
//  „Neue Geschichte · New story (KI)“ (Phase 3): a German tutor writes a Kasus story while the
//  sheet shows the three steps, Planen → Schreiben → Prüfen. The app picks the phrases, the tutor
//  writes prose around them, and the validator proves every answer before the story is shown
//  (`KasusStoryGenerator`). Then one of three endings:
//
//    passed     saved to „Deine KI-Geschichten“ (`KasusStoryStore.save`), then Lesen
//    fallback   both tries failed the check: the honest note, and a bundled story of the unit
//    failed     the tutor couldn't be used (a loadModel refusal): why, and the bundled story
//
//  Cancel stops the write and closes the sheet. The sheet never launches the player itself: it
//  hands the session to `onPlay` and closes, and the presenter launches it once the sheet has
//  gone, since a full-screen cover can't come up over a sheet.
//

import SwiftUI
import SwiftData

/// One generation for the sheet: the generator, what it's asked, and whose name to show.
struct KasusGenerationJob: Identifiable {
    let id = UUID()
    let generator: KasusStoryGenerator
    let request: KasusGenerationRequest
    /// „Gemma 4 E4B“, or „Canned · good“ for the DEBUG fixtures.
    let tutorName: String
}

struct KasusGenerationSheet: View {
    let job: KasusGenerationJob
    /// DEBUG (`-kasus.debugGenerate <unit> -kasus.debugOpen <screen>`): a story that passes goes
    /// straight on to the player at that screen, prefilled like any `-kasus.debugOpen` screen.
    var autoPlay: KasusStoryScreen? = nil
    /// The session to launch once the sheet has closed.
    var onPlay: (KasusSession) -> Void
    /// Every way out, cancelled included.
    var onFinished: (KasusGenerationResult) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @State private var started = false

    private var generator: KasusStoryGenerator { job.generator }
    private var unit: KasusUnit { job.request.unit }

    var body: some View {
        NavigationStack {
            List {
                introSection.themedListRow()
                stepsSection.themedListRow()
                if let result = generator.result, result.outcome != .cancelled {
                    resultSection(result).themedListRow()
                }
            }
            .themedListScreen()
            // A title and subtitle rather than a principal item, so it stays centered whichever
            // button the bar holds.
            .navigationTitle("Neue Geschichte")
            .navigationSubtitle("New story (KI)")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.default, value: generator.phase)
            .toolbar {
                if generator.phase == .finished {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Schließen") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        if generator.isStopping {
                            // A load can't be interrupted, and a write stops at its next token.
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Stoppt …")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Stopping the tutor")
                        } else {
                            Button("Abbrechen") { generator.cancel() }
                                .accessibilityHint("Stops the tutor and closes")
                        }
                    }
                }
            }
        }
        // A swipe away mid-write would leave the tutor writing for nobody; Abbrechen stops it.
        .interactiveDismissDisabled(generator.isRunning)
        .task { await run() }
        .onDisappear {
            if generator.isRunning { generator.cancel() }
        }
    }

    // MARK: - Running

    private func run() async {
        guard !started else { return }
        started = true
        let result = await generator.generate(job.request)
        onFinished(result)
        switch result.outcome {
        case .generated:
            KasusStoryStore.save(result, in: modelContext)
            #if DEBUG
            if let autoPlay, let story = result.story {
                // Long enough for the finished sheet to be seen (and screenshotted) first.
                try? await Task.sleep(for: .seconds(1.5))
                var session = KasusSession(generated: story, unit: unit, startStep: autoPlay.step)
                session.prefill = KasusPrefill.fromLaunchArguments() ?? KasusPrefill()
                onPlay(session)
                dismiss()
            }
            #endif
        case .cancelled:
            dismiss()
        case .fallback, .failed:
            break
        }
    }

    private func play(generated story: KasusStory) {
        onPlay(KasusSession(generated: story, unit: unit))
        dismiss()
    }

    private func play(bundled story: KasusStory) {
        onPlay(KasusSession(storyID: story.id, unit: unit))
        dismiss()
    }

    // MARK: - Intro

    private var levelLabel: String {
        generator.currentPlan?.level ?? job.request.level.rawValue
    }

    private var introSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wand.and.sparkles")
                    .font(.title2)
                    .foregroundStyle(unit.color)
                    .frame(width: 44, height: 44)
                    .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(unit.germanTitle) · \(levelLabel)")
                        .font(.headline)
                    Text("\(job.tutorName) writes the story. The app picks the phrases and checks every answer before you see it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if generator.writer.memorySaverActive {
                        Label("Memory saver on: a shorter story, at most A2.", systemImage: "memorychip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Planen → Schreiben → Prüfen

    private enum Step: CaseIterable {
        case plan, write, check

        var title: String {
            switch self {
            case .plan:  "Planen · Plan"
            case .write: "Schreiben · Write"
            case .check: "Prüfen · Check"
            }
        }
    }

    private enum StepState { case pending, active, done, failed }

    private var stepsSection: some View {
        Section {
            ForEach(Step.allCases, id: \.self) { step in
                stepRow(step)
            }
        }
    }

    private func stepRow(_ step: Step) -> some View {
        let state = state(of: step)
        return HStack(alignment: .top, spacing: 12) {
            stepIcon(state)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.subheadline.weight(state == .active ? .semibold : .medium))
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                Text(detail(for: step, state: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stepIcon(_ state: StepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
        case .active:
            ProgressView()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        case .failed:
            // Grey, not red: the app never colors right and wrong.
            Image(systemName: "xmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func state(of step: Step) -> StepState {
        switch generator.phase {
        case .idle, .planning:
            return step == .plan ? .active : .pending
        case .loadingModel, .writing:
            return step == .plan ? .done : step == .write ? .active : .pending
        case .checking:
            return step == .check ? .active : .done
        case .finished:
            guard let result = generator.result else { return .pending }
            switch result.outcome {
            case .generated:
                return .done
            case .fallback:
                // Every write threw: nothing was ever checked.
                if result.attempts.allSatisfy({ $0.check == nil }) {
                    return step == .plan ? .done : step == .write ? .failed : .pending
                }
                return step == .check ? .failed : .done
            case .failed:
                return step == .plan ? .done : step == .write ? .failed : .pending
            case .cancelled:
                return step == .plan ? .done : .pending
            }
        }
    }

    private func detail(for step: Step, state: StepState) -> String {
        switch step {
        case .plan:
            guard state == .done, let plan = generator.currentPlan else {
                return "Picking phrases whose case the app can prove"
            }
            return plan.phrases.isEmpty
                ? "A topic: \(plan.topic)"
                : "\(plan.phrases.count) phrases at \(plan.level), each with the word that decides its case"
        case .write:
            switch generator.phase {
            case .loadingModel:
                return "Loading \(job.tutorName)…"
            case .writing(let attempt):
                let tokens = generator.liveTokenCount
                let lead = attempt > 1 ? "2. Versuch · Second try. " : ""
                return lead + "\(job.tutorName) is writing" + (tokens > 0 ? " · \(tokens) tokens" : "…")
            default:
                if state == .failed {
                    return generator.result?.outcome == .failed
                        ? "\(job.tutorName) couldn't start"
                        : "\(job.tutorName) couldn't write a story"
                }
                if state == .done, let last = generator.attempts.last {
                    let words = last.check?.report?.wordCount
                    let tries = generator.attempts.count > 1 ? " · 2 tries" : ""
                    return (words.map { "\($0) words" } ?? "Written") + " in \(Int(last.seconds.rounded())) s" + tries
                }
                return "Plain German prose around the planned phrases"
            }
        case .check:
            switch state {
            case .active:
                return "Every article, ending and preposition, against the rules"
            case .done:
                let gradable = generator.result?.passing?.check?.gradableByCase.values.reduce(0, +) ?? 0
                return "\(gradable) answers the app can prove"
            case .failed:
                return generator.attempts.count > 1 ? "Neither try passed" : "The story didn't pass"
            case .pending:
                // Between the first try's check and the retry: say why it's writing again.
                if case .writing(let attempt) = generator.phase, attempt > 1, let first = generator.attempts.first {
                    return "1. Versuch didn't pass: \(KasusGenerationCopy.failure(of: first, unit: unit))"
                }
                return "Nothing is shown before it passes"
            }
        }
    }

    // MARK: - The ending

    @ViewBuilder
    private func resultSection(_ result: KasusGenerationResult) -> some View {
        switch result.outcome {
        case .generated:
            if let story = result.story { passedSection(story, result: result) }
        case .fallback:
            fallbackSection(result)
        case .failed:
            failedSection(result)
        case .cancelled:
            EmptyView()
        }
    }

    private func passedSection(_ story: KasusStory, result: KasusGenerationResult) -> some View {
        let gradable = result.passing?.check?.gradableByCase ?? [:]
        let words = result.passing?.check?.report?.wordCount
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fertig · Ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("„\(story.title)“")
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text([story.level, unit.germanTitle, words.map { "\($0) words" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                KasusCaseCountChips(counts: gradable)
                Button {
                    play(generated: story)
                } label: {
                    Text("Lesen · Start reading")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
                Button {
                    dismiss()
                } label: {
                    Text("Später · Later")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Saved under Deine KI-Geschichten on this unit.")
        }
    }

    private func fallbackSection(_ result: KasusGenerationResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(result.note ?? KasusStoryGenerator.fallbackNote)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                if let english = KasusGenerationCopy.english(forNote: result.note ?? KasusStoryGenerator.fallbackNote) {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.attempts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.attempts, id: \.number) { attempt in
                            Text("\(attempt.number). Versuch: \(KasusGenerationCopy.failure(of: attempt, unit: unit))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                fallbackButtons(result)
            }
            .padding(.vertical, 4)
        }
    }

    private func failedSection(_ result: KasusGenerationResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Der Tutor ist nicht bereit · The tutor isn't ready")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if let note = result.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                fallbackButtons(result)
            }
            .padding(.vertical, 4)
        }
    }

    /// The bundled story on offer. Schließen in the bar is the other way out.
    @ViewBuilder
    private func fallbackButtons(_ result: KasusGenerationResult) -> some View {
        if let story = result.story {
            Button {
                play(bundled: story)
            } label: {
                VStack(spacing: 2) {
                    Text("Fertige Geschichte lesen · Read it")
                    Text("„\(story.title)“ · \(story.level)")
                        .font(.caption)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
    }
}

/// „Nom 5 · Akk 4 · Dat 12“ as small chips in the case colors: how many answers a story has per
/// case. Cases with none are left out.
struct KasusCaseCountChips: View {
    let counts: [GrammarCase: Int]

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GrammarCase.allCases) { kasus in
                if let count = counts[kasus], count > 0 {
                    Text("\(kasus.short) \(count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(kasus.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(kasus.color.opacity(0.12), in: appTheme.pillShape)
                        .accessibilityLabel("\(count) \(kasus.name)")
                }
            }
        }
    }
}

// MARK: - Copy

/// The plain-English lines around a generation: why a try didn't pass, the English under the
/// German fallback note, and a tutor's short name.
enum KasusGenerationCopy {

    /// „a preposition with the wrong case („den Hund“)“: the first thing that rejected the try.
    static func failure(of attempt: KasusGenerationAttempt, unit: KasusUnit) -> String {
        guard let check = attempt.check else {
            return attempt.error == nil ? "nothing came back" : "the tutor stopped before the end"
        }
        guard check.story != nil, let report = check.report else { return "no story came back" }
        guard let code = check.rejectingCodes.first else { return "it didn't pass the check" }
        var line = reason(code, unit: unit, report: report, level: attempt.plan.cefr)
        let issue = report.errors.first { $0.code == code }
        if let index = issue?.target, report.targets.indices.contains(index) {
            line += " („\(report.targets[index].spec.phrase)“)"
        } else if code.isSentence, let message = issue?.message,
                  let open = message.firstIndex(of: "„"), let close = message[open...].firstIndex(of: "“") {
            // A sentence problem quotes its words first: „ich ist“.
            line += " (\(message[open...close]))"
        }
        return line
    }

    static func reason(_ code: KasusIssueCode, unit: KasusUnit, report: KasusReport, level: CEFRLevel?) -> String {
        switch code {
        case .triggerPrepositionCase:
            return "a preposition with the wrong case"
        case .triggerWechselVerb:
            return "Wo? and Wohin? mixed up"
        case .lexGender:
            return "a noun with the wrong gender"
        case .verbAgreement:
            return "a verb that doesn't fit its subject"
        case .unknownWord:
            return "a word that isn't German"
        case .lowercaseNoun:
            return "a noun without its capital"
        case .copulaAkkusativ:
            return "an Akkusativ after sein"
        case .objectNominativ:
            return "an object in the Nominativ"
        case .repeatedSentence:
            return "the same sentence over and over"
        case .unitCaseCount:
            guard let focus = unit.focusCase else { return "not two answers in every case" }
            switch report.gradableByCase[focus, default: 0] {
            case 0:         return "no answers in the \(focus.name)"
            case 1:         return "only 1 answer in the \(focus.name)"
            case let count: return "only \(count) answers in the \(focus.name)"
            }
        case .wordCount:
            guard let range = level?.storyWordRange else { return "\(report.wordCount) words, far from the level's length" }
            return "only \(report.wordCount) words, where \(level?.rawValue ?? "") asks for \(range.lowerBound)–\(range.upperBound)"
        default:
            return code.isMorphology ? "a wrong article or ending" : "it didn't pass the check"
        }
    }

    /// The English under the German fallback note.
    static func english(forNote note: String) -> String? {
        switch note {
        case KasusStoryGenerator.fallbackNote:
            "The tutor's story didn't pass the check, so here is a ready-made one instead."
        case KasusStoryGenerator.unavailableNote:
            "The tutor couldn't write a story just now, so here is a ready-made one instead."
        default:
            nil
        }
    }

    /// „Gemma 4 E4B“ for a tutor, „Canned · good“ for a DEBUG fixture, else the id as it is.
    static func tutorName(_ modelID: String) -> String {
        if let model = MLXModel(rawValue: modelID) { return shortName(model) }
        if modelID.hasPrefix("canned:") { return "Canned · " + modelID.dropFirst("canned:".count) }
        return modelID
    }

    static func shortName(_ model: MLXModel) -> String {
        model.displayName.replacingOccurrences(of: " German Tutor", with: "")
    }
}

// MARK: - Previews

#if DEBUG
private func previewSheet(_ fixture: KasusCannedOutput, unit: KasusUnit = .dativ) -> some View {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            let launch = KasusGenerateDebug.Launch(unit: unit, fixture: fixture)
            let (generator, request) = KasusGenerateDebug.generator(for: launch)
            KasusGenerationSheet(
                job: KasusGenerationJob(generator: generator, request: request,
                                        tutorName: KasusGenerationCopy.tutorName(generator.writer.modelID)),
                onPlay: { _ in }
            )
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .modelContainer(for: [GeneratedKasusStory.self, KasusRound.self], inMemory: true)
}

#Preview("Generation · passes · 4 themes") { previewSheet(.good) }
#Preview("Generation · fallback · 4 themes") { previewSheet(.wrongArticle) }
#Preview("Generation · too few · 4 themes") { previewSheet(.tooFew, unit: .akkusativ) }
#endif
