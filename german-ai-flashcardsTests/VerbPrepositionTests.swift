//
//  VerbPrepositionTests.swift
//  german-ai-flashcardsTests
//
//  Verben mit Präpositionen: the bundled pairs are well-formed (a content slip should fail here,
//  not in a learner's round), every pair has its scene and stills in the bundle, the fill-in
//  rounds build cleanly, a case round always offers both cases, and a verb round records under
//  `verb:` keys and its own focus without leaking into the 28-preposition counts.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
struct VerbPrepositionTests {

    private let verbs = VerbPrepositionService.all()

    @Test func theClassSheetIsAllThere() {
        #expect(verbs.count == 42)
        #expect(Set(verbs.map(\.verb)).count == 42, "a verb is listed twice")
        #expect(Set(verbs.map(\.governs)) == [.akkusativ, .dativ])
        #expect(verbs.filter { $0.governs == .akkusativ }.count == 22)
    }

    @Test func everyPairIsWellFormed() {
        for pair in verbs {
            #expect(PrepositionService.preposition(pair.preposition) != nil,
                    "\(pair.verb): \(pair.preposition) is not a preposition the app knows")
            #expect(pair.verb.hasSuffix(" \(pair.preposition)"), "\(pair.verb) should end in its preposition")
            #expect(["A1", "A2", "B1", "B2"].contains(pair.level), "\(pair.verb): level \(pair.level)")
            #expect(pair.gappedVerb.hasSuffix("___"))
            guard let example = pair.example else {
                Issue.record("\(pair.verb) has no example")
                continue
            }
            #expect(example.german.contains(example.object), "\(pair.verb): object not in the sentence")
            #expect(example.object.contains(pair.preposition) || example.object.hasPrefix(String(pair.preposition.prefix(2))),
                    "\(pair.verb): the object phrase doesn't carry the preposition")
            #expect(example.blanked.components(separatedBy: "______").count == 2,
                    "\(pair.verb): the gap must appear exactly once")
            #expect(example.wrong.count == 3, "\(pair.verb): three wrong options")
            #expect(!example.wrong.contains(example.gap), "\(pair.verb): a wrong option is the answer")
            #expect(Set(example.wrong).count == 3, "\(pair.verb): duplicate wrong options")
        }
    }

    @Test func everyPairHasItsSceneAndStills() {
        for pair in verbs {
            let pose = PrepositionScene.pose(for: pair.sceneKey)
            #expect(pose != nil, "\(pair.verb): no manifest entry \(pair.sceneKey)")
            #expect(pose?.animates == true, "\(pair.verb): a baked scene must count as live")
            #expect(Bundle.main.url(forResource: pair.sceneKey, withExtension: "usdz") != nil,
                    "\(pair.verb): \(pair.sceneKey).usdz is not in the bundle")
            for state in ["neutral", "dat"] {
                #expect(PrepositionScene.image(for: pair.sceneKey, state: state) != nil,
                        "\(pair.verb): no \(state) still")
            }
        }
    }

    @Test func dieFalleMixesPlacesAndPairs() {
        let items = VerbPrepositionService.falle()
        #expect(items.count >= 12)
        for item in items {
            #expect(item.options.contains(item.answer), "\(item.id): the answer isn't an option")
            #expect(item.sentence.components(separatedBy: "______").count == 2, "\(item.id): one gap")
        }
        // The round's point: a preposition met both ways. Every preposition with a place item
        // also has a verb item.
        let places = Set(items.filter { $0.kind == .ort }.map(\.preposition))
        let pairs = Set(items.filter { $0.kind == .verb }.map(\.preposition))
        #expect(places.isSubset(of: pairs), "place items without a verb counterpart: \(places.subtracting(pairs))")
    }

    @Test func theFillInRoundsBuild() {
        let blanks = VerbPrepositionService.lueckentextCategory()
        #expect(blanks.exercises.count == 42)
        #expect(blanks.grammaticalCase == GrammarFocus.verbenPraepositionen.rawValue)
        for exercise in blanks.exercises {
            #expect(exercise.options?.contains(exercise.correctAnswer) == true, "\(exercise.id)")
            #expect(exercise.options?.count == 4, "\(exercise.id)")
        }
        let falle = VerbPrepositionService.falleCategory()
        #expect(falle.exercises.count == VerbPrepositionService.falle().count)
    }

    @Test func aCaseRoundOffersBothCases() throws {
        let (container, context) = try store()
        _ = container
        let session = try #require(VerbPrepositionService.caseSession(count: 10, trickyFirst: true, in: context))
        #expect(session.answerCases == [.akkusativ, .dativ])
        #expect(session.questions.count == 10)
        #expect(session.focusRaw == GrammarFocus.verbenPraepositionen.rawValue)
        #expect(session.questions.allSatisfy { $0.sceneKey.hasPrefix("verb3d-") })
        #expect(VerbPrepositionService.isVerbTopic(session.topic))
    }

    @Test func aVerbRoundRecordsApartFromThePrepositions() throws {
        let (container, context) = try store()
        _ = container
        let session = try #require(VerbPrepositionService.caseSession(count: 6, trickyFirst: false, in: context))
        let outcomes = session.questions.map {
            PrepositionAnswerOutcome(word: $0.word, governs: $0.governs, meaning: $0.meaning,
                                     firstTry: false, wrongPick: $0.governs == .akkusativ ? .dativ : .akkusativ)
        }
        _ = PrepositionService.recordRound(
            PrepositionRoundResult(outcomes: outcomes, durationSeconds: 40),
            topic: session.topic, feedCoach: false,
            focus: .verbenPraepositionen, keyPrefix: session.statKeyPrefix, in: context
        )

        let stats = try context.fetch(FetchDescriptor<PrepositionStat>())
        #expect(stats.count == 6)
        #expect(stats.allSatisfy { VerbPrepositionService.isVerbStat($0.key) })
        // The preposition side never resolves a verb stat to a preposition.
        #expect(PrepositionService.trickyPrepositions(in: context).isEmpty)

        let grammar = try context.fetch(FetchDescriptor<LearnerProfile>()).first?.grammar ?? [:]
        #expect(grammar[GrammarFocus.verbenPraepositionen.rawValue] != nil, "the verb focus moved")
        #expect(grammar[GrammarFocus.praepositionen.rawValue] == nil, "the preposition focus did not")
    }

    private func store() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainer(
            for: LearnerProfile.self, StudyDay.self, PrepositionStat.self, PrepositionRound.self,
            configurations: SwiftData.ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return (container, ModelContext(container))
    }
}
