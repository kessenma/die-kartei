//
//  KasusLabView.swift
//  german-ai-flashcards
//
//  The Kasus Lab (DEBUG, Settings ▸ Developer): runs a tutor N times on the Phase 3 pipeline and
//  shows what came back, so the developer can decide whether tutor-written stories ship, or
//  whether a tutor needs a fine-tune for this workload. The table is read, not judged: no
//  thresholds, no pass/fail colors.
//
//    setup     tutor (or canned output, since the simulator can't run MLX), unit, level, runs,
//              contract A (the app plans the phrases) or B (the tutor labels every noun phrase)
//    per model gate pass rate (first try / after the retry), planned phrases verbatim / altered /
//              missing, gradable answers per case, the top issue codes, contract B's label
//              accuracy and % unverifiable, the „reads right / wrong“ taps, median seconds and
//              tokens, and how many runs had the memory saver on
//    per run   the summary lines, the two taps, and a detail screen with the text, placements,
//              harvest, issues and prompt
//    export    ShareLink: one JSONL per model (raw output, plan, report per attempt) for
//              training/results/kasus-lab_<model>.jsonl
//
//  No ModelContext anywhere: the Lab never writes rounds, the profile or a GeneratedKasusStory.
//  While it runs, the back button is hidden and the run details are locked, and leaving the
//  screen any other way (the debug sheet's Close, another tab) stops the batch, so a run can't
//  be left writing for nobody.
//

#if DEBUG
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// One model's runs as a JSONL attachment, built when the runs change rather than on every render.
struct KasusLabDocument: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}

/// Runs the Lab's generations one after another and keeps what came back. A class so the loop
/// outlives a re-render, and so the progress row alone watches the token count.
@Observable
@MainActor
final class KasusLabRunner {
    private(set) var runs: [KasusLabRun] = []
    /// The generator of the run under way.
    private(set) var generator: KasusStoryGenerator?
    private(set) var current = 0
    private(set) var total = 0
    private(set) var isRunning = false
    /// Why the last batch stopped early (a loadModel refusal), if it did.
    private(set) var stoppedNote: String?
    private(set) var exports: [String: KasusLabDocument] = [:]
    private var stopRequested = false

    /// `count` runs, each from `make(index)`. A refusal to load the tutor ends the batch: the
    /// next run would be refused the same way.
    func run(count: Int, make: (Int) -> (KasusStoryGenerator, KasusGenerationRequest)) async {
        guard !isRunning else { return }
        isRunning = true
        stopRequested = false
        stoppedNote = nil
        total = count
        for index in 0..<count {
            guard !stopRequested else { break }
            current = index + 1
            let (generator, request) = make(index)
            self.generator = generator
            let result = await generator.generate(request)
            if result.outcome == .cancelled { break }
            runs.append(KasusLabRun(result: result))
            refreshExports()
            if result.outcome == .failed {
                stoppedNote = result.note
                break
            }
        }
        generator = nil
        isRunning = false
    }

    func stop() {
        stopRequested = true
        generator?.cancel()
    }

    func setReadsRight(_ value: Bool?, for id: UUID) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].readsRight = value
        refreshExports()
    }

    func clear() {
        runs = []
        exports = [:]
        stoppedNote = nil
    }

    private func refreshExports() {
        var out: [String: KasusLabDocument] = [:]
        for model in Set(runs.map(\.modelID)) {
            let text = KasusLab.jsonl(runs.filter { $0.modelID == model })
            out[model] = KasusLabDocument(data: Data((text + "\n").utf8), fileName: KasusLab.fileName(for: model))
        }
        exports = out
    }
}

struct KasusLabView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService
    /// `-kasus.debugLab <runs>`: start that many runs on appear, with whatever writer is picked
    /// (canned mix in the simulator), so the table can be screenshotted.
    var autoRunCount: Int? = nil

    /// Who writes: a tutor on disk, or canned output (the simulator can't run MLX).
    enum Writer: Hashable {
        case tutor(MLXModel)
        case canned(KasusCannedOutput)
        /// good, altered, wrongArticle and tooFew in turn, under one name.
        case cannedMix

        var label: String {
            switch self {
            case .tutor(let model):   KasusGenerationCopy.shortName(model)
            case .canned(let kind):   "Canned · \(kind.rawValue)"
            case .cannedMix:          "Canned · mix"
            }
        }

        var isCanned: Bool {
            if case .tutor = self { return false }
            return true
        }
    }

    @State private var runner = KasusLabRunner()
    @State private var tutors: [MLXModel] = []
    @State private var writer: Writer = .cannedMix
    @State private var didSetUp = false
    @State private var unit: KasusUnit = .dativ
    @State private var level: CEFRLevel = .a2
    @State private var runCount = 5
    @State private var contract: KasusContract = .planned

    private static let levels: [CEFRLevel] = [.a1, .a2, .b1]
    private static let controlsID = "controls"

    var body: some View {
        ScrollViewReader { proxy in
            List {
                setupSection.themedListRow()
                runSection
                    .id(Self.controlsID)
                    .themedListRow()
                ForEach(KasusLab.summaries(runner.runs)) { summary in
                    summarySection(summary).themedListRow()
                }
                ForEach(Array(runner.runs.enumerated()).reversed(), id: \.element.id) { index, run in
                    runSection(run, number: index + 1).themedListRow()
                }
            }
            // When a batch ends, bring the tables up under the run button: that's what it was for.
            .onChange(of: runner.isRunning) { _, running in
                guard !running, !runner.runs.isEmpty else { return }
                withAnimation { proxy.scrollTo(Self.controlsID, anchor: .top) }
            }
        }
        .themedListScreen()
        .navigationTitle("Kasus Lab")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(runner.isRunning)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Leeren") { runner.clear() }
                    .disabled(runner.isRunning || runner.runs.isEmpty)
            }
        }
        .onAppear(perform: setUp)
        // Details are locked while a batch runs, so disappearing means the Lab was left.
        .onDisappear { if runner.isRunning { runner.stop() } }
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        tutors = MLXModel.germanTutors.filter { $0.isDownloaded && DeviceCapability.mayRun($0) }
        let picked = StoryStudyService.resolve(modelManager.selectedStoryModel)
        if let tutor = tutors.first(where: { $0 == picked }) ?? tutors.first {
            writer = .tutor(tutor)
        }
        if let autoRunCount, autoRunCount > 0 {
            runCount = min(autoRunCount, 50)
            start()
        }
    }

    // MARK: - Setup

    private var governed: Bool {
        if case .tutor(let model) = writer { return MemorySaver.isActive(for: model) }
        return false
    }

    private var setupSection: some View {
        Section {
            Picker("Tutor", selection: $writer) {
                ForEach(tutors, id: \.self) { tutor in
                    Text(KasusGenerationCopy.shortName(tutor)).tag(Writer.tutor(tutor))
                }
                Text(Writer.cannedMix.label).tag(Writer.cannedMix)
                ForEach(KasusCannedOutput.allCases, id: \.self) { kind in
                    Text(Writer.canned(kind).label).tag(Writer.canned(kind))
                }
            }
            Picker("Unit", selection: $unit) {
                ForEach(KasusUnit.allCases) { unit in
                    Text(unit.germanTitle).tag(unit)
                }
            }
            LabeledContent("Level") {
                Picker("Level", selection: $level) {
                    ForEach(Self.levels) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            Stepper("Runs: \(runCount)", value: $runCount, in: 1...50)
            VStack(alignment: .leading, spacing: 8) {
                Text("Contract")
                Picker("Contract", selection: $contract) {
                    ForEach(KasusContract.allCases, id: \.self) { contract in
                        Text(contract.label).tag(contract)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Setup").themedSectionHeader()
        } footer: {
            Text(setupFooter)
                .font(.caption2)
        }
        .disabled(runner.isRunning)
    }

    private var setupFooter: String {
        var lines: [String] = []
        lines.append(contract == .planned
                     ? "A: the app plans 5–8 phrases and the tutor must use each one verbatim."
                     : "B: no plan. The tutor writes freely and labels every noun phrase itself („FÄLLE:“), scored against the cases the form proves.")
        if tutors.isEmpty {
            lines.append("No tutor on disk fits this device, so only canned output runs here.")
        }
        if writer.isCanned {
            lines.append("Canned output plays the unit's fixture plan at its own level, always contract A.")
        }
        if governed {
            lines.append("Memory saver is on for this tutor: plans cap at A2 and 6 phrases.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: - Run

    private var runSection: some View {
        Section {
            if runner.isRunning, let generator = runner.generator {
                KasusLabProgressRow(generator: generator, current: runner.current, total: runner.total)
                Button(role: .destructive) {
                    runner.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
            } else {
                Button {
                    start()
                } label: {
                    Label(runCount == 1 ? "Run 1 story" : "Run \(runCount) stories", systemImage: "play.circle.fill")
                        .font(.headline)
                }
            }
            if let note = runner.stoppedNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func start() {
        let writer = writer, unit = unit, level = level, contract = contract
        let service = mlxService
        Task {
            await runner.run(count: runCount) { index in
                Self.makeRun(writer: writer, unit: unit, level: level, contract: contract, index: index, service: service)
            }
        }
    }

    /// One run's generator and request: a fresh seed per tutor run; canned runs play the fixture.
    private static func makeRun(writer: Writer, unit: KasusUnit, level: CEFRLevel, contract: KasusContract,
                                index: Int, service: MLXGenerationService) -> (KasusStoryGenerator, KasusGenerationRequest) {
        switch writer {
        case .tutor(let model):
            var request = KasusGenerationRequest(unit: unit, level: level, contract: contract)
            request.seed = KasusStoryPlan.randomSeed()
            return (.live(model: model, service: service), request)
        case .canned(let kind):
            let canned = KasusCannedWriter(texts: [KasusGenerationFixtures.output(for: unit, kind)],
                                           modelID: "canned:\(kind.rawValue)", delay: .milliseconds(400))
            return (KasusStoryGenerator(writer: canned), KasusGenerationFixtures.request(for: unit))
        case .cannedMix:
            let kind = KasusCannedOutput.allCases[index % KasusCannedOutput.allCases.count]
            let canned = KasusCannedWriter(texts: [KasusGenerationFixtures.output(for: unit, kind)],
                                           modelID: "canned:mix", delay: .milliseconds(400))
            return (KasusStoryGenerator(writer: canned), KasusGenerationFixtures.request(for: unit))
        }
    }

    // MARK: - Per model

    private func summarySection(_ summary: KasusLabSummary) -> some View {
        Section {
            labRow("Gate", "first try \(summary.passedFirstTry) / \(summary.runs) · after retry \(summary.passedAfterRetry) / \(summary.runs)")
            if summary.planned > 0 {
                labRow("Planned phrases", "verbatim \(summary.verbatim) / \(summary.planned) · altered \(summary.altered) · missing \(summary.missing)")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Gradable answers per story (mean)")
                    .font(.subheadline)
                if summary.gradableByCase.isEmpty {
                    Text("–").font(.caption).foregroundStyle(.secondary)
                } else {
                    KasusCaseMeanChips(means: summary.gradableByCase)
                }
            }
            codeRow("Top errors", summary.topErrors)
            codeRow("Top warnings", summary.topWarnings)
            labRow("Contract B labels", labelsLine(summary))
            labRow("Reads", "\(summary.readsRight) right · \(summary.readsWrong) wrong · \(summary.runs - summary.readsRight - summary.readsWrong) not rated")
            labRow("Median", [summary.medianSeconds.map { "\(Int($0.rounded())) s" },
                              summary.medianTokens.map { "\($0) tokens" }].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "–")
            labRow("Memory saver", "on in \(summary.governedRuns) of \(summary.runs) runs")
            if let document = runner.exports[summary.modelID] {
                ShareLink(item: document,
                          preview: SharePreview(document.fileName, image: Image(systemName: "doc.text"))) {
                    Label("Export \(document.fileName)", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Ergebnis · \(KasusGenerationCopy.tutorName(summary.modelID))").themedSectionHeader()
        } footer: {
            Text("Save the export under training/results/. One line per attempt: the raw output, the plan and the validator's report.")
                .font(.caption2)
        }
    }

    private func labelsLine(_ summary: KasusLabSummary) -> String {
        guard summary.labelAccuracy != nil || summary.unverifiableShare != nil else { return "–" }
        let accuracy = summary.labelAccuracy.map { "\(Int(($0 * 100).rounded()))% right" } ?? "none checkable"
        let share = summary.unverifiableShare.map { "\(Int(($0 * 100).rounded()))% unverifiable" } ?? "–"
        return "\(accuracy) · \(share) · \(summary.labelsByNoun) by noun · \(summary.labelsNotInStory) not in story"
    }

    private func labRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// The title over the codes: a code like coverage.untargetedDeterminer is too long to share a
    /// line with it.
    @ViewBuilder
    private func codeRow(_ title: String, _ codes: [(code: String, count: Int)]) -> some View {
        if codes.isEmpty {
            labRow(title, "none")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                ForEach(codes.prefix(5), id: \.code) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.code)
                        Spacer(minLength: 8)
                        Text("×\(entry.count)")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Per run

    private func runSection(_ run: KasusLabRun, number: Int) -> some View {
        let result = run.result
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("#\(number) · \(result.outcome.rawValue)")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("\(Int(result.totalSeconds.rounded())) s" + (result.governed ? " · saver" : ""))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let title = result.passing?.check?.story?.title ?? result.attempts.last?.check?.title {
                    Text("„\(title)“")
                        .font(.subheadline)
                }
                ForEach(result.attempts, id: \.number) { attempt in
                    Text("\(attempt.number). \(attempt.check?.summaryLine ?? attempt.error ?? "no output")")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = result.note, result.outcome == .failed {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    readsButton(run, value: true, title: "Liest sich richtig · Reads right", symbol: "hand.thumbsup")
                    readsButton(run, value: false, title: "falsch · wrong", symbol: "hand.thumbsdown")
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 2)
            NavigationLink {
                KasusLabRunDetail(run: run, number: number)
            } label: {
                Text("Text, placements, issues, prompt")
                    .font(.subheadline)
            }
            // Pushing it would count as leaving the Lab and stop the batch.
            .disabled(runner.isRunning)
        } header: {
            Text("Run \(number) · \(KasusGenerationCopy.tutorName(run.modelID)) · \(result.request.unit.germanTitle)")
                .themedSectionHeader()
        }
    }

    private func readsButton(_ run: KasusLabRun, value: Bool, title: String, symbol: String) -> some View {
        let selected = run.readsRight == value
        return Button {
            runner.setReadsRight(selected ? nil : value, for: run.id)
        } label: {
            Label(title, systemImage: selected ? symbol + ".fill" : symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .secondary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// „Nom 3.3 · Akk 2.7 · Dat 7.7 · Gen 0.0“ in the case colors, every case shown so a zero reads
/// as a zero.
private struct KasusCaseMeanChips: View {
    let means: [GrammarCase: Double]

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GrammarCase.allCases) { kasus in
                Text("\(kasus.short) \(means[kasus, default: 0], format: .number.precision(.fractionLength(1)))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(kasus.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(kasus.color.opacity(0.12), in: appTheme.pillShape)
            }
        }
    }
}

/// „Run 3 of 5 · Schreiben · 128 tokens“. Its own view so only it redraws as the tokens count up.
private struct KasusLabProgressRow: View {
    let generator: KasusStoryGenerator
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Run \(current) of \(total) · \(phaseLabel)")
                    .font(.subheadline)
                if generator.liveTokenCount > 0 {
                    Text("\(generator.liveTokenCount) tokens")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var phaseLabel: String {
        switch generator.phase {
        case .idle, .planning:         "Planen"
        case .loadingModel:            "Loading the tutor"
        case .writing(let attempt):    attempt > 1 ? "Schreiben (2. Versuch)" : "Schreiben"
        case .checking(let attempt):   attempt > 1 ? "Prüfen (2. Versuch)" : "Prüfen"
        case .finished:                "Fertig"
        }
    }
}

// MARK: - A run in detail

private struct KasusLabRunDetail: View {
    let run: KasusLabRun
    let number: Int

    var body: some View {
        List {
            Section {
                row("Outcome", run.result.outcome.rawValue)
                row("Tutor", KasusGenerationCopy.tutorName(run.modelID))
                row("Memory saver", run.result.governed ? "on" : "off")
                if let note = run.result.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .themedListRow()
            ForEach(run.result.attempts, id: \.number) { attempt in
                attemptSection(attempt).themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Run \(number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.subheadline)
    }

    private func attemptSection(_ attempt: KasusGenerationAttempt) -> some View {
        Section {
            row("Seed", "\(attempt.plan.seed)")
            row("Level · contract", "\(attempt.plan.level) · \(attempt.plan.contract.rawValue)")
            row("Time · tokens", "\(Int(attempt.seconds.rounded())) s · \(attempt.tokenCount)" + (attempt.endedEarly ? " · ended early" : ""))
            if let check = attempt.check {
                mono(check.summaryLine)
                if !check.placements.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Placements").font(.caption.weight(.semibold))
                        ForEach(check.placements, id: \.phraseID) { placement in
                            mono("\(placement.status.rawValue) · \(placement.expression)" + (placement.found.map { " → \($0)" } ?? ""))
                        }
                    }
                }
                if !check.harvest.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Harvest").font(.caption.weight(.semibold))
                        ForEach(Array(check.harvest.enumerated()), id: \.offset) { _, phrase in
                            mono("\(phrase.surface) · \(harvestLabel(phrase))")
                        }
                    }
                }
                if let issues = check.report?.issueLines, !issues.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Issues").font(.caption.weight(.semibold))
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, line in
                            mono(line)
                        }
                    }
                }
                if let labels = check.labels {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Contract B").font(.caption.weight(.semibold))
                        mono(labels.summaryLine)
                        ForEach(labels.mismatches, id: \.self) { mono($0) }
                    }
                }
            } else if let error = attempt.error {
                mono(error)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Raw output").font(.caption.weight(.semibold))
                mono(attempt.raw.isEmpty ? "(empty)" : attempt.raw)
            }
            DisclosureGroup("Prompt") {
                mono(attempt.system)
                mono(attempt.user)
            }
            .font(.subheadline)
        } header: {
            Text("\(attempt.number). Versuch · \(attempt.passes ? "passed" : "didn't pass")").themedSectionHeader()
        }
    }

    private func harvestLabel(_ phrase: KasusHarvestedPhrase) -> String {
        switch phrase.verdict {
        case .proven:                 "proven \(phrase.kasus?.short ?? "")"
        case .wrong:                  "wrong \(phrase.kasus?.short ?? "")"
        case .unverifiable(let why):  "ungraded (\(why.rawValue))"
        }
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Previews

#Preview("Kasus Lab · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                KasusLabView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}
#endif
