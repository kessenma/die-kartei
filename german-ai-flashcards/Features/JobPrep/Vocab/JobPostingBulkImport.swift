//
//  JobPostingBulkImport.swift
//  german-ai-flashcards
//
//  Several job ads at once, for the word count: pick the postings already saved, or bring in
//  more in one go — several PDFs from Files, or a list of links. A link is read the plain way
//  (`WebTextExtractor.fetch`, the Papers path): no browser, no section picking, no page copy. A
//  site that needs its browser (most job boards behind a login or a cookie wall) says so per link,
//  and the one-at-a-time import with the in-app browser is still there for it.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Choosing ads

struct JobPostingMultiPicker: View {
    @Binding var selection: Set<UUID>
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobPosting.updatedAt, order: .reverse) private var postings: [JobPosting]

    @State private var showImport = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showImport = true
                    } label: {
                        Label("Bring in several ads", systemImage: "square.and.arrow.down.on.square")
                    }
                } footer: {
                    Text("PDFs from Files, or a list of links.")
                }
                .themedListRow()

                Section {
                    if postings.isEmpty {
                        Text("No postings yet.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(postings) { posting in
                        Button {
                            if selection.contains(posting.id) { selection.remove(posting.id) } else { selection.insert(posting.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selection.contains(posting.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(posting.id) ? Color.accentColor : .secondary)
                                JobPostingRow(posting: posting, deck: JobDeckStore.deck(for: posting, context: modelContext))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Job postings").themedSectionHeader()
                        Spacer()
                        if !postings.isEmpty {
                            Button(selection.count == postings.count ? "None" : "All") {
                                selection = selection.count == postings.count ? [] : Set(postings.map(\.id))
                            }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Choose ads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showImport) {
                JobPostingBulkImportView { imported in
                    selection.formUnion(imported)
                    showImport = false
                }
            }
        }
    }
}

// MARK: - Bringing in several

struct JobPostingBulkImportView: View {
    /// The postings made, once the learner is done.
    var onDone: (Set<UUID>) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobPosting.updatedAt, order: .reverse) private var postings: [JobPosting]

    @State private var showFiles = false
    @State private var linksText = ""
    @State private var results: [Outcome] = []
    @State private var working: String?
    @State private var imported: Set<UUID> = []
    @FocusState private var linksFocused: Bool

    struct Outcome: Identifiable {
        let id = UUID()
        let title: String
        let failure: String?
    }

    private var links: [String] {
        linksText.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains(".") && !$0.isEmpty }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showFiles = true
                } label: {
                    ActivityRow("PDF files", "Pick several at once in Files", "doc.on.doc")
                }
                .buttonStyle(.plain)
                .disabled(working != nil)
            } header: {
                Text("Files").themedSectionHeader()
            } footer: {
                Text("Each PDF becomes a posting named after its file, with the PDF kept as its copy. Scanned PDFs (no selectable text) are skipped.")
            }
            .themedListRow()

            Section {
                TextEditor(text: $linksText)
                    .frame(minHeight: 110)
                    .font(.callout)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($linksFocused)
                Button {
                    linksFocused = false
                    Task { await importLinks() }
                } label: {
                    Label(links.isEmpty ? "Read the links" : "Read \(links.count) link\(links.count == 1 ? "" : "s")", systemImage: "link")
                }
                .disabled(links.isEmpty || working != nil)
            } header: {
                Text("Links, one per line").themedSectionHeader()
            } footer: {
                Text("Read without the browser, so a site behind a login or a cookie wall may not give its text. Use Study a job ad ▸ From a link for those.")
            }
            .themedListRow()

            if let working {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(working).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .themedListRow()
            }

            if !results.isEmpty {
                Section {
                    ForEach(results) { outcome in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: outcome.failure == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(outcome.failure == nil ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outcome.title).font(.subheadline).lineLimit(2)
                                if let failure = outcome.failure {
                                    Text(failure).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Brought in").themedSectionHeader()
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Several ads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(imported.isEmpty ? "Done" : "Use \(imported.count)") { onDone(imported) }
                    .disabled(working != nil)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await importFiles(urls) }
            case .failure(let error):
                results.append(Outcome(title: "Files", failure: error.localizedDescription))
            }
        }
    }

    // MARK: - Import

    private func importFiles(_ urls: [URL]) async {
        // The bytes come out of each security-scoped URL right away; the reading happens off the
        // main actor, one file at a time.
        let files: [(title: String, data: Data?)] = urls.map { url in
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            return (url.deletingPathExtension().lastPathComponent, try? Data(contentsOf: url))
        }
        for (index, file) in files.enumerated() {
            working = "Reading \(index + 1) of \(files.count)…"
            guard let data = file.data else {
                results.append(Outcome(title: file.title, failure: "Couldn't open the file."))
                continue
            }
            let extracted = await Task.detached(priority: .userInitiated) {
                PDFTextExtractor.extract(from: data)
            }.value
            guard let extracted else {
                results.append(Outcome(title: file.title, failure: "Couldn't read that PDF."))
                continue
            }
            guard !extracted.looksScanned else {
                results.append(Outcome(title: file.title, failure: "Scanned: no text to read."))
                continue
            }
            let posting = JobPosting(title: String(file.title.prefix(ConversationConfig.jobTitleCap)),
                                     text: JobPosting.cleanedText(extracted.text), sourceKind: .pdf)
            posting.snapshotFile = JobPostingSnapshotStore.save(data)
            insert(posting)
            results.append(Outcome(title: posting.title, failure: nil))
        }
        working = nil
    }

    private func importLinks() async {
        let list = links
        for (index, link) in list.enumerated() {
            working = "Reading link \(index + 1) of \(list.count)…"
            if let existing = postings.first(where: { JobURL.same($0.sourceURL, link) }) {
                imported.insert(existing.id)
                results.append(Outcome(title: existing.title, failure: "Already saved: using it."))
                continue
            }
            switch await WebTextExtractor.fetch(link) {
            case .success(let page):
                let text = JobPosting.cleanedText(page.text)
                guard text.count >= 200 else {
                    results.append(Outcome(title: link, failure: "Hardly any text came back. Open it with the browser import instead."))
                    continue
                }
                let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let posting = JobPosting(title: String((title.isEmpty ? link : title).prefix(ConversationConfig.jobTitleCap)),
                                         text: text, sourceKind: .link)
                posting.sourceURL = String(link.prefix(2_000))
                insert(posting)
                results.append(Outcome(title: posting.title, failure: nil))
            case .failure(let error):
                results.append(Outcome(title: link, failure: error.localizedDescription))
            }
        }
        linksText = ""
        working = nil
    }

    private func insert(_ posting: JobPosting) {
        modelContext.insert(posting)
        try? modelContext.save()
        imported.insert(posting.id)
    }
}
