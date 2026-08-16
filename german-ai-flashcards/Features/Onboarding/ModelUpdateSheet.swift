import SwiftUI

/// "Your tutor has been retrained." Shown once at launch to the only people it can possibly
/// concern — those with the retired build still in the hub cache — and reachable afterwards from
/// Settings → Model, both on the tutor card and in Storage.
///
/// Deliberately three answers, not two. Getting the update is the point, but the other two exist
/// because this is the user's storage and the user's data plan: someone on a train can take the
/// gigabytes back today and download the new build tonight, and someone who wants neither can say
/// so once and never be asked at launch again.
///
/// Nothing is deleted until a button is pressed, and the delete always lands *before* the download,
/// so nobody ever needs room for two copies of a 5 GB model at once.
///
/// Takes its row as a parameter rather than reaching for `.hero`, so the next retrain — of this
/// model or any other — reuses it with no edit. See ``ModelSupersession``.
struct ModelUpdateSheet: View {
    let supersession: ModelSupersession
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Lets a presenting screen refresh its cache-derived labels after a delete. No-op at launch,
    /// where nothing on screen is reading the cache yet.
    var onChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    /// Measured once when the sheet appears. Walking a repo directory is cheap but it is still file
    /// I/O, and reading it from `body` would repeat it on every re-render.
    @State private var reclaimBytes: Int64?

    private var model: MLXModel { supersession.model }

    /// Whether offering the download here makes sense. Someone running the big tutor on a phone
    /// that struggles with it is the person most motivated to take 5 GB back and the last person to
    /// push a fresh 5 GB download at, so those devices get the reclaim action alone.
    private var canOfferUpdate: Bool {
        model.isHero ? DeviceCapability.mayRunHero : DeviceCapability.canRun(model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    improvements
                    storageNote
                }
                .padding()
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .background { ModelSheetBackground(model: model) }
            .navigationTitle("A new version of your tutor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { reclaimBytes = supersession.reclaimableBytes }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            // A frosted chip so the brand logo lifts off the brand wash behind it.
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle().strokeBorder(model.theme.accent.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: model.theme.accent.opacity(0.25), radius: 14, y: 6)
                model.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)

            Text(model.rawValue)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(supersession.whatChanged)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var improvements: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(supersession.improvements, id: \.self) { point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(model.theme.accent)
                        .font(.body)
                    Text(point)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))
    }

    private var storageNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("The old copy is still on this iPhone")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(sizeText) of it. The update is about the same size, and the old copy comes "
                     + "off first, so you never need room for both at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if canOfferUpdate {
                Button {
                    updateNow()
                } label: {
                    Text("Free up \(sizeText) and get the update")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.theme.accent)

                Button("Just free up the space", role: .destructive) { deleteOnly() }
                    .font(.subheadline)
            } else {
                Button {
                    deleteOnly()
                } label: {
                    Text("Free up \(sizeText)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Button("Not now") { dismiss() }
                .font(.subheadline)
        }
        .padding()
        .background(.bar)
        // Both actions unload the model, and `unloadModel()`/`loadModel(_:)` both no-op while a
        // load is in flight, so don't offer them mid-download.
        .disabled(mlxService.isLoading)
    }

    // MARK: - Actions

    /// Reclaim the retired build, then fetch its replacement. Order matters. The download runs
    /// through the same `loadModel` path as every other model in the app, so progress lands in the
    /// nav bar, on Home and in Settings with no new plumbing.
    private func updateNow() {
        reclaimLegacyBuild()
        modelManager.selectedMLXModel = model
        dismiss()
        Task { await mlxService.loadModel(model) }
    }

    /// Reclaim and stop there. Every feature pinned to this model already knows how to ask for the
    /// download when it isn't there (the story setup screen, the queue sheets, the model pickers),
    /// so nothing breaks — it just asks later, on a screen where the learner wanted it anyway.
    private func deleteOnly() {
        reclaimLegacyBuild()
        dismiss()
    }

    private func reclaimLegacyBuild() {
        try? supersession.delete()
        // The weights in memory are the *old* ones: the container was built from the directory just
        // removed. Drop it, or the app keeps generating from the retired build out of RAM until the
        // process happens to die, and every screen reading `isDownloaded` disagrees with every
        // screen reading `isModelLoaded`.
        //
        // Deliberately NOT `mlxService.deleteModel(model)` — that deletes
        // `model.configuration.name`, which is now the *new* repo.
        if mlxService.currentModel == model { mlxService.unloadModel() }
        onChange()
    }

    /// The measured figure once `.task` has run, and the model's nominal download size until then,
    /// so the button never renders with a blank or a zero.
    private var sizeText: String {
        ByteCountFormatter.string(
            fromByteCount: reclaimBytes ?? Int64(model.approximateSizeMB) * 1_000_000,
            countStyle: .file
        )
    }
}

#Preview("Update available") {
    ModelUpdateSheet(
        supersession: ModelSupersession.all[0],
        modelManager: MLXModelManager(),
        mlxService: MLXGenerationService()
    )
}
