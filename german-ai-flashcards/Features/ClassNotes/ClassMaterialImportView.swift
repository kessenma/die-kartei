//
//  ClassMaterialImportView.swift
//  german-ai-flashcards
//
//  Bringing a class handout over. Three doors: a PDF from Files (a scanned one is read page by
//  page with the on-device recognizer, since teachers photocopy), a photo of a page (camera or
//  library), or pasted text. Everything passes through a short review step for the title, then
//  is filed under the entry it was opened from.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct ClassMaterialImportView: View {
    let course: ClassCourse
    let entry: ClassEntry
    var onImported: (ClassMaterial) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var showFileImporter = false
    @State private var showPaste = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var pending: PendingMaterial?
    @State private var errorMessage: String?
    @State private var progressText: String?
    @State private var ocr = PhotoOCRService()

    private var isWorking: Bool { progressText != nil }
    private let accent = ClassNotesTile.tint

    var body: some View {
        NavigationStack {
            List {
                targetSection.themedListRow()
                sourcesSection.themedListRow()
                if let progressText {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(progressText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
            .navigationTitle("Add a handout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
            }
            .navigationDestination(item: $pending) { item in
                ClassMaterialReviewView(draft: item, accent: accent) { reviewed in
                    save(reviewed)
                }
            }
            .navigationDestination(isPresented: $showPaste) {
                ClassMaterialPasteView(accent: accent) { draft in
                    showPaste = false
                    pending = draft
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
    }

    // MARK: - Sections

    private var targetSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: course.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name).font(.body)
                    Text("Filed under \(entry.displayTitle) · \(entry.dateLine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sourcesSection: some View {
        Section {
            Button {
                errorMessage = nil
                showFileImporter = true
            } label: {
                ActivityRow("PDF file", "From Files, Mail, or the course portal. Scans are read on-device.", "doc.richtext")
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
                ActivityRow("Take a photo", "Photograph the page now", "camera.fill")
            }
            .buttonStyle(.plain)

            Button {
                errorMessage = nil
                showPaste = true
            } label: {
                ActivityRow("Paste text", "Copied from anywhere", "doc.on.clipboard")
            }
            .buttonStyle(.plain)
        } header: {
            Text("Where is it?").themedSectionHeader()
        } footer: {
            Text("Photos and scans are read with Apple's on-device recognizer; check the text on the next screen before attaching it.")
                .font(.caption2)
        }
        .disabled(isWorking)
    }

    // MARK: - Sources

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
            guard let data else {
                errorMessage = "Couldn't read that PDF."
                return
            }
            guard let extracted = PDFTextExtractor.extract(from: url) else {
                errorMessage = "Couldn't read that PDF."
                return
            }
            if extracted.looksScanned {
                readScannedPDF(data: data, title: title)
            } else {
                pending = PendingMaterial(
                    title: title,
                    text: JobPosting.cleanedText(extracted.text),
                    sourceKind: .pdf,
                    snapshot: data,
                    ext: "pdf"
                )
            }
        }
    }

    /// No text layer: render the pages and run the recognizer over each.
    private func readScannedPDF(data: Data, title: String) {
        progressText = "Reading the scan…"
        Task {
            let text = await ScannedPDFReader.extract(data: data, ocr: ocr) { page, total in
                progressText = "Reading page \(page) of \(total)…"
            }
            progressText = nil
            if let text {
                pending = PendingMaterial(
                    title: title,
                    text: JobPosting.cleanedText(text),
                    sourceKind: .pdf,
                    snapshot: data,
                    ext: "pdf"
                )
            } else {
                errorMessage = "No readable text found in that PDF."
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
            pending = PendingMaterial(
                title: "Photo · \(Date.now.formatted(date: .abbreviated, time: .omitted))",
                text: JobPosting.cleanedText(text),
                sourceKind: .photo,
                snapshot: jpeg,
                ext: "jpg"
            )
        }
    }

    // MARK: - Save

    private func save(_ draft: PendingMaterial) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let material = ClassMaterial(
            title: title.isEmpty ? "Handout" : String(title.prefix(90)),
            text: draft.text,
            sourceKind: draft.sourceKind
        )
        if let data = draft.snapshot {
            material.snapshotFile = ClassMaterialStore.save(data, ext: draft.ext)
        }
        modelContext.insert(material)
        material.entry = entry
        entry.updatedAt = .now
        course.updatedAt = .now
        try? modelContext.save()
        dismiss()
        onImported(material)
    }
}

// MARK: - Drafts

/// A handout on its way in, before it becomes a `ClassMaterial`.
struct PendingMaterial: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var text: String
    var sourceKind: ClassMaterial.SourceKind
    /// The original to keep: the PDF's bytes, or the photo as a JPEG.
    var snapshot: Data? = nil
    var ext: String = "pdf"

    static func == (lhs: PendingMaterial, rhs: PendingMaterial) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Review

/// The title and the text to check before a handout is attached.
struct ClassMaterialReviewView: View {
    @State var draft: PendingMaterial
    let accent: Color
    let onConfirm: (PendingMaterial) -> Void

    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title)
                    .focused($titleFocused)
            } header: {
                Text("Title").themedSectionHeader()
            } footer: {
                Text("How the handout is listed: \"Arbeitsblatt Dativ\", \"Kapitel 4 Wortliste\".")
                    .font(.caption2)
            }
            .themedListRow()

            Section {
                Text(draft.text)
                    .font(.callout)
                    .lineLimit(14)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("Text").themedSectionHeader()
                    Spacer()
                    Text("\(draft.text.split { $0 == " " || $0 == "\n" }.count) Wörter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            } footer: {
                if draft.sourceKind != .paste {
                    Text("Read on-device from the \(draft.sourceKind == .pdf ? "file" : "photo"). The original is kept with it.")
                        .font(.caption2)
                }
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Check the handout")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onConfirm(draft)
            } label: {
                Text("Attach to this class")
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
                Button("Done") { titleFocused = false }
            }
        }
    }
}

// MARK: - Paste

/// A handout typed or pasted in. Hands a draft to the review step for the title.
struct ClassMaterialPasteView: View {
    let accent: Color
    let onNext: (PendingMaterial) -> Void

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
                Text("Handout text").themedSectionHeader()
            } footer: {
                Text("Paste the whole thing. German is what the reader is for; English parts are fine to leave in.")
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
                onNext(PendingMaterial(
                    title: firstLine(of: trimmed),
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
            .disabled(trimmed.count < 20)
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

    /// The first short line usually names the handout; anything longer is left for the learner.
    private func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count <= 60 ? line : ""
    }
}

// MARK: - Preview

#Preview("Handout import · 4 themes") {
    let course = ClassCourse(name: "Deutsch A2 an der Uni")
    let entry = ClassEntry(date: .now)
    return ForEach(AppTheme.allCases) { theme in
        ClassMaterialImportView(course: course, entry: entry) { _ in }
            .environment(\.appTheme, theme)
            .modelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self], inMemory: true)
    }
}
