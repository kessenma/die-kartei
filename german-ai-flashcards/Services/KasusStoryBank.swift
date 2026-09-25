//
//  KasusStoryBank.swift
//  german-ai-flashcards
//
//  The bundled Kasus stories (`Resources/kasus_stories.json`) and the lexicon the validator reads
//  in the app. A DEBUG run validates every story on first load and asserts it passes, the same
//  precedent as `PlacementGrammarBank.assertValid`: a broken story fails loudly on the developer's
//  simulator instead of reaching a learner.
//

import Foundation

struct KasusStoryBank {
    let version: Int
    let stories: [KasusStory]

    /// Decodes a story file. Tests and the Lab pass their own data; the app uses `bundled`.
    init(data: Data) throws {
        let file = try JSONDecoder().decode(KasusStoryFile.self, from: data)
        version = file.version
        stories = file.stories
    }

    private init(version: Int, stories: [KasusStory]) {
        self.version = version
        self.stories = stories
    }

    private static var cache: KasusStoryBank?

    /// The bundled bank, loaded and (in DEBUG) validated once. Empty if the file is missing or
    /// malformed, which a DEBUG run reports as an assertion.
    static var bundled: KasusStoryBank {
        if let cache { return cache }
        let bank: KasusStoryBank
        if let url = Bundle.main.url(forResource: "kasus_stories", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? KasusStoryBank(data: data) {
            bank = decoded
            #if DEBUG
            assertValid(bank)
            #endif
        } else {
            assertionFailure("kasus_stories.json is missing or doesn't decode")
            bank = KasusStoryBank(version: 0, stories: [])
        }
        cache = bank
        return bank
    }

    func story(id: String) -> KasusStory? {
        stories.first { $0.id == id }
    }

    func stories(for unit: KasusUnit) -> [KasusStory] {
        stories.filter { $0.unitRaw == unit.rawValue }
    }

    /// This bank with `extra` added after its own stories (a story whose id is already here is
    /// skipped): the bundled stories plus the tutor's (`KasusStoryStore.bank(in:)`).
    func merging(_ extra: [KasusStory]) -> KasusStoryBank {
        var ids = Set(stories.map(\.id))
        return KasusStoryBank(version: version, stories: stories + extra.filter { ids.insert($0.id).inserted })
    }

    #if DEBUG
    /// A malformed story should fail loudly in a debug run, not quietly lose a target.
    private static func assertValid(_ bank: KasusStoryBank) {
        let lexicon = AppKasusLexicon()
        var ids = Set<String>()
        for story in bank.stories {
            assert(ids.insert(story.id).inserted, "kasus_stories: duplicate id \(story.id)")
            assert(story.unit != nil, "kasus_stories: \(story.id) has unknown unit \(story.unitRaw)")
            assert(story.cefr != nil, "kasus_stories: \(story.id) has unknown level \(story.level)")
            assert(story.question.options.indices.contains(story.question.answer),
                   "kasus_stories: \(story.id) question answer out of range")
            assert(story.paragraphs.allSatisfy { !$0.de.isEmpty && !$0.en.isEmpty },
                   "kasus_stories: \(story.id) has a paragraph without German or English")
            let report = KasusValidator.validate(story, source: story.source, lexicon: lexicon)
            assert(report.passes, "kasus_stories: \(story.id) fails validation\n"
                   + report.issueLines.joined(separator: "\n"))
        }
    }

    /// The same bank narrowed to some stories, for checks written against a fixed set (the
    /// service's `KasusPath` expectations assume „Der verlorene Schlüssel“ alone).
    func only(_ ids: Set<String>) -> KasusStoryBank {
        KasusStoryBank(version: version, stories: stories.filter { ids.contains($0.id) })
    }

    /// `-kasus.debugVerify 1`: every bundled story's report (with its golden numbers, spot-only
    /// counts and label-proven targets), every planted-error fixture and the forms round trip, as
    /// printable lines. The first line reads like
    /// "ks-dat-a2-schluessel OK · 26 targets · form 20 · preposition 2 · copula 0 · label 4 · 0 errors".
    static func debugVerifyReport() -> String {
        debugVerifyReport(lexicon: AppKasusLexicon())
    }

    static func debugVerifyReport(lexicon: some KasusLexicon) -> String {
        KasusFixtures.verify(stories: bundled.stories, lexicon: lexicon).text
    }
    #endif
}

// MARK: - The app's lexicon

/// Gender, plural and preposition facts from the app's own data, in this order:
///   1. the plural-only list (Leute, Eltern …) and the dual-gender whitelist (Keks, Joghurt, Virus);
///   2. Wiktionary, when every noun entry agrees;
///   3. the Goethe lists, compared row by row across A1, A2 and B1 (the merged index would hide a
///      row that disagrees). „die“ + „only pl.“ is plural;
///   4. a reliable derivational suffix (-ung, -heit, -keit …);
///   5. otherwise unverified.
/// Wiktionary and Goethe disagreeing on a singular gender is a conflict. A Goethe „only pl.“ row
/// never contradicts Wiktionary's singular (die Möbel · das Möbel).
struct AppKasusLexicon: KasusLexicon {

    func gender(forLemma lemma: String) -> KasusLexiconVerdict {
        if KasusForms.isPluraleTantum(lemma) { return .verified(.plural) }
        if let dual = KasusForms.dualGenders(of: lemma) {
            return .conflict(Gender.allCases.filter(dual.contains))
        }
        let goethe = Self.goethe[lemma]?.genders ?? []
        if let wiktionary = WiktionaryValidator.shared.nounArticle(for: lemma)?.article.gender {
            let singular = goethe.subtracting([.plural])
            if singular.isEmpty || singular == [wiktionary] { return .verified(wiktionary) }
            return .conflict(Gender.allCases.filter { singular.contains($0) || $0 == wiktionary })
        }
        if goethe.count == 1, let only = goethe.first { return .verified(only) }
        if goethe.count > 1 { return .conflict(Gender.allCases.filter(goethe.contains)) }
        if let suffix = GermanGenderInference.suffixGender(for: lemma),
           let gender = Gender(columnLabel: suffix.gender) {
            return .verified(gender)
        }
        return .unverified
    }

    func goethePlural(forLemma lemma: String) -> String? {
        Self.goethe[lemma]?.plural
    }

    func prepositionCases(_ word: String) -> Set<GrammarCase>? {
        guard let preposition = PrepositionService.preposition(word) else { return nil }
        switch preposition.governs {
        case .akkusativ: return [.akkusativ]
        case .dativ:     return [.dativ]
        case .wechsel:   return [.akkusativ, .dativ]
        case .genitiv:   return [.genitiv]
        }
    }

    func isTwoWay(_ word: String) -> Bool {
        PrepositionService.preposition(word)?.governs == .wechsel
    }

    func partsOfSpeech(_ word: String) -> Set<String>? {
        WiktionaryValidator.shared.partsOfSpeech(of: word)
    }

    // MARK: Goethe rows

    private struct GoetheFacts {
        var genders: Set<Gender> = []
        var plural: String?
    }

    /// Every Goethe noun row, per headword: each gender any level's row gives, and the first
    /// plural marker (lowest level first). Built once.
    private static let goethe: [String: GoetheFacts] = {
        var facts: [String: GoetheFacts] = [:]
        for level in GoetheLevel.allCases {
            for entry in GoetheVocabService.entries(for: level) {
                guard let article = entry.article?.trimmingCharacters(in: .whitespaces).lowercased(),
                      !article.isEmpty else { continue }
                let onlyPlural = entry.plural == "only pl."
                let gender: Gender? = switch article {
                case "der": .der
                case "die": onlyPlural ? .plural : .die
                case "das": .das
                default:    nil
                }
                guard let gender else { continue }
                facts[entry.word, default: GoetheFacts()].genders.insert(gender)
                if facts[entry.word]?.plural == nil, let plural = entry.plural, !plural.isEmpty {
                    facts[entry.word]?.plural = plural
                }
            }
        }
        return facts
    }()
}
