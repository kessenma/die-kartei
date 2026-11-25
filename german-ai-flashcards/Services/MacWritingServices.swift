#if os(macOS)
import AppKit
import os
import Synchronization

/// The Schreibhilfe's Services menu items (declared under `NSServices` in Info-macOS.plist): select
/// text in any app, then Services ▸ „Auf Deutsch (Sie)", „Auf Deutsch (du)" or „Deutsch
/// korrigieren", and the German replaces the selection. „In der Schreibhilfe öffnen" hands the text
/// to the panel instead.
///
/// A service is synchronous: the result has to be on the pasteboard when the method returns, and
/// the requesting app freezes until then. So the model runs off the main actor and this waits by
/// spinning the run loop in short slices. Unlike a semaphore, that can't deadlock on a hop back to
/// the main actor, and Die Kartei's own windows keep drawing. Anything that can't finish cleanly in
/// place (too long, unavailable, not German, cut short, too slow) writes nothing, so the selection
/// stays as it was, and opens the panel with the text and the reason.
final class MacWritingServices: NSObject {
    static let shared = MacWritingServices()

    /// The provider's own limit, well inside the plist's `NSTimeout` (45 s), which also has to
    /// cover a cold launch.
    static let deadline: TimeInterval = 20

    /// True while a request waits for the model. A second request arriving during the wait (the
    /// run loop is spinning, so it can) is turned away.
    private(set) var isBusy = false

    /// The app was started by a service request rather than opened by the learner.
    private var launchedForService = false
    private var launchedAt = Date()

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Die Kartei", category: "WritingServices")

    /// From `applicationDidFinishLaunching`: a launch that isn't the default one (Dock, Finder) was
    /// for a service, a file, or a restore. Only a request soon after it counts as the reason.
    func noteLaunch(isDefault: Bool) {
        launchedForService = !isDefault
        launchedAt = Date()
    }

    // MARK: - Services

    @objc(transform:userData:error:)
    func transform(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let (job, address) = Self.request(userData)
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "No text was selected."
            return
        }
        guard !isBusy else {
            error.pointee = GermanWriting.Failure.busy.message as NSString
            return
        }
        if let reason = GermanWriting.unavailableReason {
            openPanel(text, job: job, address: address, notice: reason)
            error.pointee = reason as NSString
            return
        }
        if text.count > GermanWriting.inPlaceLimit {
            let fits = text.count <= GermanWriting.panelLimit
            openPanel(text, job: job, address: address,
                      notice: "That's over \(GermanWriting.inPlaceLimit.formatted()) characters, so it opened here instead of replacing your selection.",
                      autoRun: fits)
            error.pointee = "Too long to replace in place."
            return
        }

        isBusy = true
        defer { isBusy = false }
        let started = Date()
        let outcome = wait(for: job, on: text, address: address)
        let seconds = Date().timeIntervalSince(started)

        switch outcome {
        case .success(let reply) where !reply.possiblyTruncated:
            pboard.clearContents()
            pboard.setString(GermanWriting.replacement(for: text, with: reply.text), forType: .string)
            log.info("\(job.rawValue, privacy: .public) replaced \(text.count) chars in \(seconds, format: .fixed(precision: 2))s")
            handBackFocusIfLaunchedForThis()
        case .success(let reply):
            log.info("\(job.rawValue, privacy: .public) possibly truncated after \(seconds, format: .fixed(precision: 2))s")
            openPanel(text, job: job, address: address, result: reply.text,
                      notice: "The German may stop mid-sentence, so your text was left as it was. Check it here.")
            error.pointee = "The reply may be cut short."
        case .failure(let failure):
            log.info("\(job.rawValue, privacy: .public) failed after \(seconds, format: .fixed(precision: 2))s: \(failure.message, privacy: .public)")
            openPanel(text, job: job, address: address, notice: failure.message + " Your text was left as it was.")
            error.pointee = failure.message as NSString
        case nil:
            log.info("\(job.rawValue, privacy: .public) timed out after \(seconds, format: .fixed(precision: 2))s")
            openPanel(text, job: job, address: address,
                      notice: GermanWriting.Failure.timedOut.message + " Try it here, where you can watch it arrive.")
            error.pointee = GermanWriting.Failure.timedOut.message as NSString
        }
    }

    @objc(openInWritingHelper:userData:error:)
    func openInWritingHelper(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pboard.string(forType: .string) ?? ""
        launchedForService = false
        DispatchQueue.main.async {
            MacWritingHelper.shared.show(text: text)
        }
    }

    // MARK: - Helpers

    /// `NSUserData` from the plist: "translate.sie", "translate.du" or "correct".
    static func request(_ userData: String?) -> (GermanWriting.Job, GermanWriting.Address?) {
        switch userData {
        case "translate.du": return (.translate, .du)
        case "correct": return (.correct, nil)
        default: return (.translate, .sie)
        }
    }

    /// Runs the job off the main actor and waits for it, or for the deadline (nil, task cancelled).
    private func wait(
        for job: GermanWriting.Job, on text: String, address: GermanWriting.Address?
    ) -> Result<GermanWriting.Outcome, GermanWriting.Failure>? {
        let box = ResultBox()
        let task = Task.detached(priority: .userInitiated) {
            box.set(await GermanWriting.perform(job, on: text, address: address, streaming: false))
        }
        let deadline = Date().addingTimeInterval(Self.deadline)
        while box.get() == nil, Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: min(deadline, Date(timeIntervalSinceNow: 0.05)))
        }
        guard let result = box.get() else {
            task.cancel()
            return nil
        }
        return result
    }

    /// After the requesting app has its text back, so the panel doesn't open over a frozen window.
    private func openPanel(
        _ text: String, job: GermanWriting.Job, address: GermanWriting.Address?,
        result: String? = nil, notice: String, autoRun: Bool = false
    ) {
        launchedForService = false
        DispatchQueue.main.async {
            MacWritingHelper.shared.show(text: text, job: job, address: address,
                                         result: result, notice: notice, autoRun: autoRun)
        }
    }

    /// A cold launch for a service brings Die Kartei's window to the front. Once the text is back,
    /// hide the app so the learner is returned to the app they were writing in.
    private func handBackFocusIfLaunchedForThis() {
        guard launchedForService, Date().timeIntervalSince(launchedAt) < 60 else { return }
        launchedForService = false
        DispatchQueue.main.async {
            if NSApp.isActive { NSApp.hide(nil) }
        }
    }
}

/// The detached task's result, read by the main thread while it spins.
private nonisolated final class ResultBox: Sendable {
    private let value = Mutex<Result<GermanWriting.Outcome, GermanWriting.Failure>?>(nil)

    func set(_ result: Result<GermanWriting.Outcome, GermanWriting.Failure>) {
        value.withLock { $0 = result }
    }

    func get() -> Result<GermanWriting.Outcome, GermanWriting.Failure>? {
        value.withLock { $0 }
    }
}
#endif
