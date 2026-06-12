import Foundation

/// Platform-neutral view of a flashcard's spaced-repetition state.
///
/// On iOS the SwiftData `SavedCard` model conforms directly; on Android any
/// class backed by the local database can conform the same way. The SRS
/// services mutate conforming objects in place, so the protocol is
/// class-constrained.
public protocol SRSCardState: AnyObject {
    var easeFactor: Double { get set }
    var interval: Int { get set }
    var repetitions: Int { get set }
    var nextReviewDate: Date? { get set }
    var totalReviews: Int { get set }
    var lapses: Int { get set }
    var leitnerBox: Int { get set }
    var sortOrder: Int { get }
}
