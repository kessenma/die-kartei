//
//  ConversationListFilterBar.swift
//  german-ai-flashcards
//
//  The conversation library's pill strip. Shares `FilterPill` with the story library and the
//  placement review but keeps its own strip, the way each of those screens does: the pills speak
//  this screen's vocabulary (conversation types, employers), not a generic one.
//

import SwiftUI

// The filter itself is `ConversationListFilter` (Models/ConversationListFilter.swift), shared with Android.

// MARK: - Filter bar

/// Conversation types on one line, employers (when any interview chat names one) on the next.
/// Only the types and employers the library actually holds get a pill, so no pill can lead to an
/// empty list on its own. A selected pill carries an ✕ and clears itself on the next tap.
struct ConversationFilterBar: View {
    @Binding var filter: ConversationListFilter
    /// Types present in the library, in `ConversationMode.allCases` order.
    let modes: [ConversationMode]
    /// Employers present among the interview chats, most frequent first.
    let companies: [String]

    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme

    private var accent: Color { appTheme.accent(model: modelTheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            strip {
                ForEach(modes) { mode in
                    FilterPill(
                        label: mode.libraryLabel,
                        systemImage: mode.systemImage,
                        tint: accent,
                        isOn: filter.mode == mode
                    ) {
                        set { $0 = $0.toggling(mode: mode) }
                    }
                }
            }

            if !companies.isEmpty {
                strip {
                    ForEach(companies, id: \.self) { company in
                        FilterPill(
                            label: company,
                            systemImage: "building.2",
                            tint: accent,
                            isOn: filter.company.map { ConversationListFilter.sameCompany($0, company) } ?? false
                        ) {
                            set { $0 = $0.toggling(company: company) }
                        }
                    }
                }
            }
        }
    }

    /// One horizontally scrolling line of pills, inset to sit under the section header's text.
    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// Every pill mutates through here so the list rows animate in and out with the pill's own
    /// selected state.
    private func set(_ change: (inout ConversationListFilter) -> Void) {
        var updated = filter
        change(&updated)
        withAnimation(.snappy(duration: 0.25)) { filter = updated }
    }
}

extension ChatConversation: FilterableChat {}
