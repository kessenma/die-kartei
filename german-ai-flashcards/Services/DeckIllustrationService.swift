import Foundation
import SwiftData
import BackgroundTasks
import UIKit

/// Draws a picture for every card in a deck that doesn't have one yet.
///
/// A singleton, like `StoryImageService`, because two screens observe the same run: the deck being
/// studied (pictures appear as they land) and the deck's setup panel (progress + Stop). Only one
/// deck illustrates at a time — the diffusion pipeline is a single shared resource, and a cloud
/// run already draws several at once (`PictureSession.cloudParallelism`).
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
    /// What the last run left undone: pictures skipped, and why it stopped if it stopped on its
    /// own (a cloud key that stopped working, an empty OpenRouter account, a source that couldn't
    /// start). A deck run also files it in `PictureRunReports` under the deck; a draft run has no
    /// deck yet, so the create flow carries it over when the deck is saved.
    private(set) var lastReport: PictureRunReport?
    private var stopError: OpenRouterError?
    private var stopMessage: String?
    private var skippedCount = 0

    /// Fraction of the way through the whole run, blending finished pictures with the progress
    /// of the ones in flight, so the background task's progress bar moves smoothly.
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        let inFlight = laneFractions.values.reduce(0, +)
        return min(1, (Double(completedCount) + inFlight) / Double(totalCount))
    }

    /// Progress of each picture being drawn right now: one lane on-device, several in the cloud
    /// (`PictureSession.parallelism`).
    private var laneFractions: [UUID: Double] = [:]
    private var stopRequested = false

    private init() {}

    /// Ask the run to stop. The pictures in flight are abandoned (at the next diffusion step, or
    /// by cancelling the cloud request); every picture already saved stays saved.
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

        beginRun(id: deckUUID, total: pending.count)
        defer { endRun() }

        // On-device, the session unloads the ~5 GB language model first: it and the diffusion
        // pipeline don't fit together on 6 GB devices, and the learner may well have just
        // generated this deck. A cloud session leaves it loaded.
        guard let session = await StoryImageService.shared.beginSession(unloading: mlxService) else {
            noteSessionFailure()
            fileReport(drawn: 0, total: pending.count, for: deckUUID)
            return 0
        }
        defer { session.end() }

        let jobs = pending.enumerated().map { index, card in
            let fileName = CardImageStore.newFileName(for: card.id)
            return CardJob(
                index: index, english: card.englishTranslation, wordType: card.wordType,
                fileName: fileName, destination: CardImageStore.url(fileName: fileName, deckID: deckUUID)
            )
        }
        var drawn = 0
        await draw(jobs, session: session, isGone: { job in
            // The learner can delete the deck from the Library while this runs, and SwiftData
            // deletes land on this same actor between awaits.
            deck.isDeleted || pending[job.index].isDeleted
        }, onDrawn: { job in
            let card = pending[job.index]
            let previousFileName = card.imageFileName
            card.imageFileName = job.fileName
            // Only now is the replacement safe to drop: a card is never left pointing at a
            // file that isn't there.
            if let previousFileName, previousFileName != job.fileName {
                CardImageStore.delete(fileName: previousFileName, deckID: deckUUID)
            }
            try? modelContext.save()   // per picture, so partial results survive a kill
            drawn += 1
        })
        fileReport(drawn: drawn, total: pending.count, for: deckUUID)
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
    /// Same rules as `illustrate`: one run at a time, and on-device the LLM is unloaded first.
    func illustrateDraft(
        cards: [VocabCard],
        draftID: UUID,
        mlxService: MLXGenerationService
    ) async -> [String: String] {
        guard !isRunning, !cards.isEmpty else { return [:] }

        beginRun(id: draftID, total: cards.count)
        defer { endRun() }

        guard let session = await StoryImageService.shared.beginSession(unloading: mlxService) else {
            noteSessionFailure()
            fileReport(drawn: 0, total: cards.count, for: nil)
            return [:]
        }
        defer { session.end() }

        let jobs = cards.enumerated().map { index, card in
            let fileName = CardImageStore.draftFileName(index: index)
            return CardJob(
                index: index, english: card.englishTranslation, wordType: card.wordType,
                fileName: fileName, destination: CardImageStore.url(fileName: fileName, deckID: draftID)
            )
        }
        var drawn: [String: String] = [:]
        await draw(jobs, session: session, isGone: { _ in false }, onDrawn: { job in
            drawn[cards[job.index].germanWord.lowercased()] = job.fileName
        })
        fileReport(drawn: drawn.count, total: cards.count, for: nil)
        return drawn
    }

    // MARK: - Shared loop

    /// One card's picture, as plain values: what a drawing lane needs and nothing tied to SwiftData.
    private struct CardJob {
        let index: Int
        let english: String
        let wordType: String?
        let fileName: String
        let destination: URL
    }

    private enum Outcome {
        case drawn
        /// This card failed (a refused prompt, a provider hiccup); the next one is worth trying.
        case skipped
        /// Nothing more will work this run: the learner stopped, the on-device model vanished, or
        /// a cloud failure that every remaining card would hit too (error set).
        case stop(OpenRouterError?)
    }

    private func beginRun(id: UUID, total: Int) {
        isRunning = true
        stopRequested = false
        wasStopped = false
        lastReport = nil
        stopError = nil
        stopMessage = nil
        skippedCount = 0
        illustratingDeckUUID = id
        completedCount = 0
        laneFractions = [:]
        totalCount = total
    }

    /// The source couldn't start: no key, or the on-device model is missing or won't load.
    private func noteSessionFailure() {
        stopMessage = StoryImageService.shared.loadError ?? "Pictures couldn't start."
        if PictureSource.current == .cloud, !OpenRouterAccount.hasKey {
            stopError = .notConnected
            stopMessage = OpenRouterError.notConnected.reportReason
        }
    }

    /// Sum the run up in `lastReport`, and file it under the deck when there is one. A run that
    /// went fine clears whatever an earlier run left on that deck.
    private func fileReport(drawn: Int, total: Int, for deckUUID: UUID?) {
        let report = PictureRunReport(
            drawn: drawn, total: total, skipped: skippedCount,
            stopReason: stopMessage, fix: stopError?.reportFix
        )
        lastReport = report
        if let deckUUID { PictureRunReports.shared.record(report, for: deckUUID) }
    }

    private func endRun() {
        isRunning = false
        illustratingDeckUUID = nil
        completedCount = 0
        totalCount = 0
        laneFractions = [:]
    }

    /// Draw `jobs` in order, `session.parallelism` at a time. The style and detail are read as
    /// each picture starts, so changing them mid-run applies from the next picture on — the same
    /// contract `ImageGenQuality` has. `onDrawn` runs on the main actor as each one lands.
    private func draw(
        _ jobs: [CardJob],
        session: PictureSession,
        isGone: (CardJob) -> Bool,
        onDrawn: (CardJob) -> Void
    ) async {
        await withTaskGroup(of: (CardJob, Outcome).self) { group in
            var next = 0
            var inFlight = 0
            while true {
                while inFlight < session.parallelism, next < jobs.count, !stopRequested {
                    let job = jobs[next]
                    next += 1
                    if isGone(job) { stopRequested = true; break }
                    let request = CardIllustrationPrompts.request(englishTranslation: job.english, wordType: job.wordType)
                    let lane = UUID()
                    laneFractions[lane] = 0
                    inFlight += 1
                    group.addTask { @MainActor [weak self] in
                        defer { self?.laneFractions[lane] = nil }
                        do {
                            let written = try await session.draw(
                                request, saveTo: job.destination,
                                onProgress: { fraction in self?.laneFractions[lane] = fraction }
                            )
                            return (job, written ? .drawn : .stop(nil))
                        } catch let error as OpenRouterError where error.stopsRun {
                            return (job, .stop(error))
                        } catch {
                            return (job, .skipped)
                        }
                    }
                }
                guard inFlight > 0, let (job, outcome) = await group.next() else { break }
                inFlight -= 1
                completedCount += 1
                switch outcome {
                case .drawn:
                    // The picture awaited; the deck may be gone now. Don't write to a tombstone.
                    if isGone(job) { stopRequested = true } else { onDrawn(job) }
                case .skipped:
                    skippedCount += 1
                case .stop(let error):
                    if let error, stopError == nil {
                        stopError = error
                        stopMessage = error.reportReason
                    }
                    if !stopRequested {
                        stopRequested = true
                        StoryImageService.shared.requestStop()
                    }
                }
            }
        }
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

            if let report = service.lastReport, let reason = report.stopReason, report.fix != nil {
                // Credit, key or the Muse confirmation: something only the learner can fix, and
                // they may well be in another app by now.
                await DeckNotificationService.notifyStopped(topic: topic, drawn: report.drawn, total: report.total, reason: reason)
            } else if drawn > 0 {
                await DeckNotificationService.notifyReady(topic: topic, count: drawn)
            }
            task?.progress.completedUnitCount = 100
            task?.setTaskCompleted(success: drawn > 0)
            onFinish?()
        }

        if !StoryBackgroundGenerator.shared.submit(
            .deckIllustration,
            title: redrawAll ? "Redrawing your cards" : "Illustrating your cards",
            subtitle: topic,
            // Cloud pictures are web requests: asking for the GPU would only give the system a
            // reason to refuse the background task.
            requiresGPU: PictureSource.current == .onDevice,
            job: job
        ) {
            Task { @MainActor in await job(nil) }
        }
    }
}
