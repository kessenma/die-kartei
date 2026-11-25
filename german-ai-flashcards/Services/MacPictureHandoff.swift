import Foundation
import SwiftData

// MAC-PICTURES: "Draw on my Mac" (docs/MAC_PICTURES.md). The pieces both platforms share: what a
// Mac advertises, finding it from a phone, placing and cancelling an order. The Mac side that
// draws is `MacPictureInbox`; the phone side that notices pictures arriving is the watcher below.

@MainActor
enum MacPictureHandoff {

    /// What this device tells the others it can draw with (its heartbeat): the downloaded MLX
    /// models on a Mac, nil everywhere else (nil isn't written, so phones' heartbeats don't change).
    static var advertisedModels: [String]? {
        let models = ImageGenModel.macModels.filter(\.isDownloaded).map(\.rawValue)
        return models.isEmpty ? nil : models
    }

    /// The learner's Mac, as the last heartbeat described it: the most recently seen Mac running
    /// the app, preferring one with a picture model downloaded. nil without sync or a Mac.
    static func macPeer() -> SyncPeer? {
        guard let peers = SyncManager.shared.coordinator?.peers() else { return nil }
        let macs = peers.filter { !$0.isThisDevice && $0.model.contains("Mac") }
        let ready = macs.filter { !$0.macPictureModels.isEmpty }
        return (ready.isEmpty ? macs : ready).max { lastSeen($0) < lastSeen($1) }
    }

    private static func lastSeen(_ peer: SyncPeer) -> Date {
        peer.writtenAt ?? peer.lastSyncAt ?? .distantPast
    }

    /// Whether a deck can be sent: the same decks that can have pictures at all, with cards.
    /// (Wortschatz decks are out anyway: their cards never take content from a payload, so
    /// pictures drawn elsewhere wouldn't reach them.)
    static func canOrder(_ deck: SavedDeck) -> Bool {
        deck.isBrowsableContent && !deck.cards.isEmpty
    }

    /// Ask the Mac for pictures in this device's current picture style.
    static func order(_ deck: SavedDeck, redrawAll: Bool, in context: ModelContext) {
        deck.macPictureRequest = MacPictureOrder.newRequest(
            styleRaw: CardImageStyle.current.rawValue,
            detailRaw: CardImageDetail.current.rawValue,
            redrawAll: redrawAll,
            cardCount: deck.cards.count,
            fromDevice: ThisDevice.name
        )
        try? context.save()
        Task { await SyncManager.shared.syncNow() }
    }

    /// Withdraw a pending order. Writes the result, not the request: the Mac may be settling the
    /// same order right now, and both answers name the same id.
    static func cancel(_ deck: SavedDeck, in context: ModelContext) {
        guard let request = deck.macPictureRequest, deck.hasPendingMacPictures else { return }
        deck.macPictureResult = MacPictureOrder.settle(request, outcome: .cancelled, drawn: 0, byDevice: ThisDevice.name)
        try? context.save()
        Task { await SyncManager.shared.syncNow() }
    }

    // MARK: Stories

    /// A story can be redrawn on the Mac when it has pictures: their prompts are saved with them,
    /// so the Mac redraws from those and needs no tutor.
    static func canOrder(_ story: StudyStory) -> Bool {
        story.generationComplete && !story.images.isEmpty
    }

    static func order(_ story: StudyStory, in context: ModelContext) {
        story.macPictureRequest = MacPictureOrder.newRequest(
            styleRaw: nil, detailRaw: nil, redrawAll: true,
            cardCount: story.images.count, fromDevice: ThisDevice.name
        )
        try? context.save()
        Task { await SyncManager.shared.syncNow() }
    }

    static func cancel(_ story: StudyStory, in context: ModelContext) {
        guard let request = story.macPictureRequest, story.hasPendingMacPictures else { return }
        story.macPictureResult = MacPictureOrder.settle(request, outcome: .cancelled, drawn: 0, byDevice: ThisDevice.name)
        try? context.save()
        Task { await SyncManager.shared.syncNow() }
    }
}

/// On the phone: when the Mac's answer to *this device's* order arrives, say so with a
/// notification while the app is in the background ("Your Mac drew 24 pictures for „Küche“").
/// Answers already announced are remembered per device, so a re-sync doesn't repeat them.
@MainActor
final class MacPictureHandoffWatcher {
    static let shared = MacPictureHandoffWatcher()
    private var container: ModelContainer?
    private static let announcedKey = "macPictures.announcedResults"

    func start(container: ModelContainer) {
        guard self.container == nil, !ThisDevice.isMac else { return }
        self.container = container
        SyncManager.shared.observeRemoteChanges { [weak self] kinds in
            guard kinds.contains("SavedDeck") else { return }
            self?.check()
        }
    }

    private func check() {
        guard let context = container?.mainContext else { return }
        let decks = (try? context.fetch(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.macPictureResultData != nil }))) ?? []
        var announced = Set(UserDefaults.standard.stringArray(forKey: Self.announcedKey) ?? [])
        for deck in decks {
            guard let request = deck.macPictureRequest, let result = deck.macPictureResult,
                  result.settles == request.id, request.fromDevice == ThisDevice.name,
                  result.outcome == .drawn || result.outcome == .partial, result.drawn > 0,
                  !announced.contains(request.id.uuidString)
            else { continue }
            announced.insert(request.id.uuidString)
            let topic = deck.topic
            let count = result.drawn
            Task {
                await LocalNotificationService.post(
                    id: "macPictures.drawn.\(request.id.uuidString)",
                    title: "Your Mac drew the pictures",
                    body: "\(count) new picture\(count == 1 ? "" : "s") for „\(topic)“."
                )
            }
        }
        UserDefaults.standard.set(Array(announced.suffix(200)), forKey: Self.announcedKey)
    }
}
