//
//  VerbPrepositionService.swift
//  german-ai-flashcards
//
//  Content loading and round building for Verben mit Präpositionen, beside `PrepositionService`
//  and reusing its rails rather than adding new ones:
//    - the case drill is a `PrepositionCaseSession` (Akkusativ or Dativ, the pair's scene above),
//      recorded by `PrepositionService.recordRound` under `verb:` keys and its own focus;
//    - the Lückentext and „Die Falle“ are `GrammarCategory`s built in memory for the existing
//      fill-in player, which records them through the category's `grammaticalCase`;
//    - the matching round is a `MatchingSession`, tinted by case like the preposition one.
//
//  Stats share `PrepositionStat` / `PrepositionRound` with a `verb:` key prefix and a "Verben"
//  topic prefix, so no new synced model was needed. Every reader of those that means *the 36
//  prepositions* filters them back out (the hub's tricky count, the pyramid's core count, which
//  already matches on core keys).
//

import Foundation
import SwiftData
import SwiftUI

enum VerbPrepositionService {

    /// Stat keys for verb pairs, so they never collide with a bare preposition's key.
    static let statKeyPrefix = "verb:"
    /// Round topics for verb pairs start with this, which is how the hub splits its history.
    static let topicPrefix = "Verben"

    // MARK: - Bundled content

    private static var cache: VerbPrepositionsFile?

    private static var file: VerbPrepositionsFile {
        if let cache { return cache }
        guard let url = Bundle.main.url(forResource: "verb_prepositions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VerbPrepositionsFile.self, from: data)
        else { return VerbPrepositionsFile(verbs: [], falle: []) }
        cache = decoded
        return decoded
    }

    /// Every pair, in the class sheet's order (Akkusativ first, then Dativ).
    static func all() -> [VerbPreposition] { file.verbs }

    static func verbs(governing groups: Set<PrepositionCase>) -> [VerbPreposition] {
        all().filter { groups.contains($0.governs) }
    }

    /// The pairs that use one preposition: auf's six, an's three (two of them Dativ).
    static func verbs(using preposition: String) -> [VerbPreposition] {
        all().filter { $0.preposition == preposition }
    }

    static func falle() -> [VerbFalleItem] { file.falle }

    static func isVerbStat(_ key: String) -> Bool { key.hasPrefix(statKeyPrefix) }
    static func isVerbTopic(_ topic: String) -> Bool { topic.hasPrefix(topicPrefix) }

    // MARK: - Case drill

    /// A case round over the pairs: the pair on top, Akkusativ or Dativ below, its scene above.
    /// Both buttons always, because the pool is always both cases: a pairs round can't be a
    /// single-case round.
    static func caseSession(
        count: Int,
        trickyFirst: Bool,
        in context: ModelContext
    ) -> PrepositionCaseSession? {
        let pool = all()
        guard pool.count >= PrepositionService.minQuestions else { return nil }
        var picked: [VerbPreposition]
        if trickyFirst {
            let trickyKeys = Set(trickyStats(in: context).map(\.key))
            let tricky = pool.filter { trickyKeys.contains(statKey(for: $0)) }.shuffled()
            let trickyTake = Array(tricky.prefix(count / 2))
            let taken = Set(trickyTake.map(\.verb))
            let rest = pool.filter { !taken.contains($0.verb) }.shuffled()
            picked = trickyTake + rest.prefix(count - trickyTake.count)
        } else {
            picked = Array(pool.shuffled().prefix(count))
        }
        picked.shuffle()
        return PrepositionCaseSession(
            questions: picked.map(PrepositionQuestion.init),
            topic: "\(topicPrefix): Akkusativ oder Dativ",
            answerCases: [.akkusativ, .dativ],
            focusRaw: GrammarFocus.verbenPraepositionen.rawValue,
            statKeyPrefix: statKeyPrefix
        )
    }

    static func statKey(for verb: VerbPreposition) -> String {
        statKeyPrefix + PrepositionService.key(for: verb.verb)
    }

    /// Verb pairs worth re-drilling, most-missed first.
    static func trickyStats(in context: ModelContext) -> [PrepositionStat] {
        PrepositionService.trickyStats(in: context).filter { isVerbStat($0.key) }
    }

    // MARK: - Fill-in rounds

    /// The Lückentext: every pair's sentence with its preposition + article blanked, four
    /// choices. Records against `verbenPraepositionen` through `grammaticalCase`.
    static func lueckentextCategory() -> GrammarCategory {
        let exercises = all().compactMap { pair -> GrammarExercise? in
            guard let example = pair.example else { return nil }
            return GrammarExercise(
                id: "verb-\(pair.scene)-\(PrepositionService.key(for: pair.verb))",
                sentence: example.blanked,
                correctAnswer: example.gap,
                noun: example.noun,
                gender: example.gender,
                verb: pair.verb,
                options: ([example.gap] + example.wrong).shuffled(),
                verbForm: nil,
                english: example.english,
                why: "\(pair.verb) always takes \(pair.preposition) + \(pair.governs.germanLabel)"
            )
        }
        return GrammarCategory(
            id: "verben-lueckentext",
            title: "Lückentext",
            subtitle: "Preposition and article in one",
            grammaticalCase: GrammarFocus.verbenPraepositionen.rawValue,
            articleType: "verbPreposition",
            ruleNote: "The verb decides both the preposition and the case. Learn them as one piece: warten auf + Akkusativ.",
            options: [],
            exercises: exercises
        )
    }

    /// „Die Falle“: the same prepositions as places and as parts of verb pairs, mixed. Only the
    /// article is blank, so every pick is Akkusativ against Dativ, and the feedback names
    /// which rule decided it.
    static func falleCategory() -> GrammarCategory {
        let exercises = falle().map { item in
            GrammarExercise(
                id: item.id,
                sentence: item.sentence,
                correctAnswer: item.answer,
                noun: item.noun,
                gender: item.gender,
                verb: item.preposition,
                options: item.options,
                verbForm: nil,
                english: item.english,
                why: item.why
            )
        }
        return GrammarCategory(
            id: "verben-falle",
            title: "Die Falle",
            subtitle: "Place or verb pair?",
            grammaticalCase: GrammarFocus.verbenPraepositionen.rawValue,
            articleType: "definite",
            ruleNote: "Ask what decides the case. A place or a direction: Wo? Dativ, Wohin? Akkusativ. A verb pair: the verb fixes it, moving or not.",
            options: [],
            exercises: exercises
        )
    }

    // MARK: - Matching

    /// Pair ↔ meaning, the German column tinted by case.
    @MainActor
    static func matchingSession(limit: Int, colorCoded: Bool) -> MatchingSession? {
        let picked = all().shuffled().prefix(limit)
        guard picked.count >= 4 else { return nil }
        let cards = picked.map { pair in
            VocabCard(
                germanWord: pair.verb,
                englishTranslation: pair.english,
                wordType: "verb",
                article: nil,
                exampleSentence: pair.example?.german
            )
        }
        var tints: [String: Color] = [:]
        var legend: [MatchingTintLegendItem] = []
        if colorCoded {
            for pair in picked { tints[pair.verb.lowercased()] = pair.governs.color }
            legend = [PrepositionCase.akkusativ, .dativ]
                .filter { group in picked.contains { $0.governs == group } }
                .map { MatchingTintLegendItem(label: $0.germanLabel, color: $0.color) }
        }
        return MatchingSession(
            cards: Array(cards),
            topic: "\(topicPrefix): Paare",
            deckID: nil,
            subDeckLabel: "Matching · \(cards.count) pairs",
            germanTileTints: tints,
            tintLegend: legend
        )
    }
}

extension PrepositionQuestion {
    /// A verb pair as a case-drill question: the pair on top, its English below, its scene above.
    nonisolated init(_ pair: VerbPreposition) {
        self.init(word: pair.verb, governs: pair.governs, meaning: pair.english, note: pair.note,
                  examples: pair.example.map {
                      [PrepositionExample(german: $0.german, english: $0.english, caseUsed: pair.governs)]
                  } ?? [],
                  sceneKey: pair.sceneKey)
    }
}
