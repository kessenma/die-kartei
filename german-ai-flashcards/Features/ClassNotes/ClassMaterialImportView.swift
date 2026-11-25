//
//  ClassMaterialImportView.swift
//  german-ai-flashcards
//
//  Bringing a class handout over. Three doors from outside: a PDF from Files (a scanned one is read
//  page by page with the on-device recognizer, since teachers photocopy), a photo of a page (camera
//  or library), or pasted text, each through a short review step for the title. A fourth brings a
//  text the app already has (`ClassMaterialLibraryPicker`). Either way it is filed under the entry
//  the sheet was opened from. A PDF with exercises in it can go straight on to picking the homework
//  (`WorksheetSetupView`).
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct ClassMaterialImportView: View {
    let course: ClassCourse
    let entry: ClassEntry
    /// A PDF handed to the app from outside ("Open in Die Kartei"), read as soon as the sheet opens.
    var incoming: IncomingHandoutPDF? = nil
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
    /// A PDF just attached whose exercises the learner chose to set up as homework now.
    @State private var settingUp: ClassMaterial?
    /// Its pages as the import already parsed them, so the setup doesn't read the PDF again.
    @State private var settingUpPages: [WorksheetExercise]?
    /// The card shown while a PDF is read: which file, which step, how far.
    @State private var reading: HandoutReadingProgress?

    private var isWorking: Bool { progressText != nil || reading != nil }
    private let accent = ClassNotesTile.tint

    var body: some View {
        NavigationStack {
            List {
                targetSection.themedListRow()
                sourcesSection.themedListRow()
                fromAppSection.themedListRow()
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
            .navigationDestination(item: $settingUp) { material in
                WorksheetSetupView(material: material, onDone: { _ in
                    dismiss()
                    onImported(material)
                }, showsLater: true, prefetched: settingUpPages)
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
            .overlay {
                if let reading {
                    HandoutReadingCard(progress: reading, accent: accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: reading == nil)
            .task {
                guard let incoming, pending == nil, progressText == nil, reading == nil else { return }
                readPDF(incoming.data, title: incoming.title)
            }
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

    private var fromAppSection: some View {
        Section {
            NavigationLink {
                ClassMaterialLibraryPicker(course: course, entry: entry) { material in
                    dismiss()
                    onImported(material)
                }
            } label: {
                ActivityRow("From the app", "A short story, a paper or scan, or a vocab sheet you made cards from", "tray.full")
            }
        } header: {
            Text("Schon in der App · Already here").themedSectionHeader()
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
            readPDF(data, title: title)
        }
    }

    private func readPDF(_ data: Data, title: String) {
        errorMessage = nil
        // The bytes are already in hand; everything after this runs off the main actor, page by
        // page, reporting to the card: a 38-slide lesson is a few seconds, and a spinner with no
        // end in sight reads as a hang.
        let progress = HandoutReadingProgress(fileName: title)
        reading = progress
        Task {
            let extracted = await Task.detached(priority: .userInitiated) {
                PDFTextExtractor.extract(from: data, rebuildingTables: true) { done, total in
                    Task { @MainActor in progress.update(.text, done: done, of: total) }
                }
            }.value
            guard let extracted else {
                reading = nil
                errorMessage = "Couldn't read that PDF."
                return
            }
            if extracted.looksScanned {
                reading = nil
                readScannedPDF(data: data, title: title)
                return
            }
            // The exercise pages, found now so the review can offer to set them up and the setup
            // doesn't read the file a second time.
            let pages = await Task.detached(priority: .userInitiated) {
                WorksheetPDFReader.parse(data: data) { done, total in
                    Task { @MainActor in progress.update(.exercises, done: done, of: total) }
                } ?? []
            }.value
            let exercises = pages.filter(\.isExercise).count
            reading = nil
            pending = PendingMaterial(
                title: title,
                text: JobPosting.cleanedText(extracted.text),
                sourceKind: .pdf,
                snapshot: data,
                ext: "pdf",
                exerciseCount: exercises,
                setUpExercises: exercises > 0,
                pages: pages
            )
        }
    }

    /// No text layer: render the pages and run the recognizer over each.
    private func readScannedPDF(data: Data, title: String) {
        let progress = HandoutReadingProgress(fileName: title)
        progress.update(.scan, done: 0, of: 0)
        reading = progress
        Task {
            let text = await ScannedPDFReader.extract(data: data, ocr: ocr) { page, total in
                progress.update(.scan, done: page, of: total)
            }
            reading = nil
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
        if draft.setUpExercises, material.hasSnapshot {
            // Replace the review with the setup rather than stacking on it: going back must not
            // offer "Attach" a second time.
            pending = nil
            settingUpPages = draft.pages.isEmpty ? nil : draft.pages
            settingUp = material
            return
        }
        dismiss()
        onImported(material)
    }
}

// MARK: - Reading progress

/// How far reading a PDF has got, for `HandoutReadingCard`. Main-actor, so the background readers
/// report to it through a hop.
@MainActor
@Observable
final class HandoutReadingProgress {
    enum Step {
        /// The text layer, page by page.
        case text
        /// The exercise pages, page by page.
        case exercises
        /// A scan with no text layer, read with the recognizer.
        case scan
    }

    let fileName: String
    private(set) var step: Step = .text
    private(set) var done = 0
    private(set) var total = 0

    init(fileName: String) {
        self.fileName = fileName
    }

    func update(_ step: Step, done: Int, of total: Int) {
        self.step = step
        self.done = done
        self.total = total
    }

    /// Across both steps of a text PDF: the text is the first half, the exercises the second.
    var fraction: Double? {
        guard total > 0 else { return nil }
        let share = Double(done) / Double(total)
        switch step {
        case .text: return share * 0.5
        case .exercises: return 0.5 + share * 0.5
        case .scan: return share
        }
    }

    var label: String {
        switch step {
        case .text: total > 0 ? "Reading the text · page \(done) of \(total)" : "Opening the PDF…"
        case .exercises: "Finding the exercises · page \(done) of \(total)"
        case .scan: total > 0 ? "Reading the scan · page \(done) of \(total)" : "Reading the scan…"
        }
    }
}

/// The card over the import screen while a PDF is read.
struct HandoutReadingCard: View {
    let progress: HandoutReadingProgress
    let accent: Color

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: progress.step == .scan ? "doc.viewfinder" : "doc.richtext")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .symbolEffect(.pulse, options: .repeating)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progress.fileName)
                            .font(.headline)
                            .lineLimit(2)
                        Text(progress.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                    }
                }
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .tint(accent)
                        .animation(.linear(duration: 0.15), value: fraction)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                Text("Everything is read on this device. A long lesson takes a few seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16), style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
            .padding(32)
            .accessibilityElement(children: .combine)
        }
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
    /// Exercise pages the worksheet parser found in a PDF.
    var exerciseCount = 0
    /// Go on to picking the homework after attaching.
    var setUpExercises = false
    /// Every page as the worksheet parser read it, handed on to the setup.
    var pages: [WorksheetExercise] = []

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

            if draft.exerciseCount > 0 {
                Section {
                    Toggle(isOn: $draft.setUpExercises) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set them up as homework next")
                            Text("Pick the ones you didn't finish in class, then answer them here or write on the slides.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(accent)
                } header: {
                    Text("Übungen · \(draft.exerciseCount) found").themedSectionHeader()
                }
                .themedListRow()
            }

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
            .inMemoryModelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self])
    }
}
