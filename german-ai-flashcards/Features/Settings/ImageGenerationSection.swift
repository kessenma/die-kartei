import SwiftUI

/// The "Image generation" block on the Settings ▸ Model tab: where pictures for stories and
/// flashcards are drawn. On this phone, it downloads, inspects and deletes the Stable Diffusion
/// model; in the cloud, it picks the OpenRouter model and connects the learner's account
/// (`CloudPicturesRows`). Downloaded image models also appear in the Storage section below this
/// one; bumping `cacheRefreshID` after a download or delete keeps that section's totals in sync.
struct ImageGenerationSection: View {
    @Environment(\.appTheme) private var appTheme

    /// Bumped after download/delete so size labels and `isDownloaded` reads refresh.
    @Binding var cacheRefreshID: UUID

    @State private var confirmingDelete = false
    @State private var showingInfo = false
    @State private var showingCloudConsent = false

    /// Shares `PictureSource.current`'s key: every picture feature reads the source from there.
    @AppStorage(PictureSource.defaultsKey) private var source: PictureSource = .onDevice

    /// The service reads `ImageGenQuality.current` off the same key when it starts each picture.
    @AppStorage(ImageGenQuality.defaultsKey) private var quality: ImageGenQuality = .balanced

    /// Shares `ImageGenModel.current`'s UserDefaults key, so picking here switches the model that
    /// Stories and flashcards draw with.
    @AppStorage(ImageGenModel.selectionDefaultsKey) private var selectedModel: ImageGenModel = .bkSdmTiny

    /// Same key and same default as `ImageGenPreview.isEnabled`, which is what the generation
    /// path reads.
    @AppStorage(ImageGenPreview.defaultsKey) private var livePreview = true

    private var imageService: StoryImageService { .shared }
    private var model: ImageGenModel { selectedModel }
    private var deckJob: DeckIllustrationService { .shared }

    /// Deleting the weights out from under a loaded pipeline or a running deck job would strand it.
    private var deleteDisabled: Bool {
        imageService.isPipelineLoaded || deckJob.isRunning
    }

    /// Switching to the cloud the first time goes through the consent sheet; nothing is sent
    /// anywhere until the learner has said yes once.
    private var sourceBinding: Binding<PictureSource> {
        Binding(
            get: { source },
            set: { newValue in
                if newValue == .cloud,
                   !UserDefaults.standard.bool(forKey: CloudPicturesConsentSheet.acceptedDefaultsKey) {
                    showingCloudConsent = true
                } else {
                    source = newValue
                }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Pictures drawn", selection: sourceBinding) {
                ForEach(PictureSource.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            // A run already going keeps the source it started with; this picks the next one.
            .disabled(deckJob.isRunning)

            switch source {
            case .onDevice: onDeviceRows
            case .cloud:    CloudPicturesRows()
            }
        } header: {
            Text("Image generation")
                .themedSectionHeader()
        } footer: {
            Text(footer)
                .font(.caption2)
        }
        .themedListRow()
        .sheet(isPresented: $showingInfo) {
            ImageModelInfoSheet(model: model, onDelete: { confirmingDelete = true })
        }
        .sheet(isPresented: $showingCloudConsent) {
            CloudPicturesConsentSheet { source = .cloud }
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

    private var footer: String {
        let usedBy = "Used by Short Stories when \u{201C}Illustrate this story\u{201D} is on, and by flashcards when AI pictures are on."
        switch source {
        case .onDevice:
            return usedBy + " Pictures are drawn fully on-device."
        case .cloud:
            return usedBy + " Pictures are drawn by \(CloudImageModel.current.displayName) through your OpenRouter account, which pays for them. Card meanings and story scene descriptions are sent; nothing else leaves the phone."
        }
    }

    @ViewBuilder
    private var onDeviceRows: some View {
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
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(7)))
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
            livePreviewToggle
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

    /// Shown on every device rather than hidden where it can't run, so the reason is visible
    /// instead of the row just not being there.
    private var livePreviewToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Watch pictures being drawn", isOn: $livePreview)
                .disabled(!ImageGenPreview.isAvailable)
            Text(ImageGenPreview.isAvailable
                 ? "The generating screen shows the real picture appearing instead of a stand-in animation. Costs a few seconds a picture."
                 : "Needs more memory than this \(ThisDevice.name) has to spare while drawing. The generating screen shows an animation instead.")
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
