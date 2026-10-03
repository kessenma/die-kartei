//
//  ModelHandoffTests.swift
//  german-ai-flashcardsTests
//
//  Which model continues a synced chat or paper on a device that hasn't got the one it was made
//  with (`ModelHandoff.resolve`). Pure: downloads, Apple Intelligence and RAM fit are passed in.
//

import Foundation
import Testing
@testable import Die_Kartei

@MainActor
struct ModelHandoffTests {
    private let e4b = MLXModel.gemma4_E4B_german
    private let e2b = MLXModel.gemma4_E2B_german
    private let g3b = MLXModel.granite41_3B_german
    private let g2b = MLXModel.granite2B_german
    private let apple = MLXModel.appleIntelligence

    /// A Mac or a 12 GB iPhone: every tutor fits.
    private let roomy: (MLXModel) -> Bool = { _ in true }
    /// A 6 GB iPhone: everything but the E4B tutor.
    private let sixGB: (MLXModel) -> Bool = { $0 != .gemma4_E4B_german }

    @Test func originalOnDiskStays() {
        let h = ModelHandoff.resolve(original: e4b, pick: e2b, downloaded: [e4b, e2b],
                                     appleIntelligence: true, fits: roomy)
        #expect(h.model == e4b)
        #expect(h.isReady)
        #expect(!h.isHandoff)
        #expect(!h.offersOriginal)
    }

    @Test func missingOriginalHandsToThePick() {
        let h = ModelHandoff.resolve(original: e4b, pick: g3b, downloaded: [e2b, g3b],
                                     appleIntelligence: false, fits: roomy)
        #expect(h.model == g3b)
        #expect(h.isReady)
        #expect(h.isHandoff)
        #expect(h.offersOriginal)
    }

    @Test func pickNotOnDiskFallsToBestReadyTutor() {
        let h = ModelHandoff.resolve(original: e4b, pick: e4b, downloaded: [g2b, g3b],
                                     appleIntelligence: true, fits: roomy)
        #expect(h.model == g3b)
        #expect(h.isReady)
    }

    /// The Mac's E4B chat on a 6 GB iPhone with E4B somehow on disk: too big, so it hands off, and
    /// the original isn't offered because it wouldn't load anyway.
    @Test func originalTooBigIsNotOffered() {
        let h = ModelHandoff.resolve(original: e4b, pick: e4b, downloaded: [e4b, e2b],
                                     appleIntelligence: false, fits: sixGB)
        #expect(h.model == e2b)
        #expect(h.isHandoff)
        #expect(!h.offersOriginal)
    }

    @Test func applePickWaitsBehindTutorsForATutorChat() {
        let h = ModelHandoff.resolve(original: e4b, pick: apple, downloaded: [g2b],
                                     appleIntelligence: true, fits: roomy)
        #expect(h.model == g2b)
    }

    @Test func applePickStillWinsForAnAppleChat() {
        let h = ModelHandoff.resolve(original: apple, pick: apple, downloaded: [g2b],
                                     appleIntelligence: true, fits: roomy)
        #expect(h.model == apple)
        #expect(!h.isHandoff)
    }

    @Test func appleChatOnADeviceWithoutAppleIntelligence() {
        let h = ModelHandoff.resolve(original: apple, pick: apple, downloaded: [e2b],
                                     appleIntelligence: false, fits: roomy)
        #expect(h.model == e2b)
        #expect(h.isHandoff)
        #expect(!h.offersOriginal)
    }

    @Test func appleIntelligenceIsTheLastResort() {
        let h = ModelHandoff.resolve(original: e4b, pick: e4b, downloaded: [],
                                     appleIntelligence: true, fits: roomy)
        #expect(h.model == apple)
        #expect(h.isReady)
        #expect(h.offersOriginal)
    }

    /// Nothing ready: the answer is a download, so it names the original where it fits…
    @Test func nothingReadyNamesTheOriginalWhenItFits() {
        let h = ModelHandoff.resolve(original: e4b, pick: g2b, downloaded: [],
                                     appleIntelligence: false, fits: roomy)
        #expect(h.model == e4b)
        #expect(!h.isReady)
        #expect(!h.isHandoff)
    }

    /// …and otherwise the best tutor the device can hold, never one it can't.
    @Test func nothingReadyNeverNamesAModelThatDoesNotFit() {
        let h = ModelHandoff.resolve(original: e4b, pick: e4b, downloaded: [],
                                     appleIntelligence: false, fits: sixGB)
        #expect(h.model == e2b)
        #expect(!h.isReady)
    }

    /// A chat whose model was removed from the app (`original` nil) just takes what's here.
    @Test func removedModelTakesWhatIsHere() {
        let h = ModelHandoff.resolve(original: nil, pick: e4b, downloaded: [e2b],
                                     appleIntelligence: false, fits: roomy)
        #expect(h.model == e2b)
        #expect(!h.isHandoff)
    }
}
