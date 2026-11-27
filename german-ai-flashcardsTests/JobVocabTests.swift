//
//  JobVocabTests.swift
//  german-ai-flashcardsTests
//
//  The job-ad word count and bulk add (docs/JOB_PREP.md ▸ Sammeln): grouping word forms, the
//  basic-word filter, counting across ads, phrases the ads share, the sentence a word came from,
//  splitting a phrase into words, the tutor's answers landing on the right rows, and the Pencil
//  telling a tap, a stroke and a loop apart.
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct JobVocabTests {

    private let adA = JobVocabSource(id: UUID(), title: "A", text: """
    Deine Aufgaben
    • Du entwickelst gemeinsam mit dem Team neue Funktionen für unsere Plattform.
    • Du übernimmst eigenverantwortlich kleinere Projekte.
    Dein Profil
    Du hast ein abgeschlossenes Studium der Informatik und erste Erfahrung mit Swift. Sehr gute Deutschkenntnisse (m/w/d).
    Fundierte Kenntnisse in Python setzen wir voraus.
    """)

    private let adB = JobVocabSource(id: UUID(), title: "B", text: """
    Ihre Aufgaben: Sie entwickeln Software für unsere Kunden. Sie haben ein abgeschlossenes Studium und mehrjährige Erfahrungen in der Softwareentwicklung.
    Kenntnissen in Java und sehr gute Deutschkenntnisse sind erforderlich.
    """)

    // MARK: Stems

    @Test func formsOfOneWordShareAStem() {
        #expect(GermanStem.stem("Kenntnisse") == GermanStem.stem("Kenntnis"))
        #expect(GermanStem.stem("Kenntnissen") == GermanStem.stem("Kenntnis"))
        #expect(GermanStem.stem("Erfahrungen") == GermanStem.stem("Erfahrung"))
        #expect(GermanStem.stem("Kunden") == GermanStem.stem("Kunde"))
        #expect(GermanStem.stem("entwickelst") == GermanStem.stem("entwickeln"))
        #expect(GermanStem.stem("abgeschlossenes") == GermanStem.stem("abgeschlossen"))
        #expect(GermanStem.stem("Teams") == GermanStem.stem("Team"))
        #expect(GermanStem.stem("Informatik") != GermanStem.stem("Information"))
    }

    // MARK: Counting

    @Test func wordsAreCountedAcrossAds() {
        let words = JobVocabAnalyzer.words(in: [adA, adB])
        func term(_ display: String) -> JobVocabTerm? { words.first { $0.display == display } }

        let erfahrung = try! #require(term("Erfahrung"))
        #expect(erfahrung.adCount == 2)
        #expect(erfahrung.forms.keys.contains("Erfahrungen"))

        // The shortest spelling is shown, every spelling is counted.
        let kenntnisse = try! #require(term("Kenntnisse"))
        #expect(kenntnisse.adCount == 2)
        #expect(kenntnisse.total == 2)

        let entwickeln = try! #require(term("entwickeln"))
        #expect(entwickeln.forms["entwickelst"] == 1)

        // Words both ads share come before words only one has.
        let firstSingle = words.firstIndex { $0.adCount == 1 } ?? words.count
        #expect(words.prefix(firstSingle).allSatisfy { $0.adCount == 2 })
    }

    @Test func basicWordsAreMarkedAndTagsDropped() {
        let words = JobVocabAnalyzer.words(in: [adA])
        #expect(words.first { $0.display.lowercased() == "und" }?.isBasic == true)
        #expect(words.first { $0.display == "Du" }?.isBasic == true)
        #expect(words.first { $0.display == "Informatik" }?.isBasic == false)
        // „(m/w/d)“ leaves only single letters, which are not words.
        #expect(!words.contains { $0.display.count < 2 })
    }

    @Test func aNounAndAVerbWithOneStemStayApart() {
        let ad = JobVocabSource(id: UUID(), title: "C", text: "Die Arbeit macht Spaß. Wir arbeiten im Team.")
        let words = JobVocabAnalyzer.words(in: [ad])
        #expect(words.contains { $0.display == "Arbeit" })
        #expect(words.contains { $0.display == "arbeiten" })
    }

    @Test func aCapitalOnlyAtTheStartOfALineJoinsTheLowercaseWord() {
        let ad = JobVocabSource(id: UUID(), title: "D", text: "Fundierte Kenntnisse in Swift\nSie haben fundierte Erfahrung.")
        let words = JobVocabAnalyzer.words(in: [ad])
        let fundiert = words.filter { $0.key.hasSuffix(GermanStem.stem("fundierte")) }
        #expect(fundiert.count == 1)
        #expect(fundiert.first?.total == 2)
        // Shown lowercase: the capital was only the line's.
        #expect(fundiert.first?.display == "fundierte")
    }

    @Test func phrasesTheAdsShare() {
        let phrases = JobVocabAnalyzer.phrases(in: [adA, adB])
        let keys = phrases.map(\.key)
        #expect(keys.contains("abgeschlossenes studium"))
        #expect(keys.contains("gute deutschkenntnisse"))
        // Never a run that starts or ends on a basic word.
        #expect(!keys.contains { $0.hasPrefix("ein ") || $0.hasSuffix(" und") })
    }

    @Test func aPhraseInsideALongerOneIsNotListedTwice() {
        let one = JobVocabSource(id: UUID(), title: "1", text: "Sie haben fließende Deutschkenntnisse in Wort.")
        let two = JobVocabSource(id: UUID(), title: "2", text: "Du hast fließende Deutschkenntnisse in Wort und Schrift.")
        let keys = JobVocabAnalyzer.phrases(in: [one, two]).map(\.key)
        #expect(keys.contains("fließende deutschkenntnisse in wort"))
        #expect(!keys.contains("fließende deutschkenntnisse"))
        // Up to six words: a whole formula is one phrase.
        let three = JobVocabSource(id: UUID(), title: "3", text: "Sehr gute Deutschkenntnisse in Wort und Schrift.")
        let four = JobVocabSource(id: UUID(), title: "4", text: "Gute Deutschkenntnisse in Wort und Schrift sind Pflicht.")
        #expect(JobVocabAnalyzer.phrases(in: [three, four]).map(\.key) == ["gute deutschkenntnisse in wort und schrift"])
    }

    // MARK: Context and splitting

    @Test func theSentenceAWordCameFrom() {
        #expect(JobVocabAnalyzer.sentence(containing: "Kenntnisse", in: adA.text) == "Fundierte Kenntnisse in Python setzen wir voraus.")
        #expect(JobVocabAnalyzer.sentence(containing: "abgeschlossenes Studium", in: adA.text)?.hasPrefix("Du hast") == true)
        #expect(JobVocabAnalyzer.sentence(containing: "Kubernetes", in: adA.text) == nil)
        // Each bullet line is a sentence of its own.
        #expect(JobVocabAnalyzer.sentence(containing: "Projekte", in: adA.text) == "Du übernimmst eigenverantwortlich kleinere Projekte.")
    }

    @Test func aPhraseSplitsIntoItsContentWords() {
        #expect(JobVocabAnalyzer.contentWords(of: "fundierte Kenntnisse in der Python-Programmierung")
                == ["fundierte", "Kenntnisse", "Python-Programmierung"])
        #expect(JobVocabAnalyzer.contentWords(of: "in der") == [])
    }

    // MARK: The tutor's answers

    @Test func answersGoToTheirLinesByPosition() {
        let asked = ["Kenntnissen", "entwickelst", "eigenverantwortlich"]
        let pairs = [("die Kenntnis", "knowledge"), ("entwickeln", "to develop"), ("eigenverantwortlich", "independently")]
        let answers = JobVocabTranslator.assign(pairs, to: asked)
        #expect(answers[0]?.german == "die Kenntnis")
        #expect(answers[1]?.german == "entwickeln")
        #expect(answers[2]?.english == "independently")
    }

    @Test func aDictionaryFormThatIsAnotherWordIsNotTaken() {
        let answers = JobVocabTranslator.assign([("die Leitung", "management")], to: ["Führung"])
        // By position the English is kept, the German stays the learner's.
        #expect(answers[0]?.german == "Führung")
        #expect(answers[0]?.english == "management")
    }

    @Test func aMissingLineFallsBackToMatchingByWord() {
        let asked = ["Kunden", "Plattform", "Funktionen"]
        let answers = JobVocabTranslator.assign([("die Funktion", "feature"), ("der Kunde", "customer")], to: asked)
        #expect(answers[0]?.german == "der Kunde")
        #expect(answers[1] == nil)
        #expect(answers[2]?.english == "feature")
    }

    @Test func knownEnglishFillsRowsByWordForm() {
        let known: [String: JobVocabKnown.Entry] = [
            CardKind.matchKey("Kunde"): .init(german: "der Kunde", english: "customer", origin: .goethe),
            CardKind.matchKey("arbeiten"): .init(german: "arbeiten", english: "to work", origin: .deck)
        ]
        let rows = JobVocabKnown.fill([JobVocabRow(german: "Kunden"), JobVocabRow(german: "Arbeit"),
                                       JobVocabRow(german: "arbeiten")], from: known)
        #expect(rows[0].german == "der Kunde")
        #expect(rows[0].english == "customer")
        // „Arbeit“ is a noun; „arbeiten“'s English is not its English.
        #expect(rows[1].english.isEmpty)
        #expect(rows[2].english == "to work")
    }

    @Test func aRowWithoutEnglishMakesNoCard() {
        var row = JobVocabRow(german: "Kenntnis")
        #expect(!row.makesCard)
        row.english = "knowledge"
        #expect(row.makesCard)
    }

    // MARK: Saving

    @Test func savingAddsEachCardOnceWithItsSentence() {
        let container = ModelContainer.inMemory([JobPosting.self, SavedDeck.self, SavedCard.self])
        let context = container.mainContext
        let posting = JobPosting(title: "Dev", text: adA.text)
        context.insert(posting)
        let deck = JobDeckStore.orCreateDeck(for: posting, context: context)
        #expect(posting.deckID == deck.id)
        #expect(deck.kind == .job)

        var rows = [
            JobVocabRow(german: "die Kenntnis", example: "Fundierte Kenntnisse in Python setzen wir voraus."),
            JobVocabRow(german: "abgeschlossenes Studium"),
            JobVocabRow(german: "Plattform")
        ]
        rows[0].english = "knowledge"
        rows[1].english = "completed degree"
        // „Plattform“ has no English: left out.
        #expect(JobVocabSaver.save(rows, into: deck, feedsCoach: false, context: context) == 2)
        let kenntnis = deck.cards.first { $0.germanWord == "Kenntnis" }
        #expect(kenntnis?.article == "die")
        #expect(kenntnis?.exampleSentence?.hasPrefix("Fundierte") == true)
        #expect(deck.cards.first { $0.germanWord == "abgeschlossenes Studium" }?.wordType == CardKind.phrase)
        #expect(deck.includeExamples)
        // Saving the same rows again adds nothing.
        #expect(JobVocabSaver.save(rows, into: deck, feedsCoach: false, context: context) == 0)
        #expect(deck.cards.count == 2)
    }

    // MARK: The basket

    @Test func theBasketTogglesAndDedupes() {
        let basket = JobVocabBasket()
        basket.toggle("Erfahrung", example: nil)
        #expect(basket.contains("erfahrung"))
        #expect(!basket.add("Erfahrung", example: nil))
        basket.add("abgeschlossenes Studium", example: nil)
        #expect(basket.markedWords == ["erfahrung"])
        #expect(basket.markedPhrases == ["abgeschlossenes Studium"])
        basket.toggle("Erfahrung", example: nil)
        #expect(basket.count == 1)
    }

    // MARK: The Pencil

    /// Three words on one line, then one on the next.
    private let boxes: [[CGRect]] = [
        [CGRect(x: 0, y: 0, width: 60, height: 20)],
        [CGRect(x: 66, y: 0, width: 80, height: 20)],
        [CGRect(x: 152, y: 0, width: 50, height: 20)],
        [CGRect(x: 0, y: 24, width: 70, height: 20)]
    ]

    @Test func aPencilTapMarksTheWordUnderIt() {
        let gesture = PencilWordMarking.classify([CGPoint(x: 100, y: 10), CGPoint(x: 101, y: 11)])
        #expect(gesture == .tap(CGPoint(x: 100, y: 10)))
        #expect(PencilWordMarking.hits(gesture!, words: boxes) == [1])
        // Just beside a word still counts.
        #expect(PencilWordMarking.hits(.tap(CGPoint(x: 63, y: 10)), words: boxes).count == 1)
        #expect(PencilWordMarking.hits(.tap(CGPoint(x: 400, y: 10)), words: boxes).isEmpty)
    }

    @Test func aStrokeMarksTheWordsItRunsOverOrUnder() {
        let highlight = (0...40).map { CGPoint(x: 70 + CGFloat($0) * 3.5, y: 10) }
        guard case .stroke = PencilWordMarking.classify(highlight) else { Issue.record("not a stroke"); return }
        #expect(PencilWordMarking.hits(.stroke(highlight), words: boxes) == [1, 2])
        // An underline a little below the baseline.
        let underline = (0...30).map { CGPoint(x: 2 + CGFloat($0) * 4, y: 24) }
        #expect(PencilWordMarking.hits(.stroke(underline), words: boxes).contains(0))
    }

    @Test func aLoopMarksTheWordsInside() {
        let center = CGPoint(x: 110, y: 10), rx: CGFloat = 100, ry: CGFloat = 22
        let loop = (0...72).map { i -> CGPoint in
            let a = CGFloat(i) / 72 * 2 * .pi
            return CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a))
        }
        guard case .loop = PencilWordMarking.classify(loop) else { Issue.record("not a loop"); return }
        let hits = PencilWordMarking.hits(.loop(loop), words: boxes)
        #expect(hits.contains(1))
        #expect(!hits.contains(3))
    }
}
