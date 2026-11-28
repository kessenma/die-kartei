//
//  ConversationListFilter.swift
//  german-ai-flashcards
//
//  Narrowing the saved-chats list by conversation type and employer, and which pills the list
//  offers. Foundation only and shared with the Android app (DieKarteiCore): iOS's
//  `ConversationListView` and Android's Library run the same filter over their chats.
//

import Foundation

/// What the filter reads of a saved chat: iOS's `ChatConversation`, Android's
/// `ChatConversationRecord`.
protocol FilterableChat {
    var mode: ConversationMode { get }
    var jobCompany: String? { get }
}

/// The conversation library's browse filters. Every field nil means "show everything", so a fresh
/// `ConversationListFilter()` is the whole library.
struct ConversationListFilter: Equatable {
    var mode: ConversationMode?
    /// Employer, matched case-insensitively against `ChatConversation.jobCompany`. Only interview
    /// chats carry one, so a company alone already narrows the list to interviews.
    var company: String?

    var isActive: Bool { mode != nil || company != nil }

    func matches<C: FilterableChat>(_ conversation: C) -> Bool {
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

extension ConversationListFilter {
    /// The type pill tapped: on, or off again; an employer only narrows interviews, so it goes
    /// under any other type.
    func toggling(mode: ConversationMode) -> ConversationListFilter {
        var f = self
        f.mode = f.mode == mode ? nil : mode
        if let chosen = f.mode, chosen != .interview { f.company = nil }
        return f
    }

    /// An employer pill tapped: on (which means interviews), or off again.
    func toggling(company: String) -> ConversationListFilter {
        var f = self
        if let current = f.company, Self.sameCompany(current, company) {
            f.company = nil
        } else {
            f.company = company
            f.mode = .interview
        }
        return f
    }

    /// Conversation types the library holds, in declaration order.
    static func presentModes<C: FilterableChat>(_ chats: [C]) -> [ConversationMode] {
        let present = Set(chats.map(\.mode))
        return ConversationMode.allCases.filter { present.contains($0) }
    }

    /// Employers among the interview chats, most frequent first, one spelling per company.
    static func presentCompanies<C: FilterableChat>(_ chats: [C]) -> [String] {
        var counts: [String: (label: String, count: Int)] = [:]
        for chat in chats where chat.mode == .interview {
            guard let company = chat.jobCompany?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !company.isEmpty else { continue }
            counts[normalized(company), default: (company, 0)].count += 1
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
            .prefix(10)
            .map(\.label)
    }
}

extension ChatConversationRecord: FilterableChat {
    var mode: ConversationMode { setup.mode }
}
