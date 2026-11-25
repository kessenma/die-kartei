import SwiftUI

/// Release notes: the current version expanded, everything older folded into accordions.
///
/// Pushed from Settings ▸ About with its own header, or wrapped by `WhatsNewSheet` at launch where
/// the navigation title carries the name instead. Content comes from `WhatsNew.releases`; see
/// `WhatsNewService.swift` and `/CLAUDE.md` for how entries get there.
struct WhatsNewView: View {
    /// The release to show open. Nil falls back to the newest entry, so the screen is never empty
    /// just because a build's own version has no notes.
    var current: WhatsNewRelease?
    var showsHeader = true

    private var expanded: WhatsNewRelease? { current ?? WhatsNew.releases.first }
    private var earlier: [WhatsNewRelease] {
        WhatsNew.releases.filter { $0.id != expanded?.id }
    }

    var body: some View {
        List {
            if showsHeader {
                SettingsHeader(icon: "sparkles", title: "What's New")
            }

            if let expanded {
                Section {
                    ForEach(expanded.highlights) { highlight in
                        HighlightRow(highlight: highlight)
                    }
                } header: {
                    Text(expanded.isUnreleased
                         ? "In Arbeit · In progress"
                         : "Neu in \(expanded.version) · New in this version")
                        .themedSectionHeader()
                } footer: {
                    if let date = expanded.displayDate {
                        Text(date)
                    }
                }
                .themedListRow()
            }

            if !earlier.isEmpty {
                Section {
                    ForEach(earlier) { release in
                        DisclosureGroup {
                            ForEach(release.highlights) { highlight in
                                HighlightRow(highlight: highlight)
                            }
                        } label: {
                            HStack {
                                Text(release.displayTitle)
                                    .fontWeight(.semibold)
                                Spacer()
                                if let date = release.displayDate {
                                    Text(date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Früher · Earlier versions")
                        .themedSectionHeader()
                }
                .themedListRow()
            }

            if WhatsNew.releases.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "sparkles")
                    .listRowBackground(Color.clear)
            }
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Symbol + title + optional one-line detail. Same layout as the badge rows in
/// `ValidationInfoSheet`, so the two info screens read alike.
private struct HighlightRow: View {
    let highlight: WhatsNewHighlight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: highlight.resolvedSymbol)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let detail = highlight.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The launch presentation: the same list under a Done button.
struct WhatsNewSheet: View {
    let current: WhatsNewRelease
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WhatsNewView(current: current, showsHeader: false)
                .navigationTitle("Neu · What's New")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#Preview("Pushed") {
    NavigationStack {
        WhatsNewView(current: WhatsNew.current)
    }
}

#Preview("Sheet") {
    if let first = WhatsNew.releases.first {
        WhatsNewSheet(current: first)
    }
}
