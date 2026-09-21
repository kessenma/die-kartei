import Foundation
import os
import MLX
import MLXLMCommon
import UIKit

// MARK: - Memory Saver

/// Governors that keep a model larger than this device's budget from taking the app down with it.
///
/// None of this makes a big model fast. What it does is bound the parts of generation that
/// otherwise grow without limit — the KV cache, the prompt prefill, the length of a single answer,
/// and MLX's own allocator cache — and stop a run cleanly when headroom runs out, so a long answer
/// ends early with partial text instead of the app being killed mid-sentence.
///
/// Engages automatically for a model that runs over budget on this device (see
/// ``MemoryBudget/isOverBudget(_:)``); the user can force it on or off in Settings.
@MainActor
enum MemorySaver {
    enum Mode: String, CaseIterable, Identifiable {
        case automatic, on, off
        var id: String { rawValue }

        var label: String {
            switch self {
            case .automatic: "Automatic"
            case .on:        "Always On"
            case .off:       "Off"
            }
        }
    }

    private static let modeKey = "memorySaverMode"
    nonisolated private static let oversizedOptInKey = "allowsOversizedModels"

    /// Set once the user has seen the memory check for a model too big for this device and chosen
    /// to run it anyway. Features that need such a model (stories, batch story jobs) stay reachable
    /// afterwards instead of being walled off — it's their phone, and they've been told the cost.
    /// Nonisolated so the feature gates in `DeviceCapability` can read it from anywhere.
    nonisolated static var allowsOversizedModels: Bool {
        get { UserDefaults.standard.bool(forKey: oversizedOptInKey) }
        set { UserDefaults.standard.set(newValue, forKey: oversizedOptInKey) }
    }

    static var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Whether the governors apply to `model` right now. Apple Intelligence is Apple's memory to
    /// manage, not ours, so it's never governed.
    static func isActive(for model: MLXModel?) -> Bool {
        guard let model, !model.isAppleIntelligence else { return false }
        switch mode {
        case .on:        return true
        case .off:       return false
        // Governs anything that doesn't have room to spare, not just what's over budget: a model
        // that fits an ordinary turn can still outgrow the device over a long conversation, and
        // that's exactly the case on the smallest phones a model is offered to.
        case .automatic: return MemoryBudget.isOverBudget(model) || MemoryBudget.hasSlimHeadroom(model)
        }
    }

    // MARK: Generation limits

    /// Longest single answer while governed. Long outputs are the main way a run walks itself into
    /// jetsam, and every caller here already salvages partial output.
    static let maxTokensCap = 1536

    /// KV cache ceiling in tokens. Past this the cache rotates (older entries are overwritten
    /// except the first few), so a long conversation stops growing instead of climbing until the
    /// app dies.
    static let maxKVSize = 1024

    /// Apply the governors to a set of generation parameters. No-op when not active, so callers
    /// can route every generation through it unconditionally.
    static func tune(_ parameters: inout GenerateParameters, for model: MLXModel?) {
        guard isActive(for: model) else { return }
        parameters.maxTokens = min(parameters.maxTokens ?? maxTokensCap, maxTokensCap)
        parameters.maxKVSize = maxKVSize
        parameters.kvBits = 4              // quantized KV cache: a quarter of the memory per token
        parameters.quantizedKVStart = 256  // full precision for the early tokens, which matter most
        parameters.prefillStepSize = 128   // smaller prompt chunks, so prefill doesn't spike
    }

    // MARK: The MLX runtime gate

    /// Whether MLX's Metal runtime may be touched. Every `Memory.*` call — a reading, a cache
    /// clear, an allocator limit — constructs MLX's Metal device on first use, and that device
    /// aborts the process where there is no Metal (the simulator) and is pointless work before a
    /// model has ever loaded. `loadModel` flips this right before its first MLX call; until then,
    /// and always in the simulator, the helpers below are no-ops and readings report zero.
    private(set) static var mlxRuntimeReady = false

    /// Call from the model-load path, just before the first MLX allocation of the process.
    static func markRuntimeReady() {
        #if targetEnvironment(simulator)
        mlxRuntimeReady = false
        #else
        mlxRuntimeReady = true
        #endif
    }

    /// Size MLX's allocator for this model. The cache is memory MLX holds onto for reuse; on a
    /// device already at its limit that reuse is not worth the headroom it costs.
    ///
    /// The memory limit is set on *every* call, governed or not. MLX's own default is 1.5× the
    /// GPU's recommended working set, which on iOS sits above the jetsam line — so without this,
    /// an ungoverned model was free to allocate straight through the point where iOS kills the
    /// app. A ceiling rather than a hard cap: allocations past it wait on scheduled work instead
    /// of racing ahead of it, which is what keeps peaks from stacking.
    static func applyAllocatorLimits(for model: MLXModel?) {
        guard mlxRuntimeReady else { return }
        Memory.memoryLimit = max(512, MemoryBudget.totalMB - MemoryBudget.reserveMB) * 1_048_576
        Memory.cacheLimit = isActive(for: model) ? 4 * 1024 * 1024 : 20 * 1024 * 1024
    }

    /// Free everything droppable right now. Called before a load and on a memory warning.
    static func releaseCaches() {
        guard mlxRuntimeReady else { return }
        Memory.clearCache()
    }
}

// MARK: - Pressure Monitor

/// Watches how close the app is to its memory limit during generation and publishes a single
/// notice for the UI to show. One shared instance so the banner, the generation loop, and the
/// memory-warning handler all agree on the current state.
@MainActor
@Observable
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()

    /// Current headroom bucket, refreshed while a generation is running.
    private(set) var level: MemoryBudget.Pressure = .normal

    /// What the UI should be showing, or nil for nothing. Cleared on dismiss, on a new run, and
    /// when headroom recovers.
    private(set) var notice: Notice?

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let level: MemoryBudget.Pressure
        let title: String
        let message: String
        /// True when the governors are handling it, which changes the banner from a warning into
        /// an explanation of what the app is already doing.
        let isGoverned: Bool
    }

    /// Called when the app has to give memory back immediately. Set by ``MLXGenerationService`` so
    /// a system warning can shed the *weights*, which are nearly all of the footprint — clearing
    /// MLX's reuse cache on its own frees a few MB against a model measured in gigabytes, which is
    /// why warnings used to be followed by a termination anyway.
    var onCriticalPressure: (() -> Void)?

    private var observer: NSObjectProtocol?
    private var highestThisRun: MemoryBudget.Pressure = .normal
    private var notifiedInBackground = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "de.germanflashcards",
        category: "Memory"
    )

    private init() {}

    /// Start listening for system memory warnings. Safe to call more than once.
    func startMonitoring() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in MemoryPressureMonitor.shared.handleSystemWarning() }
        }
    }

    /// Called at the start of a generation run so notices describe this run, not the last one.
    func beginRun() {
        highestThisRun = .normal
        notifiedInBackground = false
        level = MemoryBudget.pressure
        if notice?.level != .critical { notice = nil }
    }

    /// Sample headroom mid-run. Cheap enough to call every few dozen tokens.
    /// Returns true when the caller should stop generating.
    @discardableResult
    func sample(model: MLXModel?) -> Bool {
        let current = MemoryBudget.pressure
        level = current
        guard current > highestThisRun else { return current == .critical }
        highestThisRun = current

        let governed = MemorySaver.isActive(for: model)
        switch current {
        case .normal:
            break
        case .elevated:
            logger.notice("Memory elevated — available=\(MemoryBudget.availableMB, privacy: .public) MB")
            MemoryDiagnostics.record(.pressureElevated, title: "Memory running low mid-generation")
            show(Notice(
                level: .elevated,
                title: governed ? "Managing memory" : "Memory is running low",
                message: governed
                    ? "This iPhone is near its limit, so answers may come out shorter than usual."
                    : "Closing other apps can help. Answers will stop early if memory runs out.",
                isGoverned: governed
            ))
        case .critical:
            logger.warning("Memory critical — available=\(MemoryBudget.availableMB, privacy: .public) MB")
            MemorySaver.releaseCaches()
            MemoryDiagnostics.record(.pressureCritical, title: "Stopped generating to save memory")
            show(Notice(
                level: .critical,
                title: "Stopped early to save memory",
                message: "There wasn't enough memory left to finish. Whatever was written is kept. "
                    + "A smaller model runs this at full length.",
                isGoverned: governed
            ))
            notifyIfBackgrounded()
        }
        return current == .critical
    }

    /// A load that never finished before the app stopped. Reported once at launch: for a model
    /// this device is small for, that almost always means iOS reclaimed the app mid-load, and
    /// silently trying again is the one thing that reliably repeats it.
    func noteInterruptedLoad(of model: MLXModel) {
        logger.warning("[\(model.rawValue, privacy: .public)] Previous load never finished — likely terminated for memory")
        MemoryDiagnostics.record(
            .interruptedLoad,
            title: "\(model.rawValue) never finished loading last time",
            detail: "The app stopped while the weights were being read into memory — on a device this model is big for, that is iOS reclaiming the app."
        )
        show(Notice(
            level: .elevated,
            title: "\(model.rawValue) didn't finish loading",
            message: "The app closed while loading it last time, which usually means memory ran "
                + "out. A model sized for this iPhone loads without the risk.",
            isGoverned: false
        ))
    }

    /// The system's own warning, which can arrive between samples.
    private func handleSystemWarning() {
        logger.warning("System memory warning — available=\(MemoryBudget.availableMB, privacy: .public) MB")
        // Recorded before anything is freed, so the row shows what was being held at the moment
        // iOS complained.
        MemoryDiagnostics.record(.memoryWarning, title: "iOS memory warning")
        MemorySaver.releaseCaches()
        // No-op mid-generation — a run in flight holds its own reference, so dropping ours frees
        // nothing and only costs a reload. It's the idle case this is for: an app holding weights
        // it isn't using is the one iOS kills.
        onCriticalPressure?()
        // The drawing model is the other multi-hundred-MB resident, and it only exists mid-run.
        // Stopping the run keeps every picture already saved (every illustrate path is
        // skip-existing) and frees the pipeline at the run's own `defer`.
        StoryImageService.shared.stopForMemoryPressure()
        level = .critical
        highestThisRun = .critical
        show(Notice(
            level: .critical,
            title: "iPhone is low on memory",
            message: "The app freed what it could. Generation will stop early if it stays this low.",
            isGoverned: MemorySaver.mode != .off
        ))
        notifyIfBackgrounded()
    }

    private func show(_ notice: Notice) {
        self.notice = notice
    }

    func dismiss() {
        notice = nil
    }

    /// A long batch job can be running with the app in the background, where a banner is no use.
    /// One notification per run, so a job that keeps brushing the limit doesn't spam.
    private func notifyIfBackgrounded() {
        guard !notifiedInBackground, UIApplication.shared.applicationState != .active else { return }
        notifiedInBackground = true
        Task {
            await LocalNotificationService.post(
                id: "memory-pressure",
                title: "Paused to save memory",
                body: "This iPhone ran low on memory, so the run stopped early. Open the app to pick up where it left off."
            )
        }
    }
}
