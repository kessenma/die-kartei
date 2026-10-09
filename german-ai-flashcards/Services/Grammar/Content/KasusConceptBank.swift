//
//  KasusConceptBank.swift
//  german-ai-flashcards
//
//  The bundled Verstehen items (`Resources/kasus_concepts.json`), loaded once and (in DEBUG)
//  audited on first load, the way `KasusStoryBank` does it: every item must pass the validator
//  with nothing but the story-level rules complaining (a one-sentence item is always "too short"
//  and has "too few" targets of the unit's case), and its facts must have no problems. A broken
//  item fails loudly on the developer's simulator instead of reaching a learner.
//
//  Which exercises a unit offers is read off the data: an exercise with fewer than its
//  `minimumItems` for a unit isn't shown there, which is how the Nominativ unit ends up with
//  Rollen only.
//

import Foundation

/// Where a round's items come from. Bundled now; a tutor-written set later goes through the same
/// audit and merges in by id, as the tutor's stories do.
nonisolated enum KasusConceptSource: Hashable {
    case bundled
    case generated(id: String)
}

/// One item checked for play: the validator's report, the facts, and everything wrong with it.
struct KasusConceptAudit {
    let item: KasusConceptItem
    let report: KasusReport
    let facts: KasusConceptFacts
    /// Validator errors and warnings (the story-level rules left out) plus the facts' problems.
    let problems: [String]

    var passes: Bool { problems.isEmpty }
}

struct KasusConceptBank {
    let version: Int
    let items: [KasusConceptItem]

    /// Decodes an item file. Tests pass their own data; the app uses `bundled`.
    init(data: Data) throws {
        let file = try JSONDecoder().decode(KasusConceptFile.self, from: data)
        version = file.version
        items = file.items
    }

    private init(version: Int, items: [KasusConceptItem]) {
        self.version = version
        self.items = items
    }

    private static var cache: KasusConceptBank?

    /// The bundled bank, loaded and (in DEBUG) audited once. Empty if the file is missing or
    /// malformed, which a DEBUG run reports as an assertion.
    static var bundled: KasusConceptBank {
        if let cache { return cache }
        let bank: KasusConceptBank
        if let url = Bundle.main.url(forResource: "kasus_concepts", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? KasusConceptBank(data: data) {
            bank = decoded
            #if DEBUG
            assertValid(bank)
            #endif
        } else {
            assertionFailure("kasus_concepts.json is missing or doesn't decode")
            bank = KasusConceptBank(version: 0, items: [])
        }
        cache = bank
        return bank
    }

    static let empty = KasusConceptBank(version: 0, items: [])

    func item(id: String) -> KasusConceptItem? {
        items.first { $0.id == id }
    }

    func items(for unit: KasusUnit) -> [KasusConceptItem] {
        items.filter { $0.unitRaw == unit.rawValue }
    }

    func items(for unit: KasusUnit, exercise: KasusConceptExercise) -> [KasusConceptItem] {
        items(for: unit).filter { $0.kind.exercise == exercise }
    }

    func items(for unit: KasusUnit, kind: KasusConceptKind) -> [KasusConceptItem] {
        items(for: unit).filter { $0.kind == kind }
    }

    /// The exercises a unit has enough items for, in the unit screen's order.
    func offered(for unit: KasusUnit) -> [KasusConceptExercise] {
        KasusConceptExercise.allCases.filter { offers($0, for: unit) }
    }

    func offers(_ exercise: KasusConceptExercise, for unit: KasusUnit) -> Bool {
        items(for: unit, exercise: exercise).count >= exercise.minimumItems
    }

    /// This bank with `extra` added after its own items (an item whose id is already here is
    /// skipped): the seam a tutor-written set will come in through.
    func merging(_ extra: [KasusConceptItem]) -> KasusConceptBank {
        var ids = Set(items.map(\.id))
        return KasusConceptBank(version: version, items: items + extra.filter { ids.insert($0.id).inserted })
    }

    // MARK: Audit

    /// Validates one item and reads its facts. The answer key for play, the assert at load, the
    /// debug report and the tests all go through here.
    static func audit(_ item: KasusConceptItem, lexicon: some KasusLexicon) -> KasusConceptAudit {
        let report = KasusValidator.validate(item.story, source: item.story.source, lexicon: lexicon)
        var problems = report.allIssues
            .filter { !$0.code.isStoryLevel }
            .map { issue in
                let target = issue.target.map { "#\($0 + 1) " } ?? ""
                return "\(issue.severity.rawValue) \(issue.code.rawValue) \(target)\(issue.message)"
            }
        let facts: KasusConceptFacts
        if let unit = item.unit {
            facts = .derive(item, unit: unit, located: report.located)
        } else {
            facts = KasusConceptFacts(roles: [:], asked: [], clues: [], isOVS: false, subjects: [],
                                      problems: ["unknown unit \(item.unitRaw)"])
        }
        problems += facts.problems
        return KasusConceptAudit(item: item, report: report, facts: facts, problems: problems)
    }

    #if DEBUG
    /// A malformed item should fail loudly in a debug run, not quietly ask the wrong thing.
    private static func assertValid(_ bank: KasusConceptBank) {
        let lexicon = AppKasusLexicon()
        var ids = Set<String>()
        for item in bank.items {
            assert(ids.insert(item.id).inserted, "kasus_concepts: duplicate id \(item.id)")
            assert(item.unit != nil, "kasus_concepts: \(item.id) has unknown unit \(item.unitRaw)")
            assert(CEFRLevel(rawValue: item.level) != nil, "kasus_concepts: \(item.id) has unknown level \(item.level)")
            assert(item.story.paragraphs.allSatisfy { !$0.de.isEmpty && !$0.en.isEmpty },
                   "kasus_concepts: \(item.id) has a sentence without German or English")
            for (index, phrase) in item.english {
                assert(item.story.paragraphs.contains { $0.en.contains(phrase) },
                       "kasus_concepts: \(item.id) target #\(index + 1) „\(phrase)“ isn't in the English line")
            }
            let audit = self.audit(item, lexicon: lexicon)
            assert(audit.passes, "kasus_concepts: \(item.id) can't be played\n"
                   + audit.problems.joined(separator: "\n"))
        }
    }

    /// The same bank narrowed to some items, for checks written against a fixed set.
    func only(_ ids: Set<String>) -> KasusConceptBank {
        KasusConceptBank(version: version, items: items.filter { ids.contains($0.id) })
    }

    /// The bundled file decoded without the load-time assert, so a report can list every
    /// problem instead of stopping at the first.
    static var bundledUnchecked: KasusConceptBank {
        guard let url = Bundle.main.url(forResource: "kasus_concepts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? KasusConceptBank(data: data) else { return empty }
        return decoded
    }

    /// `-kasus.debugVerify 1`, after the stories: every unit's items per kind with their golden
    /// numbers, every problem, and which exercises each unit offers.
    static func debugVerifyReport(lexicon: some KasusLexicon) -> String {
        KasusConceptFixtures.verify(bank: bundledUnchecked, lexicon: lexicon).text
    }
    #endif
}
