import SwiftUI

/// The inline loading detail shown while a model downloads / loads into memory: a status line,
/// a progress bar (determinate when we have a real fraction, indeterminate otherwise), elapsed
/// time + byte counts, and a Cancel button. Reads live state straight from the shared
/// `MLXGenerationService`, so every screen that shows it (Home, Settings) stays in lock-step.
struct ModelLoadingPanel: View {
    var mlxService: MLXGenerationService

    /// When true, prefixes the panel with the loading model's brand ring + status as a heading.
    /// Used in Settings, where there's no separate model button above the panel to anchor it.
    var showsHeader: Bool = false
    /// The model whose ring is shown in the header (the one currently loading).
    var headerModel: MLXModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader, let headerModel {
                HStack(spacing: 10) {
                    ModelLoadingIndicator(model: headerModel, progress: mlxService.downloadProgress, size: 30)
                    Text(mlxService.downloadInfo ?? "Loading model…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(mlxService.downloadInfo ?? "Loading model…")
                    .font(.caption)
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
    }

    private func elapsedString(since start: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
