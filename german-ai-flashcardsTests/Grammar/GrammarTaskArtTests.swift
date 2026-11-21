//
//  GrammarTaskArtTests.swift
//  german-ai-flashcardsTests
//
//  The task-preview drawings (`GrammarTaskArt`) hold their contracts: the slugs are asset names, so
//  renaming one orphans a future baked still; every step's drawing is spelled out, because a shared
//  drawing is a *claim* that two exercises ask the same thing; no two exercises offered in one
//  section of one topic may look alike, which is the property the learner actually experiences; and
//  no drawing is unreachable.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Grammar task art")
struct GrammarTaskArtTests {

    /// The raw values are asset slugs (`task-art-word-gap`): renaming one orphans a render.
    @Test("The asset slugs, pinned")
    func slugs() {
        #expect(GrammarTaskArt.allCases.map(\.rawValue) == [
            "word-gap", "ending-gap", "snap-ending", "pick-of-two", "verb-decides",
            "spot-the-odd-one", "follow-the-subject", "mark-words", "tag-phrases",
            "two-readings", "swap-in-place", "three-step-chain",
            "ring-one-span", "forked-path", "pick-the-phrase",
            "label-one-word", "match-pairs", "card-stack", "review-queue", "idea-card",
            "beat-the-clock", "fill-the-grid",
        ])
        for art in GrammarTaskArt.allCases {
            #expect(art.assetName == "task-art-\(art.rawValue)")
            #expect(!art.rawValue.contains("_"), "slugs are kebab-case, for the asset catalog")
        }
    }

    /// Every step's drawing, spelled out. Changing one is a test edit, never a drive-by.
    @Test("Every step's art, pinned")
    func stepArt() {
        let want: [KasusRoundStep: GrammarTaskArt] = [
            .find: .markWords, .fill: .endingGap, .quick: .wordGap, .build: .snapEnding,
            .roles: .tagPhrases, .wer: .twoReadings, .probe: .swapInPlace, .lesson: .ideaCard,
            .blitz: .beatTheClock, .pair: .pickOfTwo, .dativVerbs: .verbDecides,
            .fehler: .spotTheOddOne, .reflexCase: .pickOfTwo,
            .reflexPerson: .followTheSubject, .bridge: .threeStepChain,
            .frage: .ringOneSpan, .englischeFalle: .forkedPath, .findeFall: .pickThePhrase,
            .tabelle: .fillTheGrid,
        ]
        for step in KasusRoundStep.allCases {
            #expect(step.meta.art == want[step], "\(step.rawValue) changed its drawing")
        }
        // The one intended share: both are „a gap, and exactly two candidates“, and they never
        // appear in the same section (`pair` is `.hidden`, launched from the confusion card).
        #expect(KasusRoundStep.pair.meta.art == KasusRoundStep.reflexCase.meta.art)
        // The duplication that started this: Endungen and the Schnellrunde both wore
        // `character.cursor.ibeam`, and a Blitzrunde is not a Schnellrunde.
        #expect(KasusRoundStep.fill.meta.symbol == KasusRoundStep.quick.meta.symbol)
        #expect(KasusRoundStep.fill.meta.art != KasusRoundStep.quick.meta.art)
        #expect(KasusRoundStep.quick.meta.art != KasusRoundStep.blitz.meta.art)
    }

    /// The gate: a learner looking at one section must never see one drawing twice.
    @Test("No two exercises in one section share a drawing")
    @MainActor
    func distinctWithinSection() {
        for topic in GrammarTopic.allCases {
            for placement in [KasusDrillMeta.Placement.ueben, .verstehen] {
                let arts = topic.exercises().filter { $0.meta.placement == placement }.map(\.meta.art)
                #expect(Set(arts).count == arts.count,
                        "\(topic.key) · \(placement): \(arts.map(\.rawValue)) repeats a drawing")
            }
            // The Verstehen section shows the Lektion above the exercises, so it counts too.
            let verstehen = topic.exercises().filter { $0.meta.placement == .verstehen }.map(\.meta.art)
            #expect(!verstehen.contains(KasusRoundStep.lesson.meta.art),
                    "\(topic.key): an exercise wears the Lektion's drawing")
        }
    }

    /// No orphan drawing: every case is a step's, or one of the hand-wired rows' (the preposition
    /// hub and the article game have no registry to read).
    @Test("Every drawing is reached by something")
    func noOrphans() {
        let fromRegistry = Set(KasusRoundStep.allCases.map(\.meta.art))
        /// `PrepositionHubView` and the Artikel room pass these by hand.
        let handWired: Set<GrammarTaskArt> = [.labelOneWord, .matchPairs, .cardStack, .reviewQueue]
        #expect(fromRegistry.count == 18, "19 steps share one drawing, so 18 distinct")
        #expect(fromRegistry.isDisjoint(with: handWired),
                "a hand-wired drawing drifted into the registry; give the step its own or drop the literal")
        #expect(fromRegistry.union(handWired) == Set(GrammarTaskArt.allCases),
                "orphan drawings: \(Set(GrammarTaskArt.allCases).subtracting(fromRegistry.union(handWired)).map(\.rawValue))")
    }

    /// The Verstehen rows read the registry rather than carrying a second copy.
    @Test("The Verstehen exercises forward their art")
    func conceptForwards() {
        for exercise in KasusConceptExercise.allCases {
            #expect(exercise.art == exercise.kind.meta.art)
        }
        #expect(KasusConceptExercise.roles.art == .tagPhrases)
    }
}
