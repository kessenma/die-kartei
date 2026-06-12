import Foundation

struct PastTenseVerbEntry: Codable, Identifiable {
    let infinitive: String
    let translation: String
    let auxiliary: String
    let pastParticiple: String
    let isSeparable: Bool
    let prefix: String?
    let isRegular: Bool
    let example: String?
    let level: String

    var id: String { infinitive }
}

enum PastTenseLevel: String, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .a1: return "Elementary verbs"
        case .a2: return "Pre-intermediate verbs"
        case .b1: return "Intermediate verbs"
        }
    }

    var color: String {
        switch self {
        case .a1: return "green"
        case .a2: return "blue"
        case .b1: return "orange"
        }
    }
}

enum PastTenseVerbService {
    private static var cache: [PastTenseLevel: [PastTenseVerbEntry]] = [:]
    private static var allCache: [PastTenseVerbEntry]? = nil

    static func entries(for level: PastTenseLevel) -> [PastTenseVerbEntry] {
        if let cached = cache[level] { return cached }
        let all = allEntries
        let filtered = all.filter { $0.level == level.rawValue }
        cache[level] = filtered
        return filtered
    }

    static var allEntries: [PastTenseVerbEntry] {
        if let cached = allCache { return cached }
        guard let url = Bundle.main.url(forResource: "past_tense_verbs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([PastTenseVerbEntry].self, from: data)
        else { return [] }
        allCache = entries
        return entries
    }

    static func toVocabCards(_ entries: [PastTenseVerbEntry]) -> [VocabCard] {
        entries.map { entry in
            VocabCard(
                germanWord: entry.infinitive,
                englishTranslation: entry.translation,
                wordType: "verb",
                article: nil,
                exampleSentence: entry.example,
                auxiliaryVerb: entry.auxiliary,
                pastParticiple: entry.pastParticiple,
                isSeparable: entry.isSeparable,
                verbPrefix: entry.prefix,
                isRegular: entry.isRegular
            )
        }
    }
}
