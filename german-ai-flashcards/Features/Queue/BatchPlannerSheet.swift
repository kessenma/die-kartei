//
//  BatchPlannerSheet.swift
//  german-ai-flashcards
//
//  The guided way to fill the batch queue: answer a few questions (level, how many stories,
//  how many decks, how random, how many pictures) and the sheet builds the whole night's
//  jobs, steered by the learner profile — one deck aimed at the shakiest grammar spot, and
//  words the learner is building woven into the stories.
//

import SwiftUI
import SwiftData

struct BatchPlannerSheet: View {
    var coordinator: GenerationCoordinator

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    private enum Step: Int, CaseIterable {
        case level, stories, decks, review
        var title: String {
            switch self {
            case .level: "Your Level"
            case .stories: "Stories"
            case .decks: "Flashcard Decks"
            case .review: "Your Plan"
            }
        }
    }

    @State private var step: Step = .level

    // Step 1 — level & coach
    @State private var level: CEFRLevel
    @State private var coachSteering = true

    // Step 2 — stories
    @State private var storyCount = 2
    @State private var randomStoryTopics = true
    @State private var storyTopics: [String] = []
    @State private var randomStyles = true
    @State private var randomQuestionKinds = true
    @State private var imagesPerStory: Int

    // Step 3 — decks
    @State private var deckCount = 2
    @State private var randomDeckTopics = true
    @State private var deckTopics: [String] = []
    @State private var cardsPerDeck = 10
    @State private var deckImages: Bool

    // Step 4 — the built plan (fixed once built, so randomness doesn't reshuffle per render)
    @State private var plan: [PlannedJob] = []

    // The Create screen's persisted extras carry over silently, like the manual queue sheet.
    @AppStorage("home.includeExamples") private var includeExamples = true
    @AppStorage("home.includeGender") private var includeGender = true

    private var modelManager: MLXModelManager { coordinator.modelManager }

    init(coordinator: GenerationCoordinator) {
        self.coordinator = coordinator
        let mm = coordinator.modelManager
        _level = State(initialValue: mm.storyLevel)
        let imagesReady = ImageGenModel.current.isDownloaded
        _imagesPerStory = State(initialValue: (imagesReady && mm.storyIllustrationsEnabled) ? mm.storyImageCount : 0)
        _deckImages = State(initialValue: imagesReady && mm.flashcardIllustrationsEnabled)
    }

    // MARK: - Learner profile snapshot

    private var profile: LearnerProfile { LearnerMemoryService.profile(in: modelContext) }

    /// Shaky grammar structures, worst first (same threshold as Coach's Notes).
    private var weakFocuses: [GrammarFocus] {
        profile.grammar
            .compactMap { key, skill -> (GrammarFocus, Double)? in
                guard skill.struggle >= GrammarSkill.shakyThreshold,
                      let focus = GrammarFocus(rawValue: key) else { return nil }
                return (focus, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Most recent words the learner is building, for story weaving.
    private var coachWords: [String] {
        Array(profile.vocab.sorted { $0.lastSeen > $1.lastSeen }.prefix(8).map(\.german))
    }

    private var hasCoachData: Bool { !weakFocuses.isEmpty || !coachWords.isEmpty }

    /// The one deck spec the coach can aim at a weak spot (only some structures map onto
    /// deck options): past tenses become a verb deck in that tense, Artikel a noun deck
    /// with genders.
    private struct DeckTarget {
        let wordType: WordTypeFilter
        let includeConjugations: Bool
        let tenses: [String]
        let note: String
    }

    private var deckTarget: DeckTarget? {
        for focus in weakFocuses {
            switch focus {
            case .perfekt:
                return DeckTarget(
                    wordType: .verbs, includeConjugations: true, tenses: ["Präsens", "Perfekt"],
                    note: "Verb deck in Perfekt, your shakiest structure"
                )
            case .praeteritum:
                return DeckTarget(
                    wordType: .verbs, includeConjugations: true, tenses: ["Präsens", "Präteritum"],
                    note: "Verb deck in Präteritum, your shakiest structure"
                )
            case .artikel:
                return DeckTarget(
                    wordType: .nouns, includeConjugations: false, tenses: [],
                    note: "Noun deck with genders, because der/die/das needs work"
                )
            default:
                continue
            }
        }
        return nil
    }

    private var heroReady: Bool {
        DeviceCapability.mayRunHero && StoryStudyService.requiredModel.isDownloaded
    }
    private var imagesReady: Bool { ImageGenModel.current.isDownloaded }
    private var effectiveStoryCount: Int { heroReady ? storyCount : 0 }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .level: levelStep.themedListRow()
                case .stories: storiesStep.themedListRow()
                case .decks: decksStep.themedListRow()
                case .review: reviewStep.themedListRow()
                }
                navigationSection
            }
            .themedListScreen()
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                        .frame(width: 120)
                }
            }
            .onAppear { resizeTopicFields() }
            .onChange(of: storyCount) { resizeTopicFields() }
            .onChange(of: deckCount) { resizeTopicFields() }
        }
    }

    // MARK: - Step 1: level & coach

    @ViewBuilder
    private var levelStep: some View {
        Section {
            Picker("Level", selection: $level) {
                ForEach(CEFRLevel.allCases) { l in
                    Text(l.rawValue).tag(l)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
        } header: {
            Text("What level should the stories be?").themedSectionHeader()
        } footer: {
            Text("\(level.rawValue) · \(level.englishLabel). Flashcard decks aren't leveled; only the stories use this.")
        }

        if hasCoachData {
            Section {
                if !weakFocuses.isEmpty {
                    Label(
                        "Needs work: \(weakFocuses.prefix(3).map(\.germanLabel).joined(separator: ", "))",
                        systemImage: "flame"
                    )
                    .foregroundStyle(.secondary)
                }
                if !coachWords.isEmpty {
                    Label(
                        "\(coachWords.count) words you're building",
                        systemImage: "text.book.closed"
                    )
                    .foregroundStyle(.secondary)
                }
                Toggle("Let the coach steer this batch", isOn: $coachSteering)
            } header: {
                Text("Your Coach's Notes").themedSectionHeader()
            } footer: {
                Text("Steering aims one deck at your shakiest grammar spot and weaves words you're learning into the stories.")
            }
        }
    }

    // MARK: - Step 2: stories

    @ViewBuilder
    private var storiesStep: some View {
        if !heroReady {
            Section {
                Label(
                    DeviceCapability.mayRunHero
                        ? "Stories need the \(StoryStudyService.requiredModel.rawValue) downloaded first (Reading ▸ Read a Short Story). Skipping stories for this plan."
                        : "This device can't run the story model, so this plan is decks only.",
                    systemImage: "book.pages"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } else {
            Section {
                countPicker("Stories", selection: $storyCount)
            } header: {
                Text("How many stories?").themedSectionHeader()
            } footer: {
                Text("Each is a full story with questions and a glossary, written at \(level.rawValue).")
            }

            if storyCount > 0 {
                Section {
                    Toggle("Surprise me with topics", isOn: $randomStoryTopics)
                    if !randomStoryTopics {
                        ForEach(0..<storyCount, id: \.self) { index in
                            TextField("Story \(index + 1) topic", text: topicBinding($storyTopics, index))
                        }
                    }
                    Toggle("Random styles", isOn: $randomStyles)
                    Toggle("Mix up question types", isOn: $randomQuestionKinds)
                } header: {
                    Text("How random?").themedSectionHeader()
                } footer: {
                    Text(randomStoryTopics
                         ? "Topics come from the 100 bundled story ideas; styles and question types are shuffled per story when those are on."
                         : "Type a topic per story; styles and question types are shuffled per story when those are on.")
                }

                if imagesReady {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pictures per story")
                            Picker("Pictures per story", selection: $imagesPerStory) {
                                ForEach([0, 1, 2, 3, 4], id: \.self) { n in
                                    Text(n == 0 ? "None" : "\(n)").tag(n)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Illustrations").themedSectionHeader()
                    } footer: {
                        Text("Each picture adds a minute or two per story.")
                    }
                }
            }
        }
    }

    // MARK: - Step 3: decks

    @ViewBuilder
    private var decksStep: some View {
        Section {
            countPicker("Decks", selection: $deckCount)
        } header: {
            Text("How many flashcard decks?").themedSectionHeader()
        } footer: {
            Text("Generated with \(modelManager.selectedMLXModel.rawValue) and saved straight to your Library.")
        }

        if deckCount > 0 {
            Section {
                Toggle("Surprise me with topics", isOn: $randomDeckTopics)
                if !randomDeckTopics {
                    ForEach(0..<deckCount, id: \.self) { index in
                        TextField("Deck \(index + 1) topic", text: topicBinding($deckTopics, index))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cards per deck")
                    Picker("Cards per deck", selection: $cardsPerDeck) {
                        ForEach([5, 10, 15, 20, 30], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
                if imagesReady {
                    Toggle(isOn: $deckImages) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI pictures")
                            Text("Drawn at the end of the run, after all the writing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Deck setup").themedSectionHeader()
            } footer: {
                if coachSteering, let target = deckTarget {
                    Text("Coach steering: the first deck becomes a \(target.wordType == .nouns ? "noun" : "verb") deck aimed at \(weakFocusLabelForTarget).")
                }
            }
        }
    }

    private var weakFocusLabelForTarget: String {
        for focus in weakFocuses {
            switch focus {
            case .perfekt, .praeteritum, .artikel: return focus.germanLabel
            default: continue
            }
        }
        return ""
    }

    // MARK: - Step 4: review

    @ViewBuilder
    private var reviewStep: some View {
        if plan.isEmpty {
            Section {
                Label("Nothing planned. Go back and add at least one story or deck.", systemImage: "tray")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(Array(plan.enumerated()), id: \.offset) { _, planned in
                    plannedRow(planned)
                }
            } header: {
                Text("\(plan.count) job\(plan.count == 1 ? "" : "s")").themedSectionHeader()
            } footer: {
                Text("Rough estimate: about \(timeLabel(planEstimateSeconds)).")
            }

            Section {
                Button {
                    buildPlan()
                } label: {
                    Label("Shuffle Again", systemImage: "die.face.5")
                }
                Button {
                    addPlan(startNow: false)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                Button {
                    addPlan(startNow: true)
                } label: {
                    Label("Add & Run Now", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(coordinator.isGenerating || BatchQueueService.shared.isRunning)
            } footer: {
                if BatchQueueService.shared.isRunning {
                    Text("The queue is already running; these jobs will join the end of it.")
                } else {
                    Text("Run Now starts the whole batch immediately. You can leave the app while it works.")
                }
            }
        }
    }

    @ViewBuilder
    private func plannedRow(_ planned: PlannedJob) -> some View {
        HStack(spacing: 12) {
            Image(systemName: planned.isStory ? "book.pages" : "rectangle.stack")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(planned.topic)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(planned.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = planned.coachNote {
                    Label(note, systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        Section {
            HStack {
                if step != .level {
                    Button {
                        withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .level }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                if step != .review {
                    Button {
                        if step == .decks { buildPlan() }
                        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .review }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == .decks && effectiveStoryCount + deckCount == 0)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Plan building

    /// One job the wizard proposes, held as a plain value until the learner confirms.
    private struct PlannedJob {
        var isStory: Bool
        var topic: String
        var summary: String
        var coachNote: String?
        // Story fields
        var genre: StoryGenre = .alltag
        var kinds: [StoryQuestion.Kind] = [.multipleChoice]
        var imageCount: Int = 0
        var weaveWords: [String] = []
        // Deck fields
        var wordType: WordTypeFilter = .all
        var includeConjugations: Bool = false
        var tenses: [String] = []
        var deckImages: Bool = false
    }

    private func buildPlan() {
        var jobs: [PlannedJob] = []

        // Stories
        let starterPool = StoryStarters.all.shuffled().map(\.en)
        for index in 0..<effectiveStoryCount {
            var topic = randomStoryTopics ? "" : (storyTopics.indices.contains(index) ? storyTopics[index] : "")
            topic = topic.trimmingCharacters(in: .whitespaces)
            if topic.isEmpty {
                topic = starterPool.indices.contains(index) ? starterPool[index] : "Ein ganz normaler Tag"
            }
            let genre = randomStyles
                ? (StoryGenre.allCases.randomElement() ?? modelManager.storyGenre)
                : modelManager.storyGenre
            let kinds = randomQuestionKinds
                ? Array(StoryQuestion.Kind.allCases.shuffled().prefix(Int.random(in: 1...2)))
                : modelManager.storyQuestionKinds
            let weave = coachSteering ? Array(coachWords.shuffled().prefix(5)) : []

            var parts = ["\(level.rawValue)", genre.label, "\(modelManager.storyQuestionCount) questions"]
            if imagesPerStory > 0 { parts.append("\(imagesPerStory) picture\(imagesPerStory == 1 ? "" : "s")") }
            jobs.append(PlannedJob(
                isStory: true,
                topic: topic,
                summary: parts.joined(separator: " · "),
                coachNote: weave.isEmpty ? nil : "Weaves in your words: \(weave.prefix(3).joined(separator: ", "))\(weave.count > 3 ? "…" : "")",
                genre: genre,
                kinds: kinds,
                imageCount: imagesReady ? imagesPerStory : 0,
                weaveWords: weave
            ))
        }

        // Decks
        let topicPool = FlashcardTopics.sample(deckCount).map(\.en)
        for index in 0..<deckCount {
            var topic = randomDeckTopics ? "" : (deckTopics.indices.contains(index) ? deckTopics[index] : "")
            topic = topic.trimmingCharacters(in: .whitespaces)
            if topic.isEmpty {
                topic = topicPool.indices.contains(index) ? topicPool[index] : "Everyday life"
            }

            var wordType = WordTypeFilter.all
            var conjugations = false
            var tenses: [String] = []
            var note: String?
            if index == 0, coachSteering, let target = deckTarget {
                wordType = target.wordType
                conjugations = target.includeConjugations
                tenses = target.tenses
                note = target.note
            }

            var parts = ["\(cardsPerDeck) cards"]
            if wordType != .all { parts.append(wordType.rawValue.lowercased()) }
            if conjugations { parts.append("conjugations") }
            if deckImages && imagesReady { parts.append("pictures") }
            jobs.append(PlannedJob(
                isStory: false,
                topic: topic,
                summary: parts.joined(separator: " · "),
                coachNote: note,
                wordType: wordType,
                includeConjugations: conjugations,
                tenses: tenses,
                deckImages: deckImages && imagesReady
            ))
        }

        plan = jobs
    }

    private func addPlan(startNow: Bool) {
        var order = BatchQueueService.shared.nextSortOrder(in: modelContext)
        for planned in plan {
            let job: BatchJob
            if planned.isStory {
                job = BatchJob.story(
                    topic: planned.topic,
                    level: level,
                    genre: planned.genre,
                    questionCount: modelManager.storyQuestionCount,
                    questionKinds: planned.kinds,
                    withImages: planned.imageCount > 0,
                    imageCount: max(planned.imageCount, 1),
                    weaveWords: planned.weaveWords,
                    sortOrder: order
                )
            } else {
                job = BatchJob.flashcards(
                    topic: planned.topic,
                    wordCount: cardsPerDeck,
                    includeExamples: includeExamples,
                    includeGender: includeGender,
                    wordTypeFilter: planned.wordType,
                    includeConjugations: planned.includeConjugations,
                    selectedTenses: planned.tenses,
                    withImages: planned.deckImages,
                    generatorRaw: modelManager.selectedMLXModel.rawValue,
                    sortOrder: order
                )
            }
            modelContext.insert(job)
            order += 1
        }
        try? modelContext.save()

        if startNow {
            BatchQueueService.shared.start(
                modelContext: modelContext,
                mlxService: coordinator.mlxService,
                modelManager: coordinator.modelManager
            )
        }
        dismiss()
    }

    // MARK: - Helpers

    private func countPicker(_ label: String, selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach([0, 1, 2, 3, 4], id: \.self) { n in
                Text(n == 0 ? "None" : "\(n)").tag(n)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
    }

    /// Bounds-safe binding into a topic array (the arrays resize as the counts change).
    private func topicBinding(_ array: Binding<[String]>, _ index: Int) -> Binding<String> {
        Binding(
            get: { index < array.wrappedValue.count ? array.wrappedValue[index] : "" },
            set: { newValue in
                if index < array.wrappedValue.count { array.wrappedValue[index] = newValue }
            }
        )
    }

    /// Keep the manual-topic fields matched to the counts, prefilled with fresh random ideas
    /// so switching off "surprise me" starts from something editable, not blanks.
    private func resizeTopicFields() {
        while storyTopics.count < storyCount {
            storyTopics.append(StoryStarters.random(excluding: storyTopics.last)?.en ?? "")
        }
        if storyTopics.count > storyCount {
            storyTopics.removeLast(storyTopics.count - storyCount)
        }
        while deckTopics.count < deckCount {
            deckTopics.append(FlashcardTopics.random(excluding: deckTopics.last)?.en ?? "")
        }
        if deckTopics.count > deckCount {
            deckTopics.removeLast(deckTopics.count - deckCount)
        }
    }

    private var planEstimateSeconds: Double {
        plan.reduce(0) { total, planned in
            if planned.isStory {
                return total + 240 + Double(planned.imageCount) * 100
            } else {
                var seconds = 20 + 5 * Double(cardsPerDeck)
                if planned.deckImages { seconds += 100 * Double(cardsPerDeck) }
                return total + seconds
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
