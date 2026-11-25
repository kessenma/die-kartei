import Foundation
import SwiftData

/// A saved list of words to sketch: the learner's own "Quick Draw deck".
///
/// It points at cards rather than copying them, so a word's pictures, schedule and article stay
/// with its card. Card ids are stable across devices (Wortschatz and other singleton cards get
/// canonical UUIDv5 ids), so a set synced to another device finds the same cards. A card that is
/// gone is skipped when the set is played.
@Model
final class QuickDrawSet {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// Encoded `[UUID]`, in the order the learner picked them.
    var cardIDsData: Data?

    init(name: String, cardIDs: [UUID] = [], createdAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.cardIDsData = try? JSONEncoder().encode(cardIDs)
    }

    var cardIDs: [UUID] {
        get { cardIDsData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? [] }
        set {
            cardIDsData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
}
