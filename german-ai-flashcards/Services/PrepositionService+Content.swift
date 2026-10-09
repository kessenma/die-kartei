//
//  PrepositionService+Content.swift
//  german-ai-flashcards
//
//  The bundled `prepositions.json` and its lookups, apart from the rounds and the SwiftData
//  writes in `PrepositionService.swift`, so the Kasus validator's lexicon (and `training/kasus_cli`,
//  which compiles it) reads prepositions without the recording side of the service.
//

import Foundation

extension PrepositionService {

    static func key(for word: String) -> String {
        word.lowercased(with: Locale(identifier: "de_DE")).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Bundled content

    private static var cache: [Preposition]?

    /// Every preposition in the bundle, in authored order (Akkusativ → Dativ → Wechsel → Genitiv).
    static func all() -> [Preposition] {
        if let cache { return cache }
        guard let url = Bundle.main.url(forResource: "prepositions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PrepositionsFile.self, from: data)
        else { return [] }
        cache = file.prepositions
        return file.prepositions
    }

    static func prepositions(governing group: PrepositionCase) -> [Preposition] {
        all().filter { $0.governs == group }
    }

    /// The set a round or a card deck draws from. `advanced` adds the formal Genitiv prepositions
    /// (innerhalb, jenseits, …) and the entries with awkward real-world usage.
    static func prepositions(
        groups: Set<PrepositionCase> = Set(PrepositionCase.allCases),
        includeAdvanced: Bool
    ) -> [Preposition] {
        all().filter { groups.contains($0.governs) && (includeAdvanced || $0.tier == .core) }
    }

    static func preposition(_ word: String) -> Preposition? {
        let wanted = key(for: word)
        return all().first { key(for: $0.word) == wanted }
    }

    /// Every contraction in the bundle, grouped for the rules sheet ("in + das = ins").
    static func allContractions() -> [(preposition: Preposition, contraction: PrepositionContraction)] {
        all().flatMap { prep in prep.contractions.map { (prep, $0) } }
    }
}
