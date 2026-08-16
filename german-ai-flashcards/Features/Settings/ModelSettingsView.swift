import SwiftUI

/// The "Model" tab of the Settings screen: pick and load an MLX model, browse by quality/size/
/// parameters, view per-model details, and see on-disk storage usage.
struct ModelSettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @State private var cacheRefreshID = UUID()
    @State private var modelToDelete: MLXModel?
    @State private var modelForInfo: MLXModel?
    @State private var modelNeedingMemoryCheck: MLXModel?
    @State private var showModelGuide = false
    @State private var showHeroIntro = false
    @State private var modelListTab: ModelListTab = .recommended
    @State private var memorySaverMode: MemorySaver.Mode = MemorySaver.mode
    @Environment(\.appTheme) private var appTheme

    /// The retired build whose update sheet is open, and the one awaiting delete confirmation.
    /// Both stay nil for anyone without an old build cached, which is what keeps every one of these
    /// surfaces invisible to a fresh install.
    @State private var supersessionToReview: ModelSupersession?
    @State private var supersessionToDelete: ModelSupersession?

    /// The best in-house tutor this device can run, or nil when neither fits. Leads the promoted
    /// section as a full card.
    private var leadTutor: MLXModel? { MLXModel.leadTutor(ramGB: deviceRAMGB) }

    /// The remaining runnable tutors, listed under the lead card. On an 8 GB device that's the
    /// lighter E2B tutor, worth keeping in reach for anyone running under memory pressure; on a
    /// 6 GB device the E2B tutor is already the lead and there's nothing left to show.
    private var siblingTutors: [MLXModel] {
        guard let leadTutor else { return [] }
        return MLXModel.germanTutors.filter { $0 != leadTutor && $0.minimumRAMGB <= deviceRAMGB }
    }

    /// The tutors shown in the promoted section, pulled out of the list below so nothing is listed
    /// twice. A tutor this device *can't* run deliberately stays in the list, sunk to the bottom
    /// with its RAM note, rather than vanishing from the app entirely.
    private var shownTutors: [MLXModel] {
        guard let leadTutor else { return [] }
        return [leadTutor] + siblingTutors
    }

    /// Whether the promoted tutor section is shown at all.
    private var showsTutorSection: Bool { leadTutor != nil }

    enum ModelListTab: String, CaseIterable {
        case recommended = "Recommended"
        case size        = "Size"
        case parameters  = "Parameters"
    }

    /// Tester ask: a "tell us what matters, we'll pick + load a model" shortcut, so a learner doesn't
    /// have to read every spec card. The full list stays one scroll below for anyone who prefers it.
    private enum ModelGoal: String, CaseIterable, Identifiable {
        case bestGerman  = "Best German"
        case fastest     = "Fastest"
        case fitsDevice  = "Fits my device"
        case longStories = "Longest stories"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .bestGerman:  "checkmark.seal.fill"
            case .fastest:     "bolt.fill"
            case .fitsDevice:  "iphone.gen3"
            case .longStories: "book.fill"
            }
        }

        var caption: String {
            switch self {
            case .bestGerman:  "Sharpest corrections and grammar"
            case .fastest:     "Snappiest replies, smallest download"
            case .fitsDevice:  "The balanced pick for your RAM"
            case .longStories: "Most capable for long, rich text"
            }
        }
    }

    /// Resolve a goal to a concrete model. The pool is `recommendedOrder` (already filtered to what
    /// this device can actually run / has available), so a goal never points at an unreachable model.
    private func modelForGoal(_ goal: ModelGoal) -> MLXModel {
        let pool = MLXModel.recommendedOrder(ramGB: deviceRAMGB)
        guard !pool.isEmpty else { return .hero }
        switch goal {
        case .bestGerman:  return pool.max { $0.germanQualityScore < $1.germanQualityScore } ?? pool[0]
        case .fastest:     return pool.min { $0.parameterCountValue < $1.parameterCountValue } ?? pool[0]
        case .fitsDevice:  return pool.first ?? .hero
        case .longStories: return pool.max { $0.parameterCountValue < $1.parameterCountValue } ?? pool[0]
        }
    }

    /// "Pick by goal" — one tap resolves to a model and loads it (via the same `requestLoad` path,
    /// so the too-big-for-this-device check still runs). The full spec list stays below.
    private var goalSection: some View {
        Section {
            ForEach(ModelGoal.allCases) { goal in
                let model = modelForGoal(goal)
                Button {
                    requestLoad(model)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: goal.systemImage)
                            .foregroundStyle(.tint)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(goal.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(goal.caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Text(model.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if modelManager.selectedMLXModel == model {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Pick by goal").themedSectionHeader()
        } footer: {
            Text("Tell us what matters and we'll pick — and load — a model for it. Or scroll down to choose one by spec.")
                .font(.caption2)
        }
        .themedListRow()
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

                HStack {
                    Label("Available to this app", systemImage: "gauge.with.dots.needle.33percent")
                    Spacer()
                    Text(MemoryBudget.formattedGB(MemoryBudget.totalMB))
                        .foregroundStyle(.secondary)
                }

                Picker(selection: $memorySaverMode) {
                    ForEach(MemorySaver.Mode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                } label: {
                    Label("Memory Saver", systemImage: "leaf")
                }
                .onChange(of: memorySaverMode) { _, newValue in
                    MemorySaver.mode = newValue
                    // Take effect on the model that's already loaded, not just the next one.
                    MemorySaver.applyAllocatorLimits(for: mlxService.currentModel)
                }

                Button {
                    showModelGuide = true
                } label: {
                    Label("Which model should I use?", systemImage: "info.circle")
                }
            } header: {
                Text("This device").themedSectionHeader()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("iOS gives each app a slice of RAM, not all of it. Memory Saver keeps a "
                         + "model that needs more than this device's slice from using it all up: "
                         + "shorter answers, a smaller conversation memory, and a clean stop when "
                         + "memory runs out. On Automatic it turns itself on only for models that "
                         + "need more room than there is.")
                    memorySaverStatus
                }
                .font(.caption2)
            }
            .themedListRow()

            goalSection

            // The in-house German tutors, kept together above the general-purpose list. They're one
            // fine-tune at two sizes, so splitting them across the sorted list below buries the
            // lighter one under models it outscores.
            if let leadTutor {
                Section {
                    heroCard(leadTutor)
                    ForEach(siblingTutors) { model in
                        modelRow(model)
                    }
                    // A retired build of a *sibling* tutor has nowhere to hang off a plain row, so
                    // it gets its own banner line here. Empty today; free coverage when the lighter
                    // tutor is eventually retrained.
                    ForEach(siblingTutors.compactMap(pendingSupersession)) { supersession in
                        supersessionBanner(supersession)
                    }
                } header: {
                    Text("Tuned for this app").themedSectionHeader()
                } footer: {
                    Text(tutorSectionFooter)
                        .font(.caption2)
                }
                .themedListRow()
            }

            Section {
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
                Text(showsTutorSection ? "General-purpose models" : "MLX Model").themedSectionHeader()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if showsTutorSection {
                        Text("None of these were trained on German correction, so they're noticeably weaker at catching and explaining a learner's mistakes than the tutors above. They still write usable vocabulary cards. Tap one to load it; the loaded model is marked with a green checkmark.")
                    } else {
                        Text("Tap a model to load it. The one loaded and ready is marked with a green checkmark.")
                    }
                    Group {
                        switch modelListTab {
                        case .recommended:
                            Text("Ranked by German quality for your \(deviceRAMGB) GB device. Switch to Size or Parameters to reorder.")
                        case .size:
                            Text("Sorted smallest to largest download. Tap \(Image(systemName: "info.circle")) for model details. Swipe left on a downloaded model to delete it.")
                        case .parameters:
                            Text("Sorted largest to smallest by parameter count. More parameters generally means higher quality. Swipe left on a downloaded model to delete it.")
                        }
                    }
                }
                .font(.caption2)
            }
            .themedListRow()

            ImageGenerationSection(cacheRefreshID: $cacheRefreshID)

            ModelStorageSection(
                models: MLXModel.allCases,
                imageModels: ImageGenModel.allCases,
                legacyBuilds: ModelSupersession.occupyingSpace,
                cacheRefreshID: cacheRefreshID,
                onDeleteRequest: { supersessionToDelete = $0 }
            )
            .themedListRow()
        }
        .sheet(isPresented: $showModelGuide) {
            ModelGuideSheet()
        }
        .sheet(isPresented: $showHeroIntro) {
            HeroModelIntroSheet(modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(item: $supersessionToReview) { supersession in
            ModelUpdateSheet(
                supersession: supersession,
                modelManager: modelManager,
                mlxService: mlxService,
                onChange: { cacheRefreshID = UUID() }
            )
        }
        .sheet(item: $modelForInfo) { model in
            ModelInfoSheet(model: model) {
                modelToDelete = model
            }
        }
        .sheet(item: $modelNeedingMemoryCheck) { model in
            MemoryCheckSheet(
                model: model,
                alternative: MLXModel.recommended(ramGB: deviceRAMGB),
                onUseAnyway: { loadAndSelect(model) },
                onUseAlternative: { loadAndSelect($0) }
            )
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
        .alert(
            "Delete the old version?",
            isPresented: Binding(
                get: { supersessionToDelete != nil },
                set: { if !$0 { supersessionToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { supersessionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let supersession = supersessionToDelete {
                    try? supersession.delete()
                    // The container in memory came out of the directory just removed. Deliberately
                    // not `mlxService.deleteModel(_:)`, which targets the *new* repo.
                    if mlxService.currentModel == supersession.model { mlxService.unloadModel() }
                    cacheRefreshID = UUID()
                    supersessionToDelete = nil
                }
            }
        } message: {
            if let supersession = supersessionToDelete {
                Text("This removes the previous download of \(supersession.model.rawValue). The version you have now is unaffected, and nothing you've made with it changes.")
            }
        }
    }

    /// Whether the governors are running right now, and on what. Automatic mode is invisible
    /// otherwise, and an unexplained short answer is worse than a short answer you expected.
    @ViewBuilder private var memorySaverStatus: some View {
        let model = mlxService.loadedModel ?? modelManager.selectedMLXModel
        if MemorySaver.isActive(for: model) {
            Label("On now for \(model.rawValue).", systemImage: "leaf.fill")
                .foregroundStyle(.green)
        } else if memorySaverMode == .off {
            Label("Off. Large models may close the app.", systemImage: "leaf")
                .foregroundStyle(.secondary)
        } else {
            Label("Not needed for \(model.rawValue).", systemImage: "leaf")
                .foregroundStyle(.secondary)
        }
    }

    /// Why the promoted section leads with the tutor it does. Differs by device: an 8 GB phone gets
    /// both tutors and a reason to prefer one, a 6 GB phone gets the E2B tutor and an explanation of
    /// where the other one went.
    private var tutorSectionFooter: String {
        guard let leadTutor else { return "" }
        if leadTutor.isHero {
            return "Both are Gemma 4 fine-tuned on German grammar for this app, and both beat every "
                 + "general-purpose model below on the app's own grammar test. The E4B tutor scores "
                 + "highest; the E2B tutor trades a little accuracy for about 1.7 GB less memory, "
                 + "which helps if the big one makes your phone struggle."
        }
        return "Gemma 4 E2B, fine-tuned on German grammar for this app. It beats every "
             + "general-purpose model below on the app's own grammar test, and it's the tutor that "
             + "fits this device. The larger E4B tutor needs 8 GB of RAM."
    }

    // MARK: - Hero Card

    /// The prominent, promoted card for the tutor leading the section. Takes the model rather than
    /// assuming the hero, since a 6 GB device leads with the E2B tutor instead.
    @ViewBuilder private func heroCard(_ model: MLXModel) -> some View {
        let downloaded = isDownloaded(model)
        let isDownloading = mlxService.isLoading && modelManager.selectedMLXModel == model
        let isLoaded = mlxService.isModelLoaded && mlxService.currentModel == model

        VStack(alignment: .leading, spacing: 12) {
            Button {
                // The card only shows on devices in the hero's RAM tier, but the check is cheap
                // and this is the one path where getting it wrong costs the user a 5 GB download.
                requestLoad(model)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        if isDownloading {
                            ModelLoadingIndicator(model: model, progress: mlxService.downloadProgress, size: 34)
                        } else {
                            model.logoImage
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(model.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                RecommendedBadge()
                            }
                            HStack(spacing: 6) {
                                if isDownloading {
                                    Text(mlxService.downloadInfo ?? "Downloading…")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.orange)
                                    if let bytes = mlxService.downloadBytesInfo {
                                        Text(bytes).foregroundStyle(.secondary)
                                    }
                                } else if isLoaded {
                                    Text("Loaded & ready").fontWeight(.medium).foregroundStyle(.green)
                                } else if downloaded {
                                    Text("Downloaded · tap to load").foregroundStyle(.green)
                                } else {
                                    Text("~\(formattedSize(model.approximateSizeMB)) · one-time download")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }

                        Spacer()

                        if isDownloading {
                            ProgressView().controlSize(.small)
                        } else if isLoaded {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if downloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                        } else {
                            Image(systemName: "arrow.down.circle").foregroundStyle(model.theme.accent)
                        }
                    }

                    Text(model.tutorTagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .disabled(mlxService.isLoading)

            if let supersession = pendingSupersession(model) {
                supersessionBanner(supersession)
            }

            Divider()

            HStack {
                // The intro wizard is written about the hero specifically, so it's only offered
                // when the hero is the one leading the card.
                if model.isHero {
                    Button {
                        showHeroIntro = true
                    } label: {
                        Label("Why this model?", systemImage: "sparkles")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                Spacer()
                Button {
                    modelForInfo = model
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.theme.accent)
        }
        .padding(.vertical, 4)
        .heroRowHighlight()
    }

    // MARK: - Retired builds

    /// The retired build for this model, if this device still has the whole thing.
    ///
    /// Reads `cacheRefreshID` for the same reason ``isDownloaded(_:)`` does — so the banner
    /// disappears the moment a delete lands instead of waiting for some unrelated redraw.
    private func pendingSupersession(_ model: MLXModel) -> ModelSupersession? {
        _ = cacheRefreshID
        return ModelSupersession.onDisk.first { $0.model == model }
    }

    /// "You still have the old download." Rendered only when the retired repo is genuinely on this
    /// device, so for anyone who installed after the retrain, or who never downloaded the tutor,
    /// this card looks exactly as it always has.
    ///
    /// Quotes `approximateSizeMB` rather than a real byte count on purpose: this card re-renders on
    /// every download-progress tick, and a directory walk in that path would be a needless dozen
    /// `stat`s a second. The exact figure is one section down, in Storage.
    @ViewBuilder private func supersessionBanner(_ supersession: ModelSupersession) -> some View {
        Button {
            supersessionToReview = supersession
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updated version available")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("The old download is still using about \(formattedSize(supersession.model.approximateSizeMB)) here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(
                Color.orange.opacity(0.10),
                in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Model Row

    @ViewBuilder private func modelRow(_ model: MLXModel) -> some View {
        let downloaded = isDownloaded(model)
        let isDownloading = mlxService.isLoading && modelManager.selectedMLXModel == model
        let isLoaded = mlxService.isModelLoaded && mlxService.currentModel == model
        // The tutor card above already carries the recommendation, so don't also badge a list row.
        let isRecommended = !showsTutorSection && model == recommendedModel
        let isLastUsed = modelManager.lastLoadedModel == model && !isLoaded && !isDownloading
        HStack(spacing: 0) {
            Button {
                requestLoad(model)
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
        // Drop only the tutors actually promoted above, so a tutor this device can't run still
        // appears here (sunk to the bottom with its RAM note) instead of disappearing.
        let promoted = Set(shownTutors)
        let models = MLXModel.allCases.filter { !promoted.contains($0) }
        switch modelListTab {
        case .recommended:
            return MLXModel.recommendedOrder(ramGB: deviceRAMGB).filter { models.contains($0) }
        case .size:
            return models.sorted { $0.approximateSizeMB < $1.approximateSizeMB }
        case .parameters:
            return models.sorted { $0.parameterCountValue > $1.parameterCountValue }
        }
    }

    /// The single best model to badge in the *list* — used only when the hero card isn't shown (i.e.
    /// on devices that can't run the hero). Otherwise the hero card carries the recommendation.
    private var recommendedModel: MLXModel? {
        MLXModel.recommended(ramGB: deviceRAMGB)
    }

    // MARK: - Loading

    /// Tap-to-load, with the memory check in front of models this device is too small for. The
    /// check informs rather than blocks: it's the user's phone, and a slow model they chose is
    /// better than a model they can't reach.
    private func requestLoad(_ model: MLXModel) {
        if model.minimumRAMGB > deviceRAMGB {
            modelNeedingMemoryCheck = model
        } else {
            loadAndSelect(model)
        }
    }

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
            .clipShape(appTheme.pillShape)
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

/// On-disk usage for everything the app downloads: the MLX language models *and* the CoreML image
/// model, which share the same HuggingFace hub cache.
private struct ModelStorageSection: View {
    let models: [MLXModel]
    let imageModels: [ImageGenModel]
    /// Retired builds of models the app still ships. They belong to no enum case any more, so
    /// without this they'd be invisible here and silently counted in the grey "Other" segment —
    /// several GB of the learner's phone with nothing on any screen to explain it.
    let legacyBuilds: [ModelSupersession]
    let cacheRefreshID: UUID
    /// Raises the delete confirmation on the parent, which owns every destructive alert on this
    /// screen. Only legacy rows delete from here; live models are swipe-to-delete in the list above.
    var onDeleteRequest: (ModelSupersession) -> Void

    private let modelColors: [Color] = [.blue, .purple, .orange, .teal, .indigo, .pink]

    /// A downloaded model of any kind, flattened to what the bar and list need so the enums don't
    /// have to share a protocol.
    private struct ModelEntry: Identifiable {
        /// What this row is. Drives the tag beside the name and whether it can be deleted here.
        enum Kind { case language, image, legacy }

        let id: String
        let name: String
        let logo: Image
        let bytes: Int64
        let kind: Kind
        let colorIndex: Int
        /// Set on `.legacy` rows only — the row's delete target.
        let supersession: ModelSupersession?
    }

    private var downloadedModels: [ModelEntry] {
        _ = cacheRefreshID
        var result: [ModelEntry] = []
        var idx = 0
        for model in models {
            if let bytes = model.cachedSizeBytes, bytes > 0 {
                result.append(ModelEntry(
                    id: model.id,
                    name: model.rawValue,
                    logo: model.logoImage,
                    bytes: bytes,
                    kind: .language,
                    colorIndex: idx,
                    supersession: nil
                ))
                idx += 1
            }
        }
        for model in imageModels {
            if let bytes = model.cachedSizeBytes, bytes > 0 {
                result.append(ModelEntry(
                    id: "image-" + model.id,
                    name: model.displayName,
                    logo: model.logoImage,
                    bytes: bytes,
                    kind: .image,
                    colorIndex: idx,
                    supersession: nil
                ))
                idx += 1
            }
        }
        for build in legacyBuilds {
            let bytes = build.reclaimableBytes
            if bytes > 0 {
                result.append(ModelEntry(
                    id: "legacy-" + build.legacyRepoID,
                    name: build.model.rawValue,
                    logo: build.model.logoImage,
                    bytes: bytes,
                    kind: .legacy,
                    colorIndex: idx,
                    supersession: build
                ))
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
                                entry.logo
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                Circle()
                                    .fill(modelColors[entry.colorIndex % modelColors.count])
                                    .frame(width: 7, height: 7)
                                    .offset(x: 2, y: 2)
                            }
                            Text(entry.name)
                                .font(.caption)
                            switch entry.kind {
                            case .image:  tag("Pictures", color: .secondary)
                            case .legacy: tag("Old version", color: .orange)
                            case .language: EmptyView()
                            }
                            Spacer()
                            Text(formatBytes(entry.bytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            // Legacy rows need their own button: the footer's "swipe a language
                            // model above" has no row up there to swipe for them.
                            if entry.kind == .legacy, let supersession = entry.supersession {
                                Button(role: .destructive) {
                                    onDeleteRequest(supersession)
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label("Storage", systemImage: "internaldrive")
        } footer: {
            Text("Counts every downloaded model, language and image alike. Swipe a language model above to delete it; the image model has its own Delete button. A row marked \u{201C}Old version\u{201D} is a previous download of a model that has since been updated: it's never loaded again and is safe to delete here.")
                .font(.caption2)
        }
    }

    /// The small capsule beside a row's name. Shared so the "Pictures" and "Old version" tags can't
    /// drift apart visually.
    private func tag(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
                entry.logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Circle()
                    .fill(modelColors[entry.colorIndex % modelColors.count])
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: 2)
            }
            Text(entry.name)
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

// MARK: - Memory Check Sheet

/// Shown before loading a model this device doesn't have the memory for. It states the two numbers
/// that matter and what follows from them, then lets the user decide — a big model on a small phone
/// is slow and stops early, which is a trade some people will happily make.
struct MemoryCheckSheet: View {
    let model: MLXModel
    /// The best model that does fit here, offered as the one-tap alternative.
    let alternative: MLXModel
    var onUseAnyway: () -> Void
    var onUseAlternative: (MLXModel) -> Void
    @Environment(\.dismiss) private var dismiss

    private var neededMB: Int { MemoryBudget.requiredMB(for: model) }
    private var budgetMB: Int { MemoryBudget.totalMB }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: "memorychip")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text("\(model.rawValue) needs more memory than this iPhone gives an app.")
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        memoryBar
                    }
                    .padding(.vertical, 6)
                }

                Section("What that means") {
                    Label("Replies come slowly.", systemImage: "tortoise")
                    Label("Long answers stop early to stay within memory.", systemImage: "scissors")
                    Label("The app may close if memory runs out.", systemImage: "xmark.circle")
                    Label("Your decks and progress are saved either way.", systemImage: "checkmark.shield")
                }
                .font(.subheadline)

                Section {
                    Button {
                        // Remembered, so features built on this model stay reachable from here on
                        // rather than asking again on every screen.
                        MemorySaver.allowsOversizedModels = true
                        onUseAnyway()
                        dismiss()
                    } label: {
                        Text("Use It Anyway")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)

                    if alternative != model {
                        Button {
                            onUseAlternative(alternative)
                            dismiss()
                        } label: {
                            Text("Use \(alternative.rawValue) Instead")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text("Memory Saver turns on by itself for this model, so answers end cleanly "
                         + "instead of the app closing. You can change that under This device.")
                        .font(.caption2)
                }
            }
            .navigationTitle("Memory Check")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Two bars on a shared scale: what the model wants, and what this device has to give.
    private var memoryBar: some View {
        let scale = Double(max(neededMB, budgetMB))
        return VStack(alignment: .leading, spacing: 8) {
            barRow(
                label: "Needs",
                value: MemoryBudget.formattedGB(neededMB),
                fraction: scale > 0 ? Double(neededMB) / scale : 0,
                color: .orange
            )
            barRow(
                label: "You have",
                value: MemoryBudget.formattedGB(budgetMB),
                fraction: scale > 0 ? Double(budgetMB) / scale : 0,
                color: .green
            )
        }
    }

    private func barRow(label: String, value: String, fraction: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 10)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
