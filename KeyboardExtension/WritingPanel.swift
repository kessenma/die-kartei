import SwiftUI
import UIKit

/// The keyboard: transform bar on top, keys below, diagnostics tucked behind the stethoscope.
///
/// Everything the user does to the host document flows through here so `DraftTracker` sees it —
/// that buffer is what makes a transform reliable when the host won't report its own text.
struct WritingPanel: View {

    @ObservedObject var writer: GermanWriter
    @ObservedObject var log: ProbeLog
    @ObservedObject var runner: ProbeRunner

    let tracker: DraftTracker
    let proxy: () -> UITextDocumentProxy?
    let showsGlobe: Bool
    let onGlobe: () -> Void

    /// What a transform replaced, so one step can be taken back. A named type rather than a tuple:
    /// `@State` over a tuple is what made the type checker give up on this body entirely.
    private struct Undo {
        let inserted: String
        let original: String
    }

    @State private var address: GermanWriter.Address = .sie
    @State private var status: String?
    @State private var isError = false
    @State private var undoStep: Undo?
    @State private var showingDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            bar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var bar: some View {
        TransformBar(
            writer: writer,
            address: $address,
            status: status,
            isError: isError,
            onRun: { job in run(job) },
            onUndo: undoAction,
            onDiagnostics: { showingDiagnostics.toggle() }
        )
    }

    /// Spelled out rather than `undoStep == nil ? nil : undo`: that ternary asks the type checker
    /// to reconcile a bare `nil` with a method reference, and it gives up on the whole body.
    private var undoAction: (() -> Void)? {
        guard undoStep != nil else { return nil }
        return { undo() }
    }

    @ViewBuilder
    private var content: some View {
        if showingDiagnostics {
            ProbePanel(log: log, runner: runner, showsGlobe: false, onGlobe: {})
        } else {
            KeyboardKeysView(
                onType: type,
                onBackspace: backspace,
                onGlobe: onGlobe,
                showsGlobe: showsGlobe
            )
        }
    }

    // MARK: - Typing

    private func type(_ text: String) {
        proxy()?.insertText(text)
        tracker.record(text)
    }

    private func backspace() {
        proxy()?.deleteBackward()
        tracker.recordBackspace()
    }

    // MARK: - Running a transform

    private func run(_ job: GermanWriter.Job) {
        guard writer.isAvailable else {
            return fail(writer.unavailableReason ?? "Apple Intelligence isn't available.")
        }
        guard let source = tracker.source(from: proxy()) else {
            return fail("Nothing to work on. Type something, or select text first.")
        }

        isError = false
        // Naming the origin matters: the user needs to know whether it took their selection or the
        // whole paragraph *before* it rewrites their message.
        status = "\(job.title) · \(source.origin.rawValue), \(source.text.count) chars…"

        Task {
            let started = Date()
            guard let result = await writer.run(job, on: source.text, address: address) else {
                return fail(writer.lastError.map { "Failed: \($0)" } ?? "No result came back.")
            }
            tracker.replace(source, with: result, in: proxy())
            undoStep = Undo(inserted: result, original: source.text)
            let seconds = Date().timeIntervalSince(started)
            status = String(format: "%@ · %@ · %.1fs", job.title, source.origin.rawValue, seconds)
            log.good("\(job.rawValue) from \(source.origin.rawValue): \(source.text.count) → \(result.count) chars in \(String(format: "%.1f", seconds))s")
        }
    }

    /// Puts the original back. Only one step deep on purpose: this is an escape hatch for "that
    /// wasn't what I meant", not an edit history.
    private func undo() {
        guard let step = undoStep, let proxy = proxy() else { return }
        for _ in 0..<step.inserted.count { proxy.deleteBackward() }
        proxy.insertText(step.original)
        tracker.invalidate()
        tracker.record(step.original)
        undoStep = nil
        status = "Put back what you wrote."
        isError = false
    }

    private func fail(_ message: String) {
        isError = true
        status = message
        log.bad(message)
    }
}
