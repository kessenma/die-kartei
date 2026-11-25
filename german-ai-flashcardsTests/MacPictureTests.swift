//
//  MacPictureTests.swift
//  german-ai-flashcardsTests
//
//  MAC-PICTURES (docs/MAC_PICTURES.md): the order rule that decides when a deck is waiting for the
//  Mac, how it survives a sync merge, the size/memory table the Mac draws by, and that an iPhone
//  never sees a Mac picture model.
//

import Foundation
import SwiftUI
import Testing
@testable import Die_Kartei

private func request(redrawAll: Bool = false, at seconds: TimeInterval = 0) -> MacPictureOrder.Request {
    MacPictureOrder.newRequest(styleRaw: "flatIcon", detailRaw: "justTheWord", redrawAll: redrawAll,
                               cardCount: 12, fromDevice: "iPhone", now: Date(timeIntervalSinceReferenceDate: seconds))
}

private func payload(_ request: MacPictureOrder.Request?, _ result: MacPictureOrder.Result?, t: Double) -> SyncPayload {
    var f = SyncFields()
    f.set("topic", "Küche")
    f.set("macPictureRequest", jsonData: MacPictureOrder.encode(request))
    f.set("macPictureResult", jsonData: MacPictureOrder.encode(result))
    var p = f.payload
    p[SyncPayloadKey.modifiedAt] = .number(t)
    return p
}

private func decoded(_ p: SyncPayload) -> (MacPictureOrder.Request?, MacPictureOrder.Result?) {
    (MacPictureOrder.decode(MacPictureOrder.Request.self, from: p.jsonData("macPictureRequest")),
     MacPictureOrder.decode(MacPictureOrder.Result.self, from: p.jsonData("macPictureResult")))
}

@Suite struct MacPictureOrderTests {
    @Test func pendingUntilAResultNamesTheRequest() {
        let first = request()
        #expect(!MacPictureOrder.isPending(nil, nil))
        #expect(MacPictureOrder.isPending(first, nil))
        let done = MacPictureOrder.settle(first, outcome: .drawn, drawn: 12, byDevice: "Mac")
        #expect(!MacPictureOrder.isPending(first, done))
        // A new request after that is pending again, whatever the clocks say.
        let second = request(at: -1_000)
        #expect(MacPictureOrder.isPending(second, done))
    }

    @Test func storageRoundTripsAndToleratesGarbage() {
        let r = request(redrawAll: true)
        let data = MacPictureOrder.encode(r)
        #expect(MacPictureOrder.decode(MacPictureOrder.Request.self, from: data) == r)
        #expect(MacPictureOrder.decode(MacPictureOrder.Request.self, from: Data("{nope".utf8)) == nil)
        #expect(MacPictureOrder.decode(MacPictureOrder.Request.self, from: nil) == nil)
    }

    @Test func savedDeckAccessorsUseTheSameStorage() {
        let deck = SavedDeck(topic: "Küche", wordCount: 1, includeExamples: false)
        #expect(!deck.hasPendingMacPictures)
        let r = request()
        deck.macPictureRequest = r
        #expect(deck.hasPendingMacPictures)
        deck.macPictureResult = MacPictureOrder.settle(r, outcome: .cancelled, drawn: 0, byDevice: "iPhone")
        #expect(!deck.hasPendingMacPictures)
    }
}

/// The phone writes only the request and the Mac only the result, so plain LWW can't lose an
/// order. These run the real merge with the deck codec's spec.
@Suite struct MacPictureMergeTests {
    let spec = SavedDeckCodec.spec

    @Test func reRequestWhileTheMacSettlesTheOldOneStaysPending() {
        let old = request()
        let fresh = request(at: 50)
        let ancestor = payload(old, nil, t: 10)
        let phone = payload(fresh, nil, t: 50)
        let mac = payload(old, MacPictureOrder.settle(old, outcome: .drawn, drawn: 12, byDevice: "Mac"), t: 60)
        for (l, r) in [(phone, mac), (mac, phone)] {
            let (req, res) = decoded(SyncMerge.merge(ancestor: ancestor, local: l, remote: r, spec: spec))
            #expect(req == fresh)
            #expect(res?.settles == old.id)
            #expect(MacPictureOrder.isPending(req, res))
        }
    }

    @Test func cancelRacingASettleEndsSettledEitherWay() {
        let order = request()
        let ancestor = payload(order, nil, t: 10)
        let phone = payload(order, MacPictureOrder.settle(order, outcome: .cancelled, drawn: 0, byDevice: "iPhone"), t: 20)
        let mac = payload(order, MacPictureOrder.settle(order, outcome: .drawn, drawn: 12, byDevice: "Mac"), t: 30)
        for (l, r) in [(phone, mac), (mac, phone)] {
            let (req, res) = decoded(SyncMerge.merge(ancestor: ancestor, local: l, remote: r, spec: spec))
            #expect(!MacPictureOrder.isPending(req, res))
        }
    }

    @Test func aFirstSyncWithNoAncestorKeepsTheOrder() {
        let order = request()
        let phone = payload(order, nil, t: 20)
        let mac = payload(nil, nil, t: 5)
        let (req, res) = decoded(SyncMerge.merge(ancestor: nil, local: mac, remote: phone, spec: spec))
        #expect(req == order)
        #expect(MacPictureOrder.isPending(req, res))
    }
}

@Suite struct MacPictureSizingTests {
    // Budgets as the formula gives them: 8 / 16 / 24 / 32 GB Macs (Metal's recommendation ≈ 2/3
    // of RAM below 32 GB, 3/4 above).
    static let budgets = [
        8: MacPictureSizing.budgetMB(physicalMB: 8_192, recommendedGPUMB: 5_461),
        16: MacPictureSizing.budgetMB(physicalMB: 16_384, recommendedGPUMB: 10_923),
        24: MacPictureSizing.budgetMB(physicalMB: 24_576, recommendedGPUMB: 18_432),
        32: MacPictureSizing.budgetMB(physicalMB: 32_768, recommendedGPUMB: 24_576),
    ]

    @Test func eightGigabyteMacsGetNeitherModel() {
        let budget = Self.budgets[8]!
        #expect(!MacPictureSizing.isOffered(.zImageTurbo, budgetMB: budget))
        #expect(!MacPictureSizing.isOffered(.flux2Klein, budgetMB: budget))
    }

    @Test func sixteenGigabyteMacsDrawZImageAtEverySizeAndKleinUpTo768() {
        let budget = Self.budgets[16]!
        #expect(MacPictureSizing.size(.zImageTurbo, purpose: .story, tier: .best, budgetMB: budget) == 1024)
        #expect(MacPictureSizing.size(.flux2Klein, purpose: .story, tier: .best, budgetMB: budget) == 768)
        #expect(MacPictureSizing.size(.flux2Klein, purpose: .card, tier: .fast, budgetMB: budget) == 512)
    }

    @Test func biggerMacsGetTheTiersOwnSize() {
        let budget = Self.budgets[32]!
        for model in [ImageGenModel.zImageTurbo, .flux2Klein] {
            #expect(MacPictureSizing.size(model, purpose: .story, tier: .best, budgetMB: budget) == 1024)
            #expect(MacPictureSizing.size(model, purpose: .story, tier: .balanced, budgetMB: budget) == 768)
            #expect(MacPictureSizing.size(model, purpose: .card, tier: .best, budgetMB: budget) == 768)
            #expect(MacPictureSizing.size(model, purpose: .card, tier: .balanced, budgetMB: budget) == 512)
            #expect(MacPictureSizing.size(model, purpose: .sample, tier: .best, budgetMB: budget) == 512)
        }
    }

    @Test func coreMLModelsAreNeverOfferedAsMacModels() {
        #expect(!MacPictureSizing.isOffered(.bkSdmTiny, budgetMB: 100_000))
        #expect(!MacPictureSizing.isOffered(.sd21Base, budgetMB: 100_000))
    }

    @Test func purposeFollowsTheDestination() {
        let story = URL(fileURLWithPath: "/x/Application Support/StoryImages/ABC/00.png")
        let card = URL(fileURLWithPath: "/x/Application Support/CardImages/ABC/card.png")
        #expect(MacPictureSizing.purpose(destination: story, stepCountOverride: nil) == .story)
        #expect(MacPictureSizing.purpose(destination: card, stepCountOverride: nil) == .card)
        #expect(MacPictureSizing.purpose(destination: card, stepCountOverride: 15) == .sample)
    }
}

@Suite struct ImageGenModelPlatformTests {
    @Test func anIPhoneNeverListsAMacModel() {
        #expect(ImageGenModel.allCases == [.sd21Base, .bkSdmTiny])
        #expect(ImageGenModel.macModels.isEmpty)
    }

    @Test func aStoredMacModelReadsAsBKSDMOnIOS() {
        let key = ImageGenModel.selectionDefaultsKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.set(ImageGenModel.zImageTurbo.rawValue, forKey: key)
        #expect(ImageGenModel.current == .bkSdmTiny)
    }
}

/// Renders the phone's "Draw on my Mac" row in its three states to PNGs under the simulator's
/// temporary folder (the path is printed), for looking at without driving the UI.
@MainActor
@Suite struct MacPictureRowRenderTests {
    @Test func rendersTheRowStates() throws {
        let mac = SyncPeer(id: "mac", model: "Mac", appVersion: "1", lastSyncAt: .now.addingTimeInterval(-7_200),
                           writtenAt: .now.addingTimeInterval(-7_200), hasPending: false, stuck: 0, digests: [:],
                           isThisDevice: false, macPictureModels: [ImageGenModel.zImageTurbo.rawValue])
        let bare = SyncPeer(id: "mac2", model: "Mac", appVersion: "1", lastSyncAt: .now, writtenAt: .now,
                            hasPending: false, stuck: 0, digests: [:], isThisDevice: false)
        let cards = [("der Apfel", "the apple"), ("das Messer", "the knife"), ("die Tasse", "the cup")]
            .map { VocabCard(germanWord: $0.0, englishTranslation: $0.1, wordType: "noun") }

        let fresh = SavedDeck(topic: "Küche", wordCount: 3, includeExamples: false, vocabCards: cards)
        let waiting = SavedDeck(topic: "Küche", wordCount: 3, includeExamples: false, vocabCards: cards)
        waiting.macPictureRequest = MacPictureOrder.newRequest(styleRaw: "watercolor", detailRaw: "justTheWord",
                                                               redrawAll: false, cardCount: 3, fromDevice: "iPhone")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mac-picture-rows")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, deck, peer) in [("ready", fresh, mac), ("waiting", waiting, mac), ("no-model", fresh, bare)] {
            let renderer = ImageRenderer(content: MacPictureHandoffRow(deck: deck, mac: peer)
                .frame(width: 390).padding(.vertical, 20).background(Color(white: 0.96))
                .inMemoryModelContainer(for: [SavedDeck.self]))
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            try #require(image.pngData()).write(to: dir.appendingPathComponent("\(name).png"))
        }
        print("[macPictures.render] \(dir.path)")
    }
}
