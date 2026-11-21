//
//  WordClassInferenceTests.swift
//  german-ai-flashcardsTests
//
//  What part of speech a vocabulary row is (Services/WordClassInference.swift), and the one rule the
//  card merge has to keep (Services/DocumentDeckService.swift): an article always wins, inference
//  only ever speaks where there is no article.
//
//  The dictionary's answer is passed in rather than looked up, which is how these run without the
//  bundled database and how the "the dictionary knows it as both" case can be stated at all.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct WordClassInferenceTests {

    // MARK: - Which evidence wins

    @Test func theDictionaryDecidesBeforeTheRowsShape() {
        // By shape alone "Essen" is a capitalized word and so a noun; the dictionary saying verb
        // only, for a lowercase row, has to be the answer.
        #expect(WordClassInference.classify(german: "essen", english: "food",
                                            partsOfSpeech: ["verb"]) == .verb)
        // And the other way: an English side reading "to …" does not outvote a dictionary noun.
        #expect(WordClassInference.classify(german: "Reise", english: "to travel",
                                            partsOfSpeech: ["noun"]) == .noun)
    }

    @Test func theCapitalDecidesWhenTheDictionaryAlsoOffersANoun() {
        // German nominalizes freely, so the dictionary knows "essen" twice over. These are the
        // actual rows in Resources/wiktionary_de.db, which is why taking the noun reading every
        // time used to call "gestern" and "gut" Nomen.
        #expect(WordClassInference.fromDictionary(["noun", "verb"], isCapitalized: true) == .noun)
        #expect(WordClassInference.fromDictionary(["noun", "verb"], isCapitalized: false) == .verb)
        #expect(WordClassInference.classify(german: "das Essen", english: "the meal",
                                            partsOfSpeech: ["noun", "verb"]) == .noun)
        #expect(WordClassInference.classify(german: "essen", english: "to eat",
                                            partsOfSpeech: ["noun", "verb"]) == .verb)
        #expect(WordClassInference.classify(german: "gestern", english: "yesterday",
                                            partsOfSpeech: ["adv", "noun"]) == .adverb)
        #expect(WordClassInference.classify(german: "gut", english: "good",
                                            partsOfSpeech: ["adj", "adv", "noun"]) == .adjective)
        #expect(WordClassInference.classify(german: "das Gut", english: "estate",
                                            partsOfSpeech: ["adj", "adv", "noun"]) == .noun)
    }

    @Test func aLowercaseWordTheDictionaryKnowsOnlyAsANounStaysANoun() {
        // A sheet that wrote a noun in lower case is likelier than a dictionary with nothing else
        // to say about the word.
        #expect(WordClassInference.fromDictionary(["noun"], isCapitalized: false) == .noun)
    }

    @Test func theBareAdjectiveWinsOverItsAdverbReading() {
        // German uses the bare adjective adverbially, so the dictionary lists both; the adjective
        // is the one being taught.
        #expect(WordClassInference.classify(german: "schnell", english: "fast",
                                            partsOfSpeech: ["adj", "adv"]) == .adjective)
        #expect(WordClassInference.classify(german: "oben", english: "above",
                                            partsOfSpeech: ["adv"]) == .adverb)
    }

    @Test func anUnknownWordFallsThroughToTheRowsShape() {
        // An empty set is the dictionary saying "never heard of it", not "it is nothing".
        #expect(WordClassInference.classify(german: "der Datenschutzbeauftragte",
                                            english: "data protection officer",
                                            partsOfSpeech: []) == .noun)
        #expect(WordClassInference.classify(german: "segeln", english: "to sail",
                                            partsOfSpeech: nil) == .verb)
    }

    @Test func anAdverbOnlyComesFromTheDictionary() {
        #expect(WordClassInference.fromDictionary(["adv"], isCapitalized: false) == .adverb)
        #expect(WordClassInference.fromDictionary(["adverb"], isCapitalized: false) == .adverb)
        // Nothing about a row's shape says adverb. "gestern" ends -ern like an infinitive, so shape
        // alone calls it a verb; the dictionary is what makes it an adverb, and the dictionary runs
        // first. Shape is the fallback for a word no dictionary has heard of, where a lowercase
        // -en/-eln/-ern word really is almost always a verb.
        #expect(WordClassInference.fromShape(german: "gestern", english: "yesterday") == .verb)
        #expect(WordClassInference.classify(german: "gestern", english: "yesterday",
                                            partsOfSpeech: ["adv", "noun"]) == .adverb)
    }

    @Test func theDictionarysAdjectiveSpellingsBothRead() {
        #expect(WordClassInference.fromDictionary(["adj"], isCapitalized: false) == .adjective)
        #expect(WordClassInference.fromDictionary(["adjective"], isCapitalized: false) == .adjective)
    }

    // MARK: - What the row itself gives away

    @Test func anArticleMakesItANoun() {
        #expect(WordClassInference.fromShape(german: "der Tisch", english: "table") == .noun)
        #expect(WordClassInference.fromShape(german: "die Maus", english: "mouse") == .noun)
        #expect(WordClassInference.fromShape(german: "das Fenster", english: "window") == .noun)
    }

    @Test func toSomethingOnTheEnglishSideIsAVerb() {
        #expect(WordClassInference.fromShape(german: "anzünden", english: "to ignite") == .verb)
        // Even a phrase, when the English says plainly what it is.
        #expect(WordClassInference.fromShape(german: "Sorge tragen", english: "to take care") == .verb)
    }

    @Test func aLowercaseInfinitiveEndingIsAVerb() {
        #expect(WordClassInference.fromShape(german: "segeln", english: "sailing") == .verb)
        #expect(WordClassInference.fromShape(german: "wandern", english: "hiking") == .verb)
        #expect(WordClassInference.fromShape(german: "lächeln", english: "a smile") == .verb)
        #expect(WordClassInference.fromShape(german: "öffnen", english: "open") == .verb)
    }

    @Test func aCapitalizedSingleWordIsANoun() {
        #expect(WordClassInference.fromShape(german: "Bübchen", english: "young boy") == .noun)
    }

    @Test func aPhraseIsLeftUnclassified() {
        // No tag is more honest than calling this a noun because it starts with a small word.
        #expect(WordClassInference.fromShape(german: "in aller Frühe", english: "in the early morning") == nil)
        #expect(WordClassInference.classify(german: "in aller Frühe",
                                            english: "in the early morning",
                                            partsOfSpeech: []) == nil)
    }

    @Test func theLookupFormDropsWhatTheSheetWroteAroundTheWord() {
        #expect(WordClassInference.headword("der Computer") == "Computer")
        #expect(WordClassInference.headword("das Gift, -e") == "Gift")
        #expect(WordClassInference.headword("die Sorge (pl)") == "Sorge")
        #expect(WordClassInference.headword("öffnen") == "öffnen")
    }

    // MARK: - An article always wins

    @MainActor
    @Test func anArticleIsNeverOverwrittenByAnInferredClass() throws {
        var row = VocabListRow(german: "der Computer", english: "computer")
        row.wordClass = .verb
        let card = try #require(DocumentDeckService.merge([row]).first)
        #expect(card.article == "der")
        #expect(card.wordType == "noun")
    }

    @MainActor
    @Test func aRepeatWithAnArticleTurnsTheCardIntoANoun() throws {
        var bare = VocabListRow(german: "Computer", english: "computer", page: 34)
        bare.wordClass = .verb
        let withArticle = VocabListRow(german: "der Computer", english: "computer", page: 8)
        for order in [[bare, withArticle], [withArticle, bare]] {
            let merged = DocumentDeckService.merge(order)
            #expect(merged.count == 1)
            #expect(merged.first?.article == "der")
            #expect(merged.first?.wordType == "noun")
        }
    }

    @MainActor
    @Test func anInferredClassReachesTheCardWhenThereIsNoArticle() throws {
        var row = VocabListRow(german: "ernähren", english: "to feed")
        row.wordClass = .verb
        let card = try #require(DocumentDeckService.merge([row]).first)
        #expect(card.article == nil)
        #expect(card.wordType == "verb")
    }

    @MainActor
    @Test func aRowWithNoClassStoresNoWordType() throws {
        let row = VocabListRow(german: "eigenständig", english: "independently")
        let card = try #require(DocumentDeckService.merge([row]).first)
        #expect(card.wordType == nil)
    }

    @MainActor
    @Test func aPhraseRowIsStoredAsAPhraseWhateverItsTag() throws {
        var tagged = VocabListRow(german: "Sorge tragen", english: "to take care")
        tagged.wordClass = .verb
        let rows = [VocabListRow(german: "in aller Frühe", english: "in the early morning"), tagged,
                    VocabListRow(german: "der Meinung sein", english: "to be of the opinion")]
        let cards = DocumentDeckService.merge(rows)
        #expect(cards.map(\.wordType) == [CardKind.phrase, CardKind.phrase, CardKind.phrase])
        #expect(cards.map(\.germanWord) == ["in aller Frühe", "Sorge tragen", "der Meinung sein"])
        #expect(cards.allSatisfy { $0.article == nil })
    }

    // MARK: - The stored strings are the ones the app filters on

    @Test func theStoredStringsAreTheOnesTheAppFiltersOn() {
        #expect(WordClass.allCases.map(\.rawValue) == ["noun", "verb", "adjective", "adverb"])
        // What the card screens already store and what the Goethe lists read.
        #expect(GoetheWordType.normalize(article: nil, raw: WordClass.noun.rawValue) == .noun)
        #expect(GoetheWordType.normalize(article: nil, raw: WordClass.verb.rawValue) == .verb)
        #expect(GoetheWordType.normalize(article: nil, raw: WordClass.adjective.rawValue) == .adj)
        #expect(GoetheWordType.normalize(article: nil, raw: WordClass.adverb.rawValue) == .adv)
    }

    @Test func everyClassHasItsOwnColour() {
        let colours = WordClass.allCases.map { WordClassPalette.color(for: $0) }
        #expect(Set(colours.map(String.init(describing:))).count == WordClass.allCases.count)
        // The Goethe lists spell adjective "adj"; both spellings must land on the same colour.
        #expect(WordClassPalette.color(for: "adj") == WordClassPalette.color(for: "adjective"))
        #expect(WordClassPalette.color(for: String?.none) == WordClassPalette.color(for: "unterwegs"))
    }
}
