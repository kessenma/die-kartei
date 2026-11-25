//
//  GapChoiceBank.swift
//  german-ai-flashcards
//
//  The bundled gap-choice items (`Resources/gap_choice_items.json`), loaded once and (in DEBUG)
//  gated on first load, the way `KasusConceptBank` does it: every item must pass `GapChoiceCheck`
//  and the pack its composition check, or the developer's simulator stops at the item. Which
//  drills a topic offers is read off the data: a focus with fewer than
//  `GapChoiceFocus.minimumItems` items in a topic isn't shown there.
//
//  Keyed on the topic's String key, not `GrammarTopic`, so training/kasus_cli compiles it.
//

import Foundation

struct GapChoiceBank {
    let version: Int
    let items: [GapChoiceItem]

    /// Decodes an item file. Tests pass their own data; the app uses `bundled`.
    init(data: Data) throws {
        let file = try JSONDecoder().decode(GapChoiceFile.self, from: data)
        version = file.version
        items = file.items
    }

    private init(version: Int, items: [GapChoiceItem]) {
        self.version = version
        self.items = items
    }

    private static var cache: GapChoiceBank?

    /// The bundled bank, loaded and (in DEBUG) gated once. Empty if the file is missing or
    /// malformed, which a DEBUG run reports as an assertion.
    static var bundled: GapChoiceBank {
        if let cache { return cache }
        let bank: GapChoiceBank
        if let url = Bundle.main.url(forResource: "gap_choice_items", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? GapChoiceBank(data: data) {
            bank = decoded
            #if DEBUG
            assertValid(bank)
            #endif
        } else {
            assertionFailure("gap_choice_items.json is missing or doesn't decode")
            bank = GapChoiceBank(version: 0, items: [])
        }
        cache = bank
        return bank
    }

    static let empty = GapChoiceBank(version: 0, items: [])

    func item(id: String) -> GapChoiceItem? {
        items.first { $0.id == id }
    }

    func items(topic: String) -> [GapChoiceItem] {
        items.filter { $0.topic == topic }
    }

    func items(topic: String, focus: GapChoiceFocus) -> [GapChoiceItem] {
        items(topic: topic).filter { $0.focus == focus }
    }

    /// The focuses a topic has enough items for, in the registry's order.
    func offered(topic: String) -> [GapChoiceFocus] {
        GapChoiceFocus.allCases.filter { offers($0, topic: topic) }
    }

    func offers(_ focus: GapChoiceFocus, topic: String) -> Bool {
        items(topic: topic, focus: focus).count >= GapChoiceFocus.minimumItems
    }

    /// This bank with `extra` added after its own items (an item whose id is already here is
    /// skipped): the seam a later batch merges in through.
    func merging(_ extra: [GapChoiceItem]) -> GapChoiceBank {
        var ids = Set(items.map(\.id))
        return GapChoiceBank(version: version, items: items + extra.filter { ids.insert($0.id).inserted })
    }

    #if DEBUG
    /// A malformed item should fail loudly in a debug run, not quietly ask the wrong thing.
    @MainActor
    private static func assertValid(_ bank: GapChoiceBank) {
        let lexicon = AppKasusLexicon()
        for item in bank.items {
            let result = GapChoiceCheck.run(item, lexicon: lexicon)
            assert(result.passes, "gap_choice_items: \(item.id) can't be played\n" + result.errors.joined(separator: "\n"))
        }
        let composition = GapChoiceCheck.composition(bank.items)
        assert(composition.isEmpty, "gap_choice_items: " + composition.map { "\($0.code.rawValue) \($0.detail)" }.joined(separator: "\n"))
    }

    /// The bundled file decoded without the load-time assert, so a report can list every
    /// problem instead of stopping at the first.
    static var bundledUnchecked: GapChoiceBank {
        guard let url = Bundle.main.url(forResource: "gap_choice_items", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? GapChoiceBank(data: data) else { return empty }
        return decoded
    }

    /// `-kasus.debugVerify 1`, after the Verstehen items: every pack with its golden numbers,
    /// every problem, and the planted-error fixtures.
    @MainActor
    static func debugVerifyReport(lexicon: some KasusLexicon) -> String {
        GapChoiceFixtures.verify(bank: bundledUnchecked, lexicon: lexicon).text
    }
    #endif
}
