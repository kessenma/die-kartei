import Foundation
import SwiftUI

enum ValidationStatus: Equatable {
    /// Word found in dictionary, gender matches (if noun)
    case verified
    /// Word found but article/gender is wrong; `expected` is the correct article (der/die/das)
    case genderMismatch(expected: String)
    /// Word not found in dictionary
    case notFound
    /// Validation was not run or not applicable
    case unchecked

    var badgeLabel: String? {
        switch self {
        case .verified: return "Verified"
        case .genderMismatch(let expected): return "Should be \(expected)"
        case .notFound: return "Not in dictionary"
        case .unchecked: return nil
        }
    }

    var badgeSystemImage: String? {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .genderMismatch: return "exclamationmark.triangle.fill"
        case .notFound: return "questionmark.circle"
        case .unchecked: return nil
        }
    }

    var badgeColor: Color? {
        switch self {
        case .verified: return .green
        case .genderMismatch: return .orange
        case .notFound: return .secondary
        case .unchecked: return nil
        }
    }

    var badgeBackgroundColor: Color? {
        switch self {
        case .verified: return Color.green.opacity(0.15)
        case .genderMismatch: return Color.orange.opacity(0.15)
        case .notFound: return Color.gray.opacity(0.15)
        case .unchecked: return nil
        }
    }

    /// Whether the user can tap the badge to open a correction sheet.
    var isCorrectable: Bool {
        switch self {
        case .genderMismatch, .notFound: return true
        default: return false
        }
    }
}

struct ValidationResult: Equatable {
    let germanWord: String
    var status: ValidationStatus
    /// The primary English translation from the dictionary, if found
    let dictionaryTranslation: String?

    var isVerified: Bool {
        status == .verified
    }
}
