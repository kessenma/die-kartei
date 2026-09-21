import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import WebKit

/// An in-app browser. The user can navigate to (and log into) a page, then "Use this page"
/// extracts the rendered DOM text — which bypasses anti-bot blocking and handles JS-heavy
/// sites, because it's a real browser with the user's own session/cookies.
struct WebClipperView: View {
    var initialURL: String?
    /// Brand accent of the model that will process the captured page.
    var accent: Color = .accentColor
    var onCapture: (_ title: String, _ text: String, _ url: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var model = WebClipperModel()
    @State private var address = ""
    @State private var capturing = false
    @State private var didLoad = false
    @State private var tooLittle = false
    @State private var pasteSuggestion: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Paste a link (e.g. a Reddit post)…", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { load() }
                        .textFieldStyle(.roundedBorder)
                    if !address.isEmpty {
                        Button { address = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Go") { load() }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                if address.isEmpty, let pasteSuggestion {
                    Button {
                        address = pasteSuggestion
                        self.pasteSuggestion = nil
                        load()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste copied link").font(.caption).foregroundStyle(.secondary)
                            Text(pasteSuggestion).font(.caption).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                    }
                    .padding(.top, 6)
                }

                // Thin page-load progress bar.
                Group {
                    if model.isLoading && model.progress < 1 {
                        ProgressView(value: model.progress).progressViewStyle(.linear).tint(accent)
                    } else {
                        Color.clear.frame(height: 2)
                    }
                }
                .frame(height: 2)
                .padding(.top, 6)

                if tooLittle {
                    Label("That page had very little text — navigate to the actual article or post, then try again.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }

                webContent

                Divider()

                HStack(spacing: 22) {
                    Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.canGoBack)
                    Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.canGoForward)
                    Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Spacer()
                    if capturing {
                        Text("Reading the page…").font(.caption).foregroundStyle(.secondary)
                    } else if model.isLoading {
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: capture) {
                        if capturing {
                            ProgressView()
                        } else {
                            Label("Use this page", systemImage: "square.and.arrow.down.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(capturing || model.isLoading)
                }
                .padding()
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle("Open & log in if needed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: model.currentURL) { _, newValue in
                if !newValue.isEmpty { address = newValue }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let initialURL, !initialURL.isEmpty {
                    address = initialURL
                    model.load(initialURL)
                } else {
                    checkClipboard()
                }
            }
        }
    }

    private func checkClipboard() {
        #if canImport(UIKit)
        let board = UIPasteboard.general
        if board.hasURLs, let url = board.url {
            pasteSuggestion = url.absoluteString
        } else if board.hasStrings,
                  let copied = board.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  copied.count < 400, !copied.contains(" "),
                  copied.lowercased().hasPrefix("http") || copied.contains(".") {
            pasteSuggestion = copied
        }
        #endif
    }

    @ViewBuilder private var webContent: some View {
        #if canImport(UIKit)
        WebViewContainer(webView: model.webView)
        #else
        Text("In-app browser is only available on iOS.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private func load() {
        tooLittle = false
        model.load(address)
    }

    private func capture() {
        capturing = true
        tooLittle = false
        Task {
            let (title, text, url) = await model.extract()
            capturing = false
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 60 {
                tooLittle = true
                return
            }
            onCapture(title, text, url)
        }
    }
}

#if canImport(UIKit)
/// Hosts the persistent WKWebView created by the model. Shared with the job-posting clipper.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

/// Owns a persistent WKWebView (cookies/login survive across uses) and extracts page text.
///
/// Optional hooks let a caller install user scripts and receive their `postMessage` calls
/// (the job-posting clipper listens for selection changes this way); the Paper clipper uses the
/// plain `init()` and none of them.
@MainActor
@Observable
final class WebClipperModel: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var isLoading = false
    var progress: Double = 0
    var currentURL = ""
    var canGoBack = false
    var canGoForward = false
    /// Called with (handler name, message body) for every `webkit.messageHandlers` post from an
    /// installed user script.
    var onScriptMessage: ((String, Any) -> Void)?
    /// Called after every completed navigation, once the observable state has been synced.
    var onDidFinish: (() -> Void)?
    private var progressObs: NSKeyValueObservation?
    private let handlerNames: [String]

    /// `makeWebView` lets a caller supply a `WKWebView` subclass (the job-posting reader adds
    /// edit-menu items through `buildMenu(with:)`); the default is a plain web view.
    init(
        userScripts: [WKUserScript] = [],
        messageHandlerNames: [String] = [],
        makeWebView: @MainActor (WKWebViewConfiguration) -> WKWebView = { WKWebView(frame: .zero, configuration: $0) }
    ) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        for script in userScripts {
            config.userContentController.addUserScript(script)
        }
        handlerNames = messageHandlerNames
        webView = makeWebView(config)
        super.init()
        // The content controller retains its handlers, and the model owns the web view that owns
        // the controller, so a weak proxy sits between them to keep the whole thing collectable.
        for name in messageHandlerNames {
            config.userContentController.add(ScriptMessageProxy(target: self), name: name)
        }
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            // WKWebView KVO fires on the main thread, so update directly (no Task capture).
            let value = webView.estimatedProgress
            MainActor.assumeIsolated { self?.progress = value }
        }
    }

    func load(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard var url = URL(string: s) else { return }
        // Reddit's new UI lazy-loads / virtualizes comments, so innerText only sees the first
        // batch. old.reddit renders the whole thread statically → far more complete extraction.
        if let host = url.host, host.contains("reddit.com"), !host.hasPrefix("old."),
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.host = "old.reddit.com"
            if let rewritten = comps.url { url = rewritten }
        }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    /// Stop loading and drop the script message handlers. Called when the hosting view goes away;
    /// it can't live in `deinit`, which is nonisolated.
    func tearDown() {
        webView.stopLoading()
        for name in handlerNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
        onScriptMessage = nil
        onDidFinish = nil
    }

    /// Run `js`, which must evaluate to a string, and return it (nil on any failure).
    func evaluateString(_ js: String) async -> String? {
        (try? await webView.evaluateJavaScript(js)) as? String
    }

    /// Run `js`, which must evaluate to a JSON string, and decode it.
    func evaluateJSON<T: Decodable>(_ js: String, as type: T.Type) async -> T? {
        guard let json = await evaluateString(js), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Extract readable text from the loaded page, preferring the main article element.
    /// Scrolls first to coax lazy-loaded content into the DOM.
    func extract() async -> (title: String, text: String, url: String) {
        for _ in 0..<4 {
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);")
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0);")

        let js = """
        (function(){
          var el = document.querySelector('article') || document.querySelector('main') || document.body;
          return el ? el.innerText : '';
        })()
        """
        let text = (try? await webView.evaluateJavaScript(js)) as? String ?? ""
        let rawTitle = (try? await webView.evaluateJavaScript("document.title")) as? String ?? ""
        let title = rawTitle.isEmpty ? (webView.title ?? "Web page") : rawTitle
        let url = webView.url?.absoluteString ?? currentURL
        return (String(title.prefix(90)), text, url)
    }

    private func sync() {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let u = webView.url?.absoluteString { currentURL = u }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        onDidFinish?()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { sync() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { sync() }

    /// Times WebKit's content process was killed under this page. iOS reclaims a covered web
    /// view's process first when memory is tight, and this app can hold a multi-gigabyte model,
    /// so it happens; without a reload the view would sit blank.
    private(set) var processTerminations = 0

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processTerminations += 1
        webView.reload()
        sync()
    }
}

/// Forwards `WKScriptMessageHandler` calls to the model without retaining it.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebClipperModel?

    init(target: WebClipperModel) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit delivers script messages on the main thread.
        MainActor.assumeIsolated {
            target?.onScriptMessage?(message.name, message.body)
        }
    }
}
