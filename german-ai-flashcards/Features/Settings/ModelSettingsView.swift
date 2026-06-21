import SwiftUI

/// The "Model" tab of the Settings screen: pick and load an MLX model, browse by quality/size/
/// parameters, view per-model details, and see on-disk storage usage.
struct ModelSettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @State private var cacheRefreshID = UUID()
    @State private var modelToDelete: MLXModel?
    @State private var modelForInfo: MLXModel?
    @State private var modelRequiringRAMWarning: MLXModel?
    @State private var showModelGuide = false
    @State private var modelListTab: ModelListTab = .recommended

    enum ModelListTab: String, CaseIterable {
        case recommended = "Recommended"
        case size        = "Size"
        case parameters  = "Parameters"
    }

    var body: some View {
        Group {
            Section {
                HStack {
                    Label("This device", systemImage: "memorychip")
                    Spacer()
                    Text("\(deviceRAMGB) GB RAM")
                        .foregroundStyle(.secondary)
                }

                Button {
                    showModelGuide = true
                } label: {
                    Label("Which model should I use?", systemImage: "info.circle")
                }

                Picker("Sort by", selection: $modelListTab) {
                    ForEach(ModelListTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                // Active load progress — shared with Home so both screens animate identically.
                if mlxService.isLoading {
                    ModelLoadingPanel(
                        mlxService: mlxService,
                        showsHeader: true,
                        headerModel: modelManager.selectedMLXModel
                    )
                    .padding(.vertical, 4)
                }

                ForEach(sortedModels) { model in
                    modelRow(model)
                }

                if let error = mlxService.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("MLX Model")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap a model to load it. The one loaded and ready is marked with a green checkmark.")
                    Group {
                        switch modelListTab {
                        case .recommended:
                            Text("Top 3 models for your \(deviceRAMGB) GB device, ranked by German quality. Switch to Size or Parameters to browse all models.")
                        case .size:
                            Text("Sorted smallest to largest download. Tap \(Image(systemName: "info.circle")) for model details. Swipe left on a downloaded model to delete it.")
                        case .parameters:
                            Text("Sorted largest to smallest by parameter count. More parameters generally means higher quality. Swipe left on a downloaded model to delete it.")
                        }
                    }
                }
                .font(.caption2)
            }

            ModelStorageSection(models: MLXModel.allCases, cacheRefreshID: cacheRefreshID)

            FeedbackSection(loadedModelName: mlxService.currentModel?.rawValue)
        }
        .sheet(isPresented: $showModelGuide) {
            ModelGuideSheet()
        }
        .sheet(item: $modelForInfo) { model in
            ModelInfoSheet(model: model) {
                modelToDelete = model
            }
        }
        .sheet(item: $modelRequiringRAMWarning) { model in
            RAMWarningSheet(model: model, deviceRAMGB: deviceRAMGB) {
                loadAndSelect(model)
            }
        }
        .alert(
            "Delete Model?",
            isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    try? mlxService.deleteModel(model)
                    cacheRefreshID = UUID()
                    modelToDelete = nil
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("This will remove the downloaded weights for \(model.rawValue) (~\(formattedSize(model.approximateSizeMB))). You can re-download it later.")
            }
        }
    }

    // MARK: - Model Row

    @ViewBuilder private func modelRow(_ model: MLXModel) -> some View {
        let downloaded = isDownloaded(model)
        let isDownloading = mlxService.isLoading && modelManager.selectedMLXModel == model
        let isLoaded = mlxService.isModelLoaded && mlxService.currentModel == model
        let isRecommended = model == recommendedModel
        let isLastUsed = modelManager.lastLoadedModel == model && !isLoaded && !isDownloading
        HStack(spacing: 0) {
            Button {
                if model.minimumRAMGB > deviceRAMGB {
                    modelRequiringRAMWarning = model
                } else {
                    loadAndSelect(model)
                }
            } label: {
                HStack {
                    // The loading ring (shared with Home) replaces the logo on the row being loaded,
                    // visually tying the row to the progress panel above.
                    if isDownloading {
                        ModelLoadingIndicator(model: model, progress: mlxService.downloadProgress, size: 28)
                    } else {
                        model.logoImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.rawValue)
                                .foregroundStyle(.primary)
                            if isRecommended {
                                tagLabel("Best", color: .accentColor)
                            }
                            if isLastUsed {
                                tagLabel("Last used", color: .secondary)
                            }
                        }
                        HStack(spacing: 6) {
                            if isDownloading {
                                Text(mlxService.downloadInfo ?? "Downloading…")
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                                if let bytes = mlxService.downloadBytesInfo {
                                    Text(bytes)
                                        .foregroundStyle(.secondary)
                                }
                            } else if model.isAppleIntelligence {
                                if mlxService.appleService.isAvailable {
                                    Text("Built-in · no download")
                                    Text("Available")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.green)
                                } else {
                                    Text(mlxService.appleService.unavailableReason ?? "Unavailable")
                                        .foregroundStyle(.orange)
                                }
                            } else {
                                Text("~\(formattedSize(model.approximateSizeMB))")
                                if downloaded {
                                    Text("Downloaded")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Label(model.deviceNote, systemImage: "iphone")
                            .font(.caption2)
                            .foregroundStyle(model.minimumRAMGB <= deviceRAMGB ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .disabled(mlxService.isLoading)

            HStack(spacing: 8) {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else if isLoaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                }
            }
            .padding(.trailing, 8)

            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 0.5)
                .padding(.vertical, 8)

            Button {
                modelForInfo = model
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
                    .frame(width: 52)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
        .swipeActions(edge: .trailing) {
            if downloaded && !mlxService.isLoading {
                Button("Delete", role: .destructive) {
                    modelToDelete = model
                }
            }
        }
    }

    // MARK: - Device Info

    private var deviceRAMGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }

    // MARK: - Model Sorting

    private var sortedModels: [MLXModel] {
        switch modelListTab {
        case .recommended:
            let ram = deviceRAMGB
            let compatible = MLXModel.allCases
                .filter { $0.minimumRAMGB <= ram }
                .sorted { $0.germanQualityScore > $1.germanQualityScore }
            let incompatible = MLXModel.allCases
                .filter { $0.minimumRAMGB > ram }
                .sorted { $0.germanQualityScore > $1.germanQualityScore }
            return Array((compatible + incompatible).prefix(3))
        case .size:
            return MLXModel.allCases.sorted { $0.approximateSizeMB < $1.approximateSizeMB }
        case .parameters:
            return MLXModel.allCases.sorted { $0.parameterCountValue > $1.parameterCountValue }
        }
    }

    /// The single best model for this device — highest German quality among those that fit in RAM
    /// (falling back to the overall best if none fit). Marked with the "Best" tag in any sort order.
    private var recommendedModel: MLXModel? {
        let ram = deviceRAMGB
        let compatible = MLXModel.allCases.filter { $0.minimumRAMGB <= ram }
        let pool = compatible.isEmpty ? MLXModel.allCases : compatible
        return pool.max { $0.germanQualityScore < $1.germanQualityScore }
    }

    // MARK: - Loading

    /// Select a model and immediately load it — the unified tap-to-load action for the model list.
    private func loadAndSelect(_ model: MLXModel) {
        modelManager.selectedMLXModel = model
        Task {
            await mlxService.loadModel(model)
            cacheRefreshID = UUID()
        }
    }

    /// A small capsule tag shown beside a model name (e.g. "Best", "Last used").
    private func tagLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Cache Helpers

    private func isDownloaded(_ model: MLXModel) -> Bool {
        _ = cacheRefreshID
        return model.isDownloaded
    }

    // MARK: - Formatting

    private func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            let gb = Double(mb) / 1000.0
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }
}

// MARK: - Storage

private struct ModelStorageSection: View {
    let models: [MLXModel]
    let cacheRefreshID: UUID

    private let modelColors: [Color] = [.blue, .purple, .orange, .teal, .indigo, .pink]

    private struct ModelEntry: Identifiable {
        let model: MLXModel
        let bytes: Int64
        let colorIndex: Int
        var id: String { model.id }
    }

    private var downloadedModels: [ModelEntry] {
        _ = cacheRefreshID
        var result: [ModelEntry] = []
        var idx = 0
        for model in models {
            if let bytes = model.cachedSizeBytes, bytes > 0 {
                result.append(ModelEntry(model: model, bytes: bytes, colorIndex: idx))
                idx += 1
            }
        }
        return result
    }

    private var deviceStorage: (total: Int64, free: Int64) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = attrs[.systemSize] as? Int64,
              let free = attrs[.systemFreeSize] as? Int64
        else { return (0, 0) }
        return (total, free)
    }

    var body: some View {
        let entries = downloadedModels
        let totalModelBytes = entries.reduce(0) { $0 + $1.bytes }
        let stats = deviceStorage
        let usedOther = max(0, stats.total - stats.free - totalModelBytes)
        let deviceTotal = Double(stats.total)

        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatBytes(totalModelBytes))
                            .font(.subheadline).fontWeight(.semibold)
                        Text("Models (\(entries.count))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatBytes(stats.free))
                            .font(.subheadline).fontWeight(.semibold)
                        Text("Available")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if deviceTotal > 0 {
                    Canvas { context, size in
                        var x: CGFloat = 0

                        if usedOther > 0 {
                            let w = size.width * CGFloat(Double(usedOther) / deviceTotal)
                            context.fill(
                                Path(CGRect(x: x, y: 0, width: w, height: size.height)),
                                with: .color(Color(.systemGray3))
                            )
                            x += w
                        }

                        for entry in entries {
                            let w = size.width * CGFloat(Double(entry.bytes) / deviceTotal)
                            if w > 0 {
                                context.fill(
                                    Path(CGRect(x: x, y: 0, width: w, height: size.height)),
                                    with: .color(modelColors[entry.colorIndex % modelColors.count])
                                )
                                x += w
                            }
                        }
                    }
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                    HStack(spacing: 10) {
                        legendChip(color: Color(.systemGray3), label: "Other")
                        ForEach(entries) { entry in
                            modelLegendChip(entry: entry)
                        }
                        legendChip(color: Color(.systemGray6), label: "Free")
                        Spacer()
                    }
                }

                if entries.isEmpty {
                    Text("No models downloaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Divider()
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                entry.model.logoImage
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                Circle()
                                    .fill(modelColors[entry.colorIndex % modelColors.count])
                                    .frame(width: 7, height: 7)
                                    .offset(x: 2, y: 2)
                            }
                            Text(entry.model.rawValue)
                                .font(.caption)
                            Spacer()
                            Text(formatBytes(entry.bytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label("Storage", systemImage: "internaldrive")
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func modelLegendChip(entry: ModelEntry) -> some View {
        HStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                entry.model.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Circle()
                    .fill(modelColors[entry.colorIndex % modelColors.count])
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: 2)
            }
            Text(entry.model.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - RAM Warning Sheet

private struct RAMWarningSheet: View {
    let model: MLXModel
    let deviceRAMGB: Int
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Limited RAM")
                                .font(.headline)
                            Text("\(model.rawValue) recommends \(model.minimumRAMGB) GB RAM, but this device has \(deviceRAMGB) GB.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("What to expect") {
                    Label("Generation may be significantly slower than normal.", systemImage: "clock")
                    Label("The app could run out of memory and crash during generation.", systemImage: "xmark.octagon")
                    Label("You can always switch to a smaller model if problems occur.", systemImage: "arrow.left.circle")
                }
                .font(.subheadline)

                Section {
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Label("Select \(model.rawValue) Anyway", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)

                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Compatibility Warning")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
