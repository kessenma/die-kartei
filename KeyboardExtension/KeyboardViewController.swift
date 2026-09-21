import SwiftUI
import UIKit

/// The extension's entry point.
///
/// Beyond hosting the panel, this class *is* the lifecycle probe: a keyboard extension is torn
/// down and rebuilt far more aggressively than an app, and a generation that takes several seconds
/// is a long time to stay alive. Every load, memory warning and teardown is logged, so a run that
/// looks like "Foundation Models failed" can be told apart from "iOS killed us mid-call".
final class KeyboardViewController: UIInputViewController {

    private let log = ProbeLog()
    private let writer = GermanWriter()
    private let tracker = DraftTracker()
    private lazy var runner = ProbeRunner(log: log) { [weak self] in self?.textDocumentProxy }

    private var heightConstraint: NSLayoutConstraint?
    private var lastDocument: UUID?

    /// Four key rows at 44pt plus the transform bar. Matches the system keyboard closely enough
    /// that switching to this one doesn't move the host's text.
    private let panelHeight: CGFloat = 268

    private static let loadCountKey = "probe.loadCount"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Survives across extension restarts in the extension's own defaults — no App Group and
        // therefore no Allow Full Access required.
        let defaults = UserDefaults.standard
        let loads = defaults.integer(forKey: Self.loadCountKey) + 1
        defaults.set(loads, forKey: Self.loadCountKey)

        log.info("— load #\(loads) — \(ExtensionMemory.snapshot)")

        let panel = WritingPanel(
            writer: writer,
            log: log,
            runner: runner,
            tracker: tracker,
            proxy: { [weak self] in self?.textDocumentProxy },
            showsGlobe: needsInputModeSwitchKey,
            onGlobe: { [weak self] in self?.advanceToNextInputMode() }
        )

        let host = UIHostingController(rootView: panel)
        host.view.backgroundColor = .clear
        // The panel manages its own insets; letting the hosting controller apply the host app's
        // safe area pushes the content off the bottom of a keyboard.
        host.safeAreaRegions = []

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A keyboard has no intrinsic height. Without this the panel collapses to the system's
        // default keyboard height and the log is unreadable.
        applyHeightConstraint()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyHeightConstraint()
    }

    private func applyHeightConstraint() {
        guard heightConstraint == nil else { return }
        let constraint = view.heightAnchor.constraint(equalToConstant: panelHeight)
        constraint.priority = .required - 1   // the system owns the final say during rotation
        constraint.isActive = true
        heightConstraint = constraint
        inputView?.allowsSelfSizing = true
    }

    // MARK: - Probe signals

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // The single most important negative signal in the whole build: if this fires during a
        // generation, a Foundation Models session does not fit inside a keyboard extension.
        log.bad("MEMORY WARNING — \(ExtensionMemory.snapshot)")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        log.info("keyboard dismissed — \(ExtensionMemory.snapshot)")
    }

    /// A different field means a different draft. `documentIdentifier` changes when focus moves to
    /// another document, which is the one stale-buffer case the content check in `DraftTracker`
    /// can't catch on its own: a new field may legitimately already end with the same text.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let identifier = textDocumentProxy.documentIdentifier
        if identifier != lastDocument {
            lastDocument = identifier
            tracker.invalidate()
        }
    }
}
