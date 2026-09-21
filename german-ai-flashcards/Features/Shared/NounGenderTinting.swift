import Foundation

/// Finds nouns in a German text whose gender the dictionary knows unambiguously, and returns
/// their UTF-16 ranges + genders so chat bubbles can tint them der/die/das.
///
/// Two gates keep the case-insensitive dictionary honest:
/// - only capitalized surface words qualify (German nouns are capitalized; "gut" must never
///   come back as "das Gut"), and
/// - sentence-initial words are skipped, since anything is capitalized there.
///
/// Main-actor only — `WiktionaryValidator` is not thread-safe. Results are cached per message
/// (chat texts are immutable), so each message costs one dictionary pass ever.
@MainActor
enum NounGenderTinter {
    private static var cache: [UUID: [(range: NSRange, gender: Gender)]] = [:]

    static func tints(for text: String, messageID: UUID) -> [(range: NSRange, gender: Gender)] {
        if let hit = cache[messageID] { return hit }
        var found: [(range: NSRange, gender: Gender)] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byWords, .localized]) { word, range, _, _ in
            guard let word, word.first?.isUppercase == true,
                  !isSentenceInitial(range, in: ns),
                  let hit = WiktionaryValidator.shared.nounArticle(for: word) else { return }
            found.append((range, hit.article.gender))
        }
        if cache.count > 300 { cache.removeAll() }
        cache[messageID] = found
        return found
    }

    /// True when the nearest non-space character before `range` ends a sentence (or there is none).
    private static func isSentenceInitial(_ range: NSRange, in ns: NSString) -> Bool {
        var i = range.location - 1
        while i >= 0 {
            let ch = Character(UnicodeScalar(ns.character(at: i)) ?? " ")
            if ch.isNewline { return true }
            if ch.isWhitespace || ch == "\"" || ch == "„" || ch == "“" || ch == "«" || ch == "»" || ch == "'" {
                i -= 1
                continue
            }
            return ch == "." || ch == "!" || ch == "?" || ch == "…" || ch == ":"
        }
        return true
    }
}
