import Foundation
import Testing
@testable import DieKarteiCore
@testable import KarteiStore

@MainActor
@Suite struct PhraseStoreTests {
    func store() throws -> RecordStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kartei-\(UUID().uuidString)")
            .appendingPathComponent("kartei.sqlite")
        return RecordStore(database: try KarteiDatabase(url: url), replica: "android-a")
    }

    static let scenario = ConversationScenario.allCases.first!

    func phrase(_ german: String, active: Bool = true, focus: [String] = [], created: Double) -> LearnedPhraseRecord {
        var p = LearnedPhraseRecord(german: german, english: "", createdAt: Date(timeIntervalSinceReferenceDate: created))
        p.scenarioTagsRaw = [Self.scenario.rawValue]
        p.focusAreasRaw = focus
        p.isActive = active
        return p
    }

    @Test("A chat rotates through the library: unsurfaced first, then the longest unseen")
    func rotation() throws {
        let records = try store()
        let a = phrase("Sonst noch etwas?", created: 1)
        let b = phrase("Bar oder mit Karte?", focus: ["dativ"], created: 2)
        let off = phrase("Möchten Sie eine Tüte?", active: false, created: 3)
        for p in [a, b, off] { try records.savePhrase(p) }
        #expect(records.phrases().map(\.german) == ["Möchten Sie eine Tüte?", "Bar oder mit Karte?", "Sonst noch etwas?"])

        let first = PhraseRotation.sample(for: Self.scenario, from: records.phrases(), limit: 1)
        #expect(first.count == 1)
        try records.markSurfaced(first.map(\.id), at: Date(timeIntervalSinceReferenceDate: 100))
        let next = PhraseRotation.sample(for: Self.scenario, from: records.phrases(), limit: 1)
        #expect(next.map(\.id) != first.map(\.id), "the other active phrase comes next")
        #expect(!PhraseRotation.sample(for: Self.scenario, from: records.phrases()).contains { $0.id == off.id })

        var config = ConversationConfig(model: MLXModel.allCases.first!)
        config.focusAreas = [.perfekt]
        PhraseRotation.begin(&config, with: [b])
        #expect(config.learnedPhrases.map(\.german) == ["Bar oder mit Karte?"])
        #expect(config.focusAreas == GrammarFocus.allCases.filter { [.perfekt, .dativ].contains($0) })
    }

    @Test("Deleting a phrase removes it")
    func delete() throws {
        let records = try store()
        let a = phrase("Sonst noch etwas?", created: 1)
        try records.savePhrase(a)
        try records.deletePhrase(a.id)
        #expect(records.phrases().isEmpty)
    }
}
