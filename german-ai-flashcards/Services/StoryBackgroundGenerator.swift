import BackgroundTasks
import Foundation

/// Runs a long on-device generation as an iOS 26 **continued-processing task**, so it keeps going —
/// with a system progress UI in the Dynamic Island — if the learner leaves the app mid-run. Used by
/// story generation and by deck illustration (see `TaskKind`).
///
/// MLX inference is GPU-bound, so the request asks for the GPU resource. That requires two pieces of
/// configuration that live outside the code:
///   1. the `com.apple.developer.background-tasks.continued-processing.gpu` entitlement (add the
///      "Background Tasks" capability in Signing & Capabilities and enable it on the App ID), and
///   2. `Self.permittedIdentifier` listed under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
///      It's a wildcard family, so adding a new `TaskKind` beneath it needs no Info.plist change.
///
/// If either is missing, `register`/`submit` fail quietly and `submit(...)` returns false, so the
/// caller just runs the generation inline (the normal in-app path) — nothing breaks.
@MainActor
final class StoryBackgroundGenerator {
    static let shared = StoryBackgroundGenerator()

    /// The wildcard family registered for the launch handler — must match the entry in Info.plist ▸
    /// `BGTaskSchedulerPermittedIdentifiers`. Continued-processing identifiers are prefixes ending in
    /// `.*`; each submitted request uses a concrete identifier underneath it.
    static let permittedIdentifier = "kyle-essenmacher.german-ai-flashcards.storygen.*"

    /// The kinds of work that can run as a continued task. Each raw value is a concrete identifier
    /// under `permittedIdentifier`; the system hands the identifier back at launch, which is how a
    /// story job and a deck-illustration job stay told apart when both are in flight.
    enum TaskKind: String {
        case story = "kyle-essenmacher.german-ai-flashcards.storygen.generate"
        case deckIllustration = "kyle-essenmacher.german-ai-flashcards.storygen.illustrate-deck"
        case batch = "kyle-essenmacher.german-ai-flashcards.storygen.batch"
    }

    /// The work to run. The task is nil when running inline (no background continuation available).
    typealias Job = (BGContinuedProcessingTask?) async -> Void

    /// Submitted-but-not-yet-launched jobs, keyed by concrete identifier. A dictionary rather than a
    /// single slot so submitting a deck illustration can't clobber a story that's still pending.
    private var pendingJobs: [String: Job] = [:]
    private var didRegister = false

    private init() {}

    private var didAttemptRegister = false

    /// Continued-processing registration is exempt from the "before launch" rule, so we can register
    /// lazily the first time a story is generated. Idempotent. Wrapped in the exception catcher
    /// because `register` can raise (not just return false) on some misconfigurations.
    private func registerIfNeeded() {
        guard !didAttemptRegister else { return }
        didAttemptRegister = true
        var registered = false
        try? KBExceptionCatcher.run {
            registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.permittedIdentifier, using: nil
            ) { task in
                Task { @MainActor in Self.shared.launch(task) }
            }
        }
        didRegister = registered
    }

    /// Submit `job` to run as a continued task. Returns true if the system accepted it (the job will
    /// run via the launch handler); false means the caller should run the job itself with a nil task.
    ///
    /// `submit` and the request setup are wrapped in the Objective-C exception catcher: when the GPU
    /// entitlement or Info.plist identifier isn't configured, `BGTaskScheduler` raises an NSException
    /// (which Swift `do/catch` can't catch) instead of returning an error — that was crashing the app.
    /// Any failure here just means we fall back to inline generation.
    func submit(_ kind: TaskKind = .story, title: String, subtitle: String, job: @escaping Job) -> Bool {
        registerIfNeeded()
        guard didRegister else { return false }

        pendingJobs[kind.rawValue] = job
        var accepted = false
        let noException = (try? KBExceptionCatcher.run {
            let request = BGContinuedProcessingTaskRequest(
                identifier: kind.rawValue, title: title, subtitle: subtitle
            )
            request.strategy = .fail            // run promptly, or let the caller fall back to inline
            request.requiredResources = .gpu    // MLX needs the GPU; gated on the entitlement
            do {
                try BGTaskScheduler.shared.submit(request)
                accepted = true
            } catch {
                accepted = false                // ordinary rejection (e.g. not permitted)
            }
        }) != nil

        if !(noException && accepted) {
            pendingJobs[kind.rawValue] = nil
            return false
        }
        return true
    }

    private func launch(_ task: BGTask) {
        guard let continued = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }
        let job = pendingJobs.removeValue(forKey: task.identifier)
        Task { @MainActor in
            if let job {
                await job(continued)
            } else {
                continued.setTaskCompleted(success: false)
            }
        }
    }
}
