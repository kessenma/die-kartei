import Foundation
import SQLite3

/// Validates AI-generated flashcards against a bundled Wiktionary dictionary database.
/// Uses the SQLite3 C API directly (built into iOS) to query a read-only database.
///
/// Anything the dictionary or `GermanGenderInference` can settle confidently is corrected in
/// place rather than reported, so the user only ever sees the words that genuinely need a
/// human. See `validateAndCorrect(_:)`.
final class WiktionaryValidator {
    static let shared = WiktionaryValidator()

    private var db: OpaquePointer?
    private var lookupStmt: OpaquePointer?
    private var existsStmt: OpaquePointer?
    private var randomNounStmt: OpaquePointer?

    /// Compound splitting probes many candidate heads per word, and decks re-validate on every
    /// load, so results are worth keeping for the process lifetime.
    private var genderCache: [String: String?] = [:]
    private var existsCache: [String: Bool] = [:]
    private var posCache: [String: Set<String>] = [:]

    private init() {
        openDatabase()
        prepareStatements()
    }

    deinit {
        if let lookupStmt { sqlite3_finalize(lookupStmt) }
        if let existsStmt { sqlite3_finalize(existsStmt) }
        if let randomNounStmt { sqlite3_finalize(randomNounStmt) }
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

        let existsSQL = "SELECT 1 FROM words WHERE word_lower = ? LIMIT 1;"
        if sqlite3_prepare_v2(db, existsSQL, -1, &existsStmt, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            print("[WiktionaryValidator] Failed to prepare exists statement: \(error)")
        }

        // Random gendered nouns for the der/die/das game's "dictionary shuffle" source.
        let randomSQL = """
            SELECT word, gender, translation FROM words \
            WHERE pos = 'noun' AND gender IN ('m','f','n') \
            AND translation IS NOT NULL AND length(word) BETWEEN 3 AND 16 \
            ORDER BY RANDOM() LIMIT ?;
            """
        if sqlite3_prepare_v2(db, randomSQL, -1, &randomNounStmt, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            print("[WiktionaryValidator] Failed to prepare random-noun statement: \(error)")
        }
    }

    // MARK: - Public API

    /// Whether the dictionary database is loaded and ready for queries.
    var isAvailable: Bool {
        db != nil && lookupStmt != nil
    }

    /// Validate cards, correcting every article the app can settle confidently.
    ///
    /// Order matters: a dictionary entry always wins, then compound splitting, then
    /// derivational endings. Only words that survive all three reach the user.
    func validateAndCorrect(_ cards: [VocabCard]) -> ValidationOutcome {
        guard isAvailable else {
            return ValidationOutcome(
                cards: cards,
                results: cards.map {
                    ValidationResult(germanWord: $0.germanWord, status: .unchecked, dictionaryTranslation: nil)
                },
                corrections: []
            )
        }

        var corrected = cards
        var results: [ValidationResult] = []
        var corrections: [AutoCorrection] = []
        results.reserveCapacity(cards.count)

        for (index, card) in cards.enumerated() {
            let verdict = evaluate(card)
            results.append(verdict.result)

            if let article = verdict.correctedArticle, case .autoCorrected(let from, _, let source) = verdict.result.status {
                corrected[index].article = article
                corrections.append(
                    AutoCorrection(
                        index: index,
                        germanWord: card.germanWord,
                        englishTranslation: card.englishTranslation,
                        from: from,
                        to: article,
                        source: source
                    )
                )
            }
        }

        return ValidationOutcome(cards: corrected, results: results, corrections: corrections)
    }

    /// Status-only validation, for callers that just want to display badges.
    func validate(_ cards: [VocabCard]) -> [ValidationResult] {
        validateAndCorrect(cards).results
    }

    // MARK: - Article-game lookups

    /// A noun's article + translation, but only when the dictionary is unanimous about its
    /// gender — ambiguous nouns (der/die See) make unfair quiz questions. Accepts display
    /// forms ("die Gabel"); nil when the word isn't a gendered noun.
    func nounArticle(for word: String) -> (article: GermanArticle, english: String?)? {
        guard isAvailable else { return nil }
        let normalized = normalizeWord(word)
        guard let gender = unambiguousGender(of: normalized),
              let articleText = GermanGenderInference.article(for: gender),
              let article = GermanArticle(rawValue: articleText)
        else { return nil }
        let english = lookupWord(normalized)
            .first { $0.pos == "noun" && $0.translation?.isEmpty == false }?
            .translation
        return (article, english.map(Self.cleanTranslation))
    }

    /// Every part of speech the dictionary files a word under, looked up lowercased („noun“,
    /// „verb“, „adj“, „adv“). Empty when it doesn't know the word; nil when the database isn't
    /// there. The Kasus sentence checks on a tutor's story use it.
    func partsOfSpeech(of word: String) -> Set<String>? {
        guard isAvailable else { return nil }
        let lower = word.lowercased()
        if let cached = posCache[lower] { return cached }
        let parts = Set(lookupWord(lower).map(\.pos).filter { !$0.isEmpty })
        posCache[lower] = parts
        return parts
    }

    /// Random quiz-quality nouns for the der/die/das game: single capitalized words with an
    /// unambiguous gender and a usable translation. Oversamples, filters, and returns up to
    /// `count` distinct nouns.
    func randomNouns(count: Int) -> [(noun: String, article: GermanArticle, english: String)] {
        guard isAvailable, let stmt = randomNounStmt, count > 0 else { return [] }

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(count * 12))

        var picked: [(noun: String, article: GermanArticle, english: String)] = []
        var seen = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW, picked.count < count {
            guard let wordC = sqlite3_column_text(stmt, 0),
                  let genderC = sqlite3_column_text(stmt, 1),
                  let translationC = sqlite3_column_text(stmt, 2) else { continue }
            let word = String(cString: wordC)
            let translation = String(cString: translationC)

            guard Self.isQuizWord(word), Self.isQuizTranslation(translation),
                  seen.insert(word.lowercased()).inserted else { continue }
            // Re-check gender across *all* entries — the row's own gender isn't enough when
            // another entry disagrees (der/die Butter).
            guard let gender = unambiguousGender(of: word.lowercased()),
                  gender == String(cString: genderC),
                  let articleText = GermanGenderInference.article(for: gender),
                  let article = GermanArticle(rawValue: articleText) else { continue }

            picked.append((noun: word, article: article, english: Self.cleanTranslation(translation)))
        }
        return picked
    }

    /// A single capitalized dictionary word — no acronyms, hyphens, spaces, or CamelCase.
    private nonisolated static func isQuizWord(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        return word.dropFirst().allSatisfy { $0.isLowercase && $0.isLetter }
    }

    /// Filters out gloss-style translations that make useless quiz clues.
    private nonisolated static func isQuizTranslation(_ translation: String) -> Bool {
        let lower = translation.lowercased()
        let glossMarkers = [
            "initialism", "abbreviation", "acronym", "plural of", "genitive", "dative",
            "diminutive of", "obsolete", "archaic", "dated form", "alternative", "misspelling",
            "surname", "given name", "clipping of", "equivalent of", "gerund of", "agent noun",
        ]
        return !lower.isEmpty && !glossMarkers.contains { lower.contains($0) }
    }

    /// First gloss only, trimmed — "connection, joining; link" → "connection".
    private nonisolated static func cleanTranslation(_ translation: String) -> String {
        let first = translation
            .components(separatedBy: CharacterSet(charactersIn: ";,("))
            .first ?? translation
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Per-Card Validation

    private struct Verdict {
        let result: ValidationResult
        /// Non-nil when the card's article should be overwritten.
        let correctedArticle: String?
    }

    private func evaluate(_ card: VocabCard) -> Verdict {
        let normalized = normalizeWord(card.germanWord)
        let entries = lookupWithFallbacks(normalized)

        // Only nouns carry an article, so nothing else can have a gender problem. Older cards
        // sometimes have no word type recorded; an article is good enough evidence.
        let isNoun = card.wordType?.lowercased() == "noun"
            || (card.wordType == nil && card.article != nil)
        guard isNoun else {
            let status: ValidationStatus = entries.isEmpty ? .notFound : .verified
            return Verdict(
                result: ValidationResult(
                    germanWord: card.germanWord,
                    status: status,
                    dictionaryTranslation: entries.first?.translation
                ),
                correctedArticle: nil
            )
        }

        let translation = entries.first?.translation
        let cardArticle = card.article?.lowercased()

        // 1. Dictionary. Collect *every* recorded gender: 1,045 nouns in the corpus have more
        //    than one (der/das Meter, die/der Butter), and treating only the first as correct
        //    was flagging perfectly valid cards.
        let genders = Set(entries.filter { $0.pos == "noun" }.compactMap { $0.gender })
        let articles = Set(genders.compactMap { GermanGenderInference.article(for: $0) })

        if !articles.isEmpty {
            if let cardArticle, articles.contains(cardArticle) {
                let status: ValidationStatus = articles.count > 1
                    ? .ambiguous(options: articles.sorted())
                    : .verified
                return Verdict(
                    result: ValidationResult(germanWord: card.germanWord, status: status, dictionaryTranslation: translation),
                    correctedArticle: nil
                )
            }

            // The card disagrees with the dictionary, or has no article at all. When the
            // dictionary is unanimous this is not a judgement call — apply it.
            if articles.count == 1, let expected = articles.first {
                return Verdict(
                    result: ValidationResult(
                        germanWord: card.germanWord,
                        status: .autoCorrected(from: cardArticle, to: expected, source: .dictionary),
                        dictionaryTranslation: translation
                    ),
                    correctedArticle: expected
                )
            }

            // Several valid genders and the card matched none of them — a real choice, so ask.
            return Verdict(
                result: ValidationResult(
                    germanWord: card.germanWord,
                    status: .genderMismatch(expected: articles.sorted().joined(separator: "/")),
                    dictionaryTranslation: translation
                ),
                correctedArticle: nil
            )
        }

        // 2 & 3. Not in the dictionary as a gendered noun — try to derive the gender.
        if let inferred = inferGender(for: normalized) {
            if let cardArticle, cardArticle == inferred.article {
                return Verdict(
                    result: ValidationResult(germanWord: card.germanWord, status: .verified, dictionaryTranslation: translation),
                    correctedArticle: nil
                )
            }
            return Verdict(
                result: ValidationResult(
                    germanWord: card.germanWord,
                    status: .autoCorrected(from: cardArticle, to: inferred.article, source: inferred.source),
                    dictionaryTranslation: translation
                ),
                correctedArticle: inferred.article
            )
        }

        // Nothing could settle it. If the word itself is in the dictionary (just without a
        // recorded gender) the card is otherwise fine; only a true miss is worth flagging.
        let status: ValidationStatus = entries.isEmpty ? .notFound : .verified
        return Verdict(
            result: ValidationResult(germanWord: card.germanWord, status: status, dictionaryTranslation: translation),
            correctedArticle: nil
        )
    }

    /// Derive a noun's gender from its structure: compound head first (a hard grammatical
    /// rule), then a reliable derivational ending.
    private func inferGender(for word: String) -> (article: String, source: GenderSource)? {
        if let match = GermanGenderInference.compoundGender(
            for: word,
            genderOfNoun: { self.compoundHeadGender(of: $0) },
            isKnownWord: { self.wordExists($0) }
        ), let article = GermanGenderInference.article(for: match.gender) {
            return (article, .compound(head: match.head))
        }

        if let match = GermanGenderInference.suffixGender(for: word),
           let article = GermanGenderInference.article(for: match.gender) {
            return (article, .suffix(match.suffix))
        }

        return nil
    }

    private func lookupWithFallbacks(_ normalized: String) -> [DictEntry] {
        let entries = lookupWord(normalized)
        if !entries.isEmpty { return entries }

        // Try removing "zu " prefix (zu + infinitive)
        if normalized.hasPrefix("zu ") {
            let withoutZu = String(normalized.dropFirst(3))
            let zuEntries = lookupWord(withoutZu)
            if !zuEntries.isEmpty { return zuEntries }
        }

        // Try removing "-" for compound word parts
        let withoutHyphens = normalized.replacingOccurrences(of: "-", with: "")
        if withoutHyphens != normalized {
            let hyphenEntries = lookupWord(withoutHyphens)
            if !hyphenEntries.isEmpty { return hyphenEntries }
        }

        return []
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
            let rawGender = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let gender = (rawGender?.isEmpty ?? true) ? nil : rawGender
            let translation = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            entries.append(DictEntry(pos: pos, gender: gender, translation: translation))
        }

        return entries
    }

    /// A noun's gender code, but only when every dictionary entry agrees. Compound heads with
    /// competing genders (`der`/`die See`) can't be used to correct anything.
    private func unambiguousGender(of word: String) -> String? {
        if let cached = genderCache[word] { return cached }

        let genders = Set(lookupWord(word).filter { $0.pos == "noun" }.compactMap { $0.gender })
        let result = genders.count == 1 ? genders.first : nil
        genderCache[word] = result
        return result
    }

    /// As `unambiguousGender`, but rejects nominalized infinitives as compound heads.
    ///
    /// `-en` words that are also verbs are listed as neuter nouns because German can nominalize
    /// any infinitive (`das Halten`), yet they practically never head a compound — so
    /// `Asphalten` was being split as `Asph` + `Halten` and turned neuter. Skipping them lifts
    /// compound accuracy from 96.8% to 97.3% on the bundled corpus, at a cost of ~3% coverage.
    /// Kept separate from `unambiguousGender` so the article game's lookups are unaffected.
    private func compoundHeadGender(of word: String) -> String? {
        guard let gender = unambiguousGender(of: word) else { return nil }
        if word.hasSuffix("en"), lookupWord(word).contains(where: { $0.pos == "verb" }) {
            return nil
        }
        return gender
    }

    /// Whether the string appears in the dictionary at all, in any part of speech.
    private func wordExists(_ word: String) -> Bool {
        if let cached = existsCache[word] { return cached }
        guard let stmt = existsStmt else { return false }

        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, (word as NSString).utf8String, -1, nil)
        let found = sqlite3_step(stmt) == SQLITE_ROW
        existsCache[word] = found
        return found
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
}
