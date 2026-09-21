import PDFKit
import SwiftUI

/// The posting an interview chat was started from, for re-reading mid-conversation: employer,
/// location, a link back to the page, and the text the recruiter is working from. Read-only.
struct JobPostingSheet: View {
    let config: ConversationConfig
    @Environment(\.dismiss) private var dismiss

    private var company: String? { nonEmpty(config.jobCompany) }
    private var location: String? { nonEmpty(config.jobLocation) }
    private var postingURL: URL? { nonEmpty(config.jobURL).flatMap { URL(string: $0) } }
    private var hasDetails: Bool {
        company != nil || location != nil || postingURL != nil
            || config.interviewRound != nil || config.interviewFormat != nil
    }
    /// The PDF copy saved when the posting was brought over, if it is still on disk.
    private var snapshotURL: URL? {
        guard let file = config.jobSnapshotFile, JobPostingSnapshotStore.exists(file) else { return nil }
        return JobPostingSnapshotStore.url(for: file)
    }

    var body: some View {
        NavigationStack {
            List {
                if hasDetails {
                    Section {
                        if let round = config.interviewRound {
                            LabeledContent("Round") {
                                Label(round.label, systemImage: round.systemImage)
                            }
                        }
                        if let format = config.interviewFormat {
                            LabeledContent("Format") {
                                Label(format.label, systemImage: format.systemImage)
                            }
                        }
                        if let company {
                            LabeledContent("Company", value: company)
                        }
                        if let location {
                            LabeledContent("Location", value: location)
                        }
                        if let postingURL {
                            Link(destination: postingURL) {
                                Label("Open the posting", systemImage: "safari")
                            }
                        }
                    } header: {
                        Text("Details").themedSectionHeader()
                    }
                    .themedListRow()
                }

                if let snapshotURL {
                    Section {
                        NavigationLink {
                            JobPostingPDFScreen(url: snapshotURL, title: config.jobTitle ?? "Job posting")
                        } label: {
                            Label("Open the saved copy", systemImage: "doc.richtext")
                        }
                        ShareLink(item: snapshotURL) {
                            Label("Share the PDF", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("Saved copy").themedSectionHeader()
                    } footer: {
                        Text("The whole page as it looked when you brought it over, kept with this chat so it stays readable if the posting goes offline.")
                    }
                    .themedListRow()
                }

                Section {
                    if let text = nonEmpty(config.jobContext) {
                        Text(text)
                            .font(.callout)
                            .textSelection(.enabled)
                    } else {
                        Text("No posting text was saved with this chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("What the recruiter is reading").themedSectionHeader()
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle(config.jobTitle ?? "Job posting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Full-screen reader for the saved PDF copy, with a share button.
private struct JobPostingPDFScreen: View {
    let url: URL
    let title: String

    var body: some View {
        PDFKitView(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
