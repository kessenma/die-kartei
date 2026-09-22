//
//  DocumentDeckImportView.swift
//  german-ai-flashcards
//
//  Flashcards from a document rather than a topic: a teacher's vocabulary sheet, a handout, a
//  story, any PDF, photo, or pasted text. The document comes in through the same doors as a class
//  handout (plus the documents already in the app), then `DocumentDeckBuilderView` turns it into
//  rows: a two-column list is paired automatically, and anything else is picked from the text by
//  highlighting. Reached from the flashcard screens, a course page, and a handout.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The text a deck is built from, with where it came from.
struct DocumentDeckDraft: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var text: String
    /// "PDF", "Photo", "Handout", "Paper"; the deck's fallback name and the review footer.
    var sourceLabel: String

    static func == (lhs: DocumentDeckDraft, rhs: DocumentDeckDraft) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DocumentDeckImportView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Preselected course the deck should belong to.
    var course: ClassCourse? = nil
    /// A document already in hand (a handout, a paper): skips the source list.
    var prefilled: DocumentDeckDraft? = nil
    var onCreated: (SavedDeck) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \ClassMaterial.createdAt, order: .reverse) private var materials: [ClassMaterial]
    @Query(sort: \StudyPaper.createdAt, order: .reverse) private var papers: [StudyPaper]

    @State private var showFileImporter = false
    @State private var showPaste = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var draft: DocumentDeckDraft?
    @State private var errorMessage: String?
    @State private var progressText: String?
    @State private var ocr = PhotoOCRService()

    private var isWorking: Bool { progressText != nil }
    private let accent = ClassNotesTile.tint

    var body: some View {
        NavigationStack {
            Group {
                if let prefilled {
                    builder(prefilled, isRoot: true)
                } else {
                    sourcesList
                }
            }
            .navigationDestination(item: $draft) { item in
                builder(item, isRoot: false)
            }
            .navigationDestination(isPresented: $showPaste) {
                DocumentTextPasteView(accent: accent) { pasted in
                    showPaste = false
                    draft = pasted
                }
            }
        }
    }

    private func builder(_ draft: DocumentDeckDraft, isRoot: Bool) -> some View {
        DocumentDeckBuilderView(
            draft: draft,
            modelManager: modelManager,
            mlxService: mlxService,
            course: course,
            isRoot: isRoot
        ) { deck in
            dismiss()
            onCreated(deck)
        }
    }

    // MARK: - Sources

    private var sourcesList: some View {
        List {
            bringInSection.themedListRow()
            if !materials.isEmpty || !papers.isEmpty {
                yourDocumentsSection.themedListRow()
            }
            if let progressText {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(progressText).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .themedListRow()
            }
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
        .navigationTitle("From a document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isWorking)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf]) { result in
            handleFile(result)
        }
        .sheet(isPresented: $showCamera) {
            #if canImport(UIKit)
            CameraPickerView { image in
                showCamera = false
                Task { await handleImage(image) }
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
            #endif
        }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                await handlePhotoPickerItem(item)
                photoPickerItem = nil
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var bringInSection: some View {
        Section {
            Button {
                errorMessage = nil
                showFileImporter = true
            } label: {
                ActivityRow("PDF file", "A vocab sheet, a handout, a story. Scans are read on-device.", "doc.richtext")
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                ActivityRow("Photo from your library", "A page you already photographed", "photo.on.rectangle")
            }
            .buttonStyle(.plain)

            Button {
                errorMessage = nil
                showCamera = true
            } label: {
                ActivityRow("Take a photo", "Photograph a word list or a page", "camera.fill")
            }
            .buttonStyle(.plain)

            Button {
                errorMessage = nil
                showPaste = true
            } label: {
                ActivityRow("Paste text", "A list or a text copied from anywhere", "doc.on.clipboard")
            }
            .buttonStyle(.plain)
        } header: {
            Text("Bring one in").themedSectionHeader()
        } footer: {
            Text("A two-column word list (German · English) is paired for you. Anything else you pick from by highlighting; the tutor translates what you picked.")
                .font(.caption2)
        }
        .disabled(isWorking)
    }

    private var yourDocumentsSection: some View {
        Section {
            ForEach(materials.prefix(8)) { material in
                Button {
                    draft = DocumentDeckDraft(title: material.title, text: material.text, sourceLabel: "Handout")
                } label: {
                    documentRow(material.title, material.entry?.course?.name ?? "Deutschkurs", material.sourceKind.systemImage)
                }
                .buttonStyle(.plain)
            }
            ForEach(papers.prefix(8)) { paper in
                Button {
                    draft = DocumentDeckDraft(title: paper.title, text: paper.fullText, sourceLabel: "Paper")
                } label: {
                    documentRow(paper.title, "Papers & scans", paper.sourceSymbol)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Your documents").themedSectionHeader()
        }
        .disabled(isWorking)
    }

    private func documentRow(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Handlers

    private func handleFile(_ result: Result<URL, Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = "Couldn't open the file: \(error.localizedDescription)"
        case .success(let url):
            let title = url.deletingPathExtension().lastPathComponent
            let needsAccess = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if needsAccess { url.stopAccessingSecurityScopedResource() }
            guard let data, let extracted = PDFTextExtractor.extract(from: url) else {
                errorMessage = "Couldn't read that PDF."
                return
            }
            if extracted.looksScanned {
                progressText = "Reading the scan…"
                Task {
                    let text = await ScannedPDFReader.extract(data: data, ocr: ocr) { page, total in
                        progressText = "Reading page \(page) of \(total)…"
                    }
                    progressText = nil
                    if let text {
                        draft = DocumentDeckDraft(title: title, text: text, sourceLabel: "PDF")
                    } else {
                        errorMessage = "No readable text found in that PDF."
                    }
                }
            } else {
                // Page markers stay: the parser drops them per line, and the text picker reads past them.
                draft = DocumentDeckDraft(title: title, text: extracted.text, sourceLabel: "PDF")
            }
        }
    }

    private func handlePhotoPickerItem(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't load the selected photo."
                return
            }
            await handleImage(image)
        } catch {
            errorMessage = "Photo import failed: \(error.localizedDescription)"
        }
    }

    private func handleImage(_ image: UIImage) async {
        errorMessage = nil
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            errorMessage = "Couldn't process the photo."
            return
        }
        progressText = "Reading the photo…"
        let result = await ocr.extractText(from: jpeg)
        progressText = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let text):
            draft = DocumentDeckDraft(
                title: "Photo · \(Date.now.formatted(date: .abbreviated, time: .omitted))",
                text: text,
                sourceLabel: "Photo"
            )
        }
    }
}

// MARK: - Paste

/// A list or a text pasted in, straight to the builder.
struct DocumentTextPasteView: View {
    let accent: Color
    let onNext: (DocumentDeckDraft) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Text or word list").themedSectionHeader()
            } footer: {
                Text("A list with one word per line (der Tisch – table) is paired for you. A text is picked from by highlighting.")
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
                let line = trimmed.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                onNext(DocumentDeckDraft(
                    title: line.count <= 60 ? line : "",
                    text: trimmed,
                    sourceLabel: "Pasted text"
                ))
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            .disabled(trimmed.count < 3)
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
}

// MARK: - Preview

#Preview("Document deck import · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        DocumentDeckImportView(modelManager: MLXModelManager(), mlxService: MLXGenerationService()) { _ in }
            .environment(ActivityRouter())
            .environment(\.appTheme, theme)
            .modelContainer(
                for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, StudyPaper.self, SavedDeck.self, SavedCard.self],
                inMemory: true
            )
    }
}
