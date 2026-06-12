import Foundation
import Testing
@testable import DieKarteiCore

// MARK: - Resource loading (Bundle.module)

@Test func goetheVocabularyLoads() {
    #expect(GoetheVocabService.entries(for: .a1).count > 300)
    #expect(GoetheVocabService.entries(for: .a2).count > 300)
    #expect(GoetheVocabService.entries(for: .b1).count > 300)
}

@Test func pastTenseVerbsLoad() {
    #expect(!PastTenseVerbService.allEntries.isEmpty)
    #expect(!PastTenseVerbService.entries(for: .a1).isEmpty)
}

@Test func grammarExercisesLoad() {
    let categories = GrammarExerciseService.loadCategories()
    #expect(!categories.isEmpty)
    #expect(!categories[0].exercises.isEmpty)
}

// MARK: - SRS algorithms via the platform-neutral protocol

final class MockCard: SRSCardState {
    var easeFactor = 2.5
    var interval = 0
    var repetitions = 0
    var nextReviewDate: Date? = nil
    var totalReviews = 0
    var lapses = 0
    var leitnerBox = 0
    var sortOrder = 0
}

@Test func sm2GoodProgressionGrowsInterval() {
    let card = MockCard()
    SpacedRepetitionService.apply(rating: .good, to: card)
    #expect(card.interval == 1)
    SpacedRepetitionService.apply(rating: .good, to: card)
    #expect(card.interval == 6)
    SpacedRepetitionService.apply(rating: .good, to: card)
    #expect(card.interval == 15) // ceil(6 * 2.5)
    #expect(card.nextReviewDate != nil)
}

@Test func sm2AgainResetsAndRecordsLapse() {
    let card = MockCard()
    SpacedRepetitionService.apply(rating: .good, to: card)
    SpacedRepetitionService.apply(rating: .again, to: card)
    #expect(card.repetitions == 0)
    #expect(card.lapses == 1)
    #expect(card.interval == 1)
}

@Test func leitnerPromotionAndDemotion() {
    let card = MockCard()
    LeitnerService.markCorrect(card)
    #expect(card.leitnerBox == 1)
    for _ in 0..<10 { LeitnerService.markCorrect(card) }
    #expect(card.leitnerBox == LeitnerService.maxBox)
    LeitnerService.markWrong(card)
    #expect(card.leitnerBox == 1)
    #expect(card.lapses == 1)
}

// MARK: - Prompt parsing

@Test func correctionParsing() {
    let result = ConversationPrompts.parseCorrection(
        "FIX: Ich habe einen Hund.\nWHY: Akkusativ needs 'einen'.",
        original: "Ich habe ein Hund."
    )
    #expect(result.correctedText == "Ich habe einen Hund.")
    #expect(result.note == "Akkusativ needs 'einen'.")

    let clean = ConversationPrompts.parseCorrection("OK", original: "Das ist gut.")
    #expect(clean.isClean)
}

@Test func transcriptOrdersBySortOrder() {
    let lines = [
        TranscriptLine(isUser: false, text: "Hallo!", sortOrder: 0),
        TranscriptLine(isUser: true, text: "Guten Tag!", sortOrder: 1),
    ]
    let transcript = ConversationPrompts.transcript(from: lines.reversed())
    #expect(transcript == "PARTNER: Hallo!\nSTUDENT: Guten Tag!")
}
