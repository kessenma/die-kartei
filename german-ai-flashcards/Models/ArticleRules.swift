//
//  ArticleRules.swift
//  german-ai-flashcards
//
//  The gender-pattern knowledge behind the der/die/das game: which endings (and a few word
//  categories) predict a noun's article, and how reliably. One table drives two things —
//  the "Artikel-Regeln" reference sheet, and the just-in-time hint shown after a miss
//  ("words ending in -ung are almost always die").
//
//  A hint is only ever shown when its rule agrees with the noun's *actual* article, so an
//  exception word ("der Kuchen" despite -chen) never produces a misleading tip.
//

import Foundation

/// One gender pattern — an ending (or word category) that predicts an article.
struct ArticleRule: Identifiable {
    enum Reliability: Int, Comparable {
        case usually = 0      // useful, but real exceptions exist
        case almostAlways = 1 // exceptions are rare enough to bet on
        case always = 2       // safe to treat as a law

        var label: String {
            switch self {
            case .always:       "immer"
            case .almostAlways: "fast immer"
            case .usually:      "meistens"
            }
        }

        static func < (lhs: Reliability, rhs: Reliability) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var article: GermanArticle
    /// Display name of the pattern ("-ung, -heit, -keit" or "Days, months & seasons").
    var title: String
    var reliability: Reliability
    /// Ready-made example words, articles included.
    var examples: String
    /// Notable exceptions worth warning about, when any.
    var exceptions: String?
    /// Endings the in-game hint matcher checks (lowercase). Empty for sheet-only category rules.
    var suffixes: [String] = []
    /// Prefixes the matcher checks (capitalized, e.g. "Ge"). Empty for most rules.
    var prefixes: [String] = []

    var id: String { article.rawValue + "·" + title }

    /// One-line tip for the in-game hint ("-ung → fast immer die").
    func hintLine(for noun: String) -> String {
        "Words like \"\(noun)\" — \(title) — are \(reliability.label) \(article.rawValue)."
    }
}

enum ArticleRules {

    /// The full rule table, sheet order: strongest patterns first within each article.
    static let all: [ArticleRule] = [

        // MARK: die
        ArticleRule(
            article: .die, title: "-heit, -keit, -schaft, -ung",
            reliability: .almostAlways,
            examples: "die Freiheit · die Möglichkeit · die Freundschaft · die Zeitung",
            exceptions: "one-syllable -ung words: der Sprung, der Schwung",
            suffixes: ["heit", "keit", "schaft", "ung"]
        ),
        // Corpus-measured (see GermanGenderInference): -tät 100%, -tion 99.7%, -sion 99%,
        // -enz 97.9%. "-anz" is deliberately absent — it's a coin flip (der Tanz, der Glanz).
        ArticleRule(
            article: .die, title: "-tion, -sion, -tät, -enz",
            reliability: .always,
            examples: "die Nation · die Diskussion · die Universität · die Konferenz",
            exceptions: nil,
            suffixes: ["tion", "sion", "tät", "enz"]
        ),
        ArticleRule(
            article: .die, title: "-ie, -ik, -ur, -erei",
            reliability: .almostAlways,
            examples: "die Familie · die Musik · die Natur · die Bäckerei",
            exceptions: "das Genie, das Abitur",
            suffixes: ["ie", "ik", "ur", "erei"]
        ),
        ArticleRule(
            article: .die, title: "Ending in -e",
            reliability: .usually,
            examples: "die Lampe · die Blume · die Straße",
            exceptions: "der Junge, der Name, das Ende, das Auge",
            suffixes: ["e"]
        ),
        ArticleRule(
            article: .die, title: "Female people (-in)",
            reliability: .always,
            examples: "die Lehrerin · die Ärztin · die Freundin",
            exceptions: nil
        ),
        ArticleRule(
            article: .die, title: "Numbers as nouns; motorcycles & ships",
            reliability: .almostAlways,
            examples: "die Eins · die Harley · die Titanic",
            exceptions: nil
        ),

        // MARK: der
        ArticleRule(
            article: .der, title: "-ling, -ismus",
            reliability: .always,
            examples: "der Frühling · der Lehrling · der Optimismus",
            exceptions: nil,
            suffixes: ["ling", "ismus"]
        ),
        ArticleRule(
            article: .der, title: "-or, -ant, -ent, -ist (people & devices)",
            reliability: .almostAlways,
            examples: "der Motor · der Praktikant · der Student · der Tourist",
            exceptions: "das Labor, das Talent",
            suffixes: ["or", "ant", "ist"]
        ),
        ArticleRule(
            article: .der, title: "-er (people & doers)",
            reliability: .usually,
            examples: "der Lehrer · der Computer · der Fahrer",
            exceptions: "die Butter, die Mutter, das Fenster, das Wasser",
            suffixes: ["er"]
        ),
        // "-ig" is only ~58% der across the corpus, so it stays out of the hint matcher.
        ArticleRule(
            article: .der, title: "-ich, -ig",
            reliability: .usually,
            examples: "der Teppich · der Honig · der König",
            exceptions: nil,
            suffixes: ["ich"]
        ),
        ArticleRule(
            article: .der, title: "Days, months & seasons",
            reliability: .always,
            examples: "der Montag · der Juli · der Winter",
            exceptions: nil
        ),
        ArticleRule(
            article: .der, title: "Weather & compass directions; alcoholic drinks",
            reliability: .usually,
            examples: "der Regen · der Norden · der Wein",
            exceptions: "das Bier"
        ),

        // MARK: das
        ArticleRule(
            article: .das, title: "-chen, -lein (diminutives)",
            reliability: .always,
            examples: "das Mädchen · das Brötchen · das Büchlein",
            exceptions: "non-diminutives that just end the same: der Kuchen",
            suffixes: ["chen", "lein"]
        ),
        // "-um" alone is only ~74% das (der Baum, der Traum, der Raum all end in -um).
        ArticleRule(
            article: .das, title: "-um, -ment, -ma",
            reliability: .usually,
            examples: "das Museum · das Dokument · das Thema",
            exceptions: "der Moment, der Baum, die Firma",
            suffixes: ["um", "ment", "ma"]
        ),
        ArticleRule(
            article: .das, title: "Ge- collectives",
            reliability: .usually,
            examples: "das Gebäude · das Gemüse · das Gespräch",
            exceptions: "der Gedanke, die Geschichte, der Geruch",
            prefixes: ["Ge"]
        ),
        ArticleRule(
            article: .das, title: "Verbs used as nouns",
            reliability: .always,
            examples: "das Essen · das Lesen · das Schwimmen",
            exceptions: nil
        ),
        ArticleRule(
            article: .das, title: "Young people & animals",
            reliability: .usually,
            examples: "das Kind · das Baby · das Kalb",
            exceptions: "der Junge"
        ),
        ArticleRule(
            article: .das, title: "Colors & letters as nouns; metals",
            reliability: .usually,
            examples: "das Rot · das A · das Gold",
            exceptions: nil
        ),
    ]

    /// Rules for one article, for the sheet's grouped sections.
    static func rules(for article: GermanArticle) -> [ArticleRule] {
        all.filter { $0.article == article }
    }

    /// The best pattern hint for a missed noun — only rules that agree with the noun's actual
    /// article are considered, so an exception word never gets a misleading tip. Prefers the
    /// longest matching ending (so "-ment" beats "-e"-style near-misses), then reliability.
    static func hint(for noun: String, article: GermanArticle) -> ArticleRule? {
        let lower = noun.lowercased()
        let candidates = all.filter { rule in
            guard rule.article == article else { return false }
            let suffixHit = rule.suffixes.contains { lower.hasSuffix($0) && lower.count > $0.count + 1 }
            let prefixHit = rule.prefixes.contains { noun.hasPrefix($0) && noun.count > $0.count + 2 }
            return suffixHit || prefixHit
        }
        return candidates.max { a, b in
            let aLen = a.suffixes.filter { lower.hasSuffix($0) }.map(\.count).max() ?? 0
            let bLen = b.suffixes.filter { lower.hasSuffix($0) }.map(\.count).max() ?? 0
            if aLen != bLen { return aLen < bLen }
            return a.reliability < b.reliability
        }
    }

    /// The fallback line when no pattern applies — the honest pedagogical advice.
    static func noRuleHint(for noun: String, article: GermanArticle) -> String {
        "No reliable pattern here — learn it as \"\(article.rawValue) \(noun)\"."
    }
}
