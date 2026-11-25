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

    @Test func syncNamesAreStable() {
        #expect(SyncNameUUID.make("WordArt", "Hund") == SyncNameUUID.make("WordArt", "Hund"))
        #expect(SyncNameUUID.make("WordArt", "Hund") != SyncNameUUID.make("WordArt", "Katze"))
    }
}
