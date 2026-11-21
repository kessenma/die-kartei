//
//  PhraseGapPlannerTests.swift
//  german-ai-flashcardsTests
//
//  Which word a phrase card hides and what it offers instead (Services/PhraseGapPlanner.swift).
//  The verb lookup is passed in, so these run without the bundled dictionary.
//

import Foundation
import SwiftUI
import Testing
@testable import Die_Kartei

@Suite struct PhraseGapPlannerTests {

    private let verbs: Set<String> = ["beheben", "sein", "freuen", "konfigurieren", "entwickeln", "haben", "sammeln"]
    private func isVerb(_ word: String) -> Bool { verbs.contains(word.lowercased()) }

    private func gap(_ phrase: String, pairs: Set<String> = []) -> PhraseGapPlanner.Gap? {
        PhraseGapPlanner.gap(in: phrase, isVerb: isVerb, verbPrepositions: pairs)
    }

    // MARK: - Where the gap goes

    @Test func aNounAndVerbHidesTheVerb() {
        #expect(gap("eine Störung beheben")?.answer == "beheben")
        #expect(gap("eine Störung beheben")?.kind == .verb)
        #expect(gap("der Meinung sein")?.answer == "sein")
    }

    @Test func aPrepositionalPhraseHidesThePreposition() {
        #expect(gap("Erfahrung mit Git")?.answer == "mit")
        #expect(gap("fundierte Kenntnisse in Python")?.answer == "in")
        #expect(gap("Erfahrung mit Git")?.kind == .preposition)
    }

    @Test func aKnownVerbPrepositionPairHidesThePreposition() {
        #expect(gap("sich freuen auf", pairs: ["freuen auf"])?.answer == "auf")
        // Without the pair it is the verb's phrase.
        #expect(gap("sich freuen auf")?.answer == "freuen")
    }

    @Test func otherwiseTheLongestContentWord() {
        #expect(gap("eine vergleichbare Qualifikation")?.answer == "Qualifikation")
        #expect(gap("Das ist gut")?.kind == .word)
    }

    @Test func aSentenceHidesItsKeyNoun() {
        #expect(gap("Ich habe Berufserfahrung im Support.")?.answer == "Berufserfahrung")
    }

    @Test func punctuationStaysOutOfTheAnswer() throws {
        let found = try #require(gap("Wir beheben die Störung schnell."))
        #expect(!found.answer.contains("."))
    }

    @Test func aSingleWordHasNoGap() {
        #expect(gap("beheben") == nil)
    }

    // MARK: - Choices

    private func deck(_ entries: [(String, String?)]) -> [PhraseGapPlanner.DeckWord] {
        entries.map { PhraseGapPlanner.DeckWord(german: $0.0, wordType: $0.1) }
    }

    @Test func fourChoicesOfTheSameKindWithTheAnswerAmongThem() throws {
        let cards = deck([("eine Störung beheben", CardKind.phrase), ("Erfahrung mit Git", CardKind.phrase),
                          ("konfigurieren", "verb"), ("entwickeln", "verb")])
        let questions = PhraseGapPlanner.questions(for: cards, isVerb: isVerb)
        let verb = try #require(questions[0])
        #expect(verb.options.count == 4)
        #expect(verb.options.contains("beheben"))
        #expect(Set(verb.options).count == 4)
        #expect(verb.options.allSatisfy(PhraseGapPlanner.looksInfinitive))
        // The deck's own verbs come first.
        #expect(verb.options.contains("konfigurieren"))
        #expect(verb.options.contains("entwickeln"))

        let preposition = try #require(questions[1])
        #expect(preposition.options.contains("mit"))
        #expect(preposition.options.allSatisfy { PhraseGapPlanner.commonPrepositions.contains($0) })
        // Word cards get no gap.
        #expect(questions[2] == nil)
    }

    @Test func theSameDeckDealsTheSameQuestions() {
        let cards = deck([("eine Störung beheben", CardKind.phrase), ("Erfahrung mit Git", CardKind.phrase)])
        #expect(PhraseGapPlanner.questions(for: cards, isVerb: isVerb, seed: 7)
                == PhraseGapPlanner.questions(for: cards, isVerb: isVerb, seed: 7))
    }

    @Test func tooFewLikeWordsMeansNoGap() {
        // A noun gap needs three other nouns; this deck has one.
        let cards = deck([("eine vergleichbare Qualifikation", CardKind.phrase), ("Ticket", "noun")])
        #expect(PhraseGapPlanner.questions(for: cards, isVerb: isVerb).isEmpty)
    }

    @Test func theBlankKeepsThePunctuation() throws {
        let cards = deck([("Wir beheben die Störung schnell.", CardKind.phrase),
                          ("das Ticket", "noun"), ("Server", "noun"), ("Netzwerk", "noun"), ("Fehler", "noun")])
        let question = try #require(PhraseGapPlanner.questions(for: cards, isVerb: isVerb)[0])
        #expect(question.answer == "Störung")
        #expect(question.blanked().joined(separator: " ") == "Wir beheben die _____ schnell.")
    }
}

/// Renders the gap face before and after a pick to PNGs under the simulator's temporary folder
/// (the path is printed), for looking at without driving the UI.
@MainActor
@Suite struct PhraseGapCardRenderTests {
    @Test func rendersTheGapFace() throws {
        let question = PhraseGapQuestion(tokens: ["eine", "Störung", "beheben"], hiddenIndex: 2, answer: "beheben",
                                         options: ["konfigurieren", "beheben", "entwickeln", "stellen"], kind: .verb)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("phrase-gap")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, pick) in [("open", nil), ("right", "beheben"), ("wrong", "stellen")] as [(String, String?)] {
            let renderer = ImageRenderer(content: PhraseGapCardView(question: question, english: "to fix a fault",
                                                                    initialPick: pick) { _, _ in }
                .frame(width: 390).padding(.vertical, 20).background(Color(white: 0.96)))
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            try #require(image.pngData()).write(to: dir.appendingPathComponent("\(name).png"))
        }
        print("[phraseGap.render] \(dir.path)")
    }
}
