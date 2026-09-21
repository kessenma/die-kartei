import Foundation

/// One row of a bundled Goethe word list (`Resources/<level>_vocabulary.json`).
struct A1Entry: Decodable {
    let word: String
    let article: String?
    let wordType: String?
    let translation: String?
    let example: String?
    /// Plural ending for nouns ("-en", "¨-e", "only sg."), merged in from Wortkiste where known.
    let plural: String?
    /// Present + Perfekt forms for verbs ("meldet sich an · hat sich angemeldet"), from Wortkiste.
    let verbForms: String?

    init(word: String, article: String?, wordType: String?, translation: String?, example: String?,
         plural: String? = nil, verbForms: String? = nil) {
        self.word = word
        self.article = article
        self.wordType = wordType
        self.translation = translation
        self.example = example
        self.plural = plural
        self.verbForms = verbForms
    }
}

enum GoetheLevel: String, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"

    var id: String { rawValue }

    var resourceName: String {
        switch self {
        case .a1: return "a1_vocabulary"
        case .a2: return "a2_vocabulary"
        case .b1: return "b1_vocabulary"
        }
    }

    var pdfURL: URL {
        switch self {
        case .a1: return URL(string: "https://www.goethe.de/pro/relaunch/prf/de/A1_SD1_Wortliste_02.pdf")!
        case .a2: return URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_A2_Wortliste.pdf")!
        case .b1: return URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_B1_Wortliste.pdf")!
        }
    }

    var examName: String {
        switch self {
        case .a1: return "Start Deutsch 1"
        case .a2: return "Goethe-Zertifikat A2"
        case .b1: return "Goethe-Zertifikat B1"
        }
    }

    var description: String {
        switch self {
        case .a1: return "Elementary — ~585 words"
        case .a2: return "Pre-intermediate — ~1200 words"
        case .b1: return "Intermediate — ~2300 words"
        }
    }
}

/// The word classes the Wortschatz scope can filter on. Derived, not read: the lists tag nouns
/// inconsistently (A2/B1 leave `wordType` empty for most of them) but always carry the article,
/// so "has an article" is the noun test — the same one the old level screen used.
enum GoetheWordType: String, CaseIterable, Identifiable, Codable {
    case noun, verb, adj, adv, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noun: "Nouns"
        case .verb: "Verbs"
        case .adj: "Adjectives"
        case .adv: "Adverbs"
        case .other: "Other"
        }
    }

    static func normalize(article: String?, raw: String?) -> GoetheWordType {
        if let article, !article.isEmpty { return .noun }
        switch raw?.lowercased() {
        case "noun": return .noun
        case "verb": return .verb
        case "adj", "adjective": return .adj
        case "adv", "adverb": return .adv
        default: return .other
        }
    }
}

/// One Goethe headword across every list it appears on. The lists are cumulative (most of A1 is
/// in A2, most of A2 in B1), so this is the unit progress is tracked on: one record per word,
/// tagged with its levels, rather than one per list.
struct GoetheWord: Identifiable, Hashable {
    let word: String
    var article: String?
    var rawWordType: String?
    var translation: String?
    var example: String?
    var plural: String?
    var verbForms: String?
    var levels: Set<GoetheLevel>

    var id: String { word }

    var wordType: GoetheWordType { GoetheWordType.normalize(article: article, raw: rawWordType) }

    /// The first list the word appears on — its "introduced at" level.
    var lowestLevel: GoetheLevel { GoetheLevel.allCases.first { levels.contains($0) } ?? .b1 }

    var orderedLevels: [GoetheLevel] { GoetheLevel.allCases.filter { levels.contains($0) } }

    /// The row shape the list screens render.
    var entry: A1Entry {
        A1Entry(word: word, article: article, wordType: rawWordType, translation: translation,
                example: example, plural: plural, verbForms: verbForms)
    }

    /// The plural or verb-forms caption a card shows under the German word, or nil when the lists
    /// have nothing for this word.
    var formsLine: String? {
        GoetheVocabService.formsLine(plural: plural, verbForms: verbForms, wordType: wordType)
    }

    /// The card the player studies. Nil when no list has a translation for the word — the same
    /// rule `toVocabCards` applies.
    var vocabCard: VocabCard? {
        guard let translation, !translation.isEmpty else { return nil }
        return VocabCard(
            germanWord: word,
            englishTranslation: translation,
            wordType: rawWordType,
            article: article,
            exampleSentence: example?.isEmpty == false ? example : nil,
            forms: formsLine
        )
    }
}

enum GoetheVocabService {
    private static var cache: [GoetheLevel: [A1Entry]] = [:]

    static func entries(for level: GoetheLevel) -> [A1Entry] {
        if let cached = cache[level] { return cached }
        guard let url = Bundle.main.url(forResource: level.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([A1Entry].self, from: data)
        else { return [] }
        cache[level] = entries
        return entries
    }

    static func toVocabCards(_ entries: [A1Entry]) -> [VocabCard] {
        entries.compactMap { e in
            guard let translation = e.translation, !translation.isEmpty else { return nil }
            return VocabCard(
                germanWord: e.word,
                englishTranslation: translation,
                wordType: e.wordType,
                article: e.article,
                exampleSentence: e.example?.isEmpty == false ? e.example : nil,
                forms: formsLine(plural: e.plural, verbForms: e.verbForms,
                                 wordType: GoetheWordType.normalize(article: e.article, raw: e.wordType))
            )
        }
    }

    /// "Plural: -en" / "nur Singular" for nouns, the Wortkiste verb string for verbs.
    static func formsLine(plural: String?, verbForms: String?, wordType: GoetheWordType) -> String? {
        switch wordType {
        case .noun:
            guard let plural, !plural.isEmpty else { return nil }
            switch plural {
            case "only sg.": return "singular only"
            case "only pl.": return "plural only"
            case "-": return "Plural: same as singular"
            default: return "Plural: \(plural)"
            }
        case .verb:
            guard let verbForms, !verbForms.isEmpty else { return nil }
            return verbForms
        default:
            return nil
        }
    }

    // MARK: - The merged index

    /// Every headword across the three lists, keyed by the exact word. Built once.
    static var index: [String: GoetheWord] { merged.byWord }

    /// The same words in first-appearance order: the A1 list, then the words A2 adds, then B1's.
    /// This is the order new words are introduced in, and the stable `sortOrder` of the SRS deck.
    static var orderedWords: [GoetheWord] { merged.ordered }

    static func words(in scope: WortschatzScope) -> [GoetheWord] {
        orderedWords.filter { scope.contains($0) }
    }

    private static let merged: (byWord: [String: GoetheWord], ordered: [GoetheWord]) = buildIndex()

    /// Iterates A1 → A2 → B1. The first list a word appears on defines it (word, translation,
    /// type); later lists only add their level and fill in what the earlier row left empty — the
    /// A2 list, for one, drops the article on twenty A1 nouns. Exact-string keys collapse the six
    /// words the A1 list carries twice.
    private static func buildIndex() -> (byWord: [String: GoetheWord], ordered: [GoetheWord]) {
        var byWord: [String: GoetheWord] = [:]
        var order: [String] = []
        for level in GoetheLevel.allCases {
            for entry in entries(for: level) {
                if var existing = byWord[entry.word] {
                    existing.levels.insert(level)
                    if existing.article == nil, let article = entry.article, !article.isEmpty {
                        existing.article = article
                    }
                    if existing.rawWordType == nil, let type = entry.wordType, !type.isEmpty {
                        existing.rawWordType = type
                    }
                    if existing.translation?.isEmpty != false, let t = entry.translation, !t.isEmpty {
                        existing.translation = t
                    }
                    if existing.example?.isEmpty != false, let e = entry.example, !e.isEmpty {
                        existing.example = e
                    }
                    if existing.plural == nil, let p = entry.plural, !p.isEmpty { existing.plural = p }
                    if existing.verbForms == nil, let f = entry.verbForms, !f.isEmpty { existing.verbForms = f }
                    byWord[entry.word] = existing
                } else {
                    byWord[entry.word] = GoetheWord(
                        word: entry.word,
                        article: entry.article?.isEmpty == false ? entry.article : nil,
                        rawWordType: entry.wordType?.isEmpty == false ? entry.wordType : nil,
                        translation: entry.translation,
                        example: entry.example,
                        plural: entry.plural,
                        verbForms: entry.verbForms,
                        levels: [level]
                    )
                    order.append(entry.word)
                }
            }
        }
        return (byWord, order.compactMap { byWord[$0] })
    }
}
