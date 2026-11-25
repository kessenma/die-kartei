//
//  ConversationListFilterBar.swift
//  german-ai-flashcards
//
//  The conversation library's pill strip. Shares `FilterPill` with the story library and the
//  placement review but keeps its own strip, the way each of those screens does: the pills speak
//  this screen's vocabulary (conversation types, employers), not a generic one.
//

import SwiftUI

// MARK: - Filter state

/// The conversation library's browse filters. Every field nil means "show everything", so a fresh
/// `ConversationListFilter()` is the whole library.
struct ConversationListFilter: Equatable {
    var mode: ConversationMode?
    /// Employer, matched case-insensitively against `ChatConversation.jobCompany`. Only interview
    /// chats carry one, so a company alone already narrows the list to interviews.
    var company: String?

    var isActive: Bool { mode != nil || company != nil }

    func matches(_ conversation: ChatConversation) -> Bool {
        if let mode, conversation.mode != mode { return false }
        if let company {
            guard let theirs = conversation.jobCompany, Self.sameCompany(theirs, company) else { return false }
        }
        return true
    }

    static func sameCompany(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }

    static func normalized(_ company: String) -> String {
        company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension ConversationMode {
    /// How the mode reads on a library pill and row. Interviews say "Interview prep" so the pill
    /// and the row it narrows to use the same words.
    var libraryLabel: String {
        self == .interview ? "Interview prep" : rawValue
    }
}

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
                        set {
                            $0.mode = $0.mode == mode ? nil : mode
                            // An employer only narrows interviews; drop it under any other type.
                            if let chosen = $0.mode, chosen != .interview { $0.company = nil }
                        }
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
                            set {
                                if let current = $0.company, ConversationListFilter.sameCompany(current, company) {
                                    $0.company = nil
                                } else {
                                    $0.company = company
                                    $0.mode = .interview
                                }
                            }
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
