import SwiftUI

/// A model detail sheet with the brand-animated background and logo mark. Shared by the Settings
/// model list and the compact model pickers (Home / phrase library). Pass `onDelete` only where a
/// delete action makes sense (the Settings list); omit it for info-only contexts.
struct ModelInfoSheet: View {
    let model: MLXModel
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
                        if !model.isAppleIntelligence {
                            GridRow {
                                Text("Download Size")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text("~\(formattedSize(model.approximateSizeMB))")
                                    .font(.subheadline)
                            }
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
                        Label("Learn more about \(model.rawValue)", systemImage: "globe")
                    }
                }

                if isDownloaded, !model.isAppleIntelligence, let onDelete {
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
                ModelLogoMark(model: model)
            }
            .background {
                ModelSheetBackground(model: model)
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
