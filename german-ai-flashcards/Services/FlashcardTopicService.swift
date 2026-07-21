import Foundation

/// One ready-made deck idea from the bundled `flashcard_topics.json` — the English topic that
/// goes into the generator, with a German gloss and a category for the browse sheet.
struct FlashcardTopic: Decodable, Hashable, Identifiable {
    let en: String
    let de: String
    let category: String

    var id: String { en }
}

/// Loads and serves the 100 bundled flashcard topics. Mirrors `StoryStarters`: lazy bundle load
/// with a static cache, so the JSON is parsed at most once per launch.
enum FlashcardTopics {
    private static let cache: [FlashcardTopic] = {
        guard let url = Bundle.main.url(forResource: "flashcard_topics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let topics = try? JSONDecoder().decode([FlashcardTopic].self, from: data)
        else { return [] }
        return topics
    }()

    /// Every topic, in file order.
    static var all: [FlashcardTopic] { cache }

    /// Category names in first-appearance order (stable grouping for the browse sheet).
    static var categories: [String] {
        var seen = Set<String>()
        return cache.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    /// Topics for one category, in file order.
    static func topics(in category: String) -> [FlashcardTopic] {
        cache.filter { $0.category == category }
    }

    /// Topics whose English or German title matches `query`; the whole set when it's blank.
    static func search(_ query: String) -> [FlashcardTopic] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return cache }
        return cache.filter {
            $0.en.localizedCaseInsensitiveContains(trimmed)
                || $0.de.localizedCaseInsensitiveContains(trimmed)
                || $0.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// `count` distinct topics drawn at random, each from a different category where possible, so
    /// the suggestion chips never show five variations on the same theme.
    static func sample(_ count: Int) -> [FlashcardTopic] {
        var byCategory = Dictionary(grouping: cache, by: \.category)
        var picked: [FlashcardTopic] = []
        while picked.count < count, !byCategory.isEmpty {
            for category in byCategory.keys.shuffled() where picked.count < count {
                guard let index = byCategory[category]?.indices.randomElement() else {
                    byCategory[category] = nil
                    continue
                }
                picked.append(byCategory[category]!.remove(at: index))
                if byCategory[category]?.isEmpty == true { byCategory[category] = nil }
            }
        }
        return picked
    }

    /// A random topic, avoiding an immediate repeat of `excluding` (matched against either title,
    /// since the topic field may hold whatever the user last picked) when possible.
    static func random(excluding: String? = nil) -> FlashcardTopic? {
        guard !cache.isEmpty else { return nil }
        let pool = excluding.map { ex in cache.filter { $0.en != ex && $0.de != ex } } ?? cache
        return (pool.isEmpty ? cache : pool).randomElement()
    }
}
