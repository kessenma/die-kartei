import SwiftUI
import SwiftData

/// The end-of-session coaching report: stats, strengths, areas to improve, a recurring
/// pattern, vocabulary used, and a one-tap "build a flashcard deck" action.
struct ConversationSummaryView: View {
    let conversation: ChatConversation
    let summary: ConversationSummary
    var mlxService: MLXGenerationService?
    var modelManager: MLXModelManager?
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                statsSection

                if !summary.strengths.isEmpty {
                    section("What you did well", systemImage: "hand.thumbsup.fill", tint: .green, items: summary.strengths)
                }
                if !summary.improvements.isEmpty {
                    section("Room to improve", systemImage: "arrow.up.forward.circle.fill", tint: .orange, items: summary.improvements)
                }
                if !summary.patternNote.isEmpty {
                    Section("Pattern noticed") {
                        Text(summary.patternNote).font(.callout)
                    }
                }
                if let raw = summary.rawText, summary.strengths.isEmpty, summary.improvements.isEmpty {
                    Section("Coach's notes") {
                        Text(raw).font(.callout)
                    }
                }

                if !summary.wordsPracticed.isEmpty {
                    Section("Vocabulary you used") {
                        FlowChips(items: summary.wordsPracticed)
                    }
                }

                if !conversation.savedVocab.isEmpty {
                    Section {
                        ForEach(conversation.savedVocab) { item in
                            HStack {
                                Text(item.german)
                                Spacer()
                                Text(item.english).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    } header: {
                        Label("Words you saved (\(conversation.savedVocab.count))", systemImage: "bookmark.fill")
                    } footer: {
                        Text("Add these to a deck below.")
                            .font(.caption2)
                    }
                }

                deckSection
            }
            .navigationTitle("Your report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
    }

    // MARK: - Sections

    private var statItems: [(value: String, label: String)] {
        [
            ("\(summary.turnCount)", "Your turns"),
            (conversation.durationLabel, "Duration"),
            ("\(summary.correctionCount)", "Corrections"),
            ("\(summary.hintsUsed ?? 0)", "Hints used"),
            ("\(summary.translationsUsed ?? 0)", "Translations"),
            ("\(summary.phraseHelperUsed ?? 0)", "Phrase helps"),
        ]
    }

    private var statsSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ForEach(Array(statItems.enumerated()), id: \.offset) { _, item in
                    stat(value: item.value, label: item.label)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(conversation.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func section(_ title: String, systemImage: String, tint: Color, items: [String]) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: systemImage).foregroundStyle(tint).font(.caption)
                        .padding(.top, 3)
                    Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text(title)
        }
    }

    @ViewBuilder private var deckSection: some View {
        Section {
            NavigationLink {
                ReviewDeckView(
                    conversation: conversation,
                    mlxService: mlxService,
                    modelManager: modelManager
                )
            } label: {
                Label("Build a flashcard deck from this chat", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(mlxService == nil)
        } footer: {
            Text("Pick which words to keep and how many, then start a new deck or merge them into one you already have.")
                .font(.caption2)
        }
    }
}

// MARK: - Simple wrapping chips

struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlexibleWrap(items: items) { item in
            Text(item)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
    }
}

/// Minimal flow layout that wraps chips onto multiple lines.
struct FlexibleWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

/// A tiny Layout that arranges subviews left-to-right and wraps to new rows.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
