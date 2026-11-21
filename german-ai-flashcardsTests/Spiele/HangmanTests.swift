//
//  HangmanTests.swift
//  german-ai-flashcardsTests
//
//  The guessing machine and the clue chain. The clue chain is tested hardest because its failure
//  is invisible: an `imageFileName` pointing at a file that no longer exists would leave the
//  learner guessing a word with nothing on screen to say which word it is.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Galgenmännchen")
struct HangmanTests {

    private func state(_ german: String) -> HangmanState {
        HangmanState(word: SpieleTestWords.word(german, "flower", article: "die"))
    }

    @Test("A hit reveals every copy of the letter at once")
    func hits() {
        var game = state("Blume")
        #expect(game.revealed == [nil, nil, nil, nil, nil])
        #expect(game.guess("B") == .hit(count: 1))
        #expect(game.revealed == ["B", nil, nil, nil, nil])

        var treppe = state("Treppe")
        #expect(treppe.guess("P") == .hit(count: 2))
        #expect(treppe.revealed == [nil, nil, nil, "P", "P", nil])
        #expect(treppe.missCount == 0)
    }

    @Test("Six misses lose the round, and no further guess counts")
    func misses() {
        var game = state("Blume")
        for letter: Character in ["X", "Y", "Q", "Z", "J", "V"] {
            #expect(game.guess(letter) == .miss)
        }
        #expect(game.missCount == HangmanState.maxMisses)
        #expect(game.remaining == 0)
        #expect(game.isLost)
        #expect(game.isOver)
        #expect(game.isWon == false)
        // The motif has nothing left to take, so a seventh guess is refused outright.
        #expect(game.guess("B") == .ignored)
        #expect(game.missCount == HangmanState.maxMisses)
    }

    @Test("Guessing A on „Mädchen“ is a miss — the umlaut rule, at the keystroke")
    func umlautIsItsOwnLetter() {
        var game = state("Mädchen")
        #expect(game.guess("A") == .miss)
        #expect(game.guess("Ä") == .hit(count: 1))
        #expect(game.revealed == [nil, "Ä", nil, nil, nil, nil, nil])
    }

    @Test("ß is guessable, and is not reached by guessing S")
    func eszett() {
        var game = state("Straße")
        #expect(game.guess("S") == .hit(count: 1))
        #expect(game.revealed == ["S", nil, nil, nil, nil, nil])
        #expect(game.guess("ß") == .hit(count: 1))
        #expect(game.revealed == ["S", nil, nil, nil, "ß", nil])
    }

    @Test("A repeated letter is ignored and costs nothing")
    func repeats() {
        var game = state("Blume")
        #expect(game.guess("X") == .miss)
        #expect(game.guess("X") == .ignored)
        #expect(game.missCount == 1)
        #expect(game.guess("B") == .hit(count: 1))
        #expect(game.guess("B") == .ignored)
    }

    @Test("Only a win with no miss and no hint counts as recall")
    func cleanWin() {
        var clean = state("Blume")
        for letter: Character in ["B", "L", "U", "M", "E"] { clean.guess(letter) }
        #expect(clean.isWon)
        #expect(clean.isCleanWin)

        var missed = state("Blume")
        missed.guess("X")
        for letter: Character in ["B", "L", "U", "M", "E"] { missed.guess(letter) }
        #expect(missed.isWon)
        #expect(missed.isCleanWin == false, "a win after a miss is not unaided recall")

        var hinted = state("Blume")
        hinted.noteHint()
        for letter: Character in ["B", "L", "U", "M", "E"] { hinted.guess(letter) }
        #expect(hinted.isWon)
        #expect(hinted.isCleanWin == false, "a hint disqualifies the round from moving a schedule")
    }

    @Test("Giving up reveals the word and ends as a loss")
    func reveal() {
        var game = state("Blume")
        game.reveal()
        #expect(game.revealed == ["B", "L", "U", "M", "E"])
        #expect(game.isLost)
        #expect(game.isCleanWin == false)
    }

    @Test("The keyboard offers only untried letters")
    func untried() {
        var game = state("Blume")
        #expect(game.untried.count == 30)
        game.guess("B")
        game.guess("X")
        #expect(game.untried.count == 28)
        #expect(game.untried.contains("B") == false)
        #expect(game.untried.contains("X") == false)
    }

    @Test("A missing picture file falls through to the English, not to a blank clue")
    func clueChainSurvivesAMissingFile() {
        let withPicture = SpieleTestWords.word("Blume", "flower", article: "die", image: "blume.heic")

        #expect(HangmanClue.resolve(for: withPicture, mode: .pictureFirst,
                                    imageExists: { _ in true })
                == .picture(fileName: "blume.heic", deckID: SpieleTestWords.deckID))
        // The file is gone — an AirDropped deck, a restore, a cleared cache.
        #expect(HangmanClue.resolve(for: withPicture, mode: .pictureFirst,
                                    imageExists: { _ in false }) == .english("flower"))
        #expect(HangmanClue.resolve(for: withPicture, mode: .englishOnly,
                                    imageExists: { _ in true }) == .english("flower"))
    }

    @Test("A picture with no deck behind it is not offered as a clue")
    func pictureNeedsItsDeck() {
        // `CardImageStore` keys its directories by deck, so a file name alone could never be
        // loaded — the word must not claim to have a picture.
        let orphan = GameWord(german: "Blume", english: "flower",
                              imageFileName: "blume.heic", imageDeckID: nil)
        #expect(orphan?.imageFileName == nil)
        #expect(HangmanClue.resolve(for: orphan!, mode: .pictureFirst,
                                    imageExists: { _ in true }) == .english("flower"))
    }

    @Test("With no English the clue falls back to forms, then word type, then nothing")
    func clueChainTail() {
        let forms = SpieleTestWords.word("Blume", "", forms: "Plural: -n")
        #expect(HangmanClue.resolve(for: forms, mode: .pictureFirst, imageExists: { _ in false })
                == .forms("Plural: -n"))

        let typed = SpieleTestWords.word("Blume", "", wordType: "Nomen")
        #expect(HangmanClue.resolve(for: typed, mode: .pictureFirst, imageExists: { _ in false })
                == .wordType("Nomen"))

        let bare = SpieleTestWords.word("Blume", "")
        #expect(HangmanClue.resolve(for: bare, mode: .pictureFirst, imageExists: { _ in false })
                == HangmanClue.Resolved.none)
    }
}
