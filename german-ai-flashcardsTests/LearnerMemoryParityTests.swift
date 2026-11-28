//
//  LearnerMemoryParityTests.swift
//  german-ai-flashcardsTests
//
//  The coach's memory (`LearnerMemoryService`) through a fixed script of sessions, drills and
//  hand-offs, snapshotted after every step into DieKarteiCore/Tests/DieKarteiCoreTests/
//  learner_memory_golden.json. The core test replays the same script through the shared rules
//  Android runs (`LearnerMemoryRules`), so both apps remember a learner the same way.
//
//  Regenerate after a deliberate change:
//    TEST_RUNNER_LEARNER_GOLDEN_WRITE=1 xcodebuild test … -only-testing:german-ai-flashcardsTests/LearnerMemoryParityTests
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct LearnerMemoryParityTests {
    static let goldenURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DieKarteiCore/Tests/DieKarteiCoreTests/learner_memory_golden.json")

    static func letter(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + i))) }

    static func t(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }

    /// The seeded profile: vocab and slips at their caps (one pinned of each among the oldest),
    /// two grammar keys, nine notes.
    static func seed(_ p: LearnerProfile) {
        p.sessionCount = 2
        p.lastSessionAt = t(800_000_000)
        p.grammar = [
            "akkusativ": GrammarSkill(struggle: 0.5, lastSeen: t(800_000_000), samples: ["Ich sehe der Mann → Ich sehe den Mann"]),
            "dativ": GrammarSkill(struggle: 0.05, lastSeen: t(800_000_100), samples: []),
            "perfekt": GrammarSkill(struggle: 0.3, lastSeen: t(800_000_200), samples: []),
        ]
        p.vocab = (0..<LearnerProfile.vocabCap).map { i in
            VocabTouch(german: "Wort\(i)", english: i % 3 == 0 ? "" : "word \(i)", lastSeen: t(800_000_000 + Double(i)),
                       timesUsed: 1 + i % 4, pinned: i == 0)
        }
        p.slips = (0..<LearnerProfile.slipCap).map { i in
            LexicalSlip(wrong: "der" + letter(i), right: "den" + letter(i), note: i == 1 ? "Akkusativ" : "",
                        lastSeen: t(800_000_000 + Double(i)), timesSeen: 1, pinned: i == 0,
                        source: i == 2 ? MemorySource.placement : nil)
        } + [LexicalSlip(wrong: "mit den", right: "mit dem", note: "", lastSeen: t(800_001_000), timesSeen: 2)]
        p.selfReports = (0..<9).map { i in
            SelfReportNote(text: "Notiz " + letter(i) + " über Fälle", focus: i == 3 ? "dativ" : nil,
                           notedAt: t(800_000_000 + Double(i)), pinned: i == 0)
        }
    }

    /// The script, step by step. Each returns its label.
    static let summary = """
    Gut gemacht!
    WEAK: akkusativ, Wechselpräpositionen
    STRONG: perfekt
    """

    static func run(_ context: ModelContext, snapshot: (String) -> Void) {
        seed(LearnerMemoryService.profile(in: context))
        snapshot("seed")

        let lines: [(ChatRole, String, String?)] = [
            (.user, "Ich gehe in die Park.", "Ich gehe in den Park."),
            (.assistant, "Schön! Was machst du dort?", nil),
            (.user, "Ich spiele mit dem Hund und sehe denc Baum.", nil),
            (.user, "Gestern ich bin gegangen nach Hause.", "Gestern bin ich nach Hause gegangen."),
            (.user, "Ich helfe mein Bruder.", "Ich helfe meinem Bruder."),
        ]
        let messages = lines.enumerated().map { i, l in
            let m = ChatMessage(role: l.0, text: l.1, sortOrder: i)
            m.correctedText = l.2
            context.insert(m)
            return m
        }
        LearnerMemoryService.applySession(
            summaryRaw: summary, messages: messages,
            savedVocab: [SavedVocabItem(german: "der Park", english: "the park"), SavedVocabItem(german: "Wort5", english: "word five")],
            wordsPracticed: ["Hund", "wort3"], in: context)
        snapshot("session")

        LearnerMemoryService.applySession(summaryRaw: "WEAK: dativ", messages: [messages[4]], savedVocab: [],
                                          wordsPracticed: [], in: context)
        snapshot("session-one-weak")

        LearnerMemoryService.applyDrillResult(focus: .akkusativ, correct: 9, total: 10, in: context)
        LearnerMemoryService.applyDrillResult(focus: .genitiv, correct: 2, total: 10, in: context)
        LearnerMemoryService.applyDrillResult(focus: .dativ, correct: 7, total: 10, in: context)
        LearnerMemoryService.applyDrillResult(focus: .futur, correct: 0, total: 0, in: context)
        snapshot("drills")

        let p = LearnerMemoryService.profile(in: context)
        let ids = p.slips.map(\.id)
        #expect(ids.count >= 5)
        if ids.count >= 5 {
            LearnerMemoryService.applyClozeResults(mastered: [ids[0], ids[3]], missed: [ids[4]], seconds: 30, in: context)
        }
        snapshot("cloze")

        LearnerMemoryService.noteWrittenCorrections([("Ich habe ein Hund.", "Ich habe einen Hund."),
                                                     ("Das ist gut", "Das ist sehr gut")], in: context)
        snapshot("written")

        LearnerMemoryService.noteSelfReports([
            SelfReportNote(text: "Notiz e über Fälle!", focus: "genitiv", notedAt: t(0)),
            SelfReportNote(text: "Ich verwechsle immer dem und den, besonders nach Präpositionen wie mit oder bei und so weiter", notedAt: t(0)),
            SelfReportNote(text: "Adjektivendungen", focus: "adjektivendungen", notedAt: t(0), source: MemorySource.diktat),
        ], in: context)
        snapshot("self-reports")

        LearnerMemoryService.noteSlips([
            LexicalSlip(wrong: "dem", right: "den", note: "nach durch: Akkusativ", lastSeen: t(0), timesSeen: 1,
                        sentence: "Wir gehen durch den Wald.", blankIndex: 3, source: MemorySource.placement),
            LexicalSlip(wrong: "derc", right: "denc", note: "filled", lastSeen: t(0), timesSeen: 1,
                        sentence: "x", blankIndex: 0, source: MemorySource.placement),
        ], in: context)
        snapshot("slips")

        LearnerMemoryService.noteVocabEncounters([("Baum", "tree"), ("wort7", "word seven"), ("Hund", "dog")],
                                                 source: "story", in: context)
        LearnerMemoryService.noteMatchingTrouble([("Katze", "cat")], in: context)
        snapshot("vocab")

        LearnerMemoryService.archiveVocab(id: "baum", in: context)
        if let slip = LearnerMemoryService.profile(in: context).slips.last {
            LearnerMemoryService.archiveSlipItem(id: slip.id, in: context)
        }
        if let note = LearnerMemoryService.profile(in: context).selfReports.last {
            LearnerMemoryService.archiveSelfReport(id: note.id, in: context)
        }
        LearnerMemoryService.setVocabPinned("katze", pinned: true, in: context)
        let now = LearnerMemoryService.profile(in: context)
        #expect(now.slips.count >= 2 && now.selfReports.count >= 2, "slips \(now.slips.count), notes \(now.selfReports.count)")
        if let slip = now.slips.dropFirst().first { LearnerMemoryService.setSlipPinned(slip.id, pinned: true, in: context) }
        if let note = now.selfReports.dropFirst().first { LearnerMemoryService.setSelfReportPinned(note.id, pinned: true, in: context) }
        snapshot("manage")

        let archived = (try? context.fetch(FetchDescriptor<ArchivedMemoryItem>())) ?? []
        if let item = archived.first(where: { $0.kindRaw == "vocab" && $0.title == "Baum" }) {
            LearnerMemoryService.restore(item, in: context)
        }
        if let item = archived.first(where: { $0.kindRaw == "selfReport" && $0.reasonRaw == "removedByUser" }) {
            LearnerMemoryService.forget(item, in: context)
        }
        snapshot("restore")
    }

    // MARK: Snapshot

    static let dateKeys: Set<String> = ["lastSeen", "notedAt", "archivedAt"]

    /// A date set by "now" during the run prints as "now"; seeded dates stay numbers.
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

    static func number(_ j: SyncJSON) -> Double? {
        switch j {
        case .int(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }

    static func json(_ data: Data?) -> SyncJSON {
        guard let data, let j = try? SyncJSON(data: data) else { return .null }
        return j
    }

    static func state(_ context: ModelContext, start: Double) -> SyncJSON {
        let p = LearnerMemoryService.profile(in: context)
        let archived = ((try? context.fetch(FetchDescriptor<ArchivedMemoryItem>())) ?? [])
            .map { a -> SyncJSON in
                .object(["kind": .string(a.kindRaw), "reason": .string(a.reasonRaw), "title": .string(a.title),
                         "subtitle": .string(a.subtitle), "payload": json(a.payload)])
            }
            .sorted { String(decoding: $0.canonicalData, as: UTF8.self) < String(decoding: $1.canonicalData, as: UTF8.self) }
        let lastSession: SyncJSON = p.lastSessionAt.map {
            $0.timeIntervalSinceReferenceDate >= start ? .string("now") : .number($0.timeIntervalSinceReferenceDate)
        } ?? .null
        return scrub(.object([
            "sessionCount": .number(Double(p.sessionCount)),
            "lastSessionAt": lastSession,
            "grammar": json(p.grammarData),
            "vocab": json(p.vocabData),
            "slips": json(p.slipsData),
            "selfReports": json(p.selfReportsData),
            "archived": .array(archived),
            "briefing": .string(LearnerMemoryService.briefing(in: context)),
            "correctionHint": .string(LearnerMemoryService.correctionHint(in: context)),
            "shaky": .array(LearnerMemoryService.shakyFocuses(p).map { .string($0.rawValue) }),
        ]), start: start)
    }

    @Test func memoryMatchesTheGolden() throws {
        let context = ModelContext(ModelContainer.inMemory([LearnerProfile.self, ArchivedMemoryItem.self,
                                                            ChatMessage.self, ChatConversation.self, StudyDay.self]))
        let start = Date().timeIntervalSinceReferenceDate - 1
        var steps: [SyncJSON] = []
        Self.run(context) { label in
            steps.append(.object(["step": .string(label), "state": Self.state(context, start: start)]))
        }
        let doc = SyncJSON.array(steps)
        if ProcessInfo.processInfo.environment["LEARNER_GOLDEN_WRITE"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(doc).write(to: Self.goldenURL)
            return
        }
        let golden = try SyncJSON(data: Data(contentsOf: Self.goldenURL))
        guard case .array(let want) = golden, case .array(let got) = doc else { Issue.record("bad golden"); return }
        #expect(want.count == got.count)
        for (w, g) in zip(want, got) {
            #expect(w == g, "step \(w.objectValue?["step"].map { "\($0)" } ?? "?")")
        }
    }
}
