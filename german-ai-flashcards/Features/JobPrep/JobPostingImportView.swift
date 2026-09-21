//
//  JobPostingImportView.swift
//  german-ai-flashcards
//
//  Bringing a job description over to study. Four doors: the in-app browser (the interview
//  mode's clipper, with its section picker and PDF snapshot), a PDF from Files, pasted text, or an
//  interview chat that already holds a posting. Everything but the browser passes through a short
//  review step for the title and details; the browser collects those in its own panel.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct JobPostingImportView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var onImported: (JobPosting) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme

    @Query(sort: \JobPosting.updatedAt, order: .reverse) private var postings: [JobPosting]
    // See `ChatConversation.interviewModeRaw` for the literal.
    @Query(filter: #Predicate<ChatConversation> { $0.modeRaw == "Interview" },
           sort: \ChatConversation.updatedAt, order: .reverse)
    private var interviews: [ChatConversation]

    @State private var jobURLText = ""
    @State private var pasteSuggestion: String?
    @State private var clipper: JobPostingClipperModel?
    @State private var showFileImporter = false
    @State private var showPaste = false
    @State private var showChats = false
    @State private var pending: PendingPosting?
    @State private var duplicate: DuplicatePrompt?
    @State private var errorMessage: String?
    @FocusState private var urlFocused: Bool

    private var accent: Color { appTheme.accent(model: modelTheme) }

    /// Interview chats that actually carry a posting to study.
    private var adoptableChats: [ChatConversation] {
        interviews.filter { convo in
            let hasText = !(convo.jobContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasText || JobPostingSnapshotStore.exists(convo.jobSnapshotFile)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                linkSection.themedListRow()
                otherSourcesSection.themedListRow()
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Study a job ad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { urlFocused = false }
                }
            }
            .navigationDestination(item: $pending) { item in
                JobPostingReviewView(draft: item, accent: accent) { reviewed in
                    save(reviewed)
                }
            }
            .navigationDestination(isPresented: $showPaste) {
                JobPostingPasteView(accent: accent) { draft in
                    showPaste = false
                    pending = draft
                }
            }
            .navigationDestination(isPresented: $showChats) {
                chatPicker
            }
            .fullScreenCover(item: $clipper) { clipper in
                JobPostingClipperView(
                    model: clipper,
                    initialURL: jobURLText,
                    tutor: modelManager.selectedChatModel,
                    accent: accent,
                    capOverride: JobPostingClipperView.studyCap,
                    useButtonTitle: "Study this posting",
                    showsBudget: false
                ) { capture in
                    clipper.tearDown()
                    self.clipper = nil
                    received(capture)
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf]) { result in
                handleFile(result)
            }
            .confirmationDialog(
                "You already saved this posting",
                isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                titleVisibility: .visible,
                presenting: duplicate
            ) { prompt in
                Button("Open it") {
                    finish(prompt.existing)
                }
                Button("Save another copy") {
                    duplicate = nil
                    DispatchQueue.main.async { pending = prompt.draft }
                }
                Button("Cancel", role: .cancel) { duplicate = nil }
            } message: { prompt in
                Text("“\(prompt.existing.title)” is already in your postings.")
            }
            .onAppear {
                if jobURLText.isEmpty { pasteSuggestion = ClipboardLink.suggestion() }
            }
        }
    }

    // MARK: - Sections

    private var linkSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Link to the job posting…", text: $jobURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($urlFocused)
                    .onSubmit(openClipper)
                if !jobURLText.isEmpty {
                    Button {
                        jobURLText = ""
                        pasteSuggestion = ClipboardLink.suggestion()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear the link")
                }
            }

            if jobURLText.isEmpty, let pasteSuggestion {
                Button {
                    jobURLText = pasteSuggestion
                    self.pasteSuggestion = nil
                    openClipper()
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

            Button(action: openClipper) {
                Label("Open posting in the browser", systemImage: "safari")
            }
        } header: {
            Text("From a link").themedSectionHeader()
        } footer: {
            Text("Open the posting, then tap the sections that matter or highlight text on the page. A copy of the whole page is saved with it, so it stays readable if the ad goes offline.")
                .font(.caption2)
        }
    }

    private var otherSourcesSection: some View {
        Section {
            Button {
                showFileImporter = true
            } label: {
                ActivityRow("PDF file", "A posting saved from Files or Mail", "doc.richtext")
            }
            .buttonStyle(.plain)

            Button {
                showPaste = true
            } label: {
                ActivityRow("Paste text", "The posting copied from anywhere", "doc.on.clipboard")
            }
            .buttonStyle(.plain)

            Button {
                showChats = true
            } label: {
                ActivityRow(
                    "From an interview",
                    adoptableChats.isEmpty
                        ? "No interview holds a posting yet"
                        : "\(adoptableChats.count) posting\(adoptableChats.count == 1 ? "" : "s") you already prepared for",
                    "bubble.left.and.bubble.right"
                )
            }
            .buttonStyle(.plain)
            .disabled(adoptableChats.isEmpty)
        } header: {
            Text("Other sources").themedSectionHeader()
        }
    }

    private var chatPicker: some View {
        List {
            Section {
                ForEach(adoptableChats) { convo in
                    Button {
                        adopt(convo)
                    } label: {
                        ConversationRow(conversation: convo)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("The posting text and the saved page copy are brought over; the chat keeps its own.")
                    .font(.caption2)
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("From an interview")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sources

    private func openClipper() {
        urlFocused = false
        errorMessage = nil
        // The browser needs no model, and WebKit's content process is the first thing iOS reclaims
        // under memory pressure; drop the tutor so the page renders (the reader reloads it).
        mlxService.unloadModel()
        MemorySaver.releaseCaches()
        clipper = JobPostingClipperModel()
    }

    private func received(_ capture: JobPostingCapture) {
        let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        jobURLText = capture.url
        let draft = PendingPosting(
            title: capture.title,
            company: capture.company,
            location: capture.location,
            url: capture.url,
            text: text,
            sourceKind: .link,
            snapshotPDF: capture.snapshotPDF
        )
        // The browser already collected the details; no second review.
        if let existing = postings.first(where: { JobURL.same($0.sourceURL, capture.url) }) {
            duplicate = DuplicatePrompt(existing: existing, draft: draft)
        } else {
            save(draft)
        }
    }

    private func handleFile(_ result: Result<URL, Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = "Couldn’t open the file: \(error.localizedDescription)"
        case .success(let url):
            guard let extracted = PDFTextExtractor.extract(from: url) else {
                errorMessage = "Couldn’t read that PDF."
                return
            }
            guard !extracted.looksScanned else {
                errorMessage = "This PDF appears to be scanned (no selectable text). Reading needs a PDF with a real text layer."
                return
            }
            let needsAccess = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if needsAccess { url.stopAccessingSecurityScopedResource() }
            pending = PendingPosting(
                title: url.deletingPathExtension().lastPathComponent,
                company: "",
                location: "",
                url: "",
                text: JobPosting.cleanedText(extracted.text),
                sourceKind: .pdf,
                snapshotPDF: data
            )
        }
    }

    /// Bring an interview chat's posting over as a study copy of its own.
    private func adopt(_ convo: ChatConversation) {
        var text = (convo.jobContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, let file = convo.jobSnapshotFile, JobPostingSnapshotStore.exists(file),
           let extracted = PDFTextExtractor.extract(from: JobPostingSnapshotStore.url(for: file)) {
            text = JobPosting.cleanedText(extracted.text)
        }
        guard !text.isEmpty else {
            errorMessage = "That chat has no readable posting."
            showChats = false
            return
        }
        showChats = false
        pending = PendingPosting(
            title: convo.jobTitle ?? convo.title,
            company: convo.jobCompany ?? "",
            location: convo.jobLocation ?? "",
            url: convo.jobURL ?? "",
            text: text,
            sourceKind: .chat,
            snapshotSourceFile: convo.jobSnapshotFile,
            adoptedFromChatID: convo.id
        )
    }

    // MARK: - Save

    private func save(_ draft: PendingPosting) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let posting = JobPosting(
            title: title.isEmpty ? "Job posting" : String(title.prefix(ConversationConfig.jobTitleCap)),
            text: draft.text,
            sourceKind: draft.sourceKind
        )
        posting.company = detail(draft.company)
        posting.location = detail(draft.location)
        posting.sourceURL = detail(draft.url, cap: 2_000)
        // The posting's own copy: a fresh write for the browser and PDF paths, a duplicate of the
        // chat's file when adopted, so deleting either leaves the other alone.
        if let data = draft.snapshotPDF {
            posting.snapshotFile = JobPostingSnapshotStore.save(data)
        } else {
            posting.snapshotFile = JobPostingSnapshotStore.duplicate(draft.snapshotSourceFile)
        }
        posting.adoptedFromChatIDRaw = draft.adoptedFromChatID?.uuidString
        modelContext.insert(posting)
        if let chatID = draft.adoptedFromChatID, let convo = interviews.first(where: { $0.id == chatID }) {
            convo.jobPostingIDRaw = posting.id.uuidString
        }
        try? modelContext.save()
        finish(posting)
    }

    private func finish(_ posting: JobPosting) {
        dismiss()
        onImported(posting)
    }

    private func detail(_ text: String, cap: Int = ConversationConfig.jobDetailCap) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(cap))
    }
}

// MARK: - Drafts

/// A posting on its way in, before it becomes a `JobPosting`.
struct PendingPosting: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var company: String
    var location: String
    var url: String
    var text: String
    var sourceKind: JobPosting.SourceKind
    /// A PDF to write as the posting's copy (browser snapshot or the imported file).
    var snapshotPDF: Data? = nil
    /// An existing snapshot to duplicate (adopted from a chat).
    var snapshotSourceFile: String? = nil
    var adoptedFromChatID: UUID? = nil

    static func == (lhs: PendingPosting, rhs: PendingPosting) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct DuplicatePrompt: Identifiable {
    let existing: JobPosting
    let draft: PendingPosting
    var id: UUID { draft.id }
}

// MARK: - Review

/// Title and details for a posting that came in without them (a PDF, pasted text, or a chat),
/// with the text to check before it's saved.
struct JobPostingReviewView: View {
    @State var draft: PendingPosting
    let accent: Color
    let onConfirm: (PendingPosting) -> Void

    @FocusState private var focused: Field?
    private enum Field: Hashable { case title, company, location }

    var body: some View {
        Form {
            Section {
                TextField("Job title", text: $draft.title)
                    .focused($focused, equals: .title)
                TextField("Company", text: $draft.company)
                    .focused($focused, equals: .company)
                TextField("Location", text: $draft.location)
                    .focused($focused, equals: .location)
            } header: {
                Text("Details").themedSectionHeader()
            } footer: {
                Text("The title names the posting and its flashcard deck.")
                    .font(.caption2)
            }
            .themedListRow()

            Section {
                Text(draft.text)
                    .font(.callout)
                    .lineLimit(12)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Posting").themedSectionHeader()
                    Spacer()
                    Text("\(draft.text.split { $0 == " " || $0 == "\n" }.count) Wörter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Check the posting")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onConfirm(draft)
            } label: {
                Text("Study this posting")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }
}

// MARK: - Paste

/// A posting typed or pasted in. Hands a draft to the review step for the details.
struct JobPostingPasteView: View {
    let accent: Color
    let onNext: (PendingPosting) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .focused($focused)
            } header: {
                Text("Posting text").themedSectionHeader()
            } footer: {
                Text("Paste the whole ad. German is what the reader is for; English parts are fine to leave in.")
                    .font(.caption2)
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Paste text")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .safeAreaInset(edge: .bottom) {
            Button {
                focused = false
                onNext(PendingPosting(
                    title: firstLine(of: trimmed),
                    company: "",
                    location: "",
                    url: "",
                    text: JobPosting.cleanedText(trimmed),
                    sourceKind: .paste
                ))
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            .disabled(trimmed.count < 40)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    /// The first short line usually is the job title; anything longer is left for the learner.
    private func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count <= ConversationConfig.jobTitleCap ? line : ""
    }
}
