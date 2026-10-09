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

    @Test func everyPairCanBeFoundInAStory() {
        for pair in verbs {
            #expect(!pair.forms.isEmpty, "\(pair.verb): no forms for the Kasus check")
            #expect(pair.forms.allSatisfy { $0 == $0.lowercased() }, "\(pair.verb): forms are matched lowercased")
            // The pair's case must be one its preposition can take, or the check would reject
            // every phrase after it.
            let own = PrepositionService.preposition(pair.preposition)?.governs
            #expect(own == pair.governs || own == .wechsel, "\(pair.verb): \(pair.preposition) can't take the \(pair.governs)")
        }
        #expect(KasusVerbPairs.match(preposition: "auf", among: ["er", "wartet", "auf"])?.verb == "warten auf")
        #expect(KasusVerbPairs.match(preposition: "auf", among: ["er", "passt", "auf"])?.verb == "aufpassen auf")
        #expect(KasusVerbPairs.match(preposition: "vor", among: ["er", "hat", "angst", "vor"])?.kasus == .dativ)
        #expect(KasusVerbPairs.match(preposition: "vor", among: ["er", "hat", "vor"]) == nil, "haben alone is no pair")
        #expect(KasusVerbPairs.match(preposition: "an", among: ["sie", "arbeitet", "an"])?.kasus == .dativ)
    }

    // MARK: - Review box

    @Test func theReviewBoxHoldsEveryPairOnce() throws {
        let (container, context) = try reviewStore()
        _ = container
        // The hub reads the counts before the box exists; that read must not create it.
        #expect(VerbPrepositionService.counts(in: context) == .init(due: 0, new: 42, learned: 0))
        #expect(try context.fetch(FetchDescriptor<SavedDeck>()).isEmpty)
        let deck = VerbPrepositionService.fetchOrCreateDeck(in: context)
        #expect(deck.cards.count == 42)
        SpacedRepetitionService.apply(rating: .good, to: deck.cards[0])
        #expect(VerbPrepositionService.counts(in: context).new == 41)
        #expect(deck.kind == .verbPrepositionSRS && !deck.isBrowsableContent)
        #expect(deck.id == SyncSingletonDecks.deckID(generatorRaw: VerbPrepositionService.deckGenerator,
                                                     topic: VerbPrepositionService.deckTopic))
        #expect(SyncSingletonDecks.isSingleton(deck))
        // Opening it again adds nothing.
        let again = VerbPrepositionService.fetchOrCreateDeck(in: context)
        #expect(again.id == deck.id && again.cards.count == 42)
        #expect(try context.fetch(FetchDescriptor<SavedDeck>()).count == 1)
    }

    @Test func aReviewIsDueFirstThenAHandfulOfNew() throws {
        let (container, context) = try reviewStore()
        _ = container
        let deck = VerbPrepositionService.fetchOrCreateDeck(in: context)
        let fresh = VerbPrepositionService.reviewQueue(deck.cards)
        #expect(fresh.count == VerbPrepositionService.newPerSession, "a first session is all new, capped")
        #expect(VerbPrepositionService.counts(deck.cards) == .init(due: 0, new: 42, learned: 0))

        // Rate three: they leave the new pile and come back once due.
        for card in fresh.prefix(3) { SpacedRepetitionService.apply(rating: .good, to: card) }
        let later = Calendar.current.date(byAdding: .day, value: 2, to: .now)!
        let queue = VerbPrepositionService.reviewQueue(deck.cards, now: later)
        #expect(Array(queue.prefix(3)).allSatisfy { !VerbPrepositionService.isNew($0) }, "due cards lead")
        #expect(queue.count == 3 + VerbPrepositionService.newPerSession)
        #expect(VerbPrepositionService.counts(deck.cards, now: later).due == 3)
        #expect(VerbPrepositionService.counts(deck.cards).new == 39)
    }

    @Test func dueVerbPairsGetTheirOwnTodayStep() {
        var snapshot = TodaySnapshot(dueCardCount: 0, weaknesses: [], hasCoachContent: false, streak: 1,
                                     studiedToday: false, hasStartedLearning: true, dayIndex: 0)
        #expect(!TodayPlanner.plan(snapshot).contains { $0.intent == .verbReview })
        snapshot.verbDue = 4
        let step = TodayPlanner.plan(snapshot).first { $0.intent == .verbReview }
        #expect(step?.title == "Verben · 4 due")
    }

    private func reviewStore() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainer(
            for: SavedDeck.self, SavedCard.self,
            configurations: SwiftData.ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return (container, ModelContext(container))
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
