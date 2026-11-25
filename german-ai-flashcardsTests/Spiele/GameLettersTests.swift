//
//  GameLettersTests.swift
//  german-ai-flashcardsTests
//
//  The alphabet rule the whole Spiele room rests on: Ä is not A, and ß is not SS. Both are easy to
//  lose to a stray `uppercased()`, and losing either means the game teaches a wrong spelling.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Spiele · letters")
struct GameLettersTests {

    @Test("uppercased() would respell ß — letters() does not")
    func eszettSurvives() {
        // The trap this function exists to avoid.
        #expect("Straße".uppercased() == "STRASSE")
        #expect(GameLetters.letters("Straße") == ["S", "T", "R", "A", "ß", "E"])
        #expect(GameLetters.letters("Straße").count == "Straße".count)
    }

    @Test("Umlauts are their own letters, never folded onto a base letter")
    func umlautsStandAlone() {
        #expect(GameLetters.letters("Mädchen") == ["M", "Ä", "D", "C", "H", "E", "N"])
        #expect(GameLetters.equal("Ä", "A") == false)
        #expect(GameLetters.equal("Ö", "O") == false)
        #expect(GameLetters.equal("Ü", "U") == false)
        #expect(GameLetters.equal("Ä", "Ä"))
        for umlaut: Character in ["Ä", "Ö", "Ü"] {
            #expect(GameLetters.alphabet.contains(umlaut))
        }
    }

    @Test("The keyboard is 26 letters plus ÄÖÜ plus ß, with no duplicates")
    func keyboard() {
        #expect(GameLetters.hangmanKeys.count == 30)
        #expect(Set(GameLetters.hangmanKeys).count == 30)
        #expect(GameLetters.hangmanKeys.contains("ß"))
        #expect(GameLetters.alphabet.count == 29)
        #expect(GameLetters.alphabet.contains("ß") == false)
    }

    @Test("A phrase is not a single token")
    func singleToken() {
        #expect(GameLetters.isSingleToken("Blume"))
        #expect(GameLetters.isSingleToken("Mädchen"))
        #expect(GameLetters.isSingleToken("Straße"))
        #expect(GameLetters.isSingleToken("sich erinnern an") == false)
        #expect(GameLetters.isSingleToken("Hund/Katze") == false)
        #expect(GameLetters.isSingleToken("E-Mail") == false)
        #expect(GameLetters.isSingleToken("Nr. 1") == false)
        #expect(GameLetters.isSingleToken("") == false)
        #expect(GameLetters.isSingleToken("   ") == false)
    }

    @Test("The ß policies keep, refuse and expand")
    func eszettPolicies() {
        let straße = GameLetters.letters("Straße")
        #expect(GameLetters.applying(.keep, to: straße) == straße)
        #expect(GameLetters.applying(.exclude, to: straße) == nil)
        #expect(GameLetters.applying(.expandToSS, to: straße) == ["S", "T", "R", "A", "S", "S", "E"])

        // A word without ß is untouched by every policy.
        let blume = GameLetters.letters("Blume")
        for policy: EszettPolicy in [.keep, .exclude, .expandToSS] {
            #expect(GameLetters.applying(policy, to: blume) == blume)
        }
    }

    @Test("An unplayable letter is named, so the fitter can explain itself")
    func unplayable() {
        let plain = GameLetters.letters("Blume")
        #expect(GameLetters.firstUnplayable(in: plain, alphabet: GameLetters.alphabet,
                                            allowsEszett: false) == nil)
        let straße = GameLetters.letters("Straße")
        #expect(GameLetters.firstUnplayable(in: straße, alphabet: GameLetters.alphabet,
                                            allowsEszett: true) == nil)
        #expect(GameLetters.firstUnplayable(in: straße, alphabet: GameLetters.alphabet,
                                            allowsEszett: false) == "ß")
    }

    @Test("A GameWord stores its spelling and keeps its article for display only")
    func wordShape() {
        let blume = SpieleTestWords.word("Blume", "flower", article: "die")
        #expect(blume.letters == ["B", "L", "U", "M", "E"])
        #expect(blume.length == 5)
        #expect(blume.display == "die Blume")
        #expect(blume.german == "Blume")
        // The same word from two sources is one word, so per-word stats don't split.
        #expect(blume.id == SpieleTestWords.word("blume", "bloom").id)
        #expect(GameWord(german: "   ", english: "nothing") == nil)
    }
}
