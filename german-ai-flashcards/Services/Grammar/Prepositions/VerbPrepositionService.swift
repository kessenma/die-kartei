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
        guard let url = AppResources.url("verb_prepositions", "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VerbPrepositionsFile.self, from: data)
        else { return VerbPrepositionsFile(verbs: [], falle: []) }
        cache = decoded
        return decoded
    }

    /// Every pair, in the class sheet's order (Akkusativ first, then Dativ).
    static func all() -> [VerbPreposition] { file.verbs }

    /// How many scenes the pairs act in: fewer than the pairs, since a few share one.
    static var sceneCount: Int { Set(all().map(\.scene)).count }

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

// MARK: - Review box (spaced repetition)
//
// One synced SRS deck holding every pair, studied in `VerbPrepositionReviewView` with the verb
// card (gap on the front, scene, answer on the back) and the app's SM-2 scheduler. Not in the
// generic card player: that shows the German side verbatim, so „warten auf“ would sit on the
// card's face with the answer already on it, and it has no per-deck front side to turn around.
//
// The deck is a sync singleton (`SyncSingletonDecks`): its id comes from (generator, topic) and
// each card's from (deck, verb), so two devices that each create it make one deck. It fills
// itself from the whole bundled list on every open, unlike the Perfekt deck, which only ever
// holds the subsets it was launched with.

extension VerbPrepositionService {

    /// `SavedDeck.generatorRaw` for the review box. Nonisolated so `SavedDeck.kind` and the sync
    /// tables can read it off the main actor.
    nonisolated static let deckGenerator = "verb-prep-srs"
    nonisolated static let deckTopic = "Verben mit Präpositionen"

    /// New pairs a review session may introduce. A session is due cards first, then this many
    /// new ones, so the 42 arrive in steady handfuls rather than all at once.
    static let newPerSession = 10
    /// The most cards one session holds, re-shown misses aside.
    static let sessionCap = 25

    /// The review box, created on first use and topped up with any pair the bundle has gained.
    @MainActor
    @discardableResult
    static func fetchOrCreateDeck(in context: ModelContext) -> SavedDeck {
        let generator = deckGenerator
        let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.generatorRaw == generator })
        let deck: SavedDeck
        if let existing = (try? context.fetch(descriptor))?.first {
            deck = existing
        } else {
            deck = SavedDeck(topic: deckTopic, wordCount: all().count, includeExamples: true, includeGender: false)
            deck.generatorRaw = deckGenerator
            deck.id = SyncSingletonDecks.deckID(generatorRaw: deckGenerator, topic: deckTopic)
            context.insert(deck)
        }

        let existing = Set(deck.cards.map(\.germanWord))
        for (index, pair) in all().enumerated() where !existing.contains(pair.verb) {
            let card = SavedCard(
                germanWord: pair.verb,
                englishTranslation: pair.english,
                wordType: "verb",
                article: nil,
                exampleSentence: pair.example?.german,
                sortOrder: index
            )
            card.id = SyncSingletonDecks.cardID(deckID: deck.id, germanWord: pair.verb)
            deck.cards.append(card)
            context.insert(card)
        }
        deck.wordCount = deck.cards.count
        try? context.save()
        return deck
    }

    /// A never-reviewed card: new, not due.
    static func isNew(_ card: SavedCard) -> Bool {
        card.nextReviewDate == nil && card.totalReviews == 0
    }

    static func isDue(_ card: SavedCard, now: Date = .now) -> Bool {
        guard let next = card.nextReviewDate else { return false }
        return next <= now
    }

    /// Learned by the app's one rule (the pyramid's and the Wortschatz box's): three good
    /// reviews in a row, or an interval of three weeks.
    static func isLearned(_ card: SavedCard) -> Bool {
        card.interval >= 21 || card.repetitions >= 3
    }

    /// What a session would hold: every due card, soonest first, then new ones in the class
    /// sheet's order up to `newPerSession`, capped at `sessionCap`.
    static func reviewQueue(
        _ cards: [SavedCard],
        newBudget: Int = newPerSession,
        cap: Int = sessionCap,
        now: Date = .now
    ) -> [SavedCard] {
        let due = cards.filter { isDue($0, now: now) }
            .sorted { ($0.nextReviewDate ?? now) < ($1.nextReviewDate ?? now) }
        let new = cards.filter { isNew($0) }.sorted { $0.sortOrder < $1.sortOrder }.prefix(newBudget)
        return Array((due + new).prefix(cap))
    }

    struct BoxCounts: Equatable {
        var due: Int
        var new: Int
        var learned: Int
    }

    /// The box's numbers straight from the store, without creating it. For screens that show the
    /// counts but must not observe 42 cards in their body.
    static func counts(in context: ModelContext, now: Date = .now) -> BoxCounts {
        let generator = deckGenerator
        var descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.generatorRaw == generator })
        descriptor.fetchLimit = 1
        return counts((try? context.fetch(descriptor))?.first?.cards, now: now)
    }

    /// The hub row's numbers. A box not created yet is all new.
    static func counts(_ cards: [SavedCard]?, now: Date = .now) -> BoxCounts {
        guard let cards, !cards.isEmpty else {
            return BoxCounts(due: 0, new: all().count, learned: 0)
        }
        return BoxCounts(due: cards.filter { isDue($0, now: now) }.count,
                         new: cards.filter { isNew($0) }.count,
                         learned: cards.filter { isLearned($0) }.count)
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
