import Foundation
import SQLite3

/// Validates AI-generated flashcards against a bundled Wiktionary dictionary database.
/// Uses the SQLite3 C API directly (built into iOS) to query a read-only database.
final class WiktionaryValidator {
    static let shared = WiktionaryValidator()

    private var db: OpaquePointer?
    private var lookupStmt: OpaquePointer?

    private init() {
        openDatabase()
        prepareStatements()
    }

    deinit {
        if let lookupStmt { sqlite3_finalize(lookupStmt) }
        if let db { sqlite3_close(db) }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "wiktionary_de", ofType: "db") else {
            print("[WiktionaryValidator] Database file not found in bundle")
            return
        }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(dbPath, &db, flags, nil) != SQLITE_OK {
            let error = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            print("[WiktionaryValidator] Failed to open database: \(error)")
            db = nil
        }
    }

    private func prepareStatements() {
        guard let db else { return }

        let lookupSQL = "SELECT pos, gender, translation FROM words WHERE word_lower = ? LIMIT 10;"
        if sqlite3_prepare_v2(db, lookupSQL, -1, &lookupStmt, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            print("[WiktionaryValidator] Failed to prepare lookup statement: \(error)")
        }
    }

    // MARK: - Public API

    /// Whether the dictionary database is loaded and ready for queries.
    var isAvailable: Bool {
        db != nil && lookupStmt != nil
    }

    /// Validate an array of vocab cards against the dictionary.
    func validate(_ cards: [VocabCard]) -> [ValidationResult] {
        guard isAvailable else {
            return cards.map { ValidationResult(germanWord: $0.germanWord, status: .unchecked, dictionaryTranslation: nil) }
        }

        return cards.map { validateCard($0) }
    }

    // MARK: - Per-Card Validation

    private func validateCard(_ card: VocabCard) -> ValidationResult {
        let normalized = normalizeWord(card.germanWord)

        // Look up the word in the dictionary
        let entries = lookupWord(normalized)

        // If not found, try without common prefixes/suffixes
        if entries.isEmpty {
            // Try removing "zu " prefix (zu + infinitive)
            if normalized.hasPrefix("zu ") {
                let withoutZu = String(normalized.dropFirst(3))
                let zuEntries = lookupWord(withoutZu)
                if !zuEntries.isEmpty {
                    return buildResult(card: card, entries: zuEntries)
                }
            }

            // Try removing "-" for compound word parts
            let withoutHyphens = normalized.replacingOccurrences(of: "-", with: "")
            if withoutHyphens != normalized {
                let hyphenEntries = lookupWord(withoutHyphens)
                if !hyphenEntries.isEmpty {
                    return buildResult(card: card, entries: hyphenEntries)
                }
            }

            return ValidationResult(germanWord: card.germanWord, status: .notFound, dictionaryTranslation: nil)
        }

        return buildResult(card: card, entries: entries)
    }

    private func buildResult(card: VocabCard, entries: [DictEntry]) -> ValidationResult {
        let translation = entries.first?.translation

        // If the card is a noun, check gender
        if card.wordType?.lowercased() == "noun", let cardArticle = card.article?.lowercased() {
            // Find a noun entry with gender info
            if let nounEntry = entries.first(where: { $0.pos == "noun" && $0.gender != nil }) {
                let expectedArticle = articleForGender(nounEntry.gender!)
                if cardArticle != expectedArticle {
                    return ValidationResult(
                        germanWord: card.germanWord,
                        status: .genderMismatch(expected: expectedArticle),
                        dictionaryTranslation: translation
                    )
                }
            }
        }

        return ValidationResult(germanWord: card.germanWord, status: .verified, dictionaryTranslation: translation)
    }

    // MARK: - SQLite Queries

    private struct DictEntry {
        let pos: String
        let gender: String?
        let translation: String?
    }

    private func lookupWord(_ word: String) -> [DictEntry] {
        guard let stmt = lookupStmt else { return [] }

        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)

        var entries: [DictEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pos = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let gender = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let translation = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            entries.append(DictEntry(pos: pos, gender: gender, translation: translation))
        }

        return entries
    }

    // MARK: - Helpers

    /// Normalize a word for dictionary lookup: lowercase, strip leading articles.
    private func normalizeWord(_ word: String) -> String {
        var normalized = word.lowercased().trimmingCharacters(in: .whitespaces)

        let articlePrefixes = [
            "der ", "die ", "das ",
            "den ", "dem ", "des ",
            "ein ", "eine ", "einen ", "einem ", "eines "
        ]
        for prefix in articlePrefixes {
            if normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
                break
            }
        }

        return normalized
    }

    /// Map a gender code (m/f/n) to the corresponding German article.
    private func articleForGender(_ gender: String) -> String {
        switch gender {
        case "m": return "der"
        case "f": return "die"
        case "n": return "das"
        default: return gender
        }
    }
}
