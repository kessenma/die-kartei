import DieKarteiCore
import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Lists photo scans and lets the user import a new photo (camera or library) to study.
/// Beta feature — Apple's Vision recognizer extracts the text, then an MLX model
/// tidies it up and generates the study materials.
struct PhotoScanListView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \StudyPaper.createdAt, order: .reverse) private var allPapers: [StudyPaper]
    @Environment(\.modelContext) private var modelContext

    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var importError: String?
    @State private var isImporting = false
    @State private var cacheRefreshID = UUID()

    @State private var ocrService: PhotoOCRService?
    @State private var studyService: PaperStudyService?
    @State private var generatingPaper: StudyPaper?
    @State private var scanReview: ScanReview?

    private var photoScans: [StudyPaper] {
        allPapers.filter { $0.sourceURL?.hasPrefix("photo://") == true }
    }

    var body: some View {
        List {
            betaBannerSection
            importSection

            ChatModelPickerSection(
                selected: $modelManager.selectedPaperModel,
                cacheRefreshID: cacheRefreshID,
                title: "Study model",
                footerText: "Used to tidy up the scanned text and to generate the summary, deck, and questions. Any downloaded model works."
            )

            if let importError {
                Section {
                    Label(importError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            if photoScans.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No scans yet",
                        systemImage: "camera.viewfinder",
                        description: Text("Take a photo or import one from your library to extract German vocabulary.")
                    )
                }
            } else {
                Section("Your photo scans") {
                    ForEach(photoScans) { paper in
                        NavigationLink {
                            PaperDetailView(paper: paper, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            row(paper)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(paper) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Scan German Text")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            importError = nil
            isImporting = true
            Task {
                await handlePhotoPickerItem(item)
                photoPickerItem = nil
            }
        }
        .sheet(isPresented: $showCamera) {
            #if canImport(UIKit)
            CameraPickerView { uiImage in
                showCamera = false
                importError = nil
                isImporting = true
                Task {
                    await handleUIImage(uiImage)
                }
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
            #endif
        }
        .sheet(item: $scanReview) { review in
            ExtractedTextReviewView(title: "Scanned text", text: review.text) { deckCount, selectedWords in
                // Defer so the review sheet finishes dismissing before the generating sheet appears.
                DispatchQueue.main.async {
                    Task {
                        await cleanupAndGenerate(rawText: review.text, deckCount: deckCount, selectedWords: selectedWords)
                    }
                }
            }
        }
        .sheet(item: $generatingPaper) { paper in
            if let ocrService, let studyService {
                PhotoScanGeneratingView(
                    ocrService: ocrService,
                    studyService: studyService,
                    paper: paper
                ) {
                    generatingPaper = nil
                }
            }
        }
    }

    // MARK: - Sections

    private var betaBannerSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Beta Feature")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Text is read with Apple's on-device scanner, then the AI tidies it up and builds the study materials. The AI step is experimental and may make mistakes — check the extracted text before studying.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var importSection: some View {
        Section {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Label(
                    isImporting ? "Importing…" : "Choose from library",
                    systemImage: "photo.on.rectangle"
                )
                .font(.body.weight(.medium))
            }
            .disabled(isImporting)

            Button {
                showCamera = true
            } label: {
                Label("Take a photo", systemImage: "camera.fill")
                    .font(.body.weight(.medium))
            }
            .disabled(isImporting)
        } footer: {
            Text("Photograph German text — a textbook page, vocab list, menu, sign, or worksheet. The text is extracted on-device, cleaned up by the AI, and turned into a summary, vocabulary deck, and questions you can study and discuss.")
                .font(.caption2)
        }
    }

    // MARK: - Row

    private func row(_ paper: StudyPaper) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12))
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

    // MARK: - Import handlers

    private func handlePhotoPickerItem(_ item: PhotosPickerItem) async {
        defer { isImporting = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importError = "Could not load the selected photo."
                return
            }
            await runOCR(imageData: data)
        } catch {
            importError = "Photo import failed: \(error.localizedDescription)"
        }
    }

    #if canImport(UIKit)
    private func handleUIImage(_ uiImage: UIImage) async {
        defer { isImporting = false }
        guard let data = uiImage.jpegData(compressionQuality: 0.9) else {
            importError = "Could not process the captured photo."
            return
        }
        await runOCR(imageData: data)
    }
    #endif

    /// OCR is fast (Apple Vision) — run it up front, then show the review step.
    /// A failed scan leaves nothing behind.
    private func runOCR(imageData: Data) async {
        let ocr = PhotoOCRService()
        ocrService = ocr

        let result = await ocr.extractText(from: imageData)
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let rawText):
            scanReview = ScanReview(text: rawText)
        }
    }

    /// After the user confirms the review: clean up the OCR text with the AI,
    /// then generate the summary, deck, and questions.
    private func cleanupAndGenerate(rawText: String, deckCount: Int, selectedWords: [String]?) async {
        guard let ocr = ocrService else { return }

        let dateStr = Date.now.formatted(date: .abbreviated, time: .omitted)
        let paper = StudyPaper(title: "Scan — \(dateStr)", fullText: rawText, sourceURL: "photo://\(UUID())")
        modelContext.insert(paper)
        try? modelContext.save()

        let svc = PaperStudyService(mlxService: mlxService, modelContext: modelContext)
        studyService = svc
        generatingPaper = paper

        let model = modelManager.selectedPaperModel
        let cleaned = await ocr.cleanupText(rawText, mlxService: mlxService, model: model)
        paper.fullText = cleaned
        try? modelContext.save()

        await svc.generate(for: paper, model: model, deckCount: deckCount, questionCount: 6, selectedWords: selectedWords)
    }

    private func delete(_ paper: StudyPaper) {
        modelContext.delete(paper)
        try? modelContext.save()
    }
}

/// OCR result awaiting user review before cleanup + generation.
private struct ScanReview: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Generating sheet

/// Progress sheet covering both the OCR phase (PhotoOCRService) and the
/// study material generation phase (PaperStudyService).
private struct PhotoScanGeneratingView: View {
    let ocrService: PhotoOCRService
    let studyService: PaperStudyService
    let paper: StudyPaper
    let onClose: () -> Void

    private var isRunning: Bool { ocrService.isRunning || studyService.isRunning }

    private var displayPhase: String {
        if ocrService.isRunning { return ocrService.statusText }
        return studyService.statusText
    }

    private var displayProgress: Double {
        if ocrService.isRunning { return ocrService.progress * 0.45 }
        return 0.45 + studyService.progress * 0.55
    }

    private var isFailed: Bool {
        if case .failed = ocrService.phase { return true }
        if case .failed = studyService.phase { return true }
        return false
    }

    private var failureMessage: String? {
        if case .failed(let msg) = ocrService.phase { return msg }
        if case .failed(let msg) = studyService.phase { return msg }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(failureMessage ?? "Something went wrong.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                } else if !isRunning {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle).foregroundStyle(.green)
                    Text("\"\(paper.title)\" is ready to study.")
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView(value: displayProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                    Text(displayPhase).foregroundStyle(.secondary)
                    if ocrService.phase == .cleaning, let model = ocrService.model, !model.isDownloaded {
                        Text("First-time use downloads \(model.rawValue).")
                            .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Scanning photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRunning ? "Hide" : "Done") { onClose() }
                }
            }
            .interactiveDismissDisabled(isRunning)
        }
    }
}

// MARK: - Camera picker

#if canImport(UIKit)
private struct CameraPickerView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
#endif
