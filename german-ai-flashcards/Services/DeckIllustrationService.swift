import Foundation
import SwiftData
import BackgroundTasks
import UIKit

/// Draws a picture for every card in a deck that doesn't have one yet.
///
/// A singleton, like `StoryImageService`, because two screens observe the same run: the deck being
/// studied (pictures appear as they land) and the deck's setup panel (progress + Stop). Only one
/// deck illustrates at a time — the diffusion pipeline is a single shared resource.
///
/// **Skip-existing semantics.** By default every pass illustrates only the cards where
/// `imageFileName == nil`, so stopping halfway and re-running finishes the remainder instead of
/// redrawing what's there. That's what makes both entry points — the create-time toggle and the
/// illustrate-later button — the same operation. `redrawAll` is the deliberate exception: it
/// redraws every card in the learner's current `CardImageStyle`, which is the only way a style
/// change reaches pictures that already exist.
///
/// Unlike story illustrations, no language model is involved: card prompts come straight from the
/// English gloss (`CardIllustrationPrompts`), so this never has to wait on the LLM.
@Observable
@MainActor
final class DeckIllustrationService {
    static let shared = DeckIllustrationService()

    private(set) var isRunning = false
    /// The deck currently being illustrated, so a view can tell "my deck is running" from
    /// "some other deck is running".
    private(set) var illustratingDeckUUID: UUID?
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    /// Whether the run that just ended was ended by the learner rather than by finishing. The
    /// create-time flow checks this so a stopped run isn't immediately started again for the
    /// cards it didn't get to.
    private(set) var wasStopped = false

    /// Fraction of the way through the whole run, blending finished pictures with the diffusion
    /// steps of the one in flight, so the background task's progress bar moves smoothly.
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, (Double(completedCount) + stepFraction) / Double(totalCount))
    }

    private var stepFraction: Double = 0
    private var stopRequested = false

    private init() {}

    /// Ask the run to stop. The current picture is abandoned at its next diffusion step; every
    /// picture already saved stays saved.
    func stop() {
        stopRequested = true
        wasStopped = true
        StoryImageService.shared.requestStop()
    }

    // MARK: - The run

    /// Illustrate the deck's un-illustrated cards, in card order. Returns how many pictures were
    /// actually drawn. Never throws and never invalidates the deck: a deck whose illustration run
    /// failed is just a deck without pictures.
    ///
    /// Pass `redrawAll` to include cards that already have a picture — how a new
    /// `CardImageStyle` reaches an illustrated deck.
    @discardableResult
    func illustrate(
        deckUUID: UUID,
        in modelContext: ModelContext,
        mlxService: MLXGenerationService,
        redrawAll: Bool = false
    ) async -> Int {
        guard !isRunning else { return 0 }

        let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckUUID })
        guard let deck = try? modelContext.fetch(descriptor).first else { return 0 }
        let pending = deck.cards
            .filter { redrawAll || $0.imageFileName == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !pending.isEmpty else { return 0 }

        isRunning = true
        stopRequested = false
        wasStopped = false
        illustratingDeckUUID = deckUUID
        completedCount = 0
        stepFraction = 0
        totalCount = pending.count
        defer {
            isRunning = false
            illustratingDeckUUID = nil
            completedCount = 0
            totalCount = 0
            stepFraction = 0
        }

        // The ~5 GB language model and the diffusion pipeline don't fit together on 6 GB devices,
        // and the learner may well have just generated this deck. Freeing it first is the same
        // trade the story illustrator makes; the LLM reloads lazily next time it's needed.
        mlxService.unloadModel()

        let imageService = StoryImageService.shared
        guard await imageService.loadPipeline() else { return 0 }
        defer { imageService.unloadPipeline() }

        var drawn = 0
        for card in pending {
            // Re-checked every iteration: the learner can delete the deck from the Library while
            // this runs, and SwiftData deletes land on this same actor between awaits.
            guard !stopRequested, !deck.isDeleted, !card.isDeleted else { break }
            stepFraction = 0
            defer { completedCount += 1; stepFraction = 0 }

            // Read per card, so changing the style mid-run applies from the next picture on —
            // the same contract `ImageGenQuality` has.
            let style = CardImageStyle.current
            let detail = CardImageDetail.current
            let prompt = CardIllustrationPrompts.positivePrompt(
                englishTranslation: card.englishTranslation, wordType: card.wordType,
                style: style, detail: detail
            )
            let previousFileName = card.imageFileName
            let fileName = CardImageStore.newFileName(for: card.id)
            do {
                let written = try await imageService.generateImage(
                    prompt: prompt,
                    negativePrompt: CardIllustrationPrompts.negativePrompt(style: style, detail: detail),
                    saveTo: CardImageStore.url(fileName: fileName, deckID: deckUUID),
                    onStepProgress: { [weak self] fraction in self?.stepFraction = fraction }
                )
                // false = stopped, or the model files were deleted out from under us. Neither
                // gets better on the next card.
                guard written else { break }
                // The generation awaited; the deck may be gone now. Don't write to a tombstone.
                guard !deck.isDeleted, !card.isDeleted else { break }

                card.imageFileName = fileName
                // Only now is the replacement safe to drop: a card is never left pointing at a
                // file that isn't there.
                if let previousFileName, previousFileName != fileName {
                    CardImageStore.delete(fileName: previousFileName, deckID: deckUUID)
                }
                try? modelContext.save()   // per picture, so partial results survive a kill
                drawn += 1
            } catch {
                continue   // per-picture failure — try the next card
            }
        }
        return drawn
    }

    // MARK: - Draft run (pictures before the deck exists)

    /// Draw pictures for cards that have no deck yet — what `CardImageTiming.everyCard` does while
    /// the generation overlay is still up, before the learner has decided which cards to keep.
    ///
    /// Returns the draft file name for each card that got one, keyed by the card's German word
    /// lowercased. That key is safe because the generator dedupes on exactly it, so no two cards in
    /// a run share one. The caller adopts the names it keeps into the deck it saves
    /// (`CardImageStore.adopt`) and discards the rest.
    ///
    /// Same single-pipeline rule as `illustrate`: one run at a time, LLM unloaded first.
    func illustrateDraft(
        cards: [VocabCard],
        draftID: UUID,
        mlxService: MLXGenerationService
    ) async -> [String: String] {
        guard !isRunning, !cards.isEmpty else { return [:] }

        isRunning = true
        stopRequested = false
        wasStopped = false
        illustratingDeckUUID = draftID
        completedCount = 0
        stepFraction = 0
        totalCount = cards.count
        defer {
            isRunning = false
            illustratingDeckUUID = nil
            completedCount = 0
            totalCount = 0
            stepFraction = 0
        }

        mlxService.unloadModel()

        let imageService = StoryImageService.shared
        guard await imageService.loadPipeline() else { return [:] }
        defer { imageService.unloadPipeline() }

        var drawn: [String: String] = [:]
        for (index, card) in cards.enumerated() {
            guard !stopRequested else { break }
            stepFraction = 0
            defer { completedCount += 1; stepFraction = 0 }

            let style = CardImageStyle.current
            let detail = CardImageDetail.current
            let fileName = CardImageStore.draftFileName(index: index)
            do {
                let written = try await imageService.generateImage(
                    prompt: CardIllustrationPrompts.positivePrompt(
                        englishTranslation: card.englishTranslation, wordType: card.wordType,
                        style: style, detail: detail
                    ),
                    negativePrompt: CardIllustrationPrompts.negativePrompt(style: style, detail: detail),
                    saveTo: CardImageStore.url(fileName: fileName, deckID: draftID),
                    onStepProgress: { [weak self] fraction in self?.stepFraction = fraction }
                )
                // false = stopped, or the model files were deleted out from under us. Neither
                // gets better on the next card.
                guard written else { break }
                drawn[card.germanWord.lowercased()] = fileName
            } catch {
                continue   // per-picture failure — try the next card
            }
        }
        return drawn
    }

    // MARK: - Background launch

    /// Run `illustrate` as a continued-processing task so pictures keep arriving while the learner
    /// studies the deck (or leaves the app), falling back to an inline run when the system won't
    /// take the request. Mirrors the story generator's job in `StorySetupView`.
    ///
    /// `onFinish` fires when the run ends, however it ended. The create-time flow uses it to open
    /// the deck once its pictures are done; callers that just want pictures in the background
    /// leave it nil.
    static func launch(
        deckUUID: UUID,
        topic: String,
        modelContext: ModelContext,
        mlxService: MLXGenerationService,
        redrawAll: Bool = false,
        onFinish: (@MainActor () -> Void)? = nil
    ) {
        let service = shared
        let job: StoryBackgroundGenerator.Job = { task in
            await LocalNotificationService.requestAuthorizationIfNeeded()
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }

            // Continued tasks must report progress or the system may treat them as stalled.
            task?.progress.totalUnitCount = 100
            task?.expirationHandler = { Task { @MainActor in service.stop() } }
            let progressPump = Task { @MainActor in
                while !Task.isCancelled {
                    task?.progress.completedUnitCount = Int64((service.progress * 100).rounded())
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }

            let drawn = await service.illustrate(
                deckUUID: deckUUID, in: modelContext, mlxService: mlxService, redrawAll: redrawAll
            )
            progressPump.cancel()

            if drawn > 0 {
                await DeckNotificationService.notifyReady(topic: topic, count: drawn)
            }
            task?.progress.completedUnitCount = 100
            task?.setTaskCompleted(success: drawn > 0)
            onFinish?()
        }

        if !StoryBackgroundGenerator.shared.submit(
            .deckIllustration,
            title: redrawAll ? "Redrawing your cards" : "Illustrating your cards",
            subtitle: topic, job: job
        ) {
            Task { @MainActor in await job(nil) }
        }
    }
}
