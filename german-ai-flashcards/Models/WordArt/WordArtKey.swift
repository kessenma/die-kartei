import Foundation

/// The key a word's pictures and drawing stats hang on. Pictures belong to the *word*, not to a
/// card: *der Tisch* in two decks and in the Wortschatz box shares one gallery.
///
/// The key drops a leading article, lowercases, trims and folds whitespace, so "der Tisch",
/// "Tisch" and " tisch " all land in the same folder. Umlauts and ß are kept as written ("Bär" and
/// "Bar" are different words).
nonisolated enum WordArtKey {
    private static let articles: Set<String> = ["der", "die", "das"]

    static func make(_ germanWord: String) -> String {
        var parts = germanWord
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        if parts.count > 1, let first = parts.first, articles.contains(first) {
            parts.removeFirst()
        }
        return parts.joined(separator: " ")
    }

    /// The folder a word's files live in under `WordArt/`. A UUIDv5 of the key, so paths stay
    /// ASCII (CloudKit record names must be) and two devices pick the same folder for a word.
    static func folderName(for key: String) -> String {
        SyncNameUUID.make("WordArt", key).uuidString
    }
}
