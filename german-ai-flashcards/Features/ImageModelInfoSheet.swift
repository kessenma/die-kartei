import SwiftUI

/// The detail sheet for the image-generation model — the twin of `ModelInfoSheet`, which is typed
/// to `MLXModel` and can't be reused directly. Same shape and same brand background so the two
/// model cards read as one family; the logo is an SF Symbol because there's no Stability asset.
struct ImageModelInfoSheet: View {
    let model: ImageGenModel
    /// Pass only where deleting makes sense (the Settings row); omit for info-only contexts.
    var onDelete: (() -> Void)? = nil

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
                    Text(model.modelDescription)
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
                            Text("Output")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(model.outputResolution)
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
                    if let repoURL = model.huggingFaceRepoURL {
                        Link(destination: repoURL) {
                            Label("View on HuggingFace", systemImage: "arrow.up.right.square")
                        }
                    }
                    Link(destination: model.promoPageURL) {
                        Label("How Apple runs Stable Diffusion on-device", systemImage: "globe")
                    }
                }

                if isDownloaded, let onDelete {
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
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                logoMark
            }
            .background {
                ModelSheetBackground(theme: model.theme)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        model.logoImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(model.displayName)
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The `ModelLogoMark` treatment, drawn locally (that view is typed to `MLXModel`): the model's
    /// gradient tile logo floated over the brand background, like the LLM sheets.
    private var logoMark: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            model.logoImage
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .accessibilityElement()
        .accessibilityLabel("\(model.displayName) logo")
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
