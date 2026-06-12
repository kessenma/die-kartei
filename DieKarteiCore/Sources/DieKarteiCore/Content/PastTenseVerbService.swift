import Foundation

public struct PastTenseVerbEntry: Codable, Identifiable {
    public let infinitive: String
    public let translation: String
    public let auxiliary: String
    public let pastParticiple: String
    public let isSeparable: Bool
    public let prefix: String?
    public let isRegular: Bool
    public let example: String?
    public let level: String

    public var id: String { infinitive }
}

public enum PastTenseLevel: String, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .a1: return "Elementary verbs"
        case .a2: return "Pre-intermediate verbs"
        case .b1: return "Intermediate verbs"
        }
    }

    public var color: String {
        switch self {
        case .a1: return "green"
        case .a2: return "blue"
        case .b1: return "orange"
        }
    }
}

public enum PastTenseVerbService {
    private static var cache: [PastTenseLevel: [PastTenseVerbEntry]] = [:]
    private static var allCache: [PastTenseVerbEntry]? = nil

    public static func entries(for level: PastTenseLevel) -> [PastTenseVerbEntry] {
        if let cached = cache[level] { return cached }
        let all = allEntries
        let filtered = all.filter { $0.level == level.rawValue }
        cache[level] = filtered
        return filtered
    }

    public static var allEntries: [PastTenseVerbEntry] {
        if let cached = allCache { return cached }
        guard let entries = CoreResources.decode([PastTenseVerbEntry].self, resource: "past_tense_verbs")
        else { return [] }
        allCache = entries
        return entries
    }

    public static func toVocabCards(_ entries: [PastTenseVerbEntry]) -> [VocabCard] {
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
