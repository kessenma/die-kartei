//
//  JobPostingWebSurface.swift
//  german-ai-flashcards
//
//  The live page as a reading surface: the posting where it lives, with a double tap on a word
//  going to the same inspector the other surfaces use and the same markings drawn onto the page.
//  The most faithful of the three surfaces and the most fragile: it needs the network, and WebKit's
//  content process competes with the tutor for memory. The detail screen owns the model (as the
//  setup screen owns the clipper's) so nothing SwiftUI does to view identity reloads the page.
//

import SwiftUI
import WebKit

#if canImport(UIKit)

/// A web view whose selection menu offers "Translate" and "Save phrase". Wired by the model.
final class JobReadingWebView: WKWebView {
    var hasSelection: () -> Bool = { false }
    var onTranslate: (() -> Void)?
    var onSavePhrase: (() -> Void)?

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, hasSelection() else { return }
        let translate = UIAction(title: "Translate", image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
            self?.onTranslate?()
        }
        let save = UIAction(title: "Save phrase", image: UIImage(systemName: "plus.bubble")) { [weak self] _ in
            self?.onSavePhrase?()
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [translate, save]), atStartOfMenu: .root)
    }
}

/// Owns the persistent web view for one posting, routes the page's messages to the reader, and
/// re-draws the markings after every navigation (a process kill reloads the page, which wipes them).
@MainActor
@Observable
final class JobReadingWebModel {
    let web: WebClipperModel
    /// The text currently selected on the page, cached because the page resigns first responder
    /// before a menu action runs.
    private(set) var pendingSelection = ""
    var hasStarted = false
    var onWordTap: ((String) -> Void)?
    var onTranslateSelection: ((String) -> Void)?
    var onSavePhrase: ((String) -> Void)?

    private var decorations = JobReadingDecorations.none
    private var accentRGB = "0, 122, 255"

    init() {
        let script = WKUserScript(source: JobReadingScripts.reader, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        web = WebClipperModel(
            userScripts: [script],
            messageHandlerNames: JobReadingScripts.handlerNames,
            makeWebView: { JobReadingWebView(frame: .zero, configuration: $0) }
        )
        web.onScriptMessage = { [weak self] name, body in self?.handle(name, body) }
        web.onDidFinish = { [weak self] in self?.redecorate() }
        if let view = web.webView as? JobReadingWebView {
            view.hasSelection = { [weak self] in !(self?.pendingSelection.isEmpty ?? true) }
            view.onTranslate = { [weak self] in self?.translateSelection() }
            view.onSavePhrase = { [weak self] in self?.savePhrase() }
        }
    }

    func start(url: String, accent: Color) {
        guard !hasStarted else { return }
        hasStarted = true
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a) {
            accentRGB = "\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255))"
        }
        web.load(url)
    }

    /// Redraw the markings when the saved / looked-up sets change.
    func apply(_ decorations: JobReadingDecorations) {
        guard decorations != self.decorations else { return }
        self.decorations = decorations
        redecorate()
    }

    private func redecorate() {
        let js = JobReadingScripts.decorate(saved: decorations.savedWords, lookedUp: decorations.lookedUpWords, rgb: accentRGB)
        Task { _ = await web.evaluateString(js) }
    }

    private func handle(_ name: String, _ body: Any) {
        switch name {
        case JobReadingScripts.selectionHandler:
            pendingSelection = (body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case JobReadingScripts.wordTapHandler:
            if let word = body as? String, !word.isEmpty {
                pendingSelection = ""
                onWordTap?(word)
            }
        default:
            break
        }
    }

    func translateSelection() {
        Task {
            let text = await currentSelection()
            guard !text.isEmpty else { return }
            onTranslateSelection?(text)
            clearSelection()
        }
    }

    func savePhrase() {
        Task {
            let text = await currentSelection()
            guard !text.isEmpty else { return }
            onSavePhrase?(text)
            clearSelection()
        }
    }

    func clearSelection() {
        pendingSelection = ""
        Task { _ = await web.evaluateString(JobPostingScripts.clearSelection) }
    }

    /// The cached selection, or whatever the page reports right now when a page swallowed the
    /// `selectionchange` event.
    private func currentSelection() async -> String {
        if !pendingSelection.isEmpty { return pendingSelection }
        let read = await web.evaluateString(JobPostingScripts.readSelection) ?? ""
        return read.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func tearDown() {
        web.tearDown()
    }
}

/// The page plus a thin toolbar and a selection strip. The strip is the fallback for the edit-menu
/// items: whatever a page does to the menu, a highlighted phrase can always be translated or saved
/// from here.
struct JobPostingWebSurface: View {
    @Bindable var model: JobReadingWebModel
    let url: String
    let decorations: JobReadingDecorations
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { model.web.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.web.canGoBack)
                    .accessibilityLabel("Back")
                Button { model.web.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.web.canGoForward)
                    .accessibilityLabel("Forward")
                Button { model.web.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload")
                Text(model.web.currentURL.isEmpty ? url : model.web.currentURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Group {
                if model.web.isLoading && model.web.progress < 1 {
                    ProgressView(value: model.web.progress).progressViewStyle(.linear).tint(accent)
                } else {
                    Color.clear.frame(height: 2)
                }
            }
            .frame(height: 2)

            WebViewContainer(webView: model.web.webView)

            if !model.pendingSelection.isEmpty {
                selectionStrip
            }
        }
        .task {
            model.start(url: url, accent: accent)
        }
        .onChange(of: decorations, initial: true) { _, newValue in
            model.apply(newValue)
        }
    }

    private var selectionStrip: some View {
        HStack(spacing: 10) {
            Text(model.pendingSelection)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                model.translateSelection()
            } label: {
                Label("Translate", systemImage: "character.book.closed")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.small)
            Button {
                model.savePhrase()
            } label: {
                Label("Save phrase", systemImage: "plus.bubble")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                model.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear the selection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#endif
