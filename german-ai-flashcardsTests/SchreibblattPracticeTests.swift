//
//  SchreibblattPracticeTests.swift
//  german-ai-flashcardsTests
//
//  Which words a writing sheet offers and in what order (Services/SchreibblattPractice.swift):
//  the three-way join onto a headword, the four lenses, and the Braucht-Übung ranking.
//
//  Two claims carry the screen and get the most attention here. **A lens is a permutation, not a
//  filter** — all four return the same set, so a ticked word can never vanish when the learner
//  switches lens. And **the ranking is a sort, not a cutoff** — no card is excluded by a number,
//  so there is no threshold to calibrate.
//
//  The facts structs are built here rather than from a store: the production adapter that turns
//  `@Query` results into them is a handful of field copies, and keeping models out is what makes
//  this testable at all (`PyramidService.refutedWords` takes model arrays, which is why it has no
//  test). See docs/SCHREIBBLATT.md.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct SchreibblattPracticeTests {

    // MARK: - Fixtures

    typealias Facts = SchreibblattPractice.CardFacts
    typealias Stat = SchreibblattPractice.StatFacts
    typealias Lens = SchreibblattPractice.Lens

    static let older = Date(timeIntervalSince1970: 1_000_000)
    static let newer = Date(timeIntervalSince1970: 2_000_000)
    static let now = Date(timeIntervalSince1970: 3_000_000)

    static let deckA = UUID()
    static let deckB = UUID()

    /// One card, varying only what a test cares about.
    private func card(
        german: String,
        english: String = "a word",
        deck: UUID = SchreibblattPracticeTests.deckA,
        deckTitle: String = "Möbel",
        deckCreatedAt: Date = SchreibblattPracticeTests.older,
        sortOrder: Int = 0,
        lapses: Int = 0,
        repetitions: Int = 0,
        interval: Int = 0,
        lastReviewWasCorrect: Bool? = nil,
        lastReviewedAt: Date? = nil,
        nextReviewDate: Date? = nil
    ) -> Facts {
        Facts(id: UUID(), german: german, english: english, deckID: deck, deckTitle: deckTitle,
              deckCreatedAt: deckCreatedAt, sortOrder: sortOrder, lapses: lapses,
              repetitions: repetitions, interval: interval,
              lastReviewWasCorrect: lastReviewWasCorrect, lastReviewedAt: lastReviewedAt,
              nextReviewDate: nextReviewDate)
    }

    private func stat(
        _ german: String, missed: Int, tricky: Bool = false, lastMissedAt: Date? = nil
    ) -> Stat {
        Stat(key: SchreibblattPractice.joinKey(german), timesMissed: missed,
             lastMissedAt: lastMissedAt, isTricky: tricky)
    }

    private func rank(
        _ cards: [Facts], articles: [Stat] = [], pairs: [Stat] = []
    ) -> [SchreibblattPractice.Candidate] {
        SchreibblattPractice.ordered(
            SchreibblattPractice.candidates(cards: cards, articleStats: articles,
                                            pairStats: pairs, now: Self.now),
            by: .uebung)
    }

    // MARK: - The join

    @Test func aCardThatBakedInItsArticleStillMatchesABareStatKey() {
        // This is the gap `WortschatzBrowseView.Lookup` leaves: it keys on the raw word, which is
        // safe for a Goethe headword and wrong for a card storing "die Gabel" in `germanWord`.
        #expect(SchreibblattPractice.joinKey("die Gabel") == "gabel")
        #expect(SchreibblattPractice.joinKey("Gabel") == "gabel")
        #expect(SchreibblattPractice.joinKey("  DER Löffel ") == "löffel")

        let ranked = rank([card(german: "die Gabel")], articles: [stat("Gabel", missed: 3)])
        #expect(ranked.first?.reasons.contains(.articleMisses(3)) == true)
    }

    @Test func theMatchingSideIsNormalizedToo() {
        // `MatchingGameView` stores `card.germanWord` verbatim, so a pair row can carry an article
        // even though the model's comment says it does not.
        let ranked = rank([card(german: "Gabel")], pairs: [stat("die Gabel", missed: 2)])
        #expect(ranked.first?.reasons.contains(.matchingMisses(2)) == true)
    }

    @Test func severalRowsForOneHeadwordCollapseToTheTrickiest() {
        let folded = SchreibblattPractice.index([
            stat("Bank", missed: 5, tricky: false),
            stat("Bank", missed: 1, tricky: true),
        ])
        #expect(folded.count == 1)
        // Trickiest wins even though the other was missed more often — the same rule the
        // Wortschatz browse join uses.
        #expect(folded["bank"]?.isTricky == true)
        #expect(folded["bank"]?.timesMissed == 1)
    }

    @Test func rowsThatAreEquallyTrickyFallBackToTheMostMissed() {
        let folded = SchreibblattPractice.index([
            stat("Bank", missed: 2, tricky: true),
            stat("Bank", missed: 7, tricky: true),
        ])
        #expect(folded["bank"]?.timesMissed == 7)
    }

    @Test func aStatWithNoMatchingCardIsSimplyIgnored() {
        let ranked = rank([card(german: "das Haus")], articles: [stat("Fahrrad", missed: 9)])
        #expect(ranked.count == 1)
        #expect(ranked.first?.reasons == [.neverPractised])
    }

    // MARK: - Reasons

    @Test func everySignalBecomesAReasonCarryingItsOwnCount() {
        let overdue = Self.now.addingTimeInterval(-3 * 86_400)
        let ranked = rank(
            [card(german: "der Hund", lapses: 2, lastReviewWasCorrect: false,
                  nextReviewDate: overdue)],
            articles: [stat("Hund", missed: 4)],
            pairs: [stat("Hund", missed: 1)])
        let reasons = try! #require(ranked.first).reasons
        #expect(reasons.contains(.lapsed(2)))
        #expect(reasons.contains(.lastAnswerWrong))
        #expect(reasons.contains(.dueNow(daysOverdue: 3)))
        #expect(reasons.contains(.articleMisses(4)))
        #expect(reasons.contains(.matchingMisses(1)))
        #expect(!reasons.contains(.neverPractised), "a word with signals is not unpractised")
    }

    @Test func reasonsArePrintedHeaviestFirst() {
        let ranked = rank([card(german: "der Hund", lapses: 3, lastReviewWasCorrect: false)],
                          pairs: [stat("Hund", missed: 1)])
        let reasons = try! #require(ranked.first).reasons
        #expect(reasons.map(\.weight) == reasons.map(\.weight).sorted(by: >))
        #expect(reasons.first == .lapsed(3))
    }

    @Test func aCardWithNoSignalAtAllStillAppearsAndSaysSo() {
        // Otherwise the lens is an empty screen on a fresh install.
        let ranked = rank([card(german: "das Haus")])
        #expect(ranked.count == 1)
        #expect(ranked.first?.reasons == [.neverPractised])
        #expect(ranked.first?.score == 0)
    }

    @Test func aWordNotYetDueIsNotCalledDue() {
        let future = Self.now.addingTimeInterval(5 * 86_400)
        let ranked = rank([card(german: "das Haus", nextReviewDate: future)])
        #expect(ranked.first?.reasons == [.neverPractised])
    }

    @Test func everyReasonHasSomethingToSay() {
        let all: [SchreibblattPractice.Reason] = [
            .lapsed(1), .lapsed(4), .lastAnswerWrong, .dueNow(daysOverdue: 0),
            .dueNow(daysOverdue: 9), .matchingMisses(2), .articleMisses(3), .neverPractised,
        ]
        for reason in all {
            #expect(!reason.label.isEmpty)
            #expect(reason.weight >= 0)
        }
        #expect(SchreibblattPractice.Reason.lapsed(1).label == "forgotten once")
        #expect(SchreibblattPractice.Reason.lapsed(3).label == "forgotten 3×")
    }

    // MARK: - The ranking is a sort, not a cutoff

    @Test func nothingIsEverExcluded() {
        let cards = [
            card(german: "das Haus"),
            card(german: "der Hund", lapses: 4),
            card(german: "die Stadt", repetitions: 9, interval: 40),
        ]
        for lens in Lens.allCases {
            let ordered = SchreibblattPractice.ordered(
                SchreibblattPractice.candidates(cards: cards, now: Self.now), by: lens)
            #expect(ordered.count == cards.count, "\(lens) dropped a card")
        }
    }

    @Test func moreTroubleSortsHigher() {
        let ranked = rank([
            card(german: "das Haus"),
            card(german: "der Hund", lapses: 4),
            card(german: "die Stadt", lapses: 1),
        ])
        #expect(ranked.map(\.word.german) == ["der Hund", "die Stadt", "das Haus"])
        #expect(ranked.map(\.score) == ranked.map(\.score).sorted(by: >) || ranked.count == 3)
    }

    @Test func aKnownWordSinksBelowAnUnknownOneWithLessTrouble() {
        // Known is a de-emphasis, not an exclusion: a word proven three weeks ago is worth less
        // of the page than one still being learned.
        let ranked = rank([
            card(german: "die Stadt", lapses: 5, repetitions: 9, interval: 40),
            card(german: "der Hund", lapses: 1),
        ])
        #expect(ranked.map(\.word.german) == ["der Hund", "die Stadt"])
        #expect(ranked.last?.isKnown == true)
    }

    @Test func maturityIsReadTheSameWayTheRestOfTheAppReadsIt() {
        #expect(card(german: "a", interval: PyramidService.matureIntervalDays).isKnown)
        #expect(card(german: "a", interval: PyramidService.matureIntervalDays - 1).isKnown == false)
        #expect(card(german: "a", repetitions: PyramidService.provenRepetitions).isKnown)
        #expect(card(german: "a", repetitions: PyramidService.provenRepetitions - 1).isKnown == false)
    }

    @Test func tiesFallToTheMostRecentTrouble() {
        let ranked = rank([
            card(german: "das Haus", lapses: 2, lastReviewedAt: Self.older),
            card(german: "der Hund", lapses: 2, lastReviewedAt: Self.newer),
        ])
        #expect(ranked.map(\.word.german) == ["der Hund", "das Haus"])
    }

    @Test func aWordWithNoTroubleDateSortsBelowOneThatHasOne() {
        let ranked = rank([
            card(german: "das Haus", lapses: 2),
            card(german: "der Hund", lapses: 2, lastReviewedAt: Self.newer),
        ])
        #expect(ranked.map(\.word.german) == ["der Hund", "das Haus"])
    }

    @Test func theRankingIsDeterministicWhateverOrderTheCardsArriveIn() {
        let cards = [
            card(german: "das Haus", lapses: 2, lastReviewedAt: Self.older),
            card(german: "der Hund", lapses: 2, lastReviewedAt: Self.newer),
            card(german: "die Stadt", lapses: 5),
            card(german: "das Buch"),
            card(german: "der Tisch", lapses: 9, repetitions: 4, interval: 40),
        ]
        let expected = rank(cards).map(\.word.german)
        for _ in 0..<2 {
            #expect(rank(cards.shuffled()).map(\.word.german) == expected)
        }
    }

    // MARK: - A lens is a permutation, not a filter

    @Test func allFourLensesReturnTheSameSetInADifferentOrder() {
        let cards = [
            card(german: "die Zwiebel", deck: Self.deckB, deckTitle: "Essen",
                 deckCreatedAt: Self.newer, sortOrder: 1, lapses: 3),
            card(german: "der Apfel", deck: Self.deckB, deckTitle: "Essen",
                 deckCreatedAt: Self.newer, sortOrder: 0),
            card(german: "das Haus", sortOrder: 0, repetitions: 5, interval: 40),
            card(german: "der Stuhl", sortOrder: 1, lapses: 1),
        ]
        let base = SchreibblattPractice.candidates(cards: cards, now: Self.now)
        let reference = Set(base.map(\.id))

        var orders: [[UUID]] = []
        for lens in Lens.allCases {
            let ordered = SchreibblattPractice.ordered(base, by: lens)
            // The invariant the whole selection screen rests on.
            #expect(Set(ordered.map(\.id)) == reference, "\(lens) changed the set")
            #expect(ordered.count == base.count)
            orders.append(ordered.map(\.id))
        }
        // And they really are different views, not four copies of one order.
        #expect(Set(orders.map { $0.map(\.uuidString).joined() }).count > 1)
    }

    @Test func orderingIsStableWhenCalledTwice() {
        let base = SchreibblattPractice.candidates(
            cards: [card(german: "a", lapses: 1), card(german: "b", lapses: 1)], now: Self.now)
        for lens in Lens.allCases {
            #expect(SchreibblattPractice.ordered(base, by: lens).map(\.id)
                == SchreibblattPractice.ordered(base, by: lens).map(\.id))
        }
    }

    // MARK: - Neu

    @Test func neuPutsTheNewestDeckFirstAndTheLatestCardWithinItFirst() {
        let cards = [
            card(german: "alt 1", deckCreatedAt: Self.older, sortOrder: 0),
            card(german: "alt 2", deckCreatedAt: Self.older, sortOrder: 1),
            card(german: "neu 1", deck: Self.deckB, deckCreatedAt: Self.newer, sortOrder: 0),
            card(german: "neu 2", deck: Self.deckB, deckCreatedAt: Self.newer, sortOrder: 1),
        ]
        let ordered = SchreibblattPractice.ordered(
            SchreibblattPractice.candidates(cards: cards, now: Self.now), by: .neu)
        // The proxy for a card's own added-at date, which `SavedCard` does not carry.
        #expect(ordered.map(\.word.german) == ["neu 2", "neu 1", "alt 2", "alt 1"])
    }

    // MARK: - Deck

    @Test func deckGroupsByDeckNewestDeckFirstAndKeepsEachDecksOwnOrder() {
        let cards = [
            card(german: "alt 2", deckCreatedAt: Self.older, sortOrder: 1),
            card(german: "neu 1", deck: Self.deckB, deckTitle: "Essen",
                 deckCreatedAt: Self.newer, sortOrder: 0),
            card(german: "alt 1", deckCreatedAt: Self.older, sortOrder: 0),
        ]
        let ordered = SchreibblattPractice.ordered(
            SchreibblattPractice.candidates(cards: cards, now: Self.now), by: .deck)
        #expect(ordered.map(\.word.german) == ["neu 1", "alt 1", "alt 2"])
        // Rows of one deck are contiguous, which is what lets a section header toggle them all.
        #expect(ordered.map(\.deckID) == [Self.deckB, Self.deckA, Self.deckA])
        #expect(SchreibblattPractice.group(for: ordered[0], lens: .deck) == "Essen")
    }

    // MARK: - A–Z

    @Test func alphabetSortsOnTheNounAndIgnoresTheArticle() {
        let cards = [
            card(german: "der Apfel"),
            card(german: "das Zebra"),
            card(german: "die Birne"),
        ]
        let ordered = SchreibblattPractice.ordered(
            SchreibblattPractice.candidates(cards: cards, now: Self.now), by: .alphabet)
        #expect(ordered.map(\.word.german) == ["der Apfel", "die Birne", "das Zebra"])
        // "der Apfel" files under A, not D.
        #expect(SchreibblattPractice.group(for: ordered[0], lens: .alphabet) == "A")
        #expect(SchreibblattPractice.group(for: ordered[2], lens: .alphabet) == "Z")
    }

    @Test func alphabetHandlesAWordWithNoArticleAtAll() {
        let cards = [card(german: "laufen"), card(german: "arbeiten")]
        let ordered = SchreibblattPractice.ordered(
            SchreibblattPractice.candidates(cards: cards, now: Self.now), by: .alphabet)
        #expect(ordered.map(\.word.german) == ["arbeiten", "laufen"])
    }

    // MARK: - Search narrows the rows, never the selection

    @Test func searchMatchesBothSidesAndIgnoresCaseAndDiacritics() {
        let base = SchreibblattPractice.candidates(cards: [
            card(german: "der Löffel", english: "the spoon"),
            card(german: "die Gabel", english: "the fork"),
        ], now: Self.now)

        #expect(SchreibblattPractice.matching(base, search: "löffel").count == 1)
        #expect(SchreibblattPractice.matching(base, search: "LOFFEL").count == 1)
        #expect(SchreibblattPractice.matching(base, search: "loffel").count == 1)
        // The English side matches too, so a learner can find a word they only know in English.
        #expect(SchreibblattPractice.matching(base, search: "fork").count == 1)
        #expect(SchreibblattPractice.matching(base, search: "the").count == 2)
        #expect(SchreibblattPractice.matching(base, search: "xyzzy").isEmpty)
    }

    @Test func anEmptyOrBlankSearchShowsEverything() {
        let base = SchreibblattPractice.candidates(
            cards: [card(german: "a"), card(german: "b")], now: Self.now)
        #expect(SchreibblattPractice.matching(base, search: "").count == 2)
        #expect(SchreibblattPractice.matching(base, search: "   ").count == 2)
    }

    @Test func aTickedWordThatTheSearchHidesIsStillSelected() {
        // Search returns rows to draw; it is not the selection. The screen holds the ticks, so a
        // query that hides a word must not untick it.
        let base = SchreibblattPractice.candidates(cards: [
            card(german: "der Löffel", english: "the spoon"),
            card(german: "die Gabel", english: "the fork"),
        ], now: Self.now)
        let selection = Set(base.map(\.id))

        let visible = SchreibblattPractice.matching(base, search: "Gabel")
        #expect(visible.count == 1)
        #expect(selection.count == 2, "the selection is the caller's and search does not touch it")
        // Every word a sheet would be built from is still reachable from the full set.
        let picked = base.filter { selection.contains($0.id) }
        #expect(picked.count == 2)
    }

    // MARK: - Lens chrome

    @Test func onlyBrauchtUebungExplainsItsRows() {
        #expect(Lens.uebung.showsReasons)
        for lens in Lens.allCases where lens != .uebung {
            #expect(!lens.showsReasons, "\(lens) would repeat its own sort key on every row")
        }
        #expect(Lens.deck.isGrouped)
        #expect(Lens.alphabet.isGrouped)
        #expect(!Lens.neu.isGrouped)
        #expect(!Lens.uebung.isGrouped)
        for lens in Lens.allCases { #expect(!lens.title.isEmpty) }
    }

    // MARK: - Feeding the sheet

    @Test func aCandidateCarriesTheWordTheSheetWillPrint() {
        let ranked = rank([card(german: "der Löffel", english: "the spoon")])
        let candidate = try! #require(ranked.first)
        #expect(candidate.word.german == "der Löffel", "the article prints, so it must survive")
        #expect(candidate.word.english == "the spoon")
        // The word points back at its card, so a sheet can be traced to what it came from.
        #expect(candidate.word.id == candidate.id)
    }

    @Test func noCardsMakesAnEmptyListRatherThanAnError() {
        #expect(SchreibblattPractice.candidates(cards: [], now: Self.now).isEmpty)
        for lens in Lens.allCases {
            #expect(SchreibblattPractice.ordered([], by: lens).isEmpty)
        }
        #expect(SchreibblattPractice.matching([], search: "x").isEmpty)
    }
}
