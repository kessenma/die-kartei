import Foundation

struct A1Entry: Decodable {
    let word: String
    let article: String?
    let wordType: String?
    let translation: String?
    let example: String?
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
                exampleSentence: e.example?.isEmpty == false ? e.example : nil
            )
        }
    }
}
