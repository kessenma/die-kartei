import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit

/// Configure and generate a new short story. Hard-gated to the hero model: on devices that
/// can't run it the screen explains why, and until it's downloaded the screen offers the
/// download — there is no model picker here on purpose.
struct StorySetupView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @FocusState private var topicFocused: Bool
    @State private var service: StoryStudyService?
    @State private var topic = ""
    /// Set when generation finishes; drives the push to the finished story.
    @State private var finishedStory: StudyStory?
    @State private var showStarters = false
    @State private var showStyleSheet = false
    /// Briefly true after "Add to Batch Queue", to flash the confirmation state.
    @State private var justQueued = false

    private var hero: MLXModel { StoryStudyService.requiredModel }
    private var theme: ModelTheme { hero.theme }
    private var trimmedTopic: String { topic.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            if !DeviceCapability.canRunHero {
                deviceTooSmallSection
            } else if !hero.isDownloaded {
                downloadSection
            } else {
                heroSection
                topicSection
                storySection
                questionSection
                illustrationSection
                translationSection
                generateSection
                if case .failed(let message) = service?.phase {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("New Story")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .overlay {
            if service?.isRunning == true {
                generatingOverlay
            }
        }
        .navigationDestination(item: $finishedStory) { story in
            StoryDetailView(story: story, modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(isPresented: $showStarters) {
            StoryStarterBrowseSheet(accent: theme.accent) { picked in
                topic = picked
            }
        }
        .sheet(isPresented: $showStyleSheet) {
            StoryStyleSheet(selected: Binding(
                get: { modelManager.storyGenre },
                set: { modelManager.storyGenre = $0 }
            ))
        }
        .onAppear {
            if service == nil {
                service = StoryStudyService(mlxService: mlxService, modelContext: modelContext)
            }
        }
    }

    // MARK: - Gating states

    private var deviceTooSmallSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Stories need the \(hero.rawValue)", systemImage: "book.pages")
                    .font(.headline)
                Text("Writing a level-controlled German story and grading your answers takes the German Tutor model, and it needs a device with more memory than this one has. Everything else in the app still works here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var downloadSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    hero.logoImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    Text(hero.rawValue)
                        .font(.headline)
                }
                Text("Stories are written and graded by the German Tutor, fine-tuned on German for this app. One-time download of about 5 GB — after that it runs fully on-device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if mlxService.isLoading {
                    VStack(alignment: .leading, spacing: 6) {
                        if let progress = mlxService.downloadProgress {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                        }
                        if let info = mlxService.downloadInfo {
                            Text(info)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        Task { await mlxService.loadModel(hero) }
                    } label: {
                        Label("Download & Load", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let error = mlxService.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Model Needed")
        }
    }

    private var heroSection: some View {
        Section {
            HStack(spacing: 12) {
                hero.logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hero.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Writes the story and grades your answers, fully on-device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .listRowBackground(theme.linear.opacity(0.12))
        }
    }

    // MARK: - Setup form

    private var topicSection: some View {
        Section {
            TextField("e.g. a trip to Berlin, at the doctor's...", text: $topic)
                .focused($topicFocused)
                .onSubmit { topicFocused = false }

            Button {
                if let pick = StoryStarters.random(excluding: trimmedTopic) {
                    topic = pick.en
                    topicFocused = false
                }
            } label: {
                Label("Surprise me", systemImage: "die.face.5.fill")
            }

            Button {
                topicFocused = false
                showStarters = true
            } label: {
                Label("Browse 100 ideas", systemImage: "square.grid.2x2.fill")
            }
        } header: {
            Text("What should the story be about?")
        }
    }

    private var storySection: some View {
        Section {
            Button {
                showStyleSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: modelManager.storyGenre.systemImage)
                        .foregroundStyle(modelManager.storyGenre.styleAccent)
                        .frame(width: 26)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Style").font(.caption).foregroundStyle(.secondary)
                        Text(modelManager.storyGenre.label).foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("Level")
                Picker("Level", selection: Binding(
                    get: { modelManager.storyLevel },
                    set: { modelManager.storyLevel = $0 }
                )) {
                    ForEach(CEFRLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Story")
        } footer: {
            let level = modelManager.storyLevel
            Text("\(level.rawValue) · \(level.englishLabel) — about \(level.storyWordRange.lowerBound)–\(level.storyWordRange.upperBound) words.")
        }
    }

    private var questionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Number of questions")
                Picker("Number of questions", selection: Binding(
                    get: { modelManager.storyQuestionCount },
                    set: { modelManager.storyQuestionCount = $0 }
                )) {
                    ForEach([4, 6, 8, 10], id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            ForEach(StoryQuestion.Kind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { modelManager.storyQuestionKinds.contains(kind) },
                    set: { setKind(kind, isOn: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.label)
                        Text(kind.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Questions")
        } footer: {
            Text("Pick one or more question types; the questions are split across them.")
        }
    }

    private var imageService: StoryImageService { .shared }

    private var illustrationSection: some View {
        Section {
            if ImageGenModel.current.isDownloaded {
                Toggle(isOn: Binding(
                    get: { modelManager.storyIllustrationsEnabled },
                    set: { modelManager.storyIllustrationsEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Illustrate this story")
                        Text("Pictures drawn on-device by Stable Diffusion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if modelManager.storyIllustrationsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pictures")
                        Picker("Pictures", selection: Binding(
                            get: { modelManager.storyImageCount },
                            set: { modelManager.storyImageCount = $0 }
                        )) {
                            ForEach([1, 2, 3, 4], id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                imageModelDownloadRow
            }
        } header: {
            Text("Illustrations")
        } footer: {
            if !ImageGenModel.current.isDownloaded {
                Text("Optional: AI-drawn pictures for your stories, generated fully on-device.")
            } else if modelManager.storyIllustrationsEnabled {
                Text("The first picture heads the story; the rest appear between paragraphs. Each takes a minute or two after the story is written — the story itself is never blocked by them.")
            }
        }
    }

    private var translationSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { modelManager.storyTranslationEnabled },
                set: { modelManager.storyTranslationEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translate into English")
                    Text("Written afterwards, while you read the German.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Translation")
        } footer: {
            if modelManager.storyTranslationEnabled {
                Text("The story opens as soon as it's written; the English is added in the background and appears under Englisch when it's ready. Leave this off and the translation is written the first time you ask for it.")
            } else {
                Text("You can always tap Englisch on the story screen to translate it then.")
            }
        }
    }

    private var imageModelDownloadRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ImageGenModel.current.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Draws pictures for your stories and flashcards. One-time download of about 1.2 GB.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if imageService.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    if let progress = imageService.downloadProgress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                    if let info = imageService.downloadBytesInfo ?? imageService.downloadInfo {
                        Text(info)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Cancel") {
                        imageService.cancelDownload()
                    }
                    .font(.caption)
                }
            } else {
                Button {
                    Task { await imageService.downloadModel() }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.bordered)
            }

            if let error = imageService.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func setKind(_ kind: StoryQuestion.Kind, isOn: Bool) {
        var kinds = Set(modelManager.storyQuestionKinds)
        if isOn {
            kinds.insert(kind)
        } else if kinds.count > 1 {
            kinds.remove(kind)
        }
        modelManager.storyQuestionKinds = Array(kinds)
    }

    private var generateSection: some View {
        Section {
            Button(action: generate) {
                Label("Write My Story", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
            }
            .disabled(generateDisabled)
            .listRowBackground(theme.linear.opacity(generateDisabled ? 0.4 : 1))
        } footer: {
            // Same settings, but queued for later instead of written now (runs from
            // Home ▸ All Activities ▸ Batch Queue).
            Button(action: addToQueue) {
                Label(
                    justQueued ? "Added to the Batch Queue" : "Add to Batch Queue instead",
                    systemImage: justQueued ? "checkmark.circle.fill" : "text.badge.plus"
                )
                .font(.subheadline)
            }
            .disabled(trimmedTopic.isEmpty || justQueued)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private func addToQueue() {
        topicFocused = false
        let job = BatchJob.story(
            topic: trimmedTopic,
            level: modelManager.storyLevel,
            genre: modelManager.storyGenre,
            questionCount: modelManager.storyQuestionCount,
            questionKinds: modelManager.storyQuestionKinds,
            withImages: modelManager.storyIllustrationsEnabled && ImageGenModel.current.isDownloaded,
            imageCount: modelManager.storyImageCount,
            sortOrder: BatchQueueService.shared.nextSortOrder(in: modelContext)
        )
        modelContext.insert(job)
        try? modelContext.save()
        justQueued = true
        topic = ""
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            justQueued = false
        }
    }

    private var generateDisabled: Bool {
        trimmedTopic.isEmpty || service?.isRunning == true
    }

    // MARK: - Generation

    private func generate() {
        guard let service else { return }
        topicFocused = false
        let story = StudyStory(
            topic: trimmedTopic,
            level: modelManager.storyLevel,
            genre: modelManager.storyGenre
        )
        modelContext.insert(story)
        try? modelContext.save()

        let questionCount = modelManager.storyQuestionCount
        let kinds = modelManager.storyQuestionKinds
        let imageCount = (modelManager.storyIllustrationsEnabled && ImageGenModel.current.isDownloaded)
            ? modelManager.storyImageCount : 0
        let translateAfter = modelManager.storyTranslationEnabled

        // The generation job, run either as a background continued-processing task (so it survives
        // leaving the app) or, if that isn't available, inline with `task == nil`.
        let job: StoryBackgroundGenerator.Job = { task in
            // Generation runs on-device and can take a while, so offer to notify when it's done and
            // keep the screen awake while it works. Auth only prompts the first time.
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

            await service.generate(for: story, questionCount: questionCount, kinds: kinds, imageCount: imageCount)
            progressPump.cancel()

            let success: Bool
            switch service.phase {
            case .done:
                success = true
                finishedStory = story
                await StoryNotificationService.notifyReady(title: story.title)
                // The story (and its pictures) are on screen by now — the translation is written
                // behind the reader, and the story screen picks it up as soon as it lands.
                if translateAfter, !service.wasStopped {
                    _ = await service.translateIfNeeded(for: story)
                }
            case .failed:
                success = false
                await StoryNotificationService.notifyFailed()
                StoryImageStore.deleteImages(for: story.id)
                modelContext.delete(story)
                try? modelContext.save()
            default:
                // User stopped it — no notification, and don't leave a half-written story behind.
                // (A stop during illustration still ends in .done, so finished stories are safe.)
                success = false
                StoryImageStore.deleteImages(for: story.id)
                modelContext.delete(story)
                try? modelContext.save()
            }

            task?.progress.completedUnitCount = 100
            task?.setTaskCompleted(success: success)
        }

        if !StoryBackgroundGenerator.shared.submit(title: "Writing your story", subtitle: trimmedTopic, job: job) {
            Task { @MainActor in await job(nil) }
        }
    }

    private var generatingOverlay: some View {
        GeneratingStoryView(
            phase: service?.phase ?? .idle,
            progress: service?.progress ?? 0,
            tokenCount: service?.streamingTokenCount ?? 0,
            accent: theme.accent,
            imageTarget: service?.imageTarget ?? 0,
            imageSlot: service?.imageSlot ?? 0,
            imageStep: service?.imageStep ?? 0,
            imageStage: service?.imageStage ?? .planning,
            onStop: { service?.stop() }
        )
    }
}
