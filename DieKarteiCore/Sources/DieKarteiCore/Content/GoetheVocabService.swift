import Foundation

public struct A1Entry: Decodable {
    public let word: String
    public let article: String?
    public let wordType: String?
    public let translation: String?
    public let example: String?
}

public enum GoetheLevel: String, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"

    public var id: String { rawValue }

    public var resourceName: String {
        switch self {
        case .a1: return "a1_vocabulary"
        case .a2: return "a2_vocabulary"
        case .b1: return "b1_vocabulary"
        }
    }

    public var pdfURL: URL {
        switch self {
        case .a1: return URL(string: "https://www.goethe.de/pro/relaunch/prf/de/A1_SD1_Wortliste_02.pdf")!
        case .a2: return URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_A2_Wortliste.pdf")!
        case .b1: return URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_B1_Wortliste.pdf")!
        }
    }

    public var examName: String {
        switch self {
        case .a1: return "Start Deutsch 1"
        case .a2: return "Goethe-Zertifikat A2"
        case .b1: return "Goethe-Zertifikat B1"
        }
    }

    public var description: String {
        switch self {
        case .a1: return "Elementary — ~585 words"
        case .a2: return "Pre-intermediate — ~1200 words"
        case .b1: return "Intermediate — ~2300 words"
        }
    }
}

public enum GoetheVocabService {
    private static var cache: [GoetheLevel: [A1Entry]] = [:]

    public static func entries(for level: GoetheLevel) -> [A1Entry] {
        if let cached = cache[level] { return cached }
        guard let entries = CoreResources.decode([A1Entry].self, resource: level.resourceName)
        else { return [] }
        cache[level] = entries
        return entries
    }

    public static func toVocabCards(_ entries: [A1Entry]) -> [VocabCard] {
        entries.compactMap { e in
            guard let translation = e.translation, !translation.isEmpty else { return nil }
            return VocabCard(
                germanWord: e.word,
                englishTranslation: translation,
                wordType: e.wordType,
                article: e.article,
                exampleSentence: e.example?.isEmpty == false ? e.example : nil
            )
        }
    }
}
