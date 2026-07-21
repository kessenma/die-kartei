import SwiftUI

/// The "Image generation" block on the Settings ▸ Model tab: download, inspect, and delete the
/// Stable Diffusion model that draws story illustrations and flashcard pictures. Downloaded image
/// models also appear in the Storage section below this one; bumping `cacheRefreshID` after a
/// download or delete is what keeps that section's bar and totals in sync.
struct ImageGenerationSection: View {
    /// Bumped after download/delete so size labels and `isDownloaded` reads refresh.
    @Binding var cacheRefreshID: UUID

    @State private var confirmingDelete = false
    @State private var showingInfo = false

    /// The service reads `ImageGenQuality.current` off the same key when it starts each picture.
    @AppStorage(ImageGenQuality.defaultsKey) private var quality: ImageGenQuality = .balanced

    /// Shares `ImageGenModel.current`'s UserDefaults key, so picking here switches the model that
    /// Stories and flashcards draw with.
    @AppStorage(ImageGenModel.selectionDefaultsKey) private var selectedModel: ImageGenModel = .bkSdmTiny

    private var imageService: StoryImageService { .shared }
    private var model: ImageGenModel { selectedModel }
    private var deckJob: DeckIllustrationService { .shared }

    /// Deleting the weights out from under a loaded pipeline or a running deck job would strand it.
    private var deleteDisabled: Bool {
        imageService.isPipelineLoaded || deckJob.isRunning
    }

    var body: some View {
        Section {
            Picker("Image model", selection: $selectedModel) {
                ForEach(ImageGenModel.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .onChange(of: selectedModel) { _, _ in
                // The loaded pipeline belongs to the previous model; drop it so the next
                // generation reloads the newly selected one.
                imageService.unloadPipeline()
                cacheRefreshID = UUID()
            }

            HStack(spacing: 12) {
                model.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .fontWeight(.medium)
                    Text("Draws pictures for your stories and flashcards, on-device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                trailingStatus
            }
            .padding(.vertical, 2)

            if model.isDownloaded {
                qualityPicker
            }

            if imageService.isDownloading {
                downloadingRow
            } else if !model.isDownloaded {
                Button {
                    Task {
                        await imageService.downloadModel()
                        cacheRefreshID = UUID()
                    }
                } label: {
                    Label("Download (\(model.downloadSizeLabel))", systemImage: "arrow.down.circle.fill")
                }
            } else {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete Download", systemImage: "trash")
                }
                .disabled(deleteDisabled)
            }

            if let error = imageService.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Image generation")
        } footer: {
            Text("Used by Short Stories when \u{201C}Illustrate this story\u{201D} is on, and by flashcards when AI pictures are on. Pictures are drawn fully on-device.")
                .font(.caption2)
        }
        .sheet(isPresented: $showingInfo) {
            ImageModelInfoSheet(model: model, onDelete: { confirmingDelete = true })
        }
        .alert("Delete Image Model?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? imageService.deleteModel()
                cacheRefreshID = UUID()
            }
        } message: {
            Text("This removes the downloaded \(model.displayName) weights. Pictures in existing stories are kept; you can re-download the model anytime.")
        }
    }

    /// Steps per picture. Resolution is fixed by the compiled model, so this is the whole
    /// speed/quality trade — it applies to stories and flashcards alike.
    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Picture quality")
                .font(.subheadline)
            Picker("Picture quality", selection: $quality) {
                ForEach(ImageGenQuality.allCases) { tier in
                    Text(tier.label).tag(tier)
                }
            }
            .pickerStyle(.segmented)
            Text(quality.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        // Reads cacheRefreshID so a download/delete re-evaluates isDownloaded and the size.
        let _ = cacheRefreshID
        if model.isDownloaded {
            HStack(spacing: 6) {
                if let bytes = model.cachedSizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else if !imageService.isDownloading {
            Text(model.downloadSizeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var downloadingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = imageService.downloadProgress {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
            if let info = imageService.downloadBytesInfo ?? imageService.downloadInfo {
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") {
                imageService.cancelDownload()
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}
