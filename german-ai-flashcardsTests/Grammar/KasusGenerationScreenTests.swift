//
//  KasusGenerationScreenTests.swift
//  german-ai-flashcardsTests
//
//  Phase 3's screens, below the views: the plain-English lines the generation sheet shows for a
//  try that didn't pass, the English under the fallback note, tutor names, the unit row's
//  availability states, and the Kasus Lab's runner (runs, a refusal ending the batch, the „reads
//  right“ tap reaching the export). Canned output throughout: MLX doesn't run in the simulator.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Kasus generation screens")
struct KasusGenerationScreenTests {

    private let lexicon = KasusTestData.lexicon

    private func generate(_ unit: KasusUnit, _ kind: KasusCannedOutput) async -> KasusGenerationResult {
        await KasusStoryGenerator(writer: KasusGenerationFixtures.writer(for: unit, kind), lexicon: lexicon)
            .generate(KasusGenerationFixtures.request(for: unit))
    }

    // MARK: - The sheet's lines

    @Test("A wrong article is named with its phrase, on both tries")
    func failureWrongArticle() async throws {
        let result = await generate(.dativ, .wrongArticle)
        #expect(result.outcome == .fallback && result.attempts.count == 2)
        for attempt in result.attempts {
            #expect(KasusGenerationCopy.failure(of: attempt, unit: .dativ) == "a preposition with the wrong case („den Hund“)")
        }
    }

    @Test("Too few answers name the unit's case and how many there were")
    func failureTooFew() async throws {
        let result = await generate(.akkusativ, .tooFew)
        let attempt = try #require(result.attempts.first)
        let line = KasusGenerationCopy.failure(of: attempt, unit: .akkusativ)
        #expect((line.hasPrefix("only ") || line.hasPrefix("no ")) && line.hasSuffix(" in the Akkusativ"), "\(line)")
        #expect(!line.contains("only 0") && !line.contains("only 1 answers"), "\(line)")

        let alle = await generate(.alleFaelle, .tooFew)
        let alleAttempt = try #require(alle.attempts.first)
        #expect(KasusGenerationCopy.failure(of: alleAttempt, unit: .alleFaelle) == "not two answers in every case")
    }

    @Test("A write that threw, and a story that passed, read sensibly")
    func failureEdgeCases() async throws {
        let good = await generate(.dativ, .good)
        let passing = try #require(good.passing)
        #expect(KasusGenerationCopy.failure(of: passing, unit: .dativ) == "it didn't pass the check")

        let empty = KasusCannedWriter(texts: [""])
        let nothing = await KasusStoryGenerator(writer: empty, lexicon: lexicon)
            .generate(KasusGenerationFixtures.request(for: .dativ))
        let attempt = try #require(nothing.attempts.first)
        #expect(KasusGenerationCopy.failure(of: attempt, unit: .dativ) == "no story came back")
    }

    @Test("Both German notes have their English line; anything else has none")
    func noteEnglish() {
        #expect(KasusGenerationCopy.english(forNote: KasusStoryGenerator.fallbackNote)?.contains("didn't pass the check") == true)
        #expect(KasusGenerationCopy.english(forNote: KasusStoryGenerator.unavailableNote)?.contains("couldn't write") == true)
        #expect(KasusGenerationCopy.english(forNote: "Pictures are being drawn.") == nil)
    }

    @Test("Tutor names drop „German Tutor“; canned ids read as Canned · kind")
    func tutorNames() {
        #expect(KasusGenerationCopy.tutorName(MLXModel.gemma4_E4B_german.rawValue) == "Gemma 4 E4B")
        #expect(KasusGenerationCopy.shortName(.granite2B_german) == "Granite 2B")
        #expect(KasusGenerationCopy.tutorName("canned:wrongArticle") == "Canned · wrongArticle")
        #expect(KasusGenerationCopy.tutorName("something-else") == "something-else")
    }

    @Test("The unit row is hidden with the toggle off, and never ready without a tutor on disk")
    func availabilityStates() {
        let pick = MLXModel.gemma4_E2B_german
        #expect(KasusStoryGenerator.availability(selectedStoryModel: pick, enabled: false) == .hidden)
        let none = ModelReadiness(appleIntelligence: false, tutor: nil, fittingTutor: nil, hasImageModel: false)
        let state = KasusStoryGenerator.availability(selectedStoryModel: pick, readiness: none, enabled: true)
        if case .ready = state { Issue.record("no tutor on disk, yet the row is ready") }
    }

    // MARK: - The Lab's runner

    @Test("The Lab runs every canned kind in turn and exports one line per attempt")
    func labRunner() async throws {
        let runner = KasusLabRunner()
        let kinds = KasusCannedOutput.allCases
        await runner.run(count: kinds.count) { index in
            let writer = KasusCannedWriter(texts: [KasusGenerationFixtures.output(for: .dativ, kinds[index])], modelID: "canned:mix")
            return (KasusStoryGenerator(writer: writer, lexicon: lexicon), KasusGenerationFixtures.request(for: .dativ))
        }
        #expect(runner.runs.count == 4 && !runner.isRunning && runner.generator == nil && runner.stoppedNote == nil)
        #expect(runner.runs.map(\.result.outcome) == [.generated, .generated, .fallback, .fallback])

        let summary = try #require(KasusLab.summaries(runner.runs).first)
        #expect(summary.modelID == "canned:mix" && summary.runs == 4 && summary.passedFirstTry == 2)

        let document = try #require(runner.exports["canned:mix"])
        #expect(document.fileName == "kasus-lab_canned_mix.jsonl")
        let lines = String(decoding: document.data, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 6, "good 1 + altered 1 + wrongArticle 2 + tooFew 2 attempts")

        // The tap reaches the export, and a second tap on the same answer clears it.
        let first = try #require(runner.runs.first)
        runner.setReadsRight(true, for: first.id)
        #expect(runner.runs.first?.readsRight == true)
        let record = try JSONDecoder().decode(KasusLabRecord.self,
                                              from: Data(String(decoding: try #require(runner.exports["canned:mix"]).data, as: UTF8.self)
                                                .split(separator: "\n")[0].utf8))
        #expect(record.readsRight == true && record.passed)
        runner.setReadsRight(nil, for: first.id)
        #expect(runner.runs.first?.readsRight == nil)

        runner.clear()
        #expect(runner.runs.isEmpty && runner.exports.isEmpty)
    }

    @Test("A refusal to load the tutor ends the Lab's batch with its reason")
    func labRunnerRefusal() async {
        let runner = KasusLabRunner()
        await runner.run(count: 5) { _ in
            let writer = KasusGenerationFixtures.writer(for: .dativ, .good)
            writer.prepareFailure = "Pictures are being drawn."
            return (KasusStoryGenerator(writer: writer, lexicon: lexicon), KasusGenerationFixtures.request(for: .dativ))
        }
        #expect(runner.runs.count == 1 && runner.runs.first?.result.outcome == .failed)
        #expect(runner.stoppedNote == "Pictures are being drawn.")
    }
}
