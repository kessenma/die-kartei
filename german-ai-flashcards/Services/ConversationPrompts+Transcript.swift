import Foundation

// The SwiftData side of `ConversationPrompts.transcript`. Kept apart so ConversationPrompts.swift
// itself stays Foundation-only and builds for Android too.
extension ConversationPrompts {
    static func transcript(from messages: [ChatMessage]) -> String {
        transcript(lines: messages.map { (sortOrder: $0.sortOrder, isUser: $0.isUser, text: $0.text) })
    }
}
