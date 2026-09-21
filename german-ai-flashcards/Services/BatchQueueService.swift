//
//  BatchQueueService.swift
//  german-ai-flashcards
//
//  Runs the batch queue: takes `BatchJob`s in order and executes them one at a time —
//  generating decks, writing stories, and drawing card pictures — reusing the same services
//  the one-off screens use. A singleton because the queue screen, the Home hub row, and the
//  nav bar all observe the same run.
//
//  Model juggling: text jobs need the language model, picture jobs the diffusion pipeline,
//  and the two don't fit in memory together on 6 GB devices. Stories illustrate inline
//  (their scene prompts need the LLM anyway), but a generated deck's pictures are split off
//  into a follow-up `deckPictures` job appended to the END of the queue — so back-to-back
//  deck jobs keep the LLM loaded instead of swapping 5 GB per deck.
//

import Foundation
import SwiftData
import BackgroundTasks
import UIKit

@Observable
@MainActor
final class BatchQueueService {
    static let shared = BatchQueueService()
    private init() {}

    enum RunState: Equatable {
        case idle
        case running
        /// Finishing the current job, then holding the rest of the queue.
        case pausing
        /// Abandoning the current job now; it goes back to queued.
        case stopping
    }

    private(set) var runState: RunState = .idle
    var isRunning: Bool { runState != .idle }

    private(set) var currentJobID: UUID?
    private(set) var statusText = ""
    private(set) var jobsFinishedThisRun = 0
    private(set) var jobsTotalThisRun = 0

    /// Live per-job services, held only while their job runs, so the queue screen can show
    /// real progress instead of a spinner.
    private var cardCoordinator: GenerationCoordinator?
    private var storyService: StoryStudyService?

    /// 0–1 through the current job.
    var currentJobFraction: Double {
        if let story = storyService, story.isRunning { return story.progress }
        if let cards = cardCoordinator, cards.isGenerating { return cards.generationProgress }
        let illustration = DeckIllustrationService.shared
        if illustration.isRunning { return illustration.progress }
        return 0
    }

    /// 0–1 through the whole run, blending finished jobs with the one in flight.
    var progress: Double {
        guard jobsTotalThisRun > 0 else { return 0 }
        return min(1, (Double(jobsFinishedThisRun) + currentJobFraction) / Double(jobsTotalThisRun))
    }

    /// A finer-grained live line under `statusText` (streamed tokens, picture counts).
    var currentDetail: String? {
        if let story = storyService, story.isRunning {
            return story.statusText.isEmpty ? nil : story.statusText
        }
        if let cards = cardCoordinator, cards.isGenerating, cards.cardsRequested > 0 {
            return "\(cards.cardsGenerated) of \(cards.cardsRequested) cards so far"
        }
        let illustration = DeckIllustrationService.shared
        if illustration.isRunning, illustration.totalCount > 0 {
            return "Picture \(min(illustration.completedCount + 1, illustration.totalCount)) of \(illustration.totalCount)"
        }
        return nil
    }

    // MARK: - Controls

    /// Finish the job that's running, then hold the queue. The remaining jobs stay queued
    /// for the next run.
    func requestPause() {
        guard runState == .running else { return }
        runState = .pausing
    }

    /// Abandon the current job now. Its partial output is discarded (flashcards, stories) or
    /// kept where resumable (deck pictures), and the job returns to the queue.
    func stop() {
        guard isRunning else { return }
        runState = .stopping
        cardCoordinator?.stopGeneration()
        storyService?.stop()
        DeckIllustrationService.shared.stop()
    }

    /// Any job left in `running` from a killed app would block its rerun forever — sweep such
    /// orphans back to queued. Called when the queue screen appears while no run is active.
    func sweepOrphanedJobs(in modelContext: ModelContext) {
        guard !isRunning else { return }
        let runningRaw = BatchJob.Status.running.rawValue
        let descriptor = FetchDescriptor<BatchJob>(predicate: #Predicate { $0.statusRaw == runningRaw })
        guard let orphans = try? modelContext.fetch(descriptor), !orphans.isEmpty else { return }
        for job in orphans { job.status = .queued }
        try? modelContext.save()
    }

    // MARK: - Start

    /// Kick off the queue, preferring an iOS continued-processing task (so it keeps running
    /// with a system progress bar if the learner leaves the app), falling back to an inline
    /// run when the system won't take it. Mirrors the story generator's launch pattern.
    func start(
        modelContext: ModelContext,
        mlxService: MLXGenerationService,
        modelManager: MLXModelManager
    ) {
        guard runState == .idle else { return }
        sweepOrphanedJobs(in: modelContext)
        let queuedNow = queuedCount(in: modelContext)
        guard queuedNow > 0 else { return }
        runState = .running
        statusText = "Starting…"

        let job: StoryBackgroundGenerator.Job = { task in
            await LocalNotificationService.requestAuthorizationIfNeeded()
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }

            // Continued tasks must report progress or the system may treat them as stalled.
            task?.progress.totalUnitCount = 100
            task?.expirationHandler = { Task { @MainActor in BatchQueueService.shared.stop() } }
            let progressPump = Task { @MainActor in
                while !Task.isCancelled {
                    task?.progress.completedUnitCount = Int64((BatchQueueService.shared.progress * 100).rounded())
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }

            let outcome = await BatchQueueService.shared.runQueue(
                modelContext: modelContext, mlxService: mlxService, modelManager: modelManager
            )
            progressPump.cancel()

            task?.progress.completedUnitCount = 100
            task?.setTaskCompleted(success: outcome.failed == 0)
        }

        let jobs = queuedNow == 1 ? "1 job" : "\(queuedNow) jobs"
        if !StoryBackgroundGenerator.shared.submit(
            .batch, title: "Running your batch queue", subtitle: jobs, job: job
        ) {
            Task { @MainActor in await job(nil) }
        }
    }

    // MARK: - The run loop

    private func runQueue(
        modelContext: ModelContext,
        mlxService: MLXGenerationService,
        modelManager: MLXModelManager
    ) async -> (done: Int, failed: Int) {
        var done = 0
        var failed = 0
        jobsFinishedThisRun = 0
        jobsTotalThisRun = queuedCount(in: modelContext)

        defer {
            runState = .idle
            currentJobID = nil
            statusText = ""
            cardCoordinator = nil
            storyService = nil
        }

        while runState == .running {
            guard let job = nextQueuedJob(in: modelContext) else { break }
            // Deck-picture jobs get appended mid-run, so the total is re-derived each pass
            // (the current job still counts as queued here).
            jobsTotalThisRun = jobsFinishedThisRun + queuedCount(in: modelContext)

            currentJobID = job.id
            job.status = .running
            job.errorMessage = nil
            try? modelContext.save()

            switch job.kind {
            case .flashcards:
                await runFlashcards(job, modelContext: modelContext, mlxService: mlxService, modelManager: modelManager)
            case .story:
                await runStory(job, modelContext: modelContext, mlxService: mlxService)
            case .deckPictures:
                await runDeckPictures(job, modelContext: modelContext, mlxService: mlxService)
            }

            switch job.status {
            case .done:
                done += 1
                jobsFinishedThisRun += 1
            case .failed:
                failed += 1
                jobsFinishedThisRun += 1
            default:
                break // stopped — the job went back to queued
            }
            currentJobID = nil
        }

        if done + failed > 0 {
            await BatchNotificationService.notifyFinished(done: done, failed: failed)
        }
        return (done, failed)
    }

    // MARK: - Job runners

    private func runFlashcards(
        _ job: BatchJob,
        modelContext: ModelContext,
        mlxService: MLXGenerationService,
        modelManager: MLXModelManager
    ) async {
        statusText = "Generating \(job.wordCount) cards: \(job.topic)"

        // A private coordinator (sharing the one loaded-model service) keeps the Create
        // screen's UI state out of the queue run and vice versa.
        let coordinator = GenerationCoordinator(modelManager: modelManager, mlxService: mlxService)
        cardCoordinator = coordinator
        defer { cardCoordinator = nil }

        await coordinator.generateVocab(
            topic: job.topic,
            count: job.wordCount,
            includeExamples: job.includeExamples,
            includeGender: job.includeGender,
            wordTypeFilter: job.wordTypeFilter,
            includeConjugations: job.includeConjugations,
            selectedTenses: job.selectedTenses,
            model: MLXModel(rawValue: job.generatorRaw)
        )

        if runState == .stopping {
            job.status = .queued
            try? modelContext.save()
            return
        }
        let cards = coordinator.generatedCards
        guard !cards.isEmpty else {
            fail(job, coordinator.errorMessage ?? "The model produced no usable cards.", in: modelContext)
            return
        }

        // Unlike the interactive flow there's no "keep which cards?" step — every generated
        // card is saved. The deck can be pruned in the Library later.
        let deck = SavedDeck(
            topic: job.topic,
            wordCount: job.wordCount,
            includeExamples: job.includeExamples,
            includeGender: job.includeGender,
            wordTypeFilter: job.wordTypeFilter,
            includeConjugations: job.includeConjugations,
            selectedTenses: job.selectedTenses,
            vocabCards: cards
        )
        deck.generatorRaw = coordinator.lastGeneratorRaw
        deck.generationTimeSeconds = coordinator.lastGenerationTimeSeconds
        modelContext.insert(deck)
        job.resultDeckID = deck.id
        complete(job, in: modelContext)

        // Pictures are split into a follow-up job at the back of the queue (see header note).
        if job.withImages, ImageGenModel.current.isDownloaded {
            let pictures = BatchJob.deckPictures(
                deckID: deck.id, topic: deck.topic, sortOrder: nextSortOrder(in: modelContext)
            )
            modelContext.insert(pictures)
            try? modelContext.save()
        }
    }

    private func runStory(
        _ job: BatchJob,
        modelContext: ModelContext,
        mlxService: MLXGenerationService
    ) async {
        // Nobody is watching this run, so it takes a tutor that's already downloaded rather than
        // starting a multi-gigabyte download in the background.
        guard let model = StoryStudyService.unattendedModel else {
            fail(job, "Stories need one of the German Tutor models downloaded first.", in: modelContext)
            return
        }

        statusText = "Writing a story: \(job.topic)"
        let story = StudyStory(topic: job.topic, level: job.storyLevel, genre: job.storyGenre)
        modelContext.insert(story)
        try? modelContext.save()

        let service = StoryStudyService(mlxService: mlxService, modelContext: modelContext, model: model)
        storyService = service
        defer { storyService = nil }

        let imageCount = (job.withImages && ImageGenModel.current.isDownloaded) ? job.storyImageCount : 0
        await service.generate(
            for: story,
            questionCount: job.storyQuestionCount,
            kinds: job.storyQuestionKinds,
            imageCount: imageCount,
            weaveWords: job.weaveWords
        )

        switch service.phase {
        case .done:
            job.resultStoryID = story.id
            complete(job, in: modelContext)
        case .failed(let message):
            StoryImageStore.deleteImages(for: story.id)
            modelContext.delete(story)
            fail(job, message, in: modelContext)
        default:
            // Stopped mid-write. Don't keep a half-written story; the job reruns next time.
            StoryImageStore.deleteImages(for: story.id)
            modelContext.delete(story)
            job.status = .queued
            try? modelContext.save()
        }
    }

    private func runDeckPictures(
        _ job: BatchJob,
        modelContext: ModelContext,
        mlxService: MLXGenerationService
    ) async {
        guard ImageGenModel.current.isDownloaded else {
            fail(job, "The picture model isn't downloaded. You can get it in Settings.", in: modelContext)
            return
        }
        guard let deckID = job.targetDeckID else {
            fail(job, "This job lost track of its deck.", in: modelContext)
            return
        }
        let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckID })
        guard let deck = try? modelContext.fetch(descriptor).first else {
            fail(job, "That deck has been deleted.", in: modelContext)
            return
        }

        let missing = deck.cards.filter { $0.imageFileName == nil }.count
        guard missing > 0 else {
            // Every card already has a picture — nothing to do counts as success.
            job.resultDeckID = deckID
            complete(job, in: modelContext)
            return
        }

        // A per-deck illustration run started from a deck screen may still be going; the
        // pipeline is a single shared resource, so wait our turn rather than failing.
        // Pausing still lets the current job finish, so only a Stop breaks the wait.
        while DeckIllustrationService.shared.isRunning, runState != .stopping {
            statusText = "Waiting for another picture run to finish…"
            try? await Task.sleep(for: .seconds(1))
        }
        guard runState != .stopping else {
            job.status = .queued
            try? modelContext.save()
            return
        }

        statusText = "Drawing pictures: \(deck.topic)"
        let drawn = await DeckIllustrationService.shared.illustrate(
            deckUUID: deckID, in: modelContext, mlxService: mlxService
        )

        if runState == .stopping {
            // Pictures already drawn are saved per card; rerunning finishes the rest.
            job.status = .queued
            try? modelContext.save()
            return
        }
        if drawn > 0 {
            job.resultDeckID = deckID
            complete(job, in: modelContext)
        } else {
            fail(job, "Couldn't draw pictures for this deck.", in: modelContext)
        }
    }

    // MARK: - Bookkeeping

    private func complete(_ job: BatchJob, in modelContext: ModelContext) {
        job.status = .done
        job.completedAt = .now
        try? modelContext.save()
    }

    private func fail(_ job: BatchJob, _ message: String, in modelContext: ModelContext) {
        job.status = .failed
        job.errorMessage = message
        job.completedAt = .now
        try? modelContext.save()
    }

    private func queuedCount(in modelContext: ModelContext) -> Int {
        let queuedRaw = BatchJob.Status.queued.rawValue
        let descriptor = FetchDescriptor<BatchJob>(predicate: #Predicate { $0.statusRaw == queuedRaw })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func nextQueuedJob(in modelContext: ModelContext) -> BatchJob? {
        let queuedRaw = BatchJob.Status.queued.rawValue
        var descriptor = FetchDescriptor<BatchJob>(
            predicate: #Predicate { $0.statusRaw == queuedRaw },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func nextSortOrder(in modelContext: ModelContext) -> Int {
        var descriptor = FetchDescriptor<BatchJob>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        let maxOrder = (try? modelContext.fetch(descriptor))?.first?.sortOrder ?? 0
        return maxOrder + 1
    }
}
