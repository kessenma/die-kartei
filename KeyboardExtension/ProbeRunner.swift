import Foundation
import FoundationModels
import UIKit

/// Every measurement the probe build exists to take.
///
/// Two independent questions, deliberately answered in one throwaway build:
///
/// 1. **Does Foundation Models work inside a keyboard extension at all?** Apple documents the
///    keyboard APIs and the model APIs separately and never establishes that a
///    `LanguageModelSession` survives an extension's memory allowance and lifecycle.
/// 2. **How does text move between the host app and us?** Rather than committing to one transfer
///    design, every path is exercised side by side so the results pick the architecture. The
///    expensive path (composing inside the keyboard, which forces building a full QWERTY) is
///    stood in for by canned English sentences.
@MainActor
final class ProbeRunner: ObservableObject {

    @Published private(set) var isRunning = false

    private let log: ProbeLog
    /// Supplied by the view controller on every run — `textDocumentProxy` is a computed property
    /// that changes as the host's focus moves, so it must never be cached.
    private let proxy: () -> UITextDocumentProxy?

    init(log: ProbeLog, proxy: @escaping () -> UITextDocumentProxy?) {
        self.log = log
        self.proxy = proxy
    }

    // MARK: - Text transfer probes

    /// The best case. If the host reports a selection, the whole product is a transform bar:
    /// the user writes English anywhere with any keyboard, selects it, and we swap it for German.
    func readSelection() {
        guard let proxy = proxy() else { return log.bad("read selection: no proxy") }
        if let selected = proxy.selectedText, !selected.isEmpty {
            log.good("selection: \(selected.count) chars — \(preview(selected))")
        } else {
            log.bad("selection: nil or empty (select text in the host, then tap again)")
        }
    }

    /// The fallback case. Hosts vary in how much of the document they hand over — some give the
    /// whole field, some only the current paragraph, some almost nothing.
    func readContext() {
        guard let proxy = proxy() else { return log.bad("read context: no proxy") }
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        log.info("context before: \(before.count) chars — \(preview(before, tail: true))")
        log.info("context after: \(after.count) chars — \(preview(after))")
        if before.isEmpty && after.isEmpty {
            log.bad("context: host exposes nothing")
        } else {
            log.good("context: host exposes \(before.count + after.count) chars total")
        }
    }

    /// Does writing land in the right field at all? Everything else is moot if this fails.
    func insertTest() {
        guard let proxy = proxy() else { return log.bad("insert: no proxy") }
        proxy.insertText("Sehr geehrte Damen und Herren,")
        log.good("insert: wrote a German test line")
    }

    /// Does `insertText` replace a live selection, or append beside it? The answer decides whether
    /// the transform bar needs an explicit delete pass.
    func replaceSelection() {
        guard let proxy = proxy() else { return log.bad("replace: no proxy") }
        guard let selected = proxy.selectedText, !selected.isEmpty else {
            return log.bad("replace: nothing selected")
        }
        log.info("replace: selection was \(selected.count) chars")
        proxy.insertText("[ERSETZT]")
        log.good("replace: inserted over the selection — check the host to see if it replaced")
    }

    /// The no-selection fallback: walk the cursor backwards over the draft and retype it.
    /// Timed, because a few hundred `deleteBackward()` calls is a visible stutter if it is slow.
    func deleteAndReplace() {
        guard let proxy = proxy() else { return log.bad("delete+replace: no proxy") }
        let before = proxy.documentContextBeforeInput ?? ""
        guard !before.isEmpty else { return log.bad("delete+replace: nothing before the cursor") }

        // Never chew through an entire long document during a probe — one paragraph is enough
        // to measure the rate, and a runaway delete on someone's real draft is unrecoverable.
        let target = before.suffix(while: { $0 != "\n" })
        let count = min(target.count, 200)
        let started = Date()
        for _ in 0..<count { proxy.deleteBackward() }
        let elapsed = Date().timeIntervalSince(started)
        proxy.insertText("[\(count) Zeichen ersetzt]")
        log.good(String(format: "delete+replace: %d deletes in %.0f ms (%.1f/s)",
                        count, elapsed * 1000, Double(count) / max(elapsed, 0.001)))
    }

    /// Stands in for "the user typed an English draft into a panel inside the keyboard", without
    /// building the QWERTY that a real in-panel composer would need. Exercises the half that
    /// matters: generate, then insert.
    func cannedDraft(_ english: String, tone: Tone) async {
        await generate(english: english, tone: tone, insert: true, label: "canned draft")
    }

    /// The whole log, typed into the focused field. With no Full Access there is no pasteboard,
    /// so this is the only way results leave the device.
    func dumpLog() {
        guard let proxy = proxy() else { return log.bad("dump: no proxy") }
        proxy.insertText(log.rendered)
    }

    // MARK: - Platform probes

    /// What the host field looks like from in here — useful when comparing Gmail against Mail
    /// and Notes, since a secure or specialised field behaves differently.
    func describeHostField() {
        guard let proxy = proxy() else { return log.bad("host field: no proxy") }
        log.info("host field: keyboardType=\(proxy.keyboardType?.rawValue.description ?? "nil") "
                 + "returnKey=\(proxy.returnKeyType?.rawValue.description ?? "nil") "
                 + "hasText=\(proxy.hasText)")
    }

    func checkAvailability() {
        // The availability switch and its copy are lifted from the app's AppleIntelligenceService
        // — the one genuinely portable piece. Copied rather than shared, because that file reaches
        // into ChatRole and MLXModel and must not be linked here.
        switch SystemLanguageModel.default.availability {
        case .available:
            log.good("FM availability: available")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                log.bad("FM availability: device not eligible")
            case .appleIntelligenceNotEnabled:
                log.bad("FM availability: Apple Intelligence not enabled in Settings")
            case .modelNotReady:
                log.bad("FM availability: model still downloading / not ready")
            @unknown default:
                log.bad("FM availability: unavailable (unknown reason)")
            }
        @unknown default:
            log.bad("FM availability: unknown state")
        }
        log.info("memory at availability check: \(ExtensionMemory.snapshot)")
    }

    /// The gate. A realistic English email in, German out, fully timed and measured.
    func roundTrip(tone: Tone) async {
        await generate(english: Self.sampleEmail, tone: tone, insert: false, label: "round trip")
    }

    func memorySnapshot() {
        log.info("memory: \(ExtensionMemory.snapshot)")
    }

    // MARK: - Generation

    enum Tone: String, CaseIterable, Identifiable {
        case sie = "Sie"
        case du = "du"
        var id: String { rawValue }

        var instruction: String {
            switch self {
            case .sie: return "Address the recipient formally, with Sie."
            case .du:  return "Address the recipient informally, with du."
            }
        }
    }

    private func generate(english: String, tone: Tone, insert: Bool, label: String) async {
        guard !isRunning else { return log.bad("\(label): a generation is already running") }
        isRunning = true
        defer { isRunning = false }

        let system = """
        You rewrite English email drafts as natural German emails. \
        Reply with the German text only — no preamble, no notes, no English, no explanation. \
        Preserve names, dates, numbers and the sender's intent exactly. \
        \(tone.instruction)
        """

        let before = ExtensionMemory.footprintMB
        var peak = before
        let started = Date()
        var firstToken: TimeInterval?
        var latest = ""

        do {
            let session = LanguageModelSession { system }
            let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 400)
            for try await partial in session.streamResponse(to: english, options: options) {
                if firstToken == nil { firstToken = Date().timeIntervalSince(started) }
                latest = partial.content
                peak = max(peak, ExtensionMemory.footprintMB)
            }
            let total = Date().timeIntervalSince(started)
            let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)

            log.good(String(
                format: "%@: %.2fs to first token, %.2fs total, %d chars out",
                label, firstToken ?? total, total, text.count
            ))
            log.info(String(
                format: "%@ memory: %.1f → peak %.1f MB (delta %.1f), available now %.1f MB",
                label, before, peak, peak - before, ExtensionMemory.availableMB
            ))
            log.info("\(label) output: \(text)")

            if insert, let proxy = proxy() {
                proxy.insertText(text)
                log.good("\(label): inserted into the host field")
            }
        } catch {
            log.bad("\(label) FAILED: \(error)")
            log.info("\(label) memory at failure: \(ExtensionMemory.snapshot)")
        }
    }

    // MARK: - Fixtures

    /// Long enough to produce a realistic German email (~150 tokens) and to contain the things a
    /// rewrite most often mangles: a name, a date, a number, and a request.
    static let sampleEmail = """
    Hi Thomas, thanks for sending the invoice last week. I noticed the amount says 1,240 euros \
    but our agreement was 1,150. Could you check this and send a corrected version? I would also \
    like to move our meeting on 14 March to the following Tuesday if that works for you. Let me \
    know either way. Best, Kyle
    """

    static let shortDrafts = [
        "Thanks for your quick reply — I'll send the documents tomorrow morning.",
        "I'm sorry, I have to cancel our appointment on Friday. Can we find another time?",
        "Could you please confirm that you received my application?",
    ]

    // MARK: - Helpers

    private func preview(_ text: String, tail: Bool = false) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: "⏎")
        guard flat.count > 60 else { return "\"\(flat)\"" }
        return tail ? "\"…\(flat.suffix(60))\"" : "\"\(flat.prefix(60))…\""
    }
}

private extension String {
    /// The trailing run of characters satisfying `predicate` — used to bound a delete pass to the
    /// current paragraph.
    func suffix(while predicate: (Character) -> Bool) -> String {
        String(reversed().prefix(while: predicate).reversed())
    }
}
