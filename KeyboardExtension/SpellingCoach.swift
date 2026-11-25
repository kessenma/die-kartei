import Foundation
import UIKit

/// Spelling suggestions and autocorrect, per language.
///
/// iOS does not expose the system keyboard's correction engine to third-party keyboards — there is
/// no API for it at any price. `UITextChecker` is the nearest public equivalent: it spell-checks
/// and completes words in a named language, which is enough to build a suggestion strip and
/// correct-on-space from. It is not as good as Apple's, and it has no notion of context or of the
/// word you *meant*, so it never silently rewrites a word it merely fails to recognise.
///
/// The language is explicit rather than guessed. This keyboard is used to type English and German
/// in the same message, and a wrong guess is worse than no correction at all: English autocorrect
/// turned loose on German is the exact thing that makes the system keyboard painful here.
@MainActor
final class SpellingCoach: ObservableObject {

    enum Language: String, CaseIterable, Identifiable {
        case english
        case german

        var id: String { rawValue }

        var label: String {
            switch self {
            case .english: return "English"
            case .german:  return "Deutsch"
            }
        }

        /// `UITextChecker` wants a locale identifier, and falls back to no checking at all for one
        /// it doesn't have, so the resolved list is consulted before use.
        var preferredCodes: [String] {
            switch self {
            case .english: return ["en_US", "en_GB", "en"]
            case .german:  return ["de_DE", "de_AT", "de"]
            }
        }

        var other: Language {
            self == .english ? .german : .english
        }
    }

    struct Suggestion: Identifiable, Equatable {
        let text: String
        /// True when the typed word is misspelled and this replaces it. Only a correction is ever
        /// applied automatically.
        let isCorrection: Bool
        var id: String { text }
    }

    @Published var language: Language = .english {
        didSet { if language != oldValue { suggestions = [] } }
    }
    @Published private(set) var suggestions: [Suggestion] = []

    private let checker = UITextChecker()
    private lazy var available = Set(UITextChecker.availableLanguages)

    /// Enabled by default per language; the strip's own switch flips these.
    @Published var isEnabled = true

    private var code: String? {
        language.preferredCodes.first { available.contains($0) }
    }

    // MARK: - Suggestions

    /// Recompute for the word the cursor is sitting at the end of.
    func update(for textBeforeCursor: String) {
        guard isEnabled, let code else { return suggestions = [] }
        let word = Self.trailingWord(of: textBeforeCursor)
        guard word.count >= 2 else { return suggestions = [] }

        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: code
        )

        var found: [Suggestion] = []
        if misspelled.location != NSNotFound {
            let guesses = checker.guesses(forWordRange: range, in: word, language: code) ?? []
            found = guesses.prefix(3).map { Suggestion(text: $0, isCorrection: true) }
        } else {
            let completions = checker.completions(
                forPartialWordRange: range, in: word, language: code
            ) ?? []
            // Drop the word itself — offering someone what they already typed wastes a slot.
            found = completions
                .filter { $0.caseInsensitiveCompare(word) != .orderedSame }
                .prefix(3)
                .map { Suggestion(text: $0, isCorrection: false) }
        }
        suggestions = found
    }

    func clear() {
        suggestions = []
    }

    // MARK: - Autocorrect

    /// The replacement to apply when a word is finished with space or punctuation, or nil to leave
    /// it alone. Deliberately conservative: only an outright misspelling with a first guess that
    /// isn't a wild swing, so finishing a word never silently changes a name or a loan word.
    func autocorrection(for textBeforeCursor: String) -> (word: String, replacement: String)? {
        guard isEnabled, let code else { return nil }
        let word = Self.trailingWord(of: textBeforeCursor)
        guard word.count >= 3, word.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
        // A capitalised word mid-sentence is usually a name — and in German, every noun.
        guard word == word.lowercased() else { return nil }

        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: code
        )
        guard misspelled.location != NSNotFound,
              let first = checker.guesses(forWordRange: range, in: word, language: code)?.first
        else { return nil }

        // One or two edits away. Beyond that the "correction" is a different word, and having to
        // undo it costs more than the typo did.
        guard Self.editDistance(word.lowercased(), first.lowercased()) <= 2 else { return nil }
        return (word: word, replacement: first)
    }

    // MARK: - Helpers

    /// The run of letters immediately before the cursor. Apostrophes count, so "don't" and
    /// "geht's" are one word.
    static func trailingWord(of text: String) -> String {
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "'’-"))
        var word = ""
        for character in text.reversed() {
            guard character.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { break }
            word.insert(character, at: word.startIndex)
        }
        return word
    }

    /// Levenshtein, to keep a "correction" from being a different word entirely.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
