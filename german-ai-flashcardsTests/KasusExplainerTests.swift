import Foundation
import Testing
@testable import Die_Kartei

@Suite("Case explainers")
@MainActor
struct KasusExplainerTests {
    @Test("Every explainer renders clean markup and links to practice")
    func content() {
        let items = KasusExplainer.all
        #expect(Set(items.map(\.id)).count == items.count)
        for item in items {
            #expect(!item.units.isEmpty)
            #expect(item.examples.count >= 2)
            let strings = [item.idea, item.takeaway, item.prompt, item.reveal]
                + item.examples.flatMap { [$0.de, $0.en, $0.why] }
            for string in strings {
                #expect(!string.isEmpty)
                #expect(RichMarkup.problems(string).isEmpty, Comment(rawValue: "\(item.id): \(string)"))
            }
            #expect(URL(string: item.source)?.scheme == "https")
        }
    }

    @Test("Every case has relevant explainers; all cases exposes the full library")
    func coverage() {
        for unit in KasusUnit.allCases {
            let items = KasusExplainer.forUnit(unit)
            #expect(!items.isEmpty)
            if unit != .alleFaelle {
                #expect(items.allSatisfy { $0.units.contains(unit) })
            }
        }
        #expect(KasusExplainer.forUnit(.alleFaelle).map(\.id) == KasusExplainer.all.map(\.id))
        #expect(KasusExplainer.forUnit(nil).map(\.id) == KasusExplainer.all.map(\.id))
    }
}
