import Foundation

// Moved out of ChatConversation.swift (SwiftData) so the shared core and the Android app can use
// it: chat turns, the turn normalizer and the tutor engines all speak in it.

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}
