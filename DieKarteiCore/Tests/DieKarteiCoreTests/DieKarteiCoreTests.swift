import Foundation
import Testing
@testable import DieKarteiCore

/// The shared files behave the same in the package as in the app: bundled data loads through
/// `AppResources`, and the plain grammar values answer as the iOS app expects.
@MainActor
struct DieKarteiCoreTests {
    init() {
        // The package carries no data of its own; read the app's Resources folder directly.
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("german-ai-flashcards/Resources")
        AppResources.bundle = Bundle(url: resources)!
    }

    @Test func goetheListsLoadThroughAppResources() {
        for level in GoetheLevel.allCases {
            #expect(!GoetheVocabService.entries(for: level).isEmpty, "\(level.rawValue) list is empty")
        }
        #expect(GoetheVocabService.entries(for: .a1).count > 500)
    }

    @Test func articlesFollowTheCaseTable() {
        #expect(GrammarCase.dativ.article(.der) == "dem")
        #expect(GrammarCase.akkusativ.article(.der) == "den")
        #expect(GrammarCase.genitiv.code == "srsr")
        #expect(Gender(article: " Die ") == .die)
    }

    @Test func modelCatalogKeepsItsRepoIDs() {
        #expect(MLXModel.gemma4_E4B_german.repoID == "kessenma/gemma4-e4b-german-tutor-v4-4bit")
        #expect(MLXModel.appleIntelligence.huggingFaceRepoURL == nil)
    }

    /// The tutor prompts and parsers the Android tutor shares with iOS.
    @Test func correctionParsingAndTranscriptMatchTheApp() {
        let fixed = ConversationPrompts.parseCorrection(
            "FIX: Ich warte auf den Bus.\nWHY: 'warten' takes 'auf'.", original: "Ich warte für den Bus.")
        #expect(fixed.correctedText == "Ich warte auf den Bus.")
        #expect(fixed.note == "'warten' takes 'auf'.")
        // An echo that only adds punctuation is not a correction.
        #expect(ConversationPrompts.parseCorrection("FIX: Ich bin müde.", original: "ich bin müde").isClean)
        #expect(ConversationPrompts.parseCorrection("OK", original: "Ich bin müde.").isClean)

        let transcript = ConversationPrompts.transcript(lines: [
            (sortOrder: 1, isUser: true, text: "Hallo!"),
            (sortOrder: 0, isUser: false, text: "Wie geht's?"),
        ])
        #expect(transcript == "PARTNER: Wie geht's?\nSTUDENT: Hallo!")
        #expect(ClassTutorContext.promptSection("Dativ").contains("\"\"\"\nDativ\n\"\"\""))

        let config = ConversationConfig(model: .gemma4_E2B_german)
        #expect(ConversationPrompts.correctionSystemPrompt(for: config).contains("FIX: <the full corrected sentence"))
    }

    /// The SM-2 steps the iOS app has always used: 1 → 6 → interval × ease, lapses reset.
    @Test func sm2SchedulesLikeTheApp() {
        let card = TestCard()
        SRSScheduling.apply(rating: .good, to: card)
        #expect(card.interval == 1 && card.repetitions == 1)
        SRSScheduling.apply(rating: .good, to: card)
        #expect(card.interval == 6)
        SRSScheduling.apply(rating: .good, to: card)
        #expect(card.interval == 15)  // ceil(6 × 2.5)
        SRSScheduling.apply(rating: .again, to: card)
        #expect(card.interval == 1 && card.repetitions == 0 && card.lapses == 1)
        #expect(abs(card.easeFactor - 2.3) < 0.0001)
        #expect(card.totalReviews == 4 && card.lastCorrect == false)
        #expect(SRSScheduling.previewIntervals(for: TestCard()).map(\.label) == ["1d", "1d", "1d", "4d"])
    }

    @Test func leitnerMovesBoxes() {
        let card = TestCard()
        SRSScheduling.leitnerCorrect(card)
        SRSScheduling.leitnerCorrect(card)
        #expect(card.leitnerBox == 2 && card.interval == 2)
        SRSScheduling.leitnerWrong(card)
        #expect(card.leitnerBox == 1 && card.repetitions == 0)
    }

    @Test func grammarContentLoads() {
        #expect(PrepositionService.all().count > 20)
        #expect(PrepositionService.preposition("mit")?.governs == .dativ)
        #expect(ArticleRules.hint(for: "Zeitung", article: .die) != nil)
        #expect(GrammarExerciseService.loadCategories().count == 4)
        #expect(!PastTenseVerbService.entries(for: .a1).isEmpty)
    }

    @Test func syncNamesAreStable() {
        #expect(SyncNameUUID.make("WordArt", "Hund") == SyncNameUUID.make("WordArt", "Hund"))
        #expect(SyncNameUUID.make("WordArt", "Hund") != SyncNameUUID.make("WordArt", "Katze"))
    }
}

/// A bare card for the scheduler, like the Android app's.
@MainActor
final class TestCard: SRSCardState {
    let sortOrder = 0
    var easeFactor = 2.5
    var interval = 0
    var repetitions = 0
    var nextReviewDate: Date?
    var totalReviews = 0
    var lapses = 0
    var leitnerBox = 0
    var lastCorrect: Bool?

    func noteReview(correct: Bool, at now: Date) { lastCorrect = correct }
}
