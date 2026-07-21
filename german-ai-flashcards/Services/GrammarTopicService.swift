import Foundation

/// One browsable topic for AI grammar exercises — a German theme word with its English gloss.
struct GrammarTopic: Codable, Identifiable, Hashable {
    let de: String
    let en: String

    var id: String { de }
    /// The form fed to the generation prompt (and shown in the topic field when picked).
    var promptLabel: String { "\(de) (\(en))" }
}

private struct GrammarTopicsFile: Codable {
    let topics: [GrammarTopic]
}

/// Loads the bundled catalog of ~100 exercise topics the learner can scroll through
/// (or have picked at random) instead of typing their own.
enum GrammarTopicService {
    private static var cache: [GrammarTopic]?

    static func topics() -> [GrammarTopic] {
        if let cached = cache { return cached }
        guard let url = Bundle.main.url(forResource: "grammar_topics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(GrammarTopicsFile.self, from: data)
        else { return [] }
        cache = file.topics
        return file.topics
    }

    static func randomTopic() -> GrammarTopic? {
        topics().randomElement()
    }
}
