//
//  CardKindTests.swift
//  german-ai-flashcardsTests
//
//  One word or a phrase (Services/CardKind.swift), and the places that used to treat a phrase as a
//  noun: the save paths' article split, the repair for cards saved that way, the dictionary
//  check's gender guess, the der/die/das game, and chat review matching. See docs/PHRASES.md.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct CardKindTests {

    // MARK: - The rule

    @Test func anArticleAndOneWordIsANoun() {
        #expect(CardKind.split("das Ticket") == .init(word: "Ticket", article: "das", isPhrase: false))
        #expect(CardKind.split("Die Stellenanzeige") == .init(word: "Stellenanzeige", article: "die", isPhrase: false))
        // Hyphens keep a word whole.
        #expect(CardKind.split("der First-Level-Support") == .init(word: "First-Level-Support", article: "der", isPhrase: false))
    }

    @Test func whatASheetPrintsBesideAWordIsNotAWord() {
        // Her "—" means no plural; a bracketed note and plural notation are not part of the word.
        #expect(CardKind.split("die Berufserfahrung —").isPhrase == false)
        #expect(CardKind.split("die Kenntnisse (Pluralform)").isPhrase == false)
        #expect(CardKind.split("die Kenntnisse (Pluralform)").article == "die")
        #expect(CardKind.split("der Tisch, -e").isPhrase == false)
        #expect(CardKind.split("der Tisch, die Tische").isPhrase == false)
        #expect(CardKind.split("der Computer, -").isPhrase == false)
    }

    @Test func aPhraseStaysWholeWithNoArticle() {
        #expect(CardKind.split("der Meinung sein") == .init(word: "der Meinung sein", article: nil, isPhrase: true))
        #expect(CardKind.split("Das ist gut") == .init(word: "Das ist gut", article: nil, isPhrase: true))
        #expect(CardKind.split("eine Störung beheben").isPhrase)
        #expect(CardKind.split("fundierte Kenntnisse in Python").isPhrase)
        #expect(CardKind.split("sich freuen auf").isPhrase)
        #expect(CardKind.split("  in aller Frühe ").word == "in aller Frühe")
    }

    @Test func singleWordsAndReflexiveVerbsAreNotPhrases() {
        #expect(!CardKind.isPhrase("eigenständig"))
        #expect(!CardKind.isPhrase("bereitstellen"))
        #expect(!CardKind.isPhrase("sich bewerben"))
        #expect(!CardKind.isPhrase(""))
    }

    @Test func theWordTypeToStore() {
        #expect(CardKind.split("das Ticket").wordType == "noun")
        #expect(CardKind.split("entwickeln").wordType == nil)
        #expect(CardKind.split("Erfahrung mit Git").wordType == CardKind.phrase)
    }

    @Test func aStoredCardIsReadWithItsArticleInFront() {
        // A phrase an older save split: "Meinung sein" + der.
        #expect(CardKind.isPhrase(germanWord: "Meinung sein", article: "der", wordType: "noun"))
        #expect(!CardKind.isPhrase(germanWord: "Tisch", article: "der", wordType: "noun"))
        #expect(CardKind.isPhrase(germanWord: "x", article: nil, wordType: CardKind.phrase))
    }

    @Test func matchingForAlreadySavedIgnoresWhereTheArticleWent() {
        #expect(CardKind.matchKey("der Meinung sein") == CardKind.matchKey("Meinung sein"))
        #expect(CardKind.matchKey("Das Ticket") == "ticket")
    }

    // MARK: - Cards saved before the rule

    @Test func aSplitPhraseGetsItsArticleBack() {
        #expect(PhraseRepair.repaired(germanWord: "Meinung sein", article: "der", wordType: "noun",
                                      hasConjugations: false) == "der Meinung sein")
        #expect(PhraseRepair.repaired(germanWord: "gute Kenntnisse", article: nil, wordType: "adjective",
                                      hasConjugations: false) == "gute Kenntnisse")
    }

    @Test func wordsAndTaggedPhrasesAreLeftAlone() {
        #expect(PhraseRepair.repaired(germanWord: "Tisch", article: "der", wordType: "noun", hasConjugations: false) == nil)
        #expect(PhraseRepair.repaired(germanWord: "eine Störung beheben", article: nil, wordType: CardKind.phrase,
                                      hasConjugations: false) == nil)
        // Generated as a verb, with its table: stays a verb.
        #expect(PhraseRepair.repaired(germanWord: "Rad fahren", article: nil, wordType: "verb", hasConjugations: true) == nil)
    }

    @MainActor
    @Test func repairRetagsOnlyThePhrasesOfADeck() {
        let deck = SavedDeck(topic: "Test", wordCount: 2, includeExamples: false, includeGender: true,
                             vocabCards: [
                                VocabCard(germanWord: "Meinung sein", englishTranslation: "to be of the opinion",
                                          wordType: "noun", article: "der", exampleSentence: nil, conjugations: nil),
                                VocabCard(germanWord: "Tisch", englishTranslation: "table",
                                          wordType: "noun", article: "der", exampleSentence: nil, conjugations: nil),
                             ])
        #expect(PhraseRepair.apply(to: deck) == 1)
        let cards = deck.cards.sorted { $0.sortOrder < $1.sortOrder }
        #expect(cards[0].germanWord == "der Meinung sein")
        #expect(cards[0].article == nil)
        #expect(cards[0].wordType == CardKind.phrase)
        #expect(cards[1].article == "der")
        // Twice is the same as once.
        #expect(PhraseRepair.apply(to: deck) == 0)
    }

    // MARK: - Dictionary check and article game

    @MainActor
    @Test func theDictionaryCheckNeverGivesAPhraseAGender() {
        // "Ausbildung" ends in -ung: the suffix guess used to make this "die".
        let card = VocabCard(germanWord: "Ziel der Ausbildung", englishTranslation: "aim of the training",
                             wordType: "noun", article: "das", exampleSentence: nil, conjugations: nil)
        let outcome = WiktionaryValidator.shared.validateAndCorrect([card])
        #expect(outcome.corrections.isEmpty)
        #expect(outcome.cards.first?.article == "das")
        #expect(outcome.results.first?.status == .unchecked)
    }

    @MainActor
    @Test func theArticleGameSkipsPhrases() {
        let deck = SavedDeck(topic: "Test", wordCount: 2, includeExamples: false, includeGender: true,
                             vocabCards: [
                                VocabCard(germanWord: "Meinung sein", englishTranslation: "to be of the opinion",
                                          wordType: "noun", article: "der", exampleSentence: nil, conjugations: nil),
                                VocabCard(germanWord: "Tisch", englishTranslation: "table",
                                          wordType: "noun", article: "der", exampleSentence: nil, conjugations: nil),
                             ])
        #expect(ArticleGameService.deckQuestions(from: deck).map(\.noun) == ["Tisch"])
    }

    // MARK: - Chat review

    @MainActor
    @Test func aPhraseIsNotCreditedForItsLastWordAlone() {
        let targets = ["fundierte Kenntnisse in Python"]
        #expect(ConversationPrompts.matchedWords(in: "Ich programmiere gern in Python.", targetWords: targets).isEmpty)
        #expect(ConversationPrompts.matchedWords(in: "Ich habe fundierte Kenntnisse in Python.", targetWords: targets) == targets)
    }

    @MainActor
    @Test func articlesAndPronounsInAPhraseMayChange() {
        let targets = ["eine Störung beheben", "sich freuen auf"]
        #expect(ConversationPrompts.matchedWords(in: "Wir beheben die Störung heute.", targetWords: targets)
                == ["eine Störung beheben"])
    }

    @MainActor
    @Test func singleWordsMatchAsBefore() {
        #expect(ConversationPrompts.matchedWords(in: "Der Tisch ist groß.", targetWords: ["der Tisch"]) == ["der Tisch"])
    }

    // MARK: - Tutor translation

    @MainActor
    @Test func aRewordedPhraseKeepsItsEnglishByPosition() {
        var translations: [String: String] = [:]
        DocumentDeckService.assign([("eine Störung beheben", "to fix a fault"), ("das Ticket", "ticket")],
                                   to: ["Störungen beheben", "das Ticket"], into: &translations)
        #expect(translations[DocumentDeckService.key("Störungen beheben")] == "to fix a fault")
        #expect(translations[DocumentDeckService.key("das Ticket")] == "ticket")
    }

    @MainActor
    @Test func noPositionGuessWhenTheTutorSkippedALine() {
        var translations: [String: String] = [:]
        DocumentDeckService.assign([("eine Störung beheben", "to fix a fault")],
                                   to: ["Störungen beheben", "das Ticket"], into: &translations)
        #expect(translations[DocumentDeckService.key("Störungen beheben")] == nil)
    }
}
