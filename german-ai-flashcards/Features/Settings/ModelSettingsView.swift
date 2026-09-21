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
    /// Whether the rest of the tutor family is expanded. Opens itself on appear for anyone who
    /// has a non-lead tutor downloaded or selected — see `body`'s `.onAppear`.
    @State private var showsOtherSizes = false
    @State private var memorySaverMode: MemorySaver.Mode = MemorySaver.mode
    @Environment(\.appTheme) private var appTheme

    /// The retired build whose update sheet is open, and the cached build awaiting delete
    /// confirmation. Both stay nil for anyone without an old build cached, which is what keeps
    /// every one of these surfaces invisible to a fresh install.
    @State private var supersessionToReview: ModelSupersession?
    @State private var buildToDelete: DeletableBuild?
    @State private var showClearAllModels = false

    /// The best in-house tutor this device can run, or nil when neither fits. Leads the promoted
    /// section as a full card.
    private var leadTutor: MLXModel? { MLXModel.leadTutor(ramGB: deviceRAMGB) }

    /// Every tutor except the one on the card, runnable ones first.
    ///
    /// The two-pass partition is load-bearing, not tidiness: a single `filter` returns
    /// `germanTutors` order, which on a 4 GB phone puts both Gemma tutors — neither of which it
    /// can run — above the one alternative it can. Runnable first, over-tier last.
    private var otherTutors: [MLXModel] {
        guard let leadTutor else { return [] }
        let rest = MLXModel.germanTutors.filter { $0 != leadTutor }
        return rest.filter { $0.minimumRAMGB <= deviceRAMGB }
             + rest.filter { $0.minimumRAMGB > deviceRAMGB }
    }

    private var oversizedTutorCount: Int {
        otherTutors.filter { $0.minimumRAMGB > deviceRAMGB }.count
    }

    private var downloadedOtherTutorCount: Int {
        otherTutors.filter { isDownloaded($0) }.count
    }

    /// The row that opens the rest of the family.
    ///
    /// Not a `DisclosureGroup`: its content isn't made of list rows, and `modelRow` depends on
    /// being one for its edge-to-edge insets and its swipe-to-delete.
    ///
    /// The caption is what stops a collapsed row from being a black hole — "3 others" says
    /// nothing, "1 downloaded" says there is something of yours in here.
    private var otherSizesToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { showsOtherSizes.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showsOtherSizes ? 90 : 0))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Other sizes (\(otherTutors.count))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let caption = otherSizesCaption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Only the clauses that are true. Nil when there's nothing worth saying, so a plain
    /// "three other sizes exist" doesn't get dressed up as news.
    private var otherSizesCaption: String? {
        var parts: [String] = []
        if downloadedOtherTutorCount > 0 { parts.append("\(downloadedOtherTutorCount) downloaded") }
        if oversizedTutorCount > 0 {
            parts.append(oversizedTutorCount == 1
                         ? "1 needs more memory than this phone"
                         : "\(oversizedTutorCount) need more memory than this phone")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
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

            // The tutor this device should use, with the rest of the family one tap away. Every
            // row here is a direct Section child rather than a DisclosureGroup's content, which
            // is what keeps `modelRow`'s list-row insets and swipe-to-delete working.
            if let leadTutor {
                Section {
                    heroCard(leadTutor)

                    // Active load progress — shared with Home so both screens animate
                    // identically. Lives here rather than in a list below because there is no
                    // longer a list below, and a download with no visible progress is worse than
                    // a slow one.
                    if mlxService.isLoading {
                        ModelLoadingPanel(
                            mlxService: mlxService,
                            showsHeader: true,
                            headerModel: modelManager.selectedMLXModel
                        )
                        .padding(.vertical, 4)
                    }

                    if let error = mlxService.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !otherTutors.isEmpty {
                        otherSizesToggle

                        if showsOtherSizes {
                            if oversizedTutorCount > 0 {
                                Text("A tutor marked \u{201C}May struggle\u{201D} needs more memory "
                                     + "than this phone gives an app. You can still try one; the "
                                     + "memory check spells out the trade before anything downloads.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(otherTutors) { model in
                                modelRow(model)
                            }
                        }
                    }

                    // A retired build of a non-lead tutor has nowhere to hang off a plain row, so
                    // it gets its own banner line. Deliberately outside the disclosure: several GB
                    // of a dead build must not need a tap to discover.
                    ForEach(otherTutors.compactMap(pendingSupersession)) { supersession in
                        supersessionBanner(supersession)
                    }
                } header: {
                    Text("Your German tutor").themedSectionHeader()
                } footer: {
                    Text(tutorSectionFooter)
                        .font(.caption2)
                }
                .themedListRow()
            }

            Section {
                modelRow(.appleIntelligence)
            } header: {
                Text("Built in to iOS").themedSectionHeader()
            } footer: {
                Text("Apple's on-device model. Nothing to download, it starts instantly, and it "
                     + "runs privately on your phone. It's weaker at German than the tutors: 60% "
                     + "on the app's grammar test against 75\u{2013}90%, and 0 of 15 on "
                     + "da-/wo-compounds. It flags about one correct sentence in six as wrong and "
                     + "misses a third of real mistakes. Good for quick vocabulary work; for "
                     + "correction practice, use a tutor.")
                    .font(.caption2)
            }
            .themedListRow()

            reclaimBanner

            ImageGenerationSection(cacheRefreshID: $cacheRefreshID)

            ModelStorageSection(
                models: MLXModel.allCases,
                imageModels: ImageGenModel.allCases,
                legacyBuilds: ModelSupersession.occupyingSpace,
                orphans: orphanedDownloads,
                cacheRefreshID: cacheRefreshID,
                onDeleteRequest: { buildToDelete = $0 },
                onClearAllRequest: { showClearAllModels = true }
            )
            .themedListRow()
        }
        .sheet(isPresented: $showClearAllModels) {
            ClearAllModelsSheet(
                languageBytes: downloadedLanguageBytes,
                imageBytes: downloadedImageBytes,
                reclaimableBytes: reclaimableBuildBytes,
                onConfirm: clearAllModels
            )
        }
        // Open the list for anyone whose tutor isn't the one on the card. Making someone hunt
        // for the model they are actually running would be worse than not collapsing at all.
        .onAppear {
            if otherTutors.contains(where: {
                isDownloaded($0) || $0 == modelManager.selectedMLXModel || $0 == mlxService.currentModel
            }) {
                showsOtherSizes = true
            }
        }
        .sheet(isPresented: $showModelGuide) {
            ModelGuideSheet()
        }
        .sheet(isPresented: $showHeroIntro) {
            HeroModelIntroSheet(
                modelManager: modelManager,
                mlxService: mlxService,
                model: leadTutor ?? .hero
            )
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
                // The best tutor that actually fits, not "the top of a global ranking" — on a
                // 4 GB phone that difference is a Granite tutor rather than Apple Intelligence.
                alternative: MLXModel.leadTutor(ramGB: deviceRAMGB) ?? .appleIntelligence,
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
            buildToDelete.map(deleteBuildTitle) ?? "",
            isPresented: Binding(
                get: { buildToDelete != nil },
                set: { if !$0 { buildToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { buildToDelete = nil }
            Button("Delete", role: .destructive) {
                if let build = buildToDelete {
                    try? build.delete()
                    // The container in memory came out of the directory just removed. Deliberately
                    // not `mlxService.deleteModel(_:)`, which targets the *new* repo. A removed
                    // model has no live case, so `liveModel` is nil and nothing needs unloading.
                    if let model = build.liveModel, mlxService.currentModel == model {
                        mlxService.unloadModel()
                    }
                    cacheRefreshID = UUID()
                    buildToDelete = nil
                }
            }
        } message: {
            if let build = buildToDelete {
                Text(deleteBuildMessage(build))
            }
        }
    }

    /// Both delete confirmations for a cached build nothing will load again. Split by case
    /// because the two are not the same promise: an old version can be downloaded again and has
    /// a replacement already on the device, a removed model has neither.
    private func deleteBuildTitle(_ build: DeletableBuild) -> String {
        switch build {
        case .superseded: "Delete the old version?"
        case .orphaned:   "Delete this model?"
        }
    }

    private func deleteBuildMessage(_ build: DeletableBuild) -> String {
        switch build {
        case .superseded(let supersession):
            "This removes the previous download of \(supersession.model.rawValue). The version "
            + "you have now is unaffected, and nothing you've made with it changes."
        case .orphaned(let orphan):
            "This removes the downloaded weights for \(orphan.displayName) "
            + "(\(formattedBytes(orphan.bytes))). This model is no longer part of the app, so it "
            + "can't be downloaded again. Nothing you've made with it changes."
        }
    }

    /// "You have models on here that this app dropped." Storage is the last section on a long
    /// screen, so without this the bytes are findable only by someone already scrolling for them.
    /// Renders for nobody who hasn't downloaded a since-removed model, which is every new install.
    @ViewBuilder private var reclaimBanner: some View {
        let orphans = orphanedDownloads
        if !orphans.isEmpty {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(orphans.count == 1
                             ? "1 model is no longer part of this app"
                             : "\(orphans.count) models are no longer part of this app")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Still on your phone, using \(formattedBytes(orphans.reduce(0) { $0 + $1.bytes })). "
                             + "Nothing here can load them. Free the space under Storage below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
            .themedListRow()
        }
    }

    // MARK: - Cached downloads

    /// Cached models the app no longer ships. Read through `cacheRefreshID` like the other cache
    /// lookups here, so the rows disappear the moment a delete lands.
    private var orphanedDownloads: [OrphanedModelCache.Orphan] {
        _ = cacheRefreshID
        return OrphanedModelCache.all
    }

    private var downloadedLanguageBytes: Int64 {
        _ = cacheRefreshID
        return MLXModel.allCases.reduce(0) { $0 + ($1.cachedSizeBytes ?? 0) }
    }

    private var downloadedImageBytes: Int64 {
        _ = cacheRefreshID
        return ImageGenModel.allCases.reduce(0) { $0 + ($1.cachedSizeBytes ?? 0) }
    }

    /// Bytes held by builds no live model names: retired versions plus removed models.
    private var reclaimableBuildBytes: Int64 {
        _ = cacheRefreshID
        return ModelSupersession.occupyingSpace.reduce(0) { $0 + $1.reclaimableBytes }
             + orphanedDownloads.reduce(0) { $0 + $1.bytes }
    }

    /// Delete every model file the app can re-download. Unloads first so nothing keeps reading a
    /// directory that's about to go, and leaves decks, chats, stories and progress alone —
    /// those live in SwiftData, not in the model cache.
    private func clearAllModels() {
        mlxService.unloadModel()
        for model in MLXModel.allCases { try? mlxService.deleteModel(model) }
        for model in ImageGenModel.allCases { try? model.deleteFromCache() }
        for supersession in ModelSupersession.occupyingSpace { try? supersession.delete() }
        for orphan in orphanedDownloads { try? OrphanedModelCache.delete(orphan) }
        cacheRefreshID = UUID()
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
            return "Four tutors, all fine-tuned on the same German material for this app: verbs "
                 + "with prepositions, separable and reflexive verbs, da-/wo-compounds, relative "
                 + "pronouns, Konjunktiv II. On the app's own grammar test the E4B tutor scores "
                 + "90%, the E2B 83%, the Granite 3B 81%, and the Granite 2B 75%. They differ in "
                 + "download size and memory, not in what they were taught. Pick a smaller one if "
                 + "the big one makes this phone struggle."
        }
        return "All four tutors were fine-tuned on the same German material for this app. "
             + "\(leadTutor.rawValue) is the strongest one that fits this phone's memory, at "
             + "\(leadTutor.suiteScorePercent)% on the app's grammar test. The others are smaller "
             + "downloads that let more mistakes past."
    }

    // MARK: - Hero Card

    /// The prominent, promoted card for the tutor leading the section. Takes the model rather than
    /// assuming the hero, since a 6 GB device leads with the E2B tutor instead.
    @ViewBuilder private func heroCard(_ model: MLXModel) -> some View {
        let downloaded = isDownloaded(model)
        let isDownloading = mlxService.isLoading && modelManager.selectedMLXModel == model
        let isLoaded = mlxService.isModelLoaded && mlxService.currentModel == model
        let pausedBytes = pausedDownloadBytes(model)

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
                                } else if pausedBytes > 0 {
                                    Text("Paused · \(formattedBytes(pausedBytes)) saved · tap to continue")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.orange)
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
                        } else if pausedBytes > 0 {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.orange)
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
                // The pitch is per-tutor now, so this opens for whichever one leads the card
                // rather than only for the hero.
                Button {
                    showHeroIntro = true
                } label: {
                    Label("Why this model?", systemImage: "sparkles")
                        .font(.caption)
                        .fontWeight(.medium)
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
        let pausedBytes = pausedDownloadBytes(model)
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
                            if isLastUsed {
                                tagLabel("Last used", color: .secondary)
                            }
                            // Over-tier models stay tappable — the tag says the row is a knowing
                            // trade, and the memory check sheet spells it out before the download.
                            if !model.isAppleIntelligence && model.minimumRAMGB > deviceRAMGB {
                                tagLabel("May struggle", color: .orange)
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
                                } else if pausedBytes > 0 {
                                    Text("Paused · \(formattedBytes(pausedBytes)) saved")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.orange)
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
                } else if pausedBytes > 0 {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
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
            // Paused downloads are deletable too — abandoning one shouldn't strand its
            // partial gigabytes on the phone.
            if (downloaded || pausedBytes > 0) && !mlxService.isLoading {
                Button("Delete", role: .destructive) {
                    modelToDelete = model
                }
            }
        }
    }

    // MARK: - Device Info

    private var deviceRAMGB: Int { DeviceCapability.ramGB }

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

    /// Bytes an interrupted download of `model` still holds on disk, or 0. Skipped entirely
    /// while any load is running: rows re-render on every progress tick, and this walks the
    /// cache directory (same discipline as the supersession banner's size shortcut).
    private func pausedDownloadBytes(_ model: MLXModel) -> Int64 {
        _ = cacheRefreshID
        guard !mlxService.isLoading else { return 0 }
        return model.pausedDownloadBytes
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
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Deletable builds

/// Something in the cache that no live model will ever load again, and can therefore be deleted
/// from the Storage list.
///
/// Two ways that happens, and they read differently to the user, so they get different copy: a
/// model was *retrained* and the old build lingers (``ModelSupersession``), or a model was
/// *removed from the app* entirely (``OrphanedModelCache``). The first can be re-downloaded and
/// has a replacement to point at; the second cannot and does not. They share this type only
/// because the Storage section needs one delete target, not because they mean the same thing.
enum DeletableBuild: Identifiable {
    case superseded(ModelSupersession)
    case orphaned(OrphanedModelCache.Orphan)

    var id: String {
        switch self {
        case .superseded(let supersession): supersession.id
        case .orphaned(let orphan):         orphan.id
        }
    }

    var displayName: String {
        switch self {
        case .superseded(let supersession): supersession.model.rawValue
        case .orphaned(let orphan):         orphan.displayName
        }
    }

    var reclaimableBytes: Int64 {
        switch self {
        case .superseded(let supersession): supersession.reclaimableBytes
        case .orphaned(let orphan):         orphan.bytes
        }
    }

    func delete() throws {
        switch self {
        case .superseded(let supersession): try supersession.delete()
        case .orphaned(let orphan):         try OrphanedModelCache.delete(orphan)
        }
    }

    /// The model whose weights these are, when the app still ships one under that name. Nil for
    /// a removed model, which is what tells the delete path there is nothing to unload.
    var liveModel: MLXModel? {
        switch self {
        case .superseded(let supersession): supersession.model
        case .orphaned:                     nil
        }
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
    /// Cached models the app dropped entirely. Same problem as `legacyBuilds` and the same fix,
    /// but found by sweeping the cache rather than from a table, since a removed model has no
    /// enum case left to hang a row off. See ``OrphanedModelCache``.
    let orphans: [OrphanedModelCache.Orphan]
    let cacheRefreshID: UUID
    /// Raises the delete confirmation on the parent, which owns every destructive alert on this
    /// screen. Only rows for builds no live model names delete from here; live models are
    /// swipe-to-delete in the list above.
    var onDeleteRequest: (DeletableBuild) -> Void
    /// Raises the "delete everything" confirmation, also owned by the parent.
    var onClearAllRequest: () -> Void

    private let modelColors: [Color] = [.blue, .purple, .orange, .teal, .indigo, .pink]

    /// A downloaded model of any kind, flattened to what the bar and list need so the enums don't
    /// have to share a protocol.
    private struct ModelEntry: Identifiable {
        /// What this row is. Drives the tag beside the name and whether it can be deleted here.
        enum Kind { case language, image, legacy, orphaned }

        let id: String
        let name: String
        let logo: Image
        let bytes: Int64
        let kind: Kind
        let colorIndex: Int
        /// Set on `.legacy` and `.orphaned` rows only — the row's delete target.
        let build: DeletableBuild?
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
                    build: nil
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
                    build: nil
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
                    build: .superseded(build)
                ))
                idx += 1
            }
        }
        // Models the app dropped. Last in the list because they're the least explicable, and the
        // "No longer offered" tag plus the footer have to do that explaining.
        for orphan in orphans {
            result.append(ModelEntry(
                id: "orphan-" + orphan.repoID,
                name: orphan.displayName,
                logo: orphan.logoName.map { Image($0) } ?? Image(systemName: "shippingbox"),
                bytes: orphan.bytes,
                kind: .orphaned,
                colorIndex: idx,
                build: .orphaned(orphan)
            ))
            idx += 1
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
                            case .image:    tag("Pictures", color: .secondary)
                            case .legacy:   tag("Old version", color: .orange)
                            case .orphaned: tag("No longer offered", color: .orange)
                            case .language: EmptyView()
                            }
                            Spacer()
                            Text(formatBytes(entry.bytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            // These rows need their own button: the footer's "swipe a language
                            // model above" has no row up there to swipe for them.
                            if let build = entry.build {
                                Button(role: .destructive) {
                                    onDeleteRequest(build)
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    Divider()

                    // The escape hatch for "something is on my phone and I want it gone" — a
                    // single button rather than making someone delete a dozen rows one at a
                    // time. The confirmation states the total before anything happens.
                    Button(role: .destructive) {
                        onClearAllRequest()
                    } label: {
                        Label("Delete all downloaded models", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label("Storage", systemImage: "internaldrive")
        } footer: {
            Text(storageFooter)
                .font(.caption2)
        }
    }

    /// Explains only the row kinds actually on screen. The two "this can be deleted here"
    /// sentences are the ones people need and both describe something invisible to anyone who
    /// hasn't hit that case, so neither is worth saying unprompted.
    private var storageFooter: String {
        var text = "Counts every downloaded model, language and image alike. Swipe a language "
                 + "model above to delete it; the image model has its own Delete button."
        if !legacyBuilds.isEmpty {
            text += " A row marked \u{201C}Old version\u{201D} is a previous download of a model "
                  + "that has since been updated: it's never loaded again and is safe to delete here."
        }
        if !orphans.isEmpty {
            text += " A row marked \u{201C}No longer offered\u{201D} is a model this app used to "
                  + "include and no longer does. Nothing here can load it, so deleting it is free."
        }
        return text
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

// MARK: - Clear All Models Sheet

/// Confirmation for deleting every downloaded model at once.
///
/// A sheet rather than an alert because it has numbers worth showing: this is potentially ten
/// gigabytes and a long re-download, and an alert's two lines can't break that down. Same
/// discipline as ``MemoryCheckSheet`` — state what happens, then let the user decide.
struct ClearAllModelsSheet: View {
    let languageBytes: Int64
    let imageBytes: Int64
    /// Old versions and removed models, which are the bytes most people are here for.
    let reclaimableBytes: Int64
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var totalBytes: Int64 { languageBytes + imageBytes + reclaimableBytes }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: "internaldrive")
                                .font(.title)
                                .foregroundStyle(.red)
                            Text("This frees \(formatted(totalBytes)).")
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 6) {
                            if languageBytes > 0 { byteRow("Language models", languageBytes) }
                            if imageBytes > 0 { byteRow("Picture model", imageBytes) }
                            if reclaimableBytes > 0 { byteRow("Old and removed models", reclaimableBytes) }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("What that means") {
                    Label("Your decks, chats, stories and progress are untouched.", systemImage: "checkmark.shield")
                    Label("The app can't write cards, talk, or make stories until you download a model again.", systemImage: "xmark.circle")
                    Label("Downloading again needs a connection, and the largest tutor is about 5 GB.", systemImage: "arrow.down.circle")
                }
                .font(.subheadline)

                Section {
                    Button(role: .destructive) {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Delete All Models")
                            .frame(maxWidth: .infinity)
                    }

                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Delete every model?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func byteRow(_ label: String, _ bytes: Int64) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatted(bytes))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ bytes: Int64) -> String {
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
