//
//  KasusStoryGenerator.swift
//  german-ai-flashcards
//
//  A tutor-written Kasus story (Phase 3): Planen → Schreiben → Prüfen, one retry with a new seed,
//  then a bundled story with an honest note. The app is always the answer key: the planner picks
//  phrases the validator can prove, the tutor only writes prose around them, and
//  `KasusStoryCheck` proves every graded answer before a story is shown.
//
//    model       German tutors only (`StoryStudyService.resolve(selectedStoryModel)`), gated by
//                `ModelReadiness` .germanTutor. The call is `generateStreamedText` with the level's
//                `storyMaxTokens` at temperature 0.75; the output is plain TITEL:/GESCHICHTE: prose.
//    memory      one heavy resident: `loadModel` refuses while pictures are drawn or another model
//                is generating, and the refusal comes back as the failure message. The writer also
//                refuses while the tutor is already writing something else (a chat reply, the
//                batch queue), so two writes never share one model. It asks before every attempt,
//                so a tutor dropped between the tries is reloaded, or the refusal is shown. With
//                the memory saver on for the tutor, the plan is capped at A2 and six phrases.
//    cut off     a write that ended early (stopped at the memory floor, timed out) or doesn't end
//                on a full sentence is trimmed to its last complete sentence before the check.
//    storage     none here. The screen saves a passing story (`KasusStoryStore.save`); the Lab runs
//                the same generator and saves nothing.
//
//  The model call sits behind `KasusStoryWriter`, so tests, the Lab's fixtures and
//  `-kasus.debugGenerate` run the whole pipeline on canned output in the simulator, where MLX
//  can't run.
//

import Foundation

// MARK: - The model call

/// What the generator needs from a model. The app's goes through
/// `MLXGenerationService.generateStreamedText`; `KasusCannedWriter` (DEBUG) hands back fixtures.
@MainActor
protocol KasusStoryWriter: AnyObject {
    /// For records: an `MLXModel` raw value, or „canned:good“.
    var modelID: String { get }
    /// The memory saver governs this model: the plan is capped.
    var memorySaverActive: Bool { get }
    /// Tokens so far in the write under way (MLX reports it in steps of 32).
    var liveTokenCount: Int { get }
    /// Loads the model if needed. Nil when ready, else what to tell the learner.
    func prepare() async -> String?
    func write(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> KasusWriterOutput
    /// Ends the write under way; it returns the partial text.
    func stop()
}

nonisolated struct KasusWriterOutput: Hashable {
    let text: String
    let tokenCount: Int
    /// Stopped, timed out or cut at the memory floor.
    let endedEarly: Bool
}

/// A German tutor through the app's one MLX service.
@MainActor
final class KasusMLXWriter: KasusStoryWriter {
    let service: MLXGenerationService
    let model: MLXModel

    init(service: MLXGenerationService, model: MLXModel) {
        self.service = service
        self.model = model
    }

    var modelID: String { model.rawValue }
    var memorySaverActive: Bool { MemorySaver.isActive(for: model) }
    var liveTokenCount: Int { service.streamingTokenCount }

    /// The write under way, so `stop()` can cancel it even before the first token: the service
    /// clears its stop flag once the prompt is read in, but a cancelled task stays cancelled.
    private var writeTask: Task<String, Error>?

    func prepare() async -> String? {
        guard StoryStudyService.isEligible(model) else { return "Only the German tutors write Kasus stories." }
        // One write per model at a time: the queue or a chat reply may be using the tutor, and a
        // second write would share its memory, its token count and its stop button.
        if BatchQueueService.shared.isRunning {
            return "The queue is using the tutor right now. Try again once it finishes."
        }
        if service.isGenerating { return "The tutor is still answering. Try again in a moment." }
        if service.isModelLoaded && service.currentModel == model { return nil }
        // loadModel refuses quietly (another model generating, pictures being drawn, over the
        // memory budget) and leaves the reason in loadError.
        await service.loadModel(model)
        if service.isModelLoaded && service.currentModel == model { return nil }
        return service.loadError ?? "Couldn’t load \(model.displayName)."
    }

    func write(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> KasusWriterOutput {
        let service = service, model = model
        let task = Task { @MainActor in
            try await service.generateStreamedText(system: system, user: user, model: model,
                                                   maxTokens: maxTokens, temperature: temperature)
        }
        writeTask = task
        defer { writeTask = nil }
        let text = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        return KasusWriterOutput(text: text, tokenCount: service.streamingTokenCount,
                                 endedEarly: service.lastBatchEndedEarly)
    }

    func stop() {
        service.isStopRequested = true
        writeTask?.cancel()
    }
}

// MARK: - The prompt

@MainActor
enum KasusStoryPrompt {

    static let temperature: Float = 0.75
    static let phraseInstruction = "Verwende JEDEN dieser Ausdrücke genau einmal und GENAU so geschrieben:"

    /// The story prompt the Stories feature uses (level constraints, TITEL:/GESCHICHTE:), plus the
    /// planned phrases (contract A) or the „FÄLLE:“ block (contract B). The phrases are listed
    /// without quotes so the model doesn't quote them in the story.
    static func build(_ plan: KasusStoryPlan) -> (system: String, user: String) {
        let level = plan.cefr ?? .a2
        let base = StoryStudyService.storyPrompt(topic: plan.topic, level: level, genre: plan.genre)
        switch plan.contract {
        case .planned:
            let list = plan.phrases.map { "- \($0.expression)\($0.promptHint)" }.joined(separator: "\n")
            let user = base.user + """


            \(phraseInstruction)
            \(list)
            Schreibe jeden Ausdruck zusammen mit seinem Verb in denselben Satz. Ändere keinen Artikel und keine Endung.
            Schreibe genau diesen Artikel (der, den, dem, ein, einen …), nicht mein, dein, sein oder ihr. Am Satzanfang darfst du ihn großschreiben.
            """
            return (base.system, user)
        case .selfLabelled:
            let focus = plan.unit.flatMap(\.focusCase).map { "Verwende viele Nomen mit Artikel im \($0.name)." }
                ?? "Verwende Nomen mit Artikel in allen vier Fällen."
            let system = base.system + """

            \(KasusSelfLabels.heading)
            <jede Nominalgruppe mit Artikel aus der Geschichte, eine pro Zeile: Ausdruck | Fall>
            """
            let user = base.user + """

            \(focus)
            Schreibe nach der Geschichte die Zeile „\(KasusSelfLabels.heading)“. Darunter steht JEDE Nominalgruppe aus der Geschichte, die mit einem Artikel beginnt (der, die, das, ein, eine, mein, kein …), genau wie im Text, eine pro Zeile, mit ihrem Fall: Nom, Akk, Dat oder Gen. Zum Beispiel:
            den Ball | Akk
            dem Kind | Dat
            Schreibe den Artikel so, wie er im Text steht, nicht die Grundform: Steht im Text „Ich sehe den Schrank“, schreibe „den Schrank | Akk“ (nicht „der Schrank“).
            """
            return (system, user)
        }
    }

    /// The level's story budget; contract B gets room for its label block on top.
    static func maxTokens(for plan: KasusStoryPlan) -> Int {
        (plan.cefr ?? .a2).storyMaxTokens + (plan.contract == .selfLabelled ? 250 : 0)
    }
}

// MARK: - Request and result

struct KasusGenerationRequest {
    var unit: KasusUnit
    var level: CEFRLevel
    var contract: KasusContract = .planned
    /// The first attempt's seed; the retry's follows from it (`KasusStoryPlan.retrySeed`).
    var seed: UInt64 = KasusStoryPlan.randomSeed()
    /// The learner's own nouns, offered to the planner as things.
    var learnerNouns: [String] = []
    /// Tests and `-kasus.debugGenerate`: every attempt uses this plan instead of planning.
    var fixedPlan: KasusStoryPlan? = nil
    /// The bundled story to fall back on; nil picks the unit's first.
    var fallbackStoryID: String? = nil
    /// Attempts after the first. The product retries once.
    var retries: Int = 1
}

/// One write and its check.
struct KasusGenerationAttempt {
    /// 1 for the first try, 2 for the retry.
    let number: Int
    let plan: KasusStoryPlan
    let system: String
    let user: String
    let raw: String
    let seconds: Double
    let tokenCount: Int
    let endedEarly: Bool
    /// Nil when the write threw.
    let check: KasusCheckResult?
    let error: String?

    var passes: Bool { check?.passes == true }
}

struct KasusGenerationResult {
    enum Outcome: String {
        /// A story passed the check: play it, and save it (`KasusStoryStore.save`).
        case generated
        /// Every attempt failed: play the bundled story with the note.
        case fallback
        /// The model couldn't be used at all (not a tutor, a loadModel refusal). `story` still
        /// holds the bundled fallback, for the sheet to offer.
        case failed
        case cancelled
    }

    let outcome: Outcome
    /// The generated story, or the bundled fallback.
    let story: KasusStory?
    /// The fallback note, or why nothing could be written.
    let note: String?
    let attempts: [KasusGenerationAttempt]
    let modelID: String
    let governed: Bool
    let request: KasusGenerationRequest

    /// The attempt whose story is being played.
    var passing: KasusGenerationAttempt? { attempts.first(where: \.passes) }
    var passedFirstTry: Bool { attempts.first?.passes == true }
    var passedAfterRetry: Bool { passing != nil }
    var totalSeconds: Double { attempts.reduce(0) { $0 + $1.seconds } }
}

/// Whether a unit screen offers „Neue Geschichte · New story (KI)“.
enum KasusGenerationAvailability: Equatable {
    /// The developer toggle is off: show nothing.
    case hidden
    /// A tutor is on disk and fits: show the row.
    case ready(MLXModel)
    /// No tutor on disk, but this one would fit: the usual download state.
    case needsDownload(MLXModel)
    /// No tutor fits this device: the usual too-small state.
    case tooSmall
}

// MARK: - The generator

@Observable
@MainActor
final class KasusStoryGenerator {

    enum Phase: Equatable {
        case idle
        /// Planen.
        case planning
        /// Loading the tutor, before Schreiben.
        case loadingModel
        /// Schreiben.
        case writing(attempt: Int)
        /// Prüfen.
        case checking(attempt: Int)
        case finished
    }

    /// Settings ▸ Developer: „KI-Geschichten im Kasus-Pfad“. On by default in DEBUG, off in Release.
    static let enabledKey = "kasus.aiStories"

    static var defaultEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultEnabled }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Shown over the bundled story when both attempts failed the check.
    static let fallbackNote = "Die KI-Geschichte hat die Prüfung nicht bestanden. Hier ist stattdessen eine fertige Geschichte."
    /// Shown over the bundled story when the tutor gave nothing usable (a write that threw).
    static let unavailableNote = "Die KI konnte gerade keine Geschichte schreiben. Hier ist stattdessen eine fertige Geschichte."

    private(set) var phase: Phase = .idle
    /// Abbrechen was tapped and the run hasn't ended yet: a load can't be interrupted, so the
    /// sheet says it's stopping.
    private(set) var isStopping = false
    /// The attempts so far in the run under way (or the last run).
    private(set) var attempts: [KasusGenerationAttempt] = []
    private(set) var result: KasusGenerationResult?
    /// The plan of the attempt under way (or the last one), so a sheet can say what's being
    /// written before the attempt is checked.
    private(set) var currentPlan: KasusStoryPlan?

    let writer: any KasusStoryWriter
    private let lexicon: any KasusLexicon
    private var cancelRequested = false

    init(writer: any KasusStoryWriter, lexicon: (any KasusLexicon)? = nil) {
        self.writer = writer
        self.lexicon = lexicon ?? AppKasusLexicon()
    }

    /// The app's generator for a tutor.
    static func live(model: MLXModel, service: MLXGenerationService) -> KasusStoryGenerator {
        KasusStoryGenerator(writer: KasusMLXWriter(service: service, model: model))
    }

    var liveTokenCount: Int { writer.liveTokenCount }

    var isRunning: Bool {
        switch phase {
        case .idle, .finished: false
        default:               true
        }
    }

    /// Ends the run: the write under way stops and the result is `.cancelled`.
    func cancel() {
        cancelRequested = true
        if isRunning { isStopping = true }
        writer.stop()
    }

    /// Plans, writes, checks, retries once, falls back. Never throws; every way out is a result.
    func generate(_ request: KasusGenerationRequest) async -> KasusGenerationResult {
        cancelRequested = false
        isStopping = false
        attempts = []
        result = nil
        currentPlan = nil
        let governed = writer.memorySaverActive

        func finish(_ outcome: KasusGenerationResult.Outcome, story: KasusStory?, note: String?) -> KasusGenerationResult {
            let result = KasusGenerationResult(outcome: outcome, story: story, note: note, attempts: attempts,
                                               modelID: writer.modelID, governed: governed, request: request)
            self.result = result
            phase = .finished
            isStopping = false
            return result
        }
        var stopped: Bool { cancelRequested || Task.isCancelled }

        phase = .planning
        let first = request.fixedPlan ?? plan(request, seed: request.seed, governed: governed)
        currentPlan = first
        guard !stopped else { return finish(.cancelled, story: nil, note: nil) }

        phase = .loadingModel
        if let problem = await writer.prepare() {
            return finish(stopped ? .cancelled : .failed, story: fallbackStory(for: request), note: problem)
        }
        guard !stopped else { return finish(.cancelled, story: nil, note: nil) }

        var seed = request.seed
        var threw = false
        for number in 1...(1 + max(0, request.retries)) {
            let plan: KasusStoryPlan
            if number == 1 {
                plan = first
            } else {
                seed = KasusStoryPlan.retrySeed(after: seed)
                plan = request.fixedPlan ?? self.plan(request, seed: seed, governed: governed)
                // The tutor may have been dropped (memory pressure) or taken (a chat reply)
                // while the first try was checked: ask again, and say so if it can't write.
                if let problem = await writer.prepare() {
                    return finish(stopped ? .cancelled : .failed, story: fallbackStory(for: request), note: problem)
                }
                guard !stopped else { return finish(.cancelled, story: nil, note: nil) }
            }
            currentPlan = plan
            phase = .writing(attempt: number)
            let prompt = KasusStoryPrompt.build(plan)
            let started = Date()
            var output: KasusWriterOutput?
            var failure: String?
            do {
                output = try await writer.write(system: prompt.system, user: prompt.user,
                                                maxTokens: KasusStoryPrompt.maxTokens(for: plan),
                                                temperature: KasusStoryPrompt.temperature)
            } catch is CancellationError {
                return finish(.cancelled, story: nil, note: nil)
            } catch {
                failure = error.localizedDescription
                threw = true
            }
            let seconds = Date().timeIntervalSince(started)
            guard !stopped else { return finish(.cancelled, story: nil, note: nil) }

            phase = .checking(attempt: number)
            let check = output.map {
                let raw = plan.contract == .planned ? Self.completeSentences($0.text, endedEarly: $0.endedEarly) : $0.text
                return KasusStoryCheck.run(raw: raw, plan: plan, lexicon: lexicon, learnerNouns: request.learnerNouns)
            }
            let attempt = KasusGenerationAttempt(number: number, plan: plan, system: prompt.system, user: prompt.user,
                                                 raw: output?.text ?? "", seconds: seconds,
                                                 tokenCount: output?.tokenCount ?? 0,
                                                 endedEarly: output?.endedEarly ?? false, check: check, error: failure)
            attempts.append(attempt)
            if attempt.passes, let story = check?.story {
                return finish(.generated, story: story, note: nil)
            }
        }
        let note = threw && attempts.allSatisfy({ $0.check == nil }) ? Self.unavailableNote : Self.fallbackNote
        return finish(.fallback, story: fallbackStory(for: request), note: note)
    }

    /// A write cut off mid-sentence (stopped early, or not ending on . ! ? …) up to its last full
    /// sentence, so a saved story never ends halfway through one. Unchanged when it ends
    /// cleanly, or when no sentence ends anywhere (the check will say so).
    static func completeSentences(_ text: String, endedEarly: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let closers: Set<Character> = ["“", "”", "\"", "'", "»", ")"]
        let enders: Set<Character> = [".", "!", "?", "…"]
        var end = trimmed.endIndex
        while end > trimmed.startIndex, closers.contains(trimmed[trimmed.index(before: end)]) {
            end = trimmed.index(before: end)
        }
        let endsCleanly = end > trimmed.startIndex && enders.contains(trimmed[trimmed.index(before: end)])
        guard endedEarly || !endsCleanly else { return trimmed }
        guard let last = trimmed.lastIndex(where: { enders.contains($0) }) else { return trimmed }
        var cut = trimmed.index(after: last)
        while cut < trimmed.endIndex, closers.contains(trimmed[cut]) { cut = trimmed.index(after: cut) }
        // A write that ended early on a clean full stop is already whole.
        if endsCleanly, cut >= end { return trimmed }
        return String(trimmed[..<cut])
    }

    private func plan(_ request: KasusGenerationRequest, seed: UInt64, governed: Bool) -> KasusStoryPlan {
        KasusStoryPlanner.plan(unit: request.unit, level: request.level, seed: seed, governed: governed,
                               contract: request.contract, learnerNouns: request.learnerNouns, lexicon: lexicon)
    }

    /// The bundled story to show instead: the one asked for if it's in this unit, else the unit's
    /// first.
    func fallbackStory(for request: KasusGenerationRequest) -> KasusStory? {
        let stories = KasusStoryBank.bundled.stories(for: request.unit)
        if let id = request.fallbackStoryID, let story = stories.first(where: { $0.id == id }) { return story }
        return stories.first
    }

    // MARK: Availability

    /// What a unit screen shows: the row (a tutor is ready), the download or too-small state, or
    /// nothing while the developer toggle is off. The tutor is the learner's story pick when it's
    /// on disk, else any tutor on disk that fits.
    static func availability(selectedStoryModel: MLXModel, readiness: ModelReadiness? = nil,
                             enabled: Bool? = nil) -> KasusGenerationAvailability {
        guard enabled ?? isEnabled else { return .hidden }
        let readiness = readiness ?? .current
        let pick = StoryStudyService.resolve(selectedStoryModel)
        if readiness.satisfies(.germanTutor) {
            if pick.isDownloaded { return .ready(pick) }
            if let ready = StoryStudyService.readyModel { return .ready(ready) }
            if let tutor = readiness.tutor, DeviceCapability.mayRun(tutor) { return .ready(tutor) }
        }
        if StoryStudyService.runnableModels.isEmpty { return .tooSmall }
        return .needsDownload(readiness.offerableTutor ?? pick)
    }
}
