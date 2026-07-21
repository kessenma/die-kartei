import Foundation

/// One story-idea seed from the bundled `story_starters.json` — a German title with an English
/// gloss, grouped by category for the browse sheet.
struct StoryStarter: Decodable, Hashable, Identifiable {
    let de: String
    let en: String
    let category: String

    var id: String { de }
}

/// Loads and serves the ~100 bundled story starters. Mirrors `GoetheVocabService`: lazy bundle
/// load with a static cache, so the JSON is parsed at most once per launch.
enum StoryStarters {
    private static let cache: [StoryStarter] = {
        guard let url = Bundle.main.url(forResource: "story_starters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let starters = try? JSONDecoder().decode([StoryStarter].self, from: data)
        else { return [] }
        return starters
    }()

    /// Every starter, in file order.
    static var all: [StoryStarter] { cache }

    /// Category names in first-appearance order (stable grouping for the browse sheet).
    static var categories: [String] {
        var seen = Set<String>()
        return cache.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    /// Starters for one category, in file order.
    static func starters(in category: String) -> [StoryStarter] {
        cache.filter { $0.category == category }
    }

    /// A random starter, avoiding an immediate repeat of `excluding` (matched against either the
    /// German or English title, since the topic field may hold either) when possible.
    static func random(excluding: String? = nil) -> StoryStarter? {
        guard !cache.isEmpty else { return nil }
        let pool = excluding.map { ex in cache.filter { $0.de != ex && $0.en != ex } } ?? cache
        return (pool.isEmpty ? cache : pool).randomElement()
    }
}
