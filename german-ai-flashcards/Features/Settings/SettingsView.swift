import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.openURL) private var openURL

    @State private var cacheRefreshID = UUID()
    @State private var modelToDelete: MLXModel?
    @State private var modelForInfo: MLXModel?
    @State private var modelRequiringRAMWarning: MLXModel?
    @State private var germanVoices: [AVSpeechSynthesisVoice] = []
    @State private var showVoiceGuide = false
    @State private var showModelGuide = false
    @State private var selectedTab: SettingsTab = .cards
    @State private var modelListTab: ModelListTab = .recommended

    enum SettingsTab: String, CaseIterable {
        case cards = "Card Settings"
        case model = "Model Settings"
    }

    enum ModelListTab: String, CaseIterable {
        case recommended = "Recommended"
        case size        = "Size"
        case parameters  = "Parameters"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Settings", selection: $selectedTab) {
                        ForEach(SettingsTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if selectedTab == .cards { cardSettingsContent }
                if selectedTab == .model { modelSettingsContent }
            }
            .navigationTitle("Settings")
            .contentMargins(.bottom, 120)
            .onAppear {
                germanVoices = AVSpeechSynthesisVoice.speechVoices()
                    .filter { $0.language.hasPrefix("de") }
                    .sorted { lhs, rhs in
                        // Natural (Premium/Enhanced) voices first, then by name.
                        if lhs.quality != rhs.quality {
                            return lhs.quality.rawValue > rhs.quality.rawValue
                        }
                        return lhs.name < rhs.name
                    }
            }
            .onChange(of: mlxService.currentModel) { _, newModel in
                if let model = newModel {
                    modelManager.lastLoadedModel = model
                }
            }
            .sheet(isPresented: $showModelGuide) {
                ModelGuideSheet()
            }
            .sheet(isPresented: $showVoiceGuide) {
                VoiceGuideSheet()
            }
            .sheet(item: $modelForInfo) { model in
                ModelInfoSheet(model: model) {
                    modelToDelete = model
                }
            }
            .sheet(item: $modelRequiringRAMWarning) { model in
                RAMWarningSheet(model: model, deviceRAMGB: deviceRAMGB) {
                    modelManager.selectedMLXModel = model
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
    }

    // MARK: - Card Settings

    @ViewBuilder private var cardSettingsContent: some View {
        Section("Flashcard Style") {
            Picker("Style", selection: $modelManager.flashcardStyle) {
                ForEach(FlashcardStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text(modelManager.flashcardStyle.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Auto-advance", isOn: $modelManager.autoAdvance)
            Text("Moves to the next card automatically after selecting a rating — no need to tap Next.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Pronunciation") {
            Picker("German Voice", selection: Binding(
                get: { modelManager.selectedVoiceIdentifier ?? "" },
                set: { modelManager.selectedVoiceIdentifier = $0.isEmpty ? nil : $0 }
            )) {
                Text("System Default").tag("")
                ForEach(germanVoices, id: \.identifier) { voice in
                    Text(voiceName(voice)).tag(voice.identifier)
                }
            }

            Button {
                SpeechService.shared.speak("Guten Tag! Wie geht es Ihnen?")
            } label: {
                Label("Preview Voice", systemImage: "speaker.wave.2")
            }

            // Shows which natural German voices the user has downloaded. Compact
            // voices ship with iOS; an Enhanced or Premium voice only exists
            // because the user downloaded it, so quality is a reliable
            // "did I download this myself?" signal.
            if downloadedGermanVoices.isEmpty {
                Label {
                    Text("No natural German voices downloaded yet — every option above is a basic (robotic) voice. Tap below to add an Enhanced or Premium one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("You downloaded these", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    ForEach(downloadedGermanVoices, id: \.identifier) { voice in
                        Text("•  \(voiceName(voice))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                showVoiceGuide = true
            } label: {
                Label("How to download natural German voices", systemImage: "info.circle")
            }
        }

        Section("About") {
            NavigationLink(destination: SourcesView()) {
                Label("Sources & Attributions", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    // MARK: - Model Settings

    @ViewBuilder private var modelSettingsContent: some View {
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

            if modelListTab == .recommended, let top = sortedModels.first {
                Label("Best for your device: \(top.rawValue)", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(sortedModels) { model in
                modelRow(model)
            }
        } header: {
            Text("MLX Model")
        } footer: {
            switch modelListTab {
            case .recommended:
                Text("Top 3 models for your \(deviceRAMGB) GB device, ranked by German quality. Switch to Size or Parameters to browse all models.")
                    .font(.caption2)
            case .size:
                Text("Sorted smallest to largest download. Tap \(Image(systemName: "info.circle")) for model details. Swipe left on a downloaded model to delete it.")
                    .font(.caption2)
            case .parameters:
                Text("Sorted largest to smallest by parameter count. More parameters generally means higher quality. Swipe left on a downloaded model to delete it.")
                    .font(.caption2)
            }
        }

        ModelStorageSection(models: MLXModel.allCases, cacheRefreshID: cacheRefreshID)

        Section("Model Status") {
            if mlxService.isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Image(modelManager.selectedMLXModel.logoName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(mlxService.downloadInfo ?? "Loading model…")
                            .foregroundStyle(.secondary)
                    }
                    if let progress = mlxService.downloadProgress, progress > 0 {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    HStack {
                        if let start = mlxService.loadStartTime {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text("Elapsed: \(elapsedString(since: start))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                        if let bytes = mlxService.downloadBytesInfo {
                            Text(bytes)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Button("Cancel", role: .destructive) {
                        mlxService.cancelLoad()
                    }
                    .font(.caption)
                }
            } else if mlxService.isModelLoaded,
                      let current = mlxService.currentModel {
                HStack(spacing: 10) {
                    Image(current.logoName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(current.rawValue) loaded and ready")
                        .foregroundStyle(.green)
                }
                if modelManager.selectedMLXModel != current {
                    Button {
                        Task {
                            await mlxService.loadModel(modelManager.selectedMLXModel)
                            cacheRefreshID = UUID()
                        }
                    } label: {
                        Label {
                            Text("Load \(modelManager.selectedMLXModel.rawValue)")
                        } icon: {
                            Image(modelManager.selectedMLXModel.logoName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text("Downloads model on first use (~\(formattedSize(modelManager.selectedMLXModel.approximateSizeMB))), then loads into memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task {
                        await mlxService.loadModel(modelManager.selectedMLXModel)
                        cacheRefreshID = UUID()
                    }
                } label: {
                    Label {
                        Text("Load \(modelManager.selectedMLXModel.rawValue)")
                    } icon: {
                        Image(modelManager.selectedMLXModel.logoName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text("Downloads model on first use (~\(formattedSize(modelManager.selectedMLXModel.approximateSizeMB))), then loads into memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let last = modelManager.lastLoadedModel,
                   last != modelManager.selectedMLXModel,
                   isDownloaded(last) {
                    Divider()
                    Button {
                        Task {
                            await mlxService.loadModel(last)
                            cacheRefreshID = UUID()
                        }
                    } label: {
                        Label {
                            Text("Resume \(last.rawValue)")
                        } icon: {
                            Image(last.logoName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text("Last session's model — resumes from cache if still downloaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = mlxService.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Model Row

    @ViewBuilder private func modelRow(_ model: MLXModel) -> some View {
        let downloaded = isDownloaded(model)
        let isDownloading = mlxService.isLoading && modelManager.selectedMLXModel == model
        HStack(spacing: 0) {
            Button {
                if model.minimumRAMGB > deviceRAMGB {
                    modelRequiringRAMWarning = model
                } else {
                    modelManager.selectedMLXModel = model
                }
            } label: {
                HStack {
                    Image(model.logoName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.rawValue)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            if isDownloading {
                                Text(mlxService.downloadInfo ?? "Downloading…")
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                                if let bytes = mlxService.downloadBytesInfo {
                                    Text(bytes)
                                        .foregroundStyle(.secondary)
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

                        if isDownloading {
                            if let progress = mlxService.downloadProgress, progress > 0 {
                                ProgressView(value: progress)
                                    .tint(.orange)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                                    .tint(.orange)
                            }
                        }

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
                } else if downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                }
                if modelManager.selectedMLXModel == model {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
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

    // MARK: - Cache Helpers

    private func isDownloaded(_ model: MLXModel) -> Bool {
        _ = cacheRefreshID
        return model.isDownloaded
    }

    private func cachedSize(_ model: MLXModel) -> Int64? {
        _ = cacheRefreshID
        return model.cachedSizeBytes
    }

    // MARK: - Formatting

    private func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            let gb = Double(mb) / 1000.0
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func elapsedString(since start: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    /// German voices the user downloaded (Enhanced/Premium). Compact voices are
    /// pre-installed with iOS, so anything above compact quality was added by
    /// the user — we use that as the "you downloaded this" signal.
    private var downloadedGermanVoices: [AVSpeechSynthesisVoice] {
        germanVoices.filter { $0.quality == .enhanced || $0.quality == .premium }
    }

    private func voiceName(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default: return "\(voice.name) (Basic)"
        }
    }
}

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
                                Image(entry.model.logoName)
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
                Image(entry.model.logoName)
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

private struct ModelInfoSheet: View {
    let model: MLXModel
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var refreshID = UUID()

    private var isDownloaded: Bool {
        _ = refreshID
        return model.isDownloaded
    }

    private var cachedSizeBytes: Int64? {
        _ = refreshID
        return model.cachedSizeBytes
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(model.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Parameters")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(model.parameterCount)
                                .font(.subheadline)
                        }
                        GridRow {
                            Text("Quantization")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(model.quantization)
                                .font(.subheadline)
                        }
                        GridRow {
                            Text("Download Size")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("~\(formattedSize(model.approximateSizeMB))")
                                .font(.subheadline)
                        }
                        if let bytes = cachedSizeBytes, bytes > 0 {
                            GridRow {
                                Text("On Disk")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(formattedBytes(bytes))
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Link(destination: model.huggingFaceRepoURL) {
                        Label("View on HuggingFace", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: model.promoPageURL) {
                        Label("Learn more about \(model.rawValue)", systemImage: "globe")
                    }
                }

                if isDownloaded {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete Downloaded Model", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(model.logoName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(model.rawValue)
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            let gb = Double(mb) / 1000.0
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

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

// MARK: - Voice Download Guide

private struct VoiceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The voices in this app come from iOS. The built-in “basic” voices sound robotic, but iOS offers free Enhanced and Premium German voices that sound much more natural.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Siri voices can't be used")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Apple's Siri voices sound the best, but Apple keeps them private — no third-party app, including this one, is allowed to use them. The best voice available here is a Premium one, which still sounds far better than the basic voices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.bubble")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    stepRow(1, "Open the Settings app and tap the search bar at the bottom.",
                            image: "voice-guide-settings-search")
                    stepRow(2, "Type “voice”, then tap Voices under Accessibility → Live Speech.",
                            image: "voice-guide-voice-search")
                } header: {
                    Text("Quickest: search Settings")
                }

                Section {
                    stepRow(1, "Or open Settings and tap Accessibility.",
                            image: "voice-guide-accessibility")
                    stepRow(2, "Under Speech, tap Live Speech.",
                            image: "voice-guide-live-speech")
                } header: {
                    Text("Or browse to it")
                }

                Section {
                    stepRow(1, "Scroll to Preferred Voices and tap Add Preferred Voice…",
                            image: "voice-guide-add-voice")
                    stepRow(2, "Choose German. On an English iPhone it's listed as “German”, not “Deutsch”.",
                            image: "voice-guide-german")
                    stepRow(3, "Tap the cloud icon next to a voice to download its Enhanced or Premium version. Skip the Siri voices (crossed out) — apps can't use those.",
                            image: "voice-guide-voice-picker")
                } header: {
                    Text("Download a German voice")
                } footer: {
                    Text("Good picks: Yannick, Petra, Viktor, or Anna. After it downloads, force-quit this app and reopen it, then choose the voice in Pronunciation above.")
                }

                Section {
                    Label {
                        Text("Only German voices work here. English voices like “Zoe” can't pronounce German, so they won't appear in this app's voice list — make sure you download from the German section.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                }

                Section {
                    Button {
                        // openSettingsURLString is the only Apple-sanctioned deep
                        // link — it opens this app's own page in Settings. There's
                        // no public way to open Accessibility or the Settings root.
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Opens this app's page in Settings. Tap back to reach the main list, then Accessibility — or pull down and search “voice”.")
                }
            }
            .navigationTitle("Download Voices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// A numbered instruction with an optional screenshot beneath it. The image
    /// only renders when its asset exists in the catalog, so steps stay safe if
    /// a screenshot is ever renamed or removed.
    @ViewBuilder
    private func stepRow(_ number: Int, _ text: String, image: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let image, UIImage(named: image) != nil {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }
}
