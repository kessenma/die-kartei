import Foundation
import Testing
@testable import DieKarteiCore

/// The coach's memory as Android runs it: the shared rules (`LearnerMemory`) on the sync record
/// (`LearnerProfileRecord`, round-tripped after every step) with archives as
/// `ArchivedMemoryRecord`s, through the script iOS's `LearnerMemoryParityTests` plays against
/// `LearnerMemoryService` and SwiftData. Every step must match learner_memory_golden.json, which
/// that iOS test writes.
@MainActor
@Suite struct LearnerMemoryTests {
    static func t(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }
    static func letter(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + i))) }

    /// Android's side of the run: the profile record and the archive.
    final class Store {
        var record = LearnerProfileRecord()
        var archive: [ArchivedMemoryRecord] = []

        var memory: LearnerMemory { LearnerMemory(record: record) }

        func update(_ rule: (inout LearnerMemory) -> [MemoryArchive]) {
            let old = memory
            var m = old
            let archived = rule(&m)
            m.write(to: &record, from: old)
            // Through the wire format, as a put and a later read would.
            record = LearnerProfileRecord(payload: record.payload)
            archive += archived.map { ArchivedMemoryRecord($0) }
        }
    }

    static func seed(_ s: Store) {
        s.update { m in
            m.sessionCount = 2
            m.lastSessionAt = t(800_000_000)
            m.grammar = [
                "akkusativ": GrammarSkill(struggle: 0.5, lastSeen: t(800_000_000), samples: ["Ich sehe der Mann → Ich sehe den Mann"]),
                "dativ": GrammarSkill(struggle: 0.05, lastSeen: t(800_000_100), samples: []),
                "perfekt": GrammarSkill(struggle: 0.3, lastSeen: t(800_000_200), samples: []),
            ]
            m.vocab = (0..<LearnerMemory.vocabCap).map { i in
                VocabTouch(german: "Wort\(i)", english: i % 3 == 0 ? "" : "word \(i)", lastSeen: t(800_000_000 + Double(i)),
                           timesUsed: 1 + i % 4, pinned: i == 0)
            }
            m.slips = (0..<LearnerMemory.slipCap).map { i in
                LexicalSlip(wrong: "der" + letter(i), right: "den" + letter(i), note: i == 1 ? "Akkusativ" : "",
                            lastSeen: t(800_000_000 + Double(i)), timesSeen: 1, pinned: i == 0,
                            source: i == 2 ? MemorySource.placement : nil)
            } + [LexicalSlip(wrong: "mit den", right: "mit dem", note: "", lastSeen: t(800_001_000), timesSeen: 2)]
            m.selfReports = (0..<9).map { i in
                SelfReportNote(text: "Notiz " + letter(i) + " über Fälle", focus: i == 3 ? "dativ" : nil,
                               notedAt: t(800_000_000 + Double(i)), pinned: i == 0)
            }
            return []
        }
    }

    static let summary = """
    Gut gemacht!
    WEAK: akkusativ, Wechselpräpositionen
    STRONG: perfekt
    """

    static func run(_ s: Store, snapshot: (String) -> Void) {
        seed(s)
        snapshot("seed")

        let lines = [
            SessionLine(isUser: true, text: "Ich gehe in die Park.", correctedText: "Ich gehe in den Park."),
            SessionLine(isUser: false, text: "Schön! Was machst du dort?", correctedText: nil),
            SessionLine(isUser: true, text: "Ich spiele mit dem Hund und sehe denc Baum.", correctedText: nil),
            SessionLine(isUser: true, text: "Gestern ich bin gegangen nach Hause.", correctedText: "Gestern bin ich nach Hause gegangen."),
            SessionLine(isUser: true, text: "Ich helfe mein Bruder.", correctedText: "Ich helfe meinem Bruder."),
        ]
        s.update {
            $0.applySession(summaryRaw: summary, lines: lines,
                            savedVocab: [SavedVocabItem(german: "der Park", english: "the park"),
                                         SavedVocabItem(german: "Wort5", english: "word five")],
                            wordsPracticed: ["Hund", "wort3"])
        }
        snapshot("session")

        s.update { $0.applySession(summaryRaw: "WEAK: dativ", lines: [lines[4]], savedVocab: [], wordsPracticed: []) }
        snapshot("session-one-weak")

        s.update {
            $0.applyDrillResult(focus: .akkusativ, correct: 9, total: 10)
            $0.applyDrillResult(focus: .genitiv, correct: 2, total: 10)
            $0.applyDrillResult(focus: .dativ, correct: 7, total: 10)
            $0.applyDrillResult(focus: .futur, correct: 0, total: 0)
            return []
        }
        snapshot("drills")

        let ids = s.memory.slips.map(\.id)
        s.update { $0.applyClozeResults(mastered: [ids[0], ids[3]], missed: [ids[4]]) }
        snapshot("cloze")

        s.update { $0.noteWrittenCorrections([("Ich habe ein Hund.", "Ich habe einen Hund."), ("Das ist gut", "Das ist sehr gut")]) }
        snapshot("written")

        s.update {
            $0.noteSelfReports([
                SelfReportNote(text: "Notiz e über Fälle!", focus: "genitiv", notedAt: t(0)),
                SelfReportNote(text: "Ich verwechsle immer dem und den, besonders nach Präpositionen wie mit oder bei und so weiter", notedAt: t(0)),
                SelfReportNote(text: "Adjektivendungen", focus: "adjektivendungen", notedAt: t(0), source: MemorySource.diktat),
            ])
        }
        snapshot("self-reports")

        s.update {
            $0.noteSlips([
                LexicalSlip(wrong: "dem", right: "den", note: "nach durch: Akkusativ", lastSeen: t(0), timesSeen: 1,
                            sentence: "Wir gehen durch den Wald.", blankIndex: 3, source: MemorySource.placement),
                LexicalSlip(wrong: "derc", right: "denc", note: "filled", lastSeen: t(0), timesSeen: 1,
                            sentence: "x", blankIndex: 0, source: MemorySource.placement),
            ])
        }
        snapshot("slips")

        s.update { $0.noteVocabEncounters([("Baum", "tree"), ("wort7", "word seven"), ("Hund", "dog")], source: "story") }
        s.update { $0.noteVocabEncounters([("Katze", "cat")]) }
        snapshot("vocab")

        s.update { $0.archiveVocab(id: "baum").map { [$0] } ?? [] }
        if let slip = s.memory.slips.last { s.update { $0.archiveSlip(id: slip.id).map { [$0] } ?? [] } }
        if let note = s.memory.selfReports.last { s.update { $0.archiveSelfReport(id: note.id).map { [$0] } ?? [] } }
        s.update {
            $0.setVocabPinned("katze", pinned: true)
            return []
        }
        let now = s.memory
        if let slip = now.slips.dropFirst().first { s.update { $0.setSlipPinned(slip.id, pinned: true); return [] } }
        if let note = now.selfReports.dropFirst().first { s.update { $0.setSelfReportPinned(note.id, pinned: true); return [] } }
        snapshot("manage")

        if let i = s.archive.firstIndex(where: { $0.kindRaw == "vocab" && $0.title == "Baum" }) {
            let item = s.archive.remove(at: i)
            s.update { $0.restore(kindRaw: item.kindRaw, payload: item.payloadData); return [] }
        }
        if let i = s.archive.firstIndex(where: { $0.kindRaw == "selfReport" && $0.reasonRaw == "removedByUser" }) {
            s.archive.remove(at: i)
        }
        snapshot("restore")
    }

    // MARK: Snapshot (as the iOS test takes it)

    static let dateKeys: Set<String> = ["lastSeen", "notedAt", "archivedAt"]

    static func number(_ j: SyncJSON) -> Double? {
        switch j {
        case .int(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }

    static func scrub(_ j: SyncJSON, start: Double) -> SyncJSON {
        switch j {
        case .object(let o):
            return .object(o.reduce(into: [:]) { out, kv in
                if dateKeys.contains(kv.key), let n = number(kv.value), n >= start {
                    out[kv.key] = .string("now")
                } else {
                    out[kv.key] = scrub(kv.value, start: start)
                }
            })
        case .array(let a): return .array(a.map { scrub($0, start: start) })
        default: return j
        }
    }

    /// A section as iOS stores it: what a default `JSONEncoder` writes, empty as absent.
    static func section<T: Encodable>(_ value: T, empty: Bool) -> SyncJSON {
        guard !empty, let data = try? JSONEncoder().encode(value), let j = try? SyncJSON(data: data) else { return .null }
        return j
    }

    static func state(_ s: Store, start: Double) -> SyncJSON {
        let m = s.memory
        let archived = s.archive
            .map { a -> SyncJSON in
                .object(["kind": .string(a.kindRaw), "reason": .string(a.reasonRaw), "title": .string(a.title),
                         "subtitle": .string(a.subtitle), "payload": a.payload ?? .null])
            }
            .sorted { String(decoding: $0.canonicalData, as: UTF8.self) < String(decoding: $1.canonicalData, as: UTF8.self) }
        let lastSession: SyncJSON = m.lastSessionAt.map {
            $0.timeIntervalSinceReferenceDate >= start ? .string("now") : .number($0.timeIntervalSinceReferenceDate)
        } ?? .null
        return scrub(.object([
            "sessionCount": .number(Double(m.sessionCount)),
            "lastSessionAt": lastSession,
            "grammar": section(m.grammar, empty: s.record.grammar == nil),
            "vocab": section(m.vocab, empty: s.record.vocab == nil),
            "slips": section(m.slips, empty: s.record.slips == nil),
            "selfReports": section(m.selfReports, empty: s.record.selfReports == nil),
            "archived": .array(archived),
            "briefing": .string(m.briefing),
            "correctionHint": .string(m.correctionHint),
            "shaky": .array(m.shakyFocuses.map { .string($0.rawValue) }),
        ]), start: start)
    }

    @Test("Android's coach memory matches iOS at every step")
    func memoryMatchesTheGolden() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("learner_memory_golden.json")
        guard case .array(let want) = try SyncJSON(data: Data(contentsOf: url)) else {
            Issue.record("learner_memory_golden.json is not an array")
            return
        }
        let store = Store()
        let start = Date().timeIntervalSinceReferenceDate - 1
        var got: [SyncJSON] = []
        Self.run(store) { label in
            got.append(.object(["step": .string(label), "state": Self.state(store, start: start)]))
        }
        #expect(got.count == want.count)
        for (w, g) in zip(want, got) {
            let label = w.objectValue?["step"].map { "\($0)" } ?? "?"
            guard let ws = w.objectValue?["state"]?.objectValue, let gs = g.objectValue?["state"]?.objectValue else {
                Issue.record("step \(label) has no state")
                continue
            }
            for key in Set(ws.keys).union(gs.keys).sorted() {
                #expect(ws[key] == gs[key], "step \(label): \(key)")
            }
        }
    }

    @Test("Slips and notes carry their ids on the wire, as the iOS codec writes them")
    func wireSectionsCarryIDs() {
        let store = Store()
        Self.seed(store)
        let slips = store.record.slips?.arrayValue ?? []
        #expect(slips.count == 21)
        #expect(slips.first?.objectValue?["id"] == .string("dera→dena"))
        #expect(slips[2].objectValue?["id"] == .string("derc→denc@placement"))
        #expect(store.record.selfReports?.arrayValue?.first?.objectValue?["id"] == .string("notiz a über fälle"))
    }

    @Test("An archived memory is named as iOS names it")
    func archiveNames() {
        let word = ArchivedMemoryRecord(LearnerMemory.archive(VocabTouch(german: "der Park", english: "the park",
                                                                         lastSeen: Self.t(1), timesUsed: 1), reason: .replacedByLRU))
        #expect(word.key == "vocab|der park")
        let blank = ArchivedMemoryRecord(MemoryArchive(kind: .selfReport, reason: .removedByUser, title: "?", subtitle: "", payload: nil))
        #expect(blank.key == "selfReport|" + blank.id.uuidString)
    }
}
