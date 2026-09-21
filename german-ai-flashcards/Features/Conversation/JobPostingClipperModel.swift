import Foundation
import SwiftUI
import UIKit
import WebKit

/// The job-posting clipper's draft: which suggested sections are in, which highlights were added,
/// and the details the recruiter will be told. Wraps a `WebClipperModel` that carries the
/// selection/settle observer script and reports through the two message handlers.
@MainActor
@Observable
final class JobPostingClipperModel: Identifiable {
    let id = UUID()
    let web: WebClipperModel

    /// Set by the clipper view the first time it appears. The setup screen owns the model, so a
    /// re-created view finds the page already loaded and leaves it alone.
    var hasStarted = false

    /// Panel presentation state. It lives here, not in the view, because SwiftUI rebuilds the
    /// browser view when the panel covers it at full height; view state would hand the sheet its
    /// default detent again and snap it back halfway.
    var panelShown = false
    var detent: PresentationDetent = JobPostingClipperView.midDetent
    /// The page has a cookie / consent notice pinned to the bottom, right where the collapsed
    /// panel sits. Found by `JobPostingScripts.consentOverlay` on every analysis.
    private(set) var consentOverlayShown = false
    /// The panel was hidden by the model for that notice (not by the learner), so it comes back
    /// on its own once the notice is gone.
    private(set) var panelAutoHidden = false
    /// The learner hid the panel with the toolbar button. The notice check then leaves it alone.
    private(set) var panelHiddenManually = false

    /// Character budget for the composed posting; the setup screen sets it from
    /// `JobContextBudget` for the tutor the learner picked.
    var cap = 3_000

    /// "r, g, b" of the tint the page paints selected sections with; the view sets it to the
    /// same accent the section pills use, so pill and page read as one.
    var highlightRGB = "255, 204, 0"

    private(set) var sections: [SuggestedSection] = []
    var selectedSectionIDs: Set<String> = []
    private(set) var snippets: [String] = []
    /// The last non-empty highlight the page reported. WebKit drops the selection when the web
    /// view resigns first responder (tapping the panel does that), so an empty report never
    /// overwrites it; only Add or Clear do.
    private(set) var pendingSelection = ""

    var title = ""
    var company = ""
    var location = ""
    // The values the page supplied. A field is refreshed on re-analysis only while it still holds
    // the previous page value, so a learner's edit survives navigation and hydration.
    private var autoTitle = ""
    private var autoCompany = ""
    private var autoLocation = ""

    private(set) var isAnalyzing = false
    private(set) var hasAnalyzed = false
    /// True while the page is being rendered to PDF for the saved copy.
    private(set) var isCapturing = false
    private var lastAnalysisAt: Date = .distantPast
    private var analysisTask: Task<Void, Never>?

    /// Analyses are at least this far apart; single-page boards mutate the DOM in bursts.
    private static let analysisInterval: TimeInterval = 1.5

    init() {
        let observer = WKUserScript(
            source: JobPostingScripts.observer,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        web = WebClipperModel(userScripts: [observer], messageHandlerNames: JobPostingScripts.handlerNames)
        web.onScriptMessage = { [weak self] name, body in
            self?.handle(name: name, body: body)
        }
        web.onDidFinish = { [weak self] in
            self?.analyzeSoon()
        }
    }

    // MARK: Page messages

    private func handle(name: String, body: Any) {
        switch name {
        case JobPostingScripts.selectionHandler:
            if let text = body as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { pendingSelection = trimmed }
            }
        case JobPostingScripts.pageHandler:
            analyzeSoon()
        default:
            break
        }
    }

    /// Schedule an analysis, coalescing bursts into one run per interval.
    func analyzeSoon() {
        guard analysisTask == nil else { return }
        let wait = max(0, Self.analysisInterval - Date().timeIntervalSince(lastAnalysisAt))
        analysisTask = Task { [weak self] in
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard let self, !Task.isCancelled else { return }
            await self.analyze()
            self.analysisTask = nil
        }
    }

    /// Re-read the page's headings and metadata. Keeps every selected section whose heading is
    /// still on the page (ids carry the DOM index, which shifts as a page hydrates).
    func analyze() async {
        isAnalyzing = true
        defer {
            isAnalyzing = false
            hasAnalyzed = true
            lastAnalysisAt = .now
        }
        guard let result = await web.evaluateJSON(JobPostingScripts.analyze, as: JobPageAnalysis.self) else { return }
        let keptHeadings = Set(selectedSections.map(\.heading))
        sections = result.sections
        selectedSectionIDs = Set(sections.filter { keptHeadings.contains($0.heading) }.map(\.id))
        applyAuto(result.meta)
        // The page was re-tagged; paint the kept selections again.
        syncHighlights()
        await checkConsentOverlay()
    }

    // MARK: Panel vs. the page's bottom edge

    /// Cookie notices sit exactly where the collapsed panel does, and a learner can't accept
    /// what they can't reach. When one is under the panel, the panel goes away until the notice
    /// does; a learner who hid or showed the panel by hand keeps their choice.
    private func checkConsentOverlay() async {
        let overlay = await web.evaluateJSON(JobPostingScripts.consentOverlay, as: ConsentOverlayReport.self)
        let present = overlay?.present ?? false
        guard present != consentOverlayShown else { return }
        consentOverlayShown = present
        if present {
            guard !panelHiddenManually else { return }
            if panelShown { panelShown = false }
            panelAutoHidden = true
        } else if panelAutoHidden {
            panelAutoHidden = false
            panelShown = true
        }
    }

    /// The view's first presentation of the panel, once the cover has settled. Held back while a
    /// notice is already under it (the page can settle before the panel is due).
    func presentPanelInitially() {
        guard !panelHiddenManually, !panelShown else { return }
        if consentOverlayShown {
            panelAutoHidden = true
        } else {
            panelShown = true
        }
    }

    /// The learner's own toggle. Clears the automatic hide, so the notice check leaves the panel
    /// alone from here on; hiding by hand sticks until they show it again.
    func togglePanel() {
        panelAutoHidden = false
        panelShown.toggle()
        panelHiddenManually = !panelShown
    }

    private struct ConsentOverlayReport: Decodable {
        var present: Bool
    }

    /// Ask the page to tint exactly the selected sections, and optionally scroll one into view.
    private func syncHighlights(scrollTo order: Int? = nil) {
        let orders = selectedSections.map(\.order)
        let rgb = highlightRGB
        Task {
            _ = await web.evaluateString(JobPostingScripts.highlight(orders: orders, rgb: rgb))
            if let order {
                _ = await web.evaluateString(JobPostingScripts.scrollTo(order: order))
            }
        }
    }

    private func applyAuto(_ meta: JobPageMeta) {
        let pageTitle = meta.h1.isEmpty ? Self.firstSegment(of: meta.title) : meta.h1
        let newTitle = String(pageTitle.prefix(ConversationConfig.jobTitleCap))
        if !newTitle.isEmpty {
            if title.isEmpty || title == autoTitle { title = newTitle }
            autoTitle = newTitle
        }
        let newCompany = String(meta.company.prefix(ConversationConfig.jobDetailCap))
        if !newCompany.isEmpty {
            if company.isEmpty || company == autoCompany { company = newCompany }
            autoCompany = newCompany
        }
        let newLocation = String(meta.location.prefix(ConversationConfig.jobDetailCap))
        if !newLocation.isEmpty {
            if location.isEmpty || location == autoLocation { location = newLocation }
            autoLocation = newLocation
        }
    }

    /// "IT-Plattformmanager (m/w/d) - Digital Workforce Group" → "IT-Plattformmanager (m/w/d)".
    private static func firstSegment(of title: String) -> String {
        if let match = title.firstMatch(of: #/\s+[-|–—·:]\s+/#) {
            return String(title[..<match.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Draft edits

    var selectedSections: [SuggestedSection] {
        sections.filter { selectedSectionIDs.contains($0.id) }.sorted { $0.order < $1.order }
    }

    /// Include or drop a section. Including one also scrolls the page to it, so the learner sees
    /// what the tint covers.
    func toggle(_ section: SuggestedSection) {
        if selectedSectionIDs.contains(section.id) {
            selectedSectionIDs.remove(section.id)
            syncHighlights()
        } else {
            selectedSectionIDs.insert(section.id)
            syncHighlights(scrollTo: section.order)
        }
    }

    func deselectSections(at offsets: IndexSet) {
        let chosen = selectedSections
        for index in offsets where chosen.indices.contains(index) {
            selectedSectionIDs.remove(chosen[index].id)
        }
        syncHighlights()
    }

    func addSelection() {
        let text = pendingSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        snippets.append(text)
        pendingSelection = ""
        Task { _ = await web.evaluateString(JobPostingScripts.clearSelection) }
    }

    func clearSelection() {
        pendingSelection = ""
        Task { _ = await web.evaluateString(JobPostingScripts.clearSelection) }
    }

    /// Manual fallback for pages that swallow `selectionchange`.
    func readSelection() async {
        guard let text = await web.evaluateString(JobPostingScripts.readSelection) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { pendingSelection = trimmed }
    }

    func removeSnippets(at offsets: IndexSet) {
        snippets.remove(atOffsets: offsets)
    }

    /// Replace the draft with the page's main text (the Paper clipper's extraction), for static
    /// pages that have no headings worth the name. Returns false when the page had too little.
    @discardableResult
    func useWholePage() async -> Bool {
        isAnalyzing = true
        defer { isAnalyzing = false }
        let (pageTitle, text, _) = await web.extract()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 60 else { return false }
        selectedSectionIDs = []
        snippets = [trimmed]
        if title.isEmpty { title = String(pageTitle.prefix(ConversationConfig.jobTitleCap)) }
        syncHighlights()
        return true
    }

    func clearAll() {
        selectedSectionIDs = []
        snippets = []
        syncHighlights()
    }

    // MARK: Output

    /// Selected sections in page order, then the highlights, as the recruiter will read them.
    var composedText: String {
        var blocks = selectedSections.map { "\($0.heading)\n\($0.text)" }
        blocks.append(contentsOf: snippets)
        return blocks.joined(separator: "\n\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }

    var charCount: Int { composedText.count }
    var isOverCap: Bool { charCount > cap }
    var canCapture: Bool { charCount >= 60 }

    /// The draft as the setup screen receives it, plus a PDF of the page as it looks right now
    /// (without our tints) so the posting survives the link going dead.
    func capture() async -> JobPostingCapture {
        let chosenTitle = [title, autoTitle, web.webView.title ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        var result = JobPostingCapture(
            title: String(chosenTitle.prefix(ConversationConfig.jobTitleCap)),
            text: String(composedText.prefix(cap)),
            company: String(company.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ConversationConfig.jobDetailCap)),
            location: String(location.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ConversationConfig.jobDetailCap)),
            url: web.currentURL
        )
        result.snapshotPDF = await snapshotPDF()
        return result
    }

    /// Best effort. WebKit's own renderer first (the whole document as one PDF); if that fails,
    /// the print formatter paginates it onto A4 pages instead. Nil when neither produced a file.
    private func snapshotPDF() async -> Data? {
        isCapturing = true
        defer { isCapturing = false }
        _ = await web.evaluateString(JobPostingScripts.highlight(orders: [], rgb: highlightRGB))
        defer { syncHighlights() }
        if let data = await renderPDF(), data.count > 1_024 {
            return data
        }
        return printedPDF()
    }

    /// `WKWebView.createPDF` only ships its completion-handler form here.
    private func renderPDF() async -> Data? {
        await withCheckedContinuation { continuation in
            web.webView.createPDF(configuration: WKPDFConfiguration()) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    private func printedPDF() -> Data? {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.webView.viewPrintFormatter(), startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)   // A4 in points
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 28, dy: 28), forKey: "printableRect")
        guard renderer.numberOfPages > 0 else { return nil }
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data.count > 1_024 ? data as Data : nil
    }

    func tearDown() {
        analysisTask?.cancel()
        analysisTask = nil
        web.tearDown()
    }
}
