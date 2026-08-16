//
//  BatchQueueView.swift
//  german-ai-flashcards
//
//  The batch queue screen: build up a list of generation jobs (decks, stories, card
//  pictures), reorder them, then run them all with one tap — before bed, for example.
//  While a run is going it shows live progress with Pause (finish the current job, hold
//  the rest) and Stop (abandon the current job, it goes back to queued).
//

import SwiftUI
import SwiftData

struct BatchQueueView: View {
    var coordinator: GenerationCoordinator

    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \BatchJob.sortOrder) private var jobs: [BatchJob]

    @State private var showingPlanner = false
    @State private var addingFlashcards = false
    @State private var addingStory = false
    @State private var addingPictures = false
    /// Finished story a tapped row pushes to.
    @State private var openStory: StudyStory?

    private var queue: BatchQueueService { .shared }
    private var modelManager: MLXModelManager { coordinator.modelManager }

    private var queuedJobs: [BatchJob] { jobs.filter { $0.status == .queued } }
    private var runningJob: BatchJob? { jobs.first { $0.status == .running } }
    private var finishedJobs: [BatchJob] {
        jobs.filter { $0.status == .done || $0.status == .failed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if jobs.isEmpty {
                introSection.themedListRow()
            }
            if queue.isRunning || runningJob != nil {
                runningSection.themedListRow()
            }
            plannerSection.themedListRow()
            if !queuedJobs.isEmpty {
                upNextSection.themedListRow()
            }
            addSection.themedListRow()
            if !queuedJobs.isEmpty, !queue.isRunning {
                runSection.themedListRow()
            }
            if !finishedJobs.isEmpty {
                finishedSection.themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Batch Queue")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            if queuedJobs.count > 1 {
                EditButton()
            }
        }
        .sheet(isPresented: $showingPlanner) {
            BatchPlannerSheet(coordinator: coordinator)
        }
        .sheet(isPresented: $addingFlashcards) {
            QueueFlashcardJobSheet(modelManager: modelManager)
        }
        .sheet(isPresented: $addingStory) {
            QueueStoryJobSheet(modelManager: modelManager)
        }
        .sheet(isPresented: $addingPictures) {
            QueueDeckPicturesSheet()
        }
        .navigationDestination(item: $openStory) { story in
            StoryDetailView(story: story, modelManager: modelManager, mlxService: coordinator.mlxService)
        }
        .onAppear {
            queue.sweepOrphanedJobs(in: modelContext)
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Run several AI jobs back to back", systemImage: "moon.stars.fill")
                    .font(.headline)
                Text("Queue up flashcard decks, short stories, and card pictures, then start the whole batch with one tap. Handy before bed: everything is waiting in your Library the next morning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var runningSection: some View {
        Section {
            if let job = runningJob {
                QueueJobRow(job: job)
            }
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: queue.progress)
                Text(queue.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail = queue.currentDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Button {
                    queue.requestPause()
                } label: {
                    Label(
                        queue.runState == .pausing ? "Pausing after this job…" : "Pause",
                        systemImage: "pause.fill"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(queue.runState != .running)

                Spacer()

                Button(role: .destructive) {
                    queue.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(queue.runState == .stopping)
            }
        } header: {
            Text("Job \(min(queue.jobsFinishedThisRun + 1, max(queue.jobsTotalThisRun, 1))) of \(max(queue.jobsTotalThisRun, 1))")
                .themedSectionHeader()
        } footer: {
            Text("Pause finishes the current job and holds the rest. Stop abandons the current job; it stays queued for next time.")
        }
    }

    private var upNextSection: some View {
        Section {
            ForEach(queuedJobs, id: \.id) { job in
                QueueJobRow(job: job)
            }
            .onDelete(perform: deleteQueued)
            .onMove(perform: moveQueued)
        } header: {
            Text("Up Next").themedSectionHeader()
        } footer: {
            if queuedJobs.count > 1 {
                Text("Jobs run top to bottom. Use Edit to reorder.")
            }
        }
    }

    private var plannerSection: some View {
        Section {
            Button {
                showingPlanner = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan It for Me")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text("A few quick questions and the queue fills itself, steered by your coach's notes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var addSection: some View {
        Section {
            Button {
                addingFlashcards = true
            } label: {
                Label("Add a Flashcard Deck", systemImage: "rectangle.stack.badge.plus")
            }
            Button {
                addingStory = true
            } label: {
                Label("Add a Short Story", systemImage: "book.pages")
            }
            Button {
                addingPictures = true
            } label: {
                Label("Add Pictures for Existing Decks", systemImage: "photo.on.rectangle.angled")
            }
        } header: {
            Text("Add Jobs").themedSectionHeader()
        }
    }

    private var runSection: some View {
        Section {
            Button(action: startQueue) {
                Label(
                    queuedJobs.count == 1 ? "Run 1 Job" : "Run \(queuedJobs.count) Jobs",
                    systemImage: "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .disabled(runDisabled)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if coordinator.isGenerating {
                    Text("A flashcard generation is already running. The queue can start once it finishes.")
                } else {
                    Text("Rough estimate: about \(timeLabel(totalEstimateSeconds)). You can leave the app while it runs; iOS keeps a progress bar going. Plug the phone in for a long queue.")
                }
            }
        }
    }

    private var finishedSection: some View {
        Section {
            ForEach(finishedJobs, id: \.id) { job in
                Button {
                    openResult(of: job)
                } label: {
                    QueueJobRow(job: job)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteFinished)

            Button {
                clearFinished()
            } label: {
                Label("Clear Finished", systemImage: "trash")
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("Finished").themedSectionHeader()
        } footer: {
            Text("Tap a finished job to open what it made.")
        }
    }

    // MARK: - Actions

    private var runDisabled: Bool {
        queuedJobs.isEmpty || queue.isRunning || coordinator.isGenerating
    }

    private func startQueue() {
        queue.start(
            modelContext: modelContext,
            mlxService: coordinator.mlxService,
            modelManager: coordinator.modelManager
        )
    }

    private func deleteQueued(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(queuedJobs[index])
        }
        try? modelContext.save()
    }

    private func deleteFinished(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(finishedJobs[index])
        }
        try? modelContext.save()
    }

    private func clearFinished() {
        for job in finishedJobs {
            modelContext.delete(job)
        }
        try? modelContext.save()
    }

    private func moveQueued(from source: IndexSet, to destination: Int) {
        var reordered = queuedJobs
        reordered.move(fromOffsets: source, toOffset: destination)
        // Renumber above every existing sortOrder so the new order can't collide with
        // finished rows, and future appends still land at the end.
        let base = (jobs.map(\.sortOrder).max() ?? 0) + 1
        for (index, job) in reordered.enumerated() {
            job.sortOrder = base + index
        }
        try? modelContext.save()
    }

    private func openResult(of job: BatchJob) {
        guard job.status == .done else { return }
        switch job.kind {
        case .story:
            guard let storyID = job.resultStoryID else { return }
            let descriptor = FetchDescriptor<StudyStory>(predicate: #Predicate { $0.id == storyID })
            if let story = try? modelContext.fetch(descriptor).first {
                openStory = story
            }
        case .flashcards, .deckPictures:
            guard let deckID = job.resultDeckID else { return }
            let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckID })
            if let deck = try? modelContext.fetch(descriptor).first {
                let store = DeckStore(modelContext: modelContext)
                router.launch(.cardDeck(store.session(for: deck, style: modelManager.flashcardStyle)))
            }
        }
    }

    // MARK: - Estimates

    private var totalEstimateSeconds: Double {
        queuedJobs.reduce(0) { $0 + estimateSeconds(for: $1) }
    }

    /// Deliberately rough (real speed depends on the device and the model): recorded
    /// seconds-per-card where available, generic guesses otherwise.
    private func estimateSeconds(for job: BatchJob) -> Double {
        switch job.kind {
        case .flashcards:
            let model = MLXModel(rawValue: job.generatorRaw) ?? modelManager.selectedMLXModel
            let perCard: Double
            if let stats = modelManager.lastGenerationStats(for: model), stats.cardCount > 0 {
                perCard = stats.seconds / Double(stats.cardCount)
            } else {
                perCard = 5
            }
            var seconds = 20 + perCard * Double(job.wordCount)
            if job.withImages { seconds += 100 * Double(job.wordCount) }
            return seconds
        case .story:
            var seconds: Double = 240
            if job.withImages { seconds += 100 * Double(job.storyImageCount) }
            return seconds
        case .deckPictures:
            guard let deckID = job.targetDeckID else { return 0 }
            let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckID })
            let missing = (try? modelContext.fetch(descriptor).first)?
                .cards.filter { $0.imageFileName == nil }.count ?? 0
            return 100 * Double(missing)
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

// MARK: - Row

struct QueueJobRow: View {
    let job: BatchJob

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(job.topic)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(job.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if job.status == .failed, let message = job.errorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 8)

            statusBadge
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch job.status {
        case .queued:
            EmptyView()
        case .running:
            ProgressView()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
