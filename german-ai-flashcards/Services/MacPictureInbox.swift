#if os(macOS)
import AppKit
import Foundation
import SwiftData
import Synchronization

// MAC-PICTURES: the Mac side of "Draw on my Mac" (docs/MAC_PICTURES.md).

/// Decks and stories another device asked this Mac to illustrate, and the run that draws them.
///
/// There's no server and no login item, so the inbox only looks while the app runs: at launch,
/// whenever the app comes to the front, and whenever iCloud brings deck or story changes. New
/// orders show as a banner, plus a notification when the app isn't in front. Nothing draws until
/// the learner says so ("Draw now"). A deck runs through the ordinary deck illustrator with the
/// style the phone asked for; a story is redrawn from its saved prompts (`MacStoryRedrawer`);
/// both with the best downloaded Mac model.
@Observable
@MainActor
final class MacPictureInbox {
    static let shared = MacPictureInbox()

    struct Order: Identifiable, Equatable {
        enum Kind: Equatable { case deck, story }
        let kind: Kind
        /// The deck's or the story's id.
        let targetID: UUID
        /// The deck's topic or the story's title.
        let topic: String
        let request: MacPictureOrder.Request
        /// Cards still without a picture (what a fill-in order will draw); 0 for stories.
        let missing: Int
        /// Cards in the deck, or pictures in the story.
        let cardCount: Int
        var id: UUID { request.id }
        /// What the run will draw: every card for a redraw, otherwise the missing ones.
        var pictureCount: Int { request.redrawAll ? cardCount : missing }
    }

    private(set) var orders: [Order] = []
    private(set) var isDrawing = false
    /// 1-based position of the order being drawn, for "Deck 2 of 3".
    private(set) var drawingIndex = 0
    private(set) var drawingTopic: String?
    /// Why the last "Draw now" couldn't start or stopped early, for the banner.
    private(set) var problem: String?
    /// The banner's "Later": hidden until a new order arrives.
    var isSnoozed = false

    private var container: ModelContainer?
    private weak var mlxService: MLXGenerationService?
    private var announced: Set<UUID> = []

    private init() {}

    func start(container: ModelContainer, mlxService: MLXGenerationService) {
        guard self.container == nil else { return }
        self.container = container
        self.mlxService = mlxService
        SyncManager.shared.observeRemoteChanges { [weak self] kinds in
            guard kinds.contains(SavedDeckCodec.spec.kind) || kinds.contains(StudyStoryCodec.spec.kind) else { return }
            self?.refresh()
        }
        #if DEBUG
        MacPictureInboxDebug.applyLaunchArguments(container: container)
        #endif
        // Orders that synced while the app was closed: CKSyncEngine applies them before this runs
        // or reports them as remote changes once its first fetch lands.
        Task { @MainActor in self.refresh() }
    }

    /// Re-read pending orders from the store. Cheap: one fetch each of decks and stories that
    /// have a request.
    func refresh() {
        guard let context = container?.mainContext, !isDrawing else { return }
        let decks = (try? context.fetch(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.macPictureRequestData != nil }))) ?? []
        let stories = (try? context.fetch(FetchDescriptor<StudyStory>(predicate: #Predicate { $0.macPictureRequestData != nil }))) ?? []
        let deckOrders = decks
            .filter { $0.hasPendingMacPictures && $0.macPictureRequest?.fromDevice != ThisDevice.name }
            .compactMap { deck -> Order? in
                guard let request = deck.macPictureRequest else { return nil }
                return Order(
                    kind: .deck, targetID: deck.id, topic: deck.topic, request: request,
                    missing: deck.cards.filter { $0.imageFileName == nil }.count,
                    cardCount: deck.cards.count
                )
            }
        let storyOrders = stories
            .filter { $0.hasPendingMacPictures && $0.macPictureRequest?.fromDevice != ThisDevice.name }
            .compactMap { story -> Order? in
                guard let request = story.macPictureRequest else { return nil }
                return Order(kind: .story, targetID: story.id, topic: story.title, request: request,
                             missing: 0, cardCount: story.images.count)
            }
        let fresh = (deckOrders + storyOrders).sorted { $0.request.requestedAt < $1.request.requestedAt }
        let new = fresh.filter { !announced.contains($0.id) }
        if !new.isEmpty {
            isSnoozed = false
            announced.formUnion(new.map(\.id))
            if !NSApp.isActive { notifyWaiting(fresh) }
        }
        orders = fresh
    }

    /// The model an inbox run draws with: the learner's pick if it's a Mac model, otherwise the
    /// best one downloaded. nil when no Mac model is downloaded.
    var drawingModel: ImageGenModel? {
        let current = ImageGenModel.current
        if current.engine == .mlx, current.isDownloaded { return current }
        return ImageGenModel.macModels.first(where: \.isDownloaded)
    }

    /// Rough minutes for every pending picture with `drawingModel`: deck pictures at card size,
    /// story pictures at story size.
    var estimatedMinutes: Int? {
        guard let model = drawingModel else { return nil }
        let budget = MacPictureSizing.deviceBudgetMB
        var seconds = 0
        for order in orders {
            let purpose: MacPictureSizing.Purpose = order.kind == .story ? .story : .card
            guard let size = MacPictureSizing.size(model, purpose: purpose, tier: .current, budgetMB: budget) else { return nil }
            seconds += order.pictureCount * MacPictureTiming.seconds(model, size: size)
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    /// "3 decks", "2 stories", "1 deck and 1 story".
    static func countPhrase(_ orders: [Order]) -> String {
        let decks = orders.filter { $0.kind == .deck }.count
        let stories = orders.count - decks
        let d = "\(decks) deck\(decks == 1 ? "" : "s")"
        let s = "\(stories) \(stories == 1 ? "story" : "stories")"
        return stories == 0 ? d : decks == 0 ? s : "\(d) and \(s)"
    }

    // MARK: Drawing

    /// Draw every pending order, oldest first, and answer each one.
    func drawNow() async {
        guard !isDrawing, let context = container?.mainContext, let mlxService else { return }
        problem = nil
        guard let model = drawingModel else {
            problem = "Download Z-Image Turbo or FLUX.2 klein in Settings ▸ Image generation first."
            return
        }
        guard !StoryImageService.shared.isBusy, !DeckIllustrationService.shared.isRunning else {
            problem = "Pictures are already being drawn. Try again when that's done."
            return
        }

        isDrawing = true
        ImageGenModel.runOverride.withLock { $0 = model }
        PictureSource.runOverride.withLock { $0 = .onDevice }   // an order never goes to the cloud
        UIApplication.shared.isIdleTimerDisabled = true   // holds off idle sleep on the Mac
        defer {
            ImageGenModel.runOverride.withLock { $0 = nil }
            PictureSource.runOverride.withLock { $0 = nil }
            CardImageStyle.runOverride.withLock { $0 = nil }
            CardImageDetail.runOverride.withLock { $0 = nil }
            UIApplication.shared.isIdleTimerDisabled = false
            isDrawing = false
            drawingIndex = 0
            drawingTopic = nil
        }

        let queue = orders
        var drawnTotal = 0
        for (index, order) in queue.enumerated() {
            drawingIndex = index + 1
            drawingTopic = order.topic
            if order.kind == .story {
                let (drawn, keepGoing) = await drawStory(order, in: context, mlxService: mlxService)
                drawnTotal += drawn
                if keepGoing { continue } else { break }
            }
            guard let deck = SavedDeckCodec.fetchDeck(id: order.targetID, in: context),
                  deck.macPictureRequest?.id == order.request.id, deck.hasPendingMacPictures
            else { continue }   // deleted, cancelled or re-requested meanwhile

            guard MacPictureHandoff.canOrder(deck) else {
                settle(deck, order.request, .unsupported, drawn: 0, in: context)
                continue
            }
            // The phone saw more cards than have synced here: give them a few minutes to arrive.
            if deck.cards.count < order.request.cardCount,
               Date().timeIntervalSince(order.request.requestedAt) < 600 {
                problem = "Some cards of „\(deck.topic)“ are still arriving from iCloud. Try again in a minute."
                continue
            }

            CardImageStyle.runOverride.withLock { $0 = order.request.styleRaw.flatMap(CardImageStyle.init(rawValue:)) }
            CardImageDetail.runOverride.withLock { $0 = order.request.detailRaw.flatMap(CardImageDetail.init(rawValue:)) }

            let service = DeckIllustrationService.shared
            let drawn = await service.illustrate(
                deckUUID: deck.id, in: context, mlxService: mlxService, redrawAll: order.request.redrawAll
            )
            drawnTotal += drawn
            guard !deck.isDeleted else { continue }

            if service.wasStopped {
                // A fill-in stays pending, so the next "Draw now" finishes it. A redraw would
                // start over, so it ends here with what it got.
                if order.request.redrawAll { settle(deck, order.request, .stopped, drawn: drawn, in: context) }
                break
            }
            if drawn == 0, let error = StoryImageService.shared.loadError {
                problem = error
                break   // the model didn't load; the next deck won't fare better
            }
            let stillMissing = deck.cards.filter { $0.imageFileName == nil }.count
            let outcome: MacPictureOrder.Outcome =
                drawn == 0 && stillMissing == 0 && !order.request.redrawAll ? .nothingToDraw
                : stillMissing == 0 ? .drawn
                : .partial
            settle(deck, order.request, outcome, drawn: drawn, in: context)
        }

        refresh()
        if drawnTotal > 0, !NSApp.isActive {
            await LocalNotificationService.post(
                id: "macPictures.done",
                title: "Pictures drawn",
                body: "\(drawnTotal) picture\(drawnTotal == 1 ? "" : "s") are on their way to your other devices."
            )
        }
    }

    /// One story order: redraw its pictures and answer it. Returns what was drawn and whether
    /// the run should go on to the next order.
    private func drawStory(_ order: Order, in context: ModelContext,
                           mlxService: MLXGenerationService) async -> (drawn: Int, keepGoing: Bool) {
        let id = order.targetID
        guard let story = try? context.fetch(FetchDescriptor<StudyStory>(predicate: #Predicate { $0.id == id })).first,
              story.macPictureRequest?.id == order.request.id, story.hasPendingMacPictures
        else { return (0, true) }
        guard MacPictureHandoff.canOrder(story) else {
            settle(story, order.request, .unsupported, drawn: 0, in: context)
            return (0, true)
        }
        let outcome = await MacStoryRedrawer.redraw(story, in: context, mlxService: mlxService)
        guard !story.isDeleted else { return (outcome.drawn, true) }
        if outcome.stopped {
            settle(story, order.request, .stopped, drawn: outcome.drawn, in: context)
            return (outcome.drawn, false)
        }
        if outcome.drawn == 0, let error = StoryImageService.shared.loadError {
            problem = error
            return (0, false)
        }
        settle(story, order.request, outcome.drawn == story.images.count ? .drawn : .partial,
               drawn: outcome.drawn, in: context)
        return (outcome.drawn, true)
    }

    /// Answer an order without drawing it.
    func skip(_ order: Order) {
        guard let context = container?.mainContext else { return }
        switch order.kind {
        case .deck:
            guard let deck = SavedDeckCodec.fetchDeck(id: order.targetID, in: context),
                  deck.macPictureRequest?.id == order.request.id else { return }
            settle(deck, order.request, .cancelled, drawn: 0, in: context)
        case .story:
            let id = order.targetID
            guard let story = try? context.fetch(FetchDescriptor<StudyStory>(predicate: #Predicate { $0.id == id })).first,
                  story.macPictureRequest?.id == order.request.id else { return }
            settle(story, order.request, .cancelled, drawn: 0, in: context)
        }
        refresh()
    }

    private func settle(_ deck: SavedDeck, _ request: MacPictureOrder.Request,
                        _ outcome: MacPictureOrder.Outcome, drawn: Int, in context: ModelContext) {
        deck.macPictureResult = MacPictureOrder.settle(request, outcome: outcome, drawn: drawn, byDevice: ThisDevice.name)
        try? context.save()
    }

    private func settle(_ story: StudyStory, _ request: MacPictureOrder.Request,
                        _ outcome: MacPictureOrder.Outcome, drawn: Int, in context: ModelContext) {
        story.macPictureResult = MacPictureOrder.settle(request, outcome: outcome, drawn: drawn, byDevice: ThisDevice.name)
        try? context.save()
    }

    private func notifyWaiting(_ orders: [Order]) {
        let from = orders.first?.request.fromDevice ?? "iPhone"
        let body = orders.count == 1
            ? "„\(orders[0].topic)“ from your \(from) is waiting for pictures."
            : "\(Self.countPhrase(orders)) from your \(from) are waiting for pictures."
        Task {
            await LocalNotificationService.requestAuthorizationIfNeeded()
            await LocalNotificationService.post(id: "macPictures.waiting", title: "Pictures to draw", body: body)
        }
    }
}

#if DEBUG
/// Launch arguments for trying the inbox on one Mac, no phone needed (docs/MAC_PICTURES.md):
/// - `-macPictures.debugModel zimage|klein` selects that model.
/// - `-macPictures.debugDownload 1` downloads the selected model if it's missing.
/// - `-macPictures.debugFakeOrder 1` writes an order "from iPhone" on the smallest deck that can
///   take one (a three-card "Küche" deck is made when there's none).
/// - `-macPictures.debugFakeOrderDelay 20` does it 20 s after launch (switch apps to see the
///   notification).
/// - `-macPictures.debugFakeStoryOrder 1` does the same for a two-picture test story.
/// - `-macPictures.debugDrawNow 1` then draws it and prints `[macPictures.verify]` lines.
/// - `-macPictures.debugCleanUp 1` deletes the test deck and story (and their pictures).
/// Sync is off in Debug by default, so nothing here reaches iCloud.
enum MacPictureInboxDebug {
    static func applyLaunchArguments(container: ModelContainer) {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "macPictures.debugModel") {
        case "zimage": ImageGenModel.current = .zImageTurbo
        case "klein": ImageGenModel.current = .flux2Klein
        default: break
        }
        let delay = defaults.double(forKey: "macPictures.debugFakeOrderDelay")
        let fake = defaults.bool(forKey: "macPictures.debugFakeOrder") || delay > 0
        let fakeStory = defaults.bool(forKey: "macPictures.debugFakeStoryOrder")
        let download = defaults.bool(forKey: "macPictures.debugDownload")
        let draw = defaults.bool(forKey: "macPictures.debugDrawNow")
        if defaults.bool(forKey: "macPictures.debugCleanUp") {
            cleanUp(container.mainContext)
            return
        }
        guard fake || fakeStory || download || draw else { return }
        Task { @MainActor in
            say("model \(ImageGenModel.current.rawValue), budget \(MacPictureSizing.deviceBudgetMB) MB, downloaded \(ImageGenModel.current.isDownloaded)")
            if download, !ImageGenModel.current.isDownloaded {
                let started = Date()
                let ok = await StoryImageService.shared.downloadModel()
                say("download \(ok ? "ok" : "FAILED") in \(Int(Date().timeIntervalSince(started))) s")
            }
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            if fake { placeFakeOrder(in: container.mainContext) }
            if fakeStory { placeFakeStoryOrder(in: container.mainContext) }
            MacPictureInbox.shared.refresh()
            say("pending orders: \(MacPictureInbox.shared.orders.count)")
            guard draw else { return }
            let started = Date()
            await MacPictureInbox.shared.drawNow()
            let context = container.mainContext
            let decks = (try? context.fetch(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.macPictureResultData != nil }))) ?? []
            for deck in decks {
                guard let result = deck.macPictureResult else { continue }
                let files = deck.cards.compactMap(\.imageFileName)
                    .filter { FileManager.default.fileExists(atPath: CardImageStore.url(fileName: $0, deckID: deck.id).path) }
                say("deck „\(deck.topic)“: \(result.outcome.rawValue), drew \(result.drawn), \(files.count)/\(deck.cards.count) cards have a picture file, pending \(deck.hasPendingMacPictures)")
            }
            let stories = (try? context.fetch(FetchDescriptor<StudyStory>(predicate: #Predicate { $0.macPictureResultData != nil }))) ?? []
            for story in stories {
                guard let result = story.macPictureResult else { continue }
                let files = story.images.filter {
                    FileManager.default.fileExists(atPath: StoryImageStore.url(fileName: $0.fileName, storyID: story.id).path)
                }
                say("story „\(story.title)“: \(result.outcome.rawValue), drew \(result.drawn), \(files.count)/\(story.images.count) pictures on disk (\(story.images.map(\.fileName).joined(separator: ", "))), pending \(story.hasPendingMacPictures)")
            }
            say("problem: \(MacPictureInbox.shared.problem ?? "none"); \(Int(Date().timeIntervalSince(started))) s")
        }
    }

    /// Always its own three-card deck, never one of the learner's: a Debug build shares the store
    /// with the learner's other Debug runs, and an order on a real deck could redraw its pictures.
    private static func placeFakeOrder(in context: ModelContext) {
        let topic = "Küche · Mac-Bilder test"
        let deck = ((try? context.fetch(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.topic == topic }))) ?? []).first
            ?? {
                let words = [("der Apfel", "the apple"), ("das Messer", "the knife"), ("die Tasse", "the cup")]
                let cards = words.map { VocabCard(germanWord: $0.0, englishTranslation: $0.1, wordType: "noun") }
                let made = SavedDeck(topic: topic, wordCount: cards.count, includeExamples: false, vocabCards: cards)
                context.insert(made)
                return made
            }()
        deck.macPictureRequest = MacPictureOrder.newRequest(
            styleRaw: CardImageStyle.current.rawValue, detailRaw: CardImageDetail.current.rawValue,
            redrawAll: deck.cards.allSatisfy { $0.imageFileName != nil },
            cardCount: deck.cards.count, fromDevice: "iPhone"
        )
        try? context.save()
        say("fake order on „\(deck.topic)“ (\(deck.cards.count) cards)")
    }

    /// Its own story with two picture records whose files don't exist yet: the redraw draws them
    /// from the saved prompts, so the learner's stories are never touched.
    private static func placeFakeStoryOrder(in context: ModelContext) {
        let title = "Die Taube · Mac-Bilder test"
        let story = ((try? context.fetch(FetchDescriptor<StudyStory>(predicate: #Predicate { $0.title == title }))) ?? []).first
            ?? {
                let made = StudyStory(topic: title, level: .a2, genre: .fabel)
                made.storyText = "Eine Taube sitzt auf einer Bank im Park. Am Abend fliegt sie über die Dächer der Altstadt."
                made.generationComplete = true
                let pigeon = "plump gray pigeon with a white belly and a coral-orange beak"
                made.setImages([
                    StoryImageRecord(fileName: "00.png", prompt: "\(pigeon) sits on a park bench next to an old man feeding it breadcrumbs, children's picture-book illustration of animals, gentle watercolor", paragraphAnchorIndex: nil),
                    StoryImageRecord(fileName: "01.png", prompt: "\(pigeon) flies over the red rooftops of an old German town at sunset, children's picture-book illustration of animals, gentle watercolor", paragraphAnchorIndex: 0),
                ])
                context.insert(made)
                return made
            }()
        story.macPictureRequest = MacPictureOrder.newRequest(
            styleRaw: nil, detailRaw: nil, redrawAll: true, cardCount: story.images.count, fromDevice: "iPhone"
        )
        try? context.save()
        say("fake story order on „\(story.title)“ (\(story.images.count) pictures)")
    }

    private static func cleanUp(_ context: ModelContext) {
        let deckTopic = "Küche · Mac-Bilder test"
        let storyTitle = "Die Taube · Mac-Bilder test"
        for deck in (try? context.fetch(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.topic == deckTopic }))) ?? [] {
            for card in deck.cards {
                if let name = card.imageFileName { CardImageStore.delete(fileName: name, deckID: deck.id) }
            }
            context.delete(deck)
        }
        for story in (try? context.fetch(FetchDescriptor<StudyStory>(predicate: #Predicate { $0.title == storyTitle }))) ?? [] {
            StoryImageStore.deleteImages(for: story.id)
            context.delete(story)
        }
        try? context.save()
        MacPictureInbox.shared.refresh()
        say("cleaned up the test deck and story; pending orders: \(MacPictureInbox.shared.orders.count)")
    }

    private static func say(_ line: String) {
        print("[macPictures.verify] \(line)")
        fflush(stdout)   // stdout to a file is block-buffered; the verify lines are read live
    }
}
#endif
#endif
