import Foundation
import Testing
@testable import DieKarteiCore
@testable import KarteiStore

@Suite struct LearnerMemoryStoreTests {
    func store() throws -> RecordStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kartei-\(UUID().uuidString)")
            .appendingPathComponent("kartei.sqlite")
        return RecordStore(database: try KarteiDatabase(url: url), replica: "android-a")
    }

    static let lines = [
        SessionLine(isUser: true, text: "Ich gehe in die Park.", correctedText: "Ich gehe in den Park."),
        SessionLine(isUser: false, text: "Schön!", correctedText: nil),
    ]

    @Test("A finished chat lands in the one profile record and counts as a conversation")
    func sessionIsStored() throws {
        let records = try store()
        let now = Date()
        try records.applySession(summaryRaw: "WEAK: akkusativ", lines: Self.lines,
                                 savedVocab: [SavedVocabItem(german: "der Park", english: "the park")],
                                 wordsPracticed: ["Hund"], now: now)
        #expect(records.count(kind: "LearnerProfile") == 1)
        let profile = try #require(records.record(LearnerProfileRecord.self, id: SyncKinds.learnerProfileName.id))
        #expect(profile.sessionCount == 1)
        let memory = records.learnerMemory
        #expect(memory.vocab.map(\.german) == ["der Park", "Hund"])
        #expect(memory.slips.map(\.id) == ["die→den"])
        #expect(memory.grammar["akkusativ"]?.struggle == 0.3)
        #expect(records.studyDay(at: now)?["conversations"] == 1)
        #expect(records.learnerMemory.briefing.contains("der Park"))
    }

    @Test("Past the cap the oldest unpinned word is archived, once, and can be restored")
    func evictionArchivesAndRestores() throws {
        let records = try store()
        try records.updateLearnerMemory {
            $0.vocab = (0..<LearnerMemory.vocabCap).map {
                VocabTouch(german: "Wort\($0)", english: "", lastSeen: Date(timeIntervalSinceReferenceDate: Double($0)), timesUsed: 1)
            }
            return []
        }
        try records.updateLearnerMemory { $0.noteVocabEncounters([("Katze", "cat")]) }
        #expect(records.learnerMemory.vocab.count == LearnerMemory.vocabCap)
        let archived = records.archivedMemories()
        #expect(archived.map(\.title) == ["Wort0"])
        #expect(archived.first?.key == "vocab|wort0")

        try records.restore(try #require(archived.first))
        #expect(records.archivedMemories().isEmpty)
        let restored = try #require(records.learnerMemory.vocab.first { $0.german == "Wort0" })
        #expect(restored.pinned)
    }

    @Test("Writing the memory keeps the Förderplan and fields from newer builds")
    func unknownFieldsSurvive() throws {
        let records = try store()
        var profile = LearnerProfileRecord()
        profile.foerderplan = .object(["focus": .string("dativ")])
        profile.extra = ["futureField": .string("kept")]
        try records.put(profile)
        try records.updateLearnerMemory { $0.noteVocabEncounters([("Baum", "tree")]) }
        let back = records.learnerProfile
        #expect(back.foerderplan == .object(["focus": .string("dativ")]))
        #expect(back.payload["futureField"] == .string("kept"))
        #expect(back.vocab?.arrayValue?.count == 1)
    }

    @Test("Reset empties the profile and the archive")
    func resetClearsEverything() throws {
        let records = try store()
        try records.applySession(summaryRaw: "", lines: Self.lines, savedVocab: [], wordsPracticed: ["Hund"])
        try records.updateLearnerMemory { $0.archiveVocab(id: "hund").map { [$0] } ?? [] }
        #expect(records.archivedMemories().count == 1)
        try records.resetLearnerMemory()
        #expect(records.learnerMemory == LearnerMemory())
        #expect(records.archivedMemories().isEmpty)
    }
}
