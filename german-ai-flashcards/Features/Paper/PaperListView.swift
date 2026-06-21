import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Lists imported German papers and lets the user import a new PDF to study & discuss.
struct PaperListView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \StudyPaper.createdAt, order: .reverse) private var papers: [StudyPaper]
    @Environment(\.modelContext) private var modelContext

    @State private var showImporter = false
    @State private var showURLImport = false
    @State private var importError: String?
    @State private var generatingPaper: StudyPaper?
    @State private var service: PaperStudyService?
    @State private var cacheRefreshID = UUID()
    @State private var duplicatePrompt: PendingImport?
    @State private var reviewItem: PendingReview?

    private var regularPapers: [StudyPaper] {
        papers.filter { $0.sourceURL?.hasPrefix("photo://") != true }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Import a German PDF", systemImage: "doc.badge.plus")
                        .font(.body.weight(.medium))
                }
                Button {
                    showURLImport = true
                } label: {
                    Label("Import from a link", systemImage: "link.badge.plus")
                        .font(.body.weight(.medium))
                }
            } footer: {
                Text("Upload a German paper or paste a link. The AI extracts a summary, a vocabulary deck, and questions — then you can discuss it.")
                    .font(.caption2)
            }

            ChatModelPickerSection(
                selected: $modelManager.selectedPaperModel,
                cacheRefreshID: cacheRefreshID,
                title: "Study model",
                footerText: "Used to generate the summary, deck, and questions, and to discuss the paper. \(PaperStudyService.requiredModel.rawValue) is recommended for its German quality, but any downloaded model works."
            )

            if let importError {
                Section {
                    Label(importError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            if regularPapers.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No papers yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Import a German PDF to study and discuss it.")
                    )
                }
            } else {
                Section("Your papers") {
                    ForEach(regularPapers) { paper in
                        NavigationLink {
                            PaperDetailView(paper: paper, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            row(paper)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(paper) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Study a Paper")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            handleImport(result)
        }
        .sheet(item: $generatingPaper) { paper in
            if let service {
                PaperGeneratingView(service: service, paper: paper) {
                    generatingPaper = nil
                }
            }
        }
        .sheet(isPresented: $showURLImport) {
            URLImportView(accent: modelManager.selectedPaperModel.theme.accent) { title, text, url in
                // Defer so the URL sheet finishes dismissing before the next sheet/dialog appears.
                DispatchQueue.main.async {
                    tryImport(title: title, text: text, sourceURL: url)
                }
            }
        }
        .sheet(item: $reviewItem) { item in
            ExtractedTextReviewView(title: item.title, text: item.text, accent: modelManager.selectedPaperModel.theme.accent) { deckCount, selectedWords in
                // Defer so the review sheet finishes dismissing before the generating sheet appears.
                DispatchQueue.main.async {
                    createAndGenerate(
                        title: item.title, text: item.text, sourceURL: item.sourceURL,
                        deckCount: deckCount, selectedWords: selectedWords
                    )
                }
            }
        }
        .confirmationDialog(
            "Already imported",
            isPresented: Binding(get: { duplicatePrompt != nil }, set: { if !$0 { duplicatePrompt = nil } }),
            titleVisibility: .visible,
            presenting: duplicatePrompt
        ) { item in
            Button("Import again anyway") {
                duplicatePrompt = nil
                DispatchQueue.main.async {
                    reviewItem = PendingReview(title: item.title, text: item.text, sourceURL: item.sourceURL)
                }
            }
            Button("Cancel", role: .cancel) { duplicatePrompt = nil }
        } message: { item in
            Text("You’ve already studied this as “\(item.existingTitle)” — it’s in your list below.")
        }
    }

    private func row(_ paper: StudyPaper) -> some View {
        let accent = paper.rowTheme?.accent ?? modelManager.selectedPaperModel.theme.accent
        return HStack(spacing: 12) {
            Image(systemName: paper.sourceSymbol)
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(paper.title).lineLimit(1)
                HStack(spacing: 8) {
                    Text(paper.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Text("\(paper.wordCount) words")
                    if !paper.generationComplete {
                        Label("incomplete", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Import

    private func handleImport(_ result: Result<URL, Error>) {
        importError = nil
        switch result {
        case .failure(let error):
            importError = "Couldn’t open the file: \(error.localizedDescription)"
        case .success(let url):
            guard let extracted = PDFTextExtractor.extract(from: url) else {
                importError = "Couldn’t read that PDF."
                return
            }
            guard !extracted.looksScanned else {
                importError = "This PDF appears to be scanned (no selectable text). Text extraction needs a PDF with a real text layer."
                return
            }
            let title = url.deletingPathExtension().lastPathComponent
            tryImport(title: title, text: extracted.text, sourceURL: nil)
        }
    }

    /// Check for a prior import of the same link/file before showing the review step.
    private func tryImport(title: String, text: String, sourceURL: String?) {
        importError = nil
        if let existing = findDuplicate(sourceURL: sourceURL, title: title, text: text) {
            duplicatePrompt = PendingImport(title: title, text: text, sourceURL: sourceURL, existingTitle: existing.title)
        } else {
            reviewItem = PendingReview(title: title, text: text, sourceURL: sourceURL)
        }
    }

    private func createAndGenerate(title: String, text: String, sourceURL: String?, deckCount: Int, selectedWords: [String]?) {
        let paper = StudyPaper(title: title, fullText: text, sourceURL: sourceURL)
        modelContext.insert(paper)
        try? modelContext.save()
        startGeneration(for: paper, deckCount: deckCount, selectedWords: selectedWords)
    }

    private func findDuplicate(sourceURL: String?, title: String, text: String) -> StudyPaper? {
        if let sourceURL {
            let key = normalizedURLKey(sourceURL)
            if let match = papers.first(where: { $0.sourceURL.map(normalizedURLKey) == key }) {
                return match
            }
        }
        // PDFs (no URL): same name and near-identical length.
        return papers.first { $0.sourceURL == nil && $0.title == title && abs($0.fullText.count - text.count) < 50 }
    }

    /// Normalize a URL for dedup: drop scheme/www/old, key Reddit on its /comments/<id>.
    private func normalizedURLKey(_ raw: String) -> String {
        var k = raw.lowercased()
        for prefix in ["https://", "http://"] where k.hasPrefix(prefix) { k.removeFirst(prefix.count) }
        if k.hasPrefix("www.") { k.removeFirst(4) }
        if k.hasPrefix("old.") { k.removeFirst(4) }
        if k.contains("reddit.com"), let r = k.range(of: "/comments/") {
            let id = k[r.upperBound...].prefix { $0 != "/" }
            return "reddit:\(id)"
        }
        if let q = k.firstIndex(of: "?") { k = String(k[..<q]) }
        if k.hasSuffix("/") { k.removeLast() }
        return k
    }

    private func startGeneration(for paper: StudyPaper, deckCount: Int, selectedWords: [String]?) {
        let svc = PaperStudyService(mlxService: mlxService, modelContext: modelContext)
        service = svc
        generatingPaper = paper
        Task {
            await svc.generate(
                for: paper, model: modelManager.selectedPaperModel,
                deckCount: deckCount, questionCount: 6, selectedWords: selectedWords
            )
        }
    }

    private func delete(_ paper: StudyPaper) {
        modelContext.delete(paper)
        try? modelContext.save()
    }
}

private struct PendingImport: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let sourceURL: String?
    let existingTitle: String
}

/// Extraction awaiting user review (deck size / word picks) before generation starts.
private struct PendingReview: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let sourceURL: String?
}

/// Progress view shown while the paper's study materials are generated.
private struct PaperGeneratingView: View {
    let service: PaperStudyService
    let paper: StudyPaper
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch service.phase {
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
                case .done:
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                    Text("“\(paper.title)” is ready to study.").multilineTextAlignment(.center)
                default:
                    ProgressView(value: service.progress)
                        .progressViewStyle(.linear)
                        .tint(service.model.theme.accent)
                        .frame(maxWidth: 260)
                    Text(service.statusText).foregroundStyle(.secondary)
                    if service.phase == .loadingModel {
                        Text("First-time use downloads \(service.model.rawValue).")
                            .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Studying paper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(service.isRunning ? "Hide" : "Done") { onClose() }
                }
            }
            .interactiveDismissDisabled(service.isRunning)
        }
    }
}

/// Paste a link to fetch and study its German text.
private struct URLImportView: View {
    var accent: Color = .accentColor
    var onFetched: (_ title: String, _ text: String, _ url: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var loading = false
    @State private var error: String?
    @State private var showBrowser = false
    @State private var pasteSuggestion: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("https://www.reddit.com/r/de/…", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit(fetch)
                        if !urlText.isEmpty {
                            Button { urlText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if urlText.isEmpty, let pasteSuggestion {
                        Button {
                            urlText = pasteSuggestion
                            self.pasteSuggestion = nil
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.on.clipboard")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Paste copied link").font(.caption).foregroundStyle(.secondary)
                                    Text(pasteSuggestion).font(.callout).lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Link")
                } footer: {
                    Text("Tested on German Reddit posts and the AI Factory Austria news page (ai-at.eu/news). Other sites may work too. but... lots of sites have bot protection. and this feature can be fickle. You can also save pages as PDFs in Safari and then upload the PDF if you're having trouble.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section {
                    Button(action: fetch) {
                        if loading {
                            HStack(spacing: 8) { ProgressView(); Text("Fetching…") }
                        } else {
                            Label("Quick fetch & study", systemImage: "arrow.down.doc")
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || loading)

                    Button { showBrowser = true } label: {
                        Label("Open in browser (log in if needed)", systemImage: "safari")
                    }
                } footer: {
                    Text("Reddit often blocks direct fetches. If the quick fetch fails, open the page in the in-app browser, log in or navigate to the post, then tap “Use this page”.")
                }
            }
            .navigationTitle("Study a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showBrowser) {
                WebClipperView(initialURL: urlText.isEmpty ? nil : urlText, accent: accent) { title, text, url in
                    showBrowser = false
                    onFetched(title, text, url)
                    dismiss()
                }
            }
            .onAppear { checkClipboard() }
        }
    }

    /// Offer a one-tap paste when a URL is on the clipboard (like Maps' "paste copied link").
    private func checkClipboard() {
        #if canImport(UIKit)
        guard urlText.isEmpty else { return }
        let board = UIPasteboard.general
        // `hasURLs` / `hasStrings` don't expose content (no "pasted from…" banner); reading does.
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

    private func fetch() {
        let input = urlText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, !loading else { return }
        loading = true
        error = nil
        Task {
            let result = await WebTextExtractor.fetch(input)
            loading = false
            switch result {
            case .success(let extracted):
                onFetched(extracted.title, extracted.text, input)
                dismiss()
            case .failure(let webError):
                error = webError.errorDescription
            }
        }
    }
}
