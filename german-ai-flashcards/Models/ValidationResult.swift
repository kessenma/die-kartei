import Foundation
import SwiftUI

/// Where a noun's gender came from when the app decided a card's article was wrong.
/// Surfaced in the review sheet so a correction is never unexplained.
enum GenderSource: Equatable {
    /// Straight hit in the bundled Wiktionary data.
    case dictionary
    /// The word wasn't in the dictionary, but its final component was. German compounds
    /// take the gender of their last element — `Wohnzimmertisch` → `Tisch` → der.
    case compound(head: String)
    /// Resolved by a derivational ending with a near-certain gender (`-ung` → die).
    case suffix(String)

    /// Short human explanation, shown under the corrected word.
    var explanation: String {
        switch self {
        case .dictionary:
            return "Dictionary entry"
        case .compound(let head):
            return "Compound of \u{201C}\(head.capitalized)\u{201D}"
        case .suffix(let ending):
            return "Words ending in -\(ending)"
        }
    }

    var systemImage: String {
        switch self {
        case .dictionary: return "book.closed"
        case .compound: return "square.split.2x1"
        case .suffix: return "textformat.abc"
        }
    }
}

enum ValidationStatus: Equatable {
    /// Word found in dictionary, gender matches (if noun).
    case verified
    /// The card's article disagreed with a confident source and was corrected on the spot.
    /// `from` is nil when the model gave no article at all.
    case autoCorrected(from: String?, to: String, source: GenderSource)
    /// The dictionary records more than one valid gender and the card picked one of them
    /// (`der`/`das Meter`). Not a problem — worth knowing, not worth fixing.
    case ambiguous(options: [String])
    /// Word found but article/gender is wrong; `expected` is the correct article (der/die/das).
    case genderMismatch(expected: String)
    /// Not in the dictionary and no rule could resolve it — the only case that needs a human.
    case notFound
    /// Validation was not run or not applicable.
    case unchecked

    var badgeLabel: String? {
        switch self {
        // A corrected card *is* correct now; the correction is reported in the deck summary
        // rather than on the card, so studying isn't interrupted by resolved problems.
        case .verified, .autoCorrected: return "Verified"
        case .ambiguous(let options): return options.joined(separator: "/")
        case .genderMismatch(let expected): return "Should be \(expected)"
        case .notFound: return "Not in dictionary"
        case .unchecked: return nil
        }
    }

    var badgeSystemImage: String? {
        switch self {
        case .verified, .autoCorrected: return "checkmark.seal.fill"
        case .ambiguous: return "info.circle"
        case .genderMismatch: return "exclamationmark.triangle.fill"
        case .notFound: return "questionmark.circle"
        case .unchecked: return nil
        }
    }

    var badgeColor: Color? {
        switch self {
        case .verified, .autoCorrected: return .green
        case .ambiguous: return .blue
        case .genderMismatch: return .orange
        case .notFound: return .secondary
        case .unchecked: return nil
        }
    }

    var badgeBackgroundColor: Color? {
        switch self {
        case .verified, .autoCorrected: return Color.green.opacity(0.15)
        case .ambiguous: return Color.blue.opacity(0.15)
        case .genderMismatch: return Color.orange.opacity(0.15)
        case .notFound: return Color.gray.opacity(0.15)
        case .unchecked: return nil
        }
    }

    /// Whether the user can tap the badge to open a correction sheet. Only the cases the app
    /// genuinely can't settle on its own qualify.
    var isCorrectable: Bool {
        switch self {
        case .genderMismatch, .notFound: return true
        default: return false
        }
    }

    /// Cases that belong in the "needs your input" section of the review sheet.
    var needsAttention: Bool { isCorrectable }

    var wasAutoCorrected: Bool {
        if case .autoCorrected = self { return true }
        return false
    }
}

struct ValidationResult: Equatable {
    let germanWord: String
    var status: ValidationStatus
    /// The primary English translation from the dictionary, if found
    let dictionaryTranslation: String?

    var isVerified: Bool {
        switch status {
        case .verified, .autoCorrected, .ambiguous: return true
        default: return false
        }
    }
}

/// One silently-applied article fix, kept so the deck summary can report "3 articles corrected"
/// and the review sheet can undo any of them.
struct AutoCorrection: Identifiable, Equatable {
    /// Index into the validated card array.
    let index: Int
    let germanWord: String
    let englishTranslation: String
    /// The article the model produced, or nil if it gave none.
    let from: String?
    let to: String
    let source: GenderSource

    var id: Int { index }
}

/// The result of validating a set of cards: the cards with their articles already fixed,
/// the per-card status, and a record of what changed.
struct ValidationOutcome {
    var cards: [VocabCard]
    var results: [ValidationResult]
    var corrections: [AutoCorrection]

    /// Cards the app could not settle on its own.
    var needsAttentionCount: Int {
        results.filter { $0.status.needsAttention }.count
    }

    var verifiedCount: Int {
        results.filter { $0.isVerified }.count
    }

    static let empty = ValidationOutcome(cards: [], results: [], corrections: [])
}
