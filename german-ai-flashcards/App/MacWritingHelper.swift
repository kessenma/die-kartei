#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// The Schreibhilfe: a small floating panel for „Auf Deutsch" and „Korrigieren", the Mac's stand-in
/// for the iPhone's German keyboard.
///
/// It catches what the Services menu can't do in place: text over the in-place limit, apps that
/// don't take a service's text back, and every failure (the request lands here with the text and
/// the reason, so nothing is lost). It also opens from Edit ▸ Schreibhilfe… and from the
/// „In der Schreibhilfe öffnen" service.
///
/// A non-activating panel: it floats over Mail without making Die Kartei the active app, so
/// „Kopieren & schließen" leaves the learner where they were, ready to paste. It never reads the
/// clipboard (the learner pastes with ⌘V), which keeps macOS's paste-permission prompt away.
@MainActor
final class MacWritingHelper: NSObject, NSWindowDelegate {
    static let shared = MacWritingHelper()

    private var panel: SchreibhilfePanel?
    private let model = MacWritingHelperModel()

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Opens the panel. `text` replaces the draft; `result` shows a finished reply (one the service
    /// didn't put back); `autoRun` starts `job` straight away.
    func show(
        text: String? = nil,
        job: GermanWriting.Job? = nil,
        address: GermanWriting.Address? = nil,
        result: String? = nil,
        notice: String? = nil,
        autoRun: Bool = false
    ) {
        if let text { model.load(text: text, result: result, notice: notice) }
        if let address { model.address = address }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        // A service can arrive while the app is hidden (it hides itself after a cold launch);
        // a hidden app's windows don't show.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        panel.makeKeyAndOrderFront(nil)

        if autoRun, let job { model.run(job, keepNotice: true) }
    }

    func close() {
        panel?.close()
    }

    private func makePanel() -> SchreibhilfePanel {
        let panel = SchreibhilfePanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            // Non-activating has to be set here: changing the style mask later doesn't take.
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Schreibhilfe"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        // Opens on the Space the learner is writing in, full screen included.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self

        let root = MacWritingHelperView(model: model, writer: model.writer) { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: root)
        // Only a minimum: the panel keeps the size the learner gives it as the reply grows.
        hosting.sizingOptions = [.minSize]
        panel.contentView = hosting

        panel.center()
        panel.setFrameAutosaveName("Schreibhilfe")
        return panel
    }
}

/// The panel itself. It handles the editing shortcuts directly, because a non-activating panel
/// can't count on the menu bar: while another app is active, the menu bar is that app's.
final class SchreibhilfePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let action: Selector?
        switch (key, flags.contains(.shift)) {
        case ("v", false): action = #selector(NSText.paste(_:))
        case ("c", false): action = #selector(NSText.copy(_:))
        case ("x", false): action = #selector(NSText.cut(_:))
        case ("a", false): action = #selector(NSText.selectAll(_:))
        case ("z", false): action = Selector(("undo:"))
        case ("z", true): action = Selector(("redo:"))
        case ("w", false): performClose(nil); return true
        default: action = nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    /// Esc closes, as it does any Mac panel.
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// What the panel holds between openings: the draft, the reply, and the Sie/du choice.
@MainActor
final class MacWritingHelperModel: ObservableObject {
    static let addressKey = "schreibhilfe.address"

    let writer = GermanWriter()

    @Published var draft = ""
    /// Why the panel opened (a service that couldn't finish in place), shown above the draft.
    @Published var notice: String?
    @Published private(set) var result = ""

    /// Sie or du for „Auf Deutsch". „Korrigieren" keeps whichever the writer used.
    @Published var address: GermanWriting.Address {
        didSet { UserDefaults.standard.set(address.rawValue, forKey: Self.addressKey) }
    }

    init() {
        address = UserDefaults.standard.string(forKey: Self.addressKey)
            .flatMap(GermanWriting.Address.init(rawValue:)) ?? .sie
    }

    func load(text: String, result: String?, notice: String?) {
        draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.result = result ?? ""
        self.notice = notice
    }

    var canRun: Bool {
        !writer.isWorking && writer.isAvailable
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= GermanWriting.panelLimit
    }

    /// `keepNotice`: a run the panel started itself on opening, under the notice that says why.
    func run(_ job: GermanWriting.Job, keepNotice: Bool = false) {
        guard canRun else { return }
        let text = draft
        let address = job == .translate ? self.address : nil
        if !keepNotice { notice = nil }
        result = ""
        Task {
            if let out = await writer.run(job, on: text, address: address) {
                result = out
            }
        }
    }

    /// What the reply area shows: the German arriving, or the finished reply.
    var shownResult: String { writer.isWorking ? writer.partial : result }
}

struct MacWritingHelperView: View {
    @ObservedObject var model: MacWritingHelperModel
    @ObservedObject var writer: GermanWriter
    var close: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reason = writer.unavailableReason {
                banner(reason, systemImage: "exclamationmark.triangle", tint: .orange) {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                            openURL(url)
                        }
                    }
                    .controlSize(.small)
                }
            } else if let notice = model.notice {
                banner(notice, systemImage: "info.circle", tint: .accentColor) { EmptyView() }
            }

            editor
            controls
            Divider()
            reply
            footer
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 480)
    }

    // MARK: - Pieces

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
            if model.draft.isEmpty {
                Text("Type or paste (⌘V) your English, or German to correct")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 130)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { model.run(.translate) } label: {
                Label(GermanWriting.Job.translate.title, systemImage: GermanWriting.Job.translate.symbol)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRun)

            Picker("Anrede", selection: $model.address) {
                ForEach(GermanWriting.Address.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
            .help("Sie or du for Auf Deutsch. Korrigieren keeps the one you wrote.")

            Button { model.run(.correct) } label: {
                Label(GermanWriting.Job.correct.title, systemImage: GermanWriting.Job.correct.symbol)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canRun)

            Spacer()

            Text("\(model.draft.count.formatted()) / \(GermanWriting.panelLimit.formatted())")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(model.draft.count > GermanWriting.panelLimit ? Color.red : Color.secondary)
        }
    }

    private var reply: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                Group {
                    if writer.isWorking && writer.partial.isEmpty {
                        ProgressView().controlSize(.small)
                    } else if model.shownResult.isEmpty {
                        Text("The German appears here.")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(model.shownResult)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 140)

            if let error = writer.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if writer.lastWasTruncated && !writer.isWorking {
                Label("This may stop mid-sentence. Check the end before you use it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Runs on Apple's on-device model.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Kopieren") { copy() }
            Button("Kopieren & schließen") {
                copy()
                close()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .disabled(model.result.isEmpty || writer.isWorking)
    }

    private func banner<Accessory: View>(
        _ text: String, systemImage: String, tint: Color,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Writing to the clipboard needs no permission; only reading it does.
    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.result, forType: .string)
    }
}
#endif
