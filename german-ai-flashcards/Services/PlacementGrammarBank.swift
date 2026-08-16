//
//  PlacementGrammarBank.swift
//  german-ai-flashcards
//
//  The authored grammar bank behind the placement check: single-gap items for the anchor pair and
//  the grammar staircase, plus one cloze paragraph per level for the finale. Every sentence here
//  was written for this app — the bank mimics the *shapes* of telc/Goethe-style placement items
//  (3-option gaps, distractors that are morphological neighbours of the key), never their content.
//
//  This bank exists separately from `grammar_exercises.json` on purpose: the drills' exercises are
//  keyed by case and built for teaching, while placement needs items keyed by CEFR level whose
//  constructs discriminate *between* levels (Perfekt auxiliary at A2, Konjunktiv II at B1,
//  Passiversatz at B2).
//

import Foundation

struct PlacementGrammarItem: Decodable, Identifiable {
    let id: String
    let level: String
    let construct: String
    let sentence: String
    let options: [String]
    let correct: String
    let english: String?
    let why: String?

    var cefr: CEFRLevel? { CEFRLevel(rawValue: level) }
}

struct PlacementClozeGap: Decodable {
    let construct: String
    let options: [String]
    let correct: String
    let why: String?
}

struct PlacementClozeParagraph: Decodable, Identifiable {
    let id: String
    let level: String
    let title: String
    /// Running text with `{0}` / `{1}` / `{2}` marking where the gaps sit.
    let text: String
    let gaps: [PlacementClozeGap]

    var cefr: CEFRLevel? { CEFRLevel(rawValue: level) }
}

struct PlacementGrammarFile: Decodable {
    let version: Int
    let anchors: [String]
    let items: [PlacementGrammarItem]
    let cloze: [PlacementClozeParagraph]
}

enum PlacementGrammarBank {
    private static var cache: PlacementGrammarFile?

    private static func load() -> PlacementGrammarFile? {
        if let cache { return cache }
        guard let url = Bundle.main.url(forResource: "placement_grammar", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PlacementGrammarFile.self, from: data)
        else { return nil }
        #if DEBUG
        assertValid(file)
        #endif
        cache = file
        return file
    }

    /// The two anchor items, in file order — asked first every run to pick the staircase's start.
    static func anchors() -> [PlacementGrammarItem] {
        guard let file = load() else { return [] }
        return file.anchors.compactMap { id in file.items.first { $0.id == id } }
    }

    /// Staircase pool for one level, minus anything already asked this run.
    static func items(level: CEFRLevel, excluding used: Set<String>) -> [PlacementGrammarItem] {
        guard let file = load() else { return [] }
        return file.items.filter { $0.level == level.rawValue && !used.contains($0.id) }
    }

    static func clozeParagraph(level: CEFRLevel) -> PlacementClozeParagraph? {
        load()?.cloze.first { $0.level == level.rawValue }
    }

    // MARK: - Lookup by id (the review screen)

    /// The bank's version, stamped onto each recorded attempt so a later failed lookup can say
    /// which bank the question came from instead of rendering a blank explanation.
    static var version: Int { load()?.version ?? 0 }

    /// One item by id — how the review screen gets back to the `english` / `why` an item carries
    /// but the quiz deliberately never shows. Attempts store only `sourceID`, so an explanation
    /// always comes from the *current* bank: re-authoring one improves old reviews rather than
    /// leaving a stale copy frozen in history.
    static func item(id: String) -> PlacementGrammarItem? {
        load()?.items.first { $0.id == id }
    }

    /// One cloze gap by paragraph id and index. Gaps have no ids of their own, so a cloze record's
    /// `sourceID` is the paragraph and its `gap` is the offset.
    static func clozeGap(paragraphID: String, gap: Int) -> PlacementClozeGap? {
        guard let paragraph = load()?.cloze.first(where: { $0.id == paragraphID }),
              paragraph.gaps.indices.contains(gap)
        else { return nil }
        return paragraph.gaps[gap]
    }

#if DEBUG
    /// A malformed bank should fail loudly in a debug run, not silently shorten the quiz.
    private static func assertValid(_ file: PlacementGrammarFile) {
        for item in file.items {
            assert(item.options.count == 3, "placement_grammar: \(item.id) needs exactly 3 options")
            assert(item.options.contains(item.correct), "placement_grammar: \(item.id) correct not in options")
            assert(item.cefr != nil, "placement_grammar: \(item.id) has unknown level \(item.level)")
        }
        for id in file.anchors {
            assert(file.items.contains { $0.id == id }, "placement_grammar: anchor \(id) missing from items")
        }
        for level in PlacementService.grammarLadder {
            let pool = file.items.filter { $0.level == level.rawValue }
            assert(pool.count >= PlacementService.grammarItems + 2,
                   "placement_grammar: level \(level.rawValue) needs ≥\(PlacementService.grammarItems + 2) items")
            let paragraphs = file.cloze.filter { $0.level == level.rawValue }
            assert(paragraphs.count == 1, "placement_grammar: level \(level.rawValue) needs exactly one cloze")
            for paragraph in paragraphs {
                assert(paragraph.gaps.count == PlacementService.clozeGaps,
                       "placement_grammar: \(paragraph.id) needs \(PlacementService.clozeGaps) gaps")
                for (index, gap) in paragraph.gaps.enumerated() {
                    assert(paragraph.text.contains("{\(index)}"),
                           "placement_grammar: \(paragraph.id) text missing marker {\(index)}")
                    assert(gap.options.count == 3, "placement_grammar: \(paragraph.id) gap \(index) needs 3 options")
                    assert(gap.options.contains(gap.correct),
                           "placement_grammar: \(paragraph.id) gap \(index) correct not in options")
                }
            }
        }
    }
#endif
}
