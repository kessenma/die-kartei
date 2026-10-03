import SwiftUI

/// "Pictures stopped" / "Some pictures are missing", with the one fix that helps. Shown at the top
/// of a deck's start screen and a story, for the deck or story the run belonged to. Deliberately
/// not gated on the picture source being ready: a revoked key disconnects the account, and that
/// is exactly when this needs to stay on screen.
struct PictureRunReportBanner: View {
    let report: PictureRunReport
    /// What a retry is called on this screen ("Illustrate this deck"), or nil where there's no
    /// retry, which is the case for stories.
    var retryHint: String?
    var onDismiss: () -> Void

    @State private var showingAccount = false
    @Environment(\.appTheme) private var appTheme

    private var stopped: Bool { report.stopReason != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: stopped ? "exclamationmark.triangle.fill" : "photo.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(stopped ? "Pictures stopped" : "Some pictures are missing")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let fix = report.fix {
                fixButton(fix)
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
        .sheet(isPresented: $showingAccount) {
            CloudAccountSheet()
        }
    }

    private var lines: [String] {
        var lines: [String] = []
        if report.total > 0, report.drawn < report.total {
            lines.append("\(report.drawn) of \(report.total) pictures were drawn.")
        }
        if let reason = report.stopReason {
            lines.append(reason)
        }
        if report.skipped > 0 {
            let pictures = report.skipped == 1 ? "1 picture couldn't" : "\(report.skipped) pictures couldn't"
            var line = "\(pictures) be drawn: the model declined it or the service failed."
            if let retryHint { line += " Tap \u{201C}\(retryHint)\u{201D} to try those cards again." }
            lines.append(line)
        } else if stopped, let retryHint, report.drawn < report.total {
            lines.append("Once that's sorted, tap \u{201C}\(retryHint)\u{201D} to draw the rest.")
        }
        return lines
    }

    @ViewBuilder
    private func fixButton(_ fix: PictureRunReport.Fix) -> some View {
        switch fix {
        case .addCredit:
            Link(destination: URL(string: "https://openrouter.ai/settings/credits")!) {
                Label("Add credit on OpenRouter", systemImage: "creditcard")
            }
        case .raiseKeyLimit:
            Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                Label("Raise the key's limit on OpenRouter", systemImage: "arrow.up.right.square")
            }
        case .confirmAge:
            Link(destination: CloudImageModel.museImage.openRouterPage) {
                Label("Open the Muse page", systemImage: "checkmark.shield")
            }
        case .reconnect:
            Button {
                showingAccount = true
            } label: {
                Label("Reconnect OpenRouter", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }
    }
}

/// The cloud account rows in a sheet of their own, so "Reconnect" works from wherever the banner
/// is — a deck opens full screen, out of reach of Settings.
struct CloudAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CloudPicturesRows()
                }
            }
            .navigationTitle("OpenRouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
