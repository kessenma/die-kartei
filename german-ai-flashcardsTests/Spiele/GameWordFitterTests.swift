//
//  GameWordFitterTests.swift
//  german-ai-flashcardsTests
//
//  Which words a game can use, and why it turned the others down. The reasons are tested because
//  they are shown to the learner: a deck of 40 cards that yields 5 playable words has to say
//  „zu lang“ or „mehrere Wörter“, or it reads as the game being broken.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Spiele · word fitter")
struct GameWordFitterTests {

    private var hangman: GameWordRequirements { HangmanRound.requirements }
    private var wordSearch: GameWordRequirements { WordSearchRound.requirements }

    @Test("Each rejection names its own reason")
    func reasons() {
        #expect(GameWordFitter.reject(SpieleTestWords.word("Blume", "flower"), by: hangman) == nil)
        #expect(GameWordFitter.reject(SpieleTestWords.word("Uhr", "clock"), by: hangman)
                == .tooShort(3))
        #expect(GameWordFitter.reject(SpieleTestWords.word("Geschwindigkeitsbegrenzung", "limit"),
                                      by: hangman) == .tooLong(26))
        #expect(GameWordFitter.reject(SpieleTestWords.word("sich erinnern an", "to remember"),
                                      by: hangman) == .multiToken)
        #expect(GameWordFitter.reject(SpieleTestWords.word("Blume", ""), by: hangman) == .noEnglish)
    }

    @Test("Hangman keeps a ß word; the grid games refuse it")
    func eszettPerGame() {
        let straße = SpieleTestWords.word("Straße", "street")
        #expect(GameWordFitter.reject(straße, by: hangman) == nil)
        #expect(GameWordFitter.reject(straße, by: wordSearch) == .eszett)
    }

    @Test("A word is counted once, however many times the source lists it")
    func duplicates() {
        let fit = GameWordFitter.fit([
            SpieleTestWords.word("Blume", "flower"),
            SpieleTestWords.word("blume", "bloom"),
            SpieleTestWords.word("Tisch", "table"),
        ], to: hangman)
        #expect(fit.usable.count == 2)
        #expect(fit.rejected.count == 1)
        #expect(fit.rejected.first?.reason == .duplicate)
    }

    @Test("Shortfall counts what is missing, and isEnough follows it")
    func shortfall() {
        let thin = GameWordFitter.fit(SpieleTestWords.words(["Blume", "Tisch", "Stein"]), to: hangman)
        #expect(thin.usable.count == 3)
        #expect(thin.shortfall == 5, "hangman wants 8 words to start")
        #expect(thin.isEnough == false)

        let enough = GameWordFitter.fit(SpieleTestWords.küche, to: wordSearch)
        #expect(enough.usable.count == 10)
        #expect(enough.shortfall == 0)
        #expect(enough.isEnough)
    }

    @Test("The tally counts a reason once, however many lengths it covers")
    func tally() {
        let fit = GameWordFitter.fit([
            SpieleTestWords.word("Uhr", "clock"),                   // 3 letters
            SpieleTestWords.word("Tee", "tea"),                     // 3 letters
            SpieleTestWords.word("Ei", "egg"),                      // 2 letters
            SpieleTestWords.word("sich freuen auf", "to look forward to"),
        ], to: hangman)

        #expect(fit.usable.isEmpty)
        // All three short words are one reason, even though they are short by different amounts —
        // the learner reads „drei Wörter sind zu kurz“, not one line per length.
        #expect(fit.reasonTally.first?.kind == .tooShort)
        #expect(fit.reasonTally.first?.count == 3)
        #expect(fit.reasonTally.count == 2)
        #expect(fit.reasonTally.last?.kind == .multiToken)

        // The per-word reason still carries the detail a single row shows.
        #expect(fit.rejected.first?.reason == .tooShort(3))
        #expect(GameWordFitter.Kind.tooShort.englishReason == "are too short")
    }

    @Test("A round is a seeded pick, reproducible and inside the game's word count")
    func roundIsSeeded() {
        let fit = GameWordFitter.fit(SpieleTestWords.küche, to: wordSearch)
        let first = GameWordFitter.round(WordSearchRound.self, from: fit, seed: 42)
        let again = GameWordFitter.round(WordSearchRound.self, from: fit, seed: 42)
        #expect(first?.map(\.id) == again?.map(\.id))

        let other = GameWordFitter.round(WordSearchRound.self, from: fit, seed: 99)
        #expect(other != nil)
        if let picked = first {
            #expect(picked.count <= WordSearchRound.requirements.wordCount.upperBound)
            #expect(picked.count >= WordSearchRound.requirements.wordCount.lowerBound)
        }
    }

    @Test("Too few words is nil, not a short round")
    func roundRefusesThinSources() {
        let fit = GameWordFitter.fit(SpieleTestWords.words(["Blume", "Tisch"]), to: wordSearch)
        #expect(GameWordFitter.round(WordSearchRound.self, from: fit, seed: 1) == nil)
    }
}
