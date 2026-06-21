import SwiftUI

/// A compact model selector: one row showing the bound model and its load state; tapping opens a
/// sheet of downloaded models to pick and load. Shared across the app (Home, the phrase library,
/// and anywhere a model needs choosing) so the picker looks and behaves identically everywhere.
///
/// Drives the `selection` binding — `selectedMLXModel` on Home, `selectedChatModel` for conversation
/// features — and loads the chosen model immediately. Renders `Section`s, so drop it in at the top
/// of a `Form`.
struct ModelPickerButton: View {
    @Binding var selection: MLXModel
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Optional explanatory footer shown under the model row.
    var footer: String? = nil
    /// When non-nil, the **host** owns the picker-sheet presentation and must itself attach
    /// `.sheet(isPresented:) { ModelPickerSheet(...) }` to a stable container (its `NavigationStack`/
    /// `Form` root). Required whenever this button lives inside another sheet.
    ///
    /// Why: a `.sheet` attached to a `Section` inside a `Form`/`List` is realized multiple times as the
    /// list builds its cells, so opening it fires several presentations at the same hosting controller
    /// ("Attempt to present … which is already presenting …"). Harmless-looking at the top level, but
    /// inside another sheet the collision tears the whole stack down. Hosting the sheet on a single
    /// stable view avoids the duplicate presentation. When nil, the button self-presents — fine for
    /// top-level screens like Home that aren't nested in a sheet.
    var present: Binding<Bool>? = nil

    @State private var ownShowing = false

    private var isReady: Bool { mlxService.isModelLoaded && mlxService.currentModel == selection }
    /// The host's binding when provided, otherwise our own.
    private var showing: Binding<Bool> { present ?? $ownShowing }

    var body: some View {
        Section {
            Button { showing.wrappedValue = true } label: { row }
                .disabled(mlxService.isLoading)

            // Inline loading progress — shared with Settings so it animates identically.
            if mlxService.isLoading {
                ModelLoadingPanel(mlxService: mlxService)
            }
        } header: {
            Label("Model", systemImage: "cpu")
        } footer: {
            if let footer {
                Text(footer).font(.caption2)
            }
        }
        // Self-present only when the host hasn't taken over. When `present` is provided the host
        // attaches its own `.sheet` to a stable anchor, so this one stays inert (never opens).
        .sheet(isPresented: present == nil ? $ownShowing : .constant(false)) {
            ModelPickerSheet(selection: $selection, modelManager: modelManager, mlxService: mlxService)
        }

        if let error = mlxService.loadError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var row: some View {
        HStack {
            if mlxService.isLoading {
                ModelLoadingIndicator(model: selection, progress: mlxService.downloadProgress, size: 30)
            } else {
                selection.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selection.rawValue).foregroundStyle(.primary)
                status
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var status: some View {
        if mlxService.isLoading {
            if let p = mlxService.downloadProgress, p > 0 {
                Text("Loading… \(Int(p * 100))%").font(.caption).foregroundStyle(.orange)
            } else {
                Text("Loading…").font(.caption).foregroundStyle(.orange)
            }
        } else if isReady {
            Text("Ready").font(.caption).foregroundStyle(.green)
        } else {
            Text("Not loaded").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The model-picker sheet body — a list of downloaded models with a medium detent, each row tappable
/// to pick (sets the binding, dismisses, loads) with an info button opening `ModelInfoSheet`.
///
/// Extracted from `ModelPickerButton` so it can be presented either by the button itself (top-level
/// screens) or by a host that must own the presentation because the picker has to be anchored above a
/// `Form`/sheet (see `ModelPickerButton.present`).
struct ModelPickerSheet: View {
    @Binding var selection: MLXModel
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.dismiss) private var dismiss
    /// The model whose detail sheet is open. Presented over the picker (a second, nested sheet). Its
    /// `.sheet` is attached to the `List` container — a single instance, so it doesn't hit the
    /// duplicate-presentation trap that a `Section`-level `.sheet` would.
    @State private var modelForInfo: MLXModel?

    var body: some View {
        let downloaded = MLXModel.allCases.filter { $0.isDownloaded }
        let lastLoaded = modelManager.lastLoadedModel

        NavigationStack {
            List {
                Section {
                    if downloaded.isEmpty {
                        Label("No models downloaded yet. Go to Settings → Model to download one.", systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(downloaded) { model in
                            modelRow(model, lastLoaded: lastLoaded)
                        }
                    }
                } header: {
                    Text("MLX Models")
                } footer: {
                    Text("Download more models in Settings → Model.")
                }
            }
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // A second sheet presented over the picker — info-only (no delete here).
            .sheet(item: $modelForInfo) { model in
                ModelInfoSheet(model: model)
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder private func modelRow(_ model: MLXModel, lastLoaded: MLXModel?) -> some View {
        let active = mlxService.isModelLoaded && mlxService.currentModel == model
        let lastUsed = lastLoaded == model && !active

        HStack(spacing: 0) {
            Button {
                pick(model)
            } label: {
                HStack {
                    model.logoImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.rawValue).foregroundStyle(.primary)
                            if lastUsed { lastUsedTag }
                        }
                        Text("~\(formattedSize(model.approximateSizeMB))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model == selection {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

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
    }

    private var lastUsedTag: some View {
        Text("Last used")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
    }

    /// Sets the binding, dismisses the picker, then loads the chosen model. The load (and its
    /// `isLoading` re-render) happens after dismissal begins, so it can't disturb the picker transition.
    private func pick(_ model: MLXModel) {
        selection = model
        let needsLoad = !(mlxService.isModelLoaded && mlxService.currentModel == model)
        dismiss()
        guard needsLoad else { return }
        Task {
            await mlxService.loadModel(model)
            if mlxService.isModelLoaded, mlxService.currentModel == model {
                modelManager.lastLoadedModel = model
            }
        }
    }

    private func formattedSize(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000.0) : "\(mb) MB"
    }
}
