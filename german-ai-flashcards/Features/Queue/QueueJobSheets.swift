//
//  QueueJobSheets.swift
//  german-ai-flashcards
//
//  The three "add a job" sheets for the batch queue. Each is a compact version of the
//  matching setup screen: enough to describe the job, nothing that needs a model loaded —
//  models load when the queue actually runs.
//

import SwiftUI
import SwiftData

// MARK: - Flashcard deck job

struct QueueFlashcardJobSheet: View {
    var modelManager: MLXModelManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var topicFocused: Bool

    @State private var topic = ""
    @State private var wordCount = 10
    @State private var wordTypeFilter: WordTypeFilter = .all
    @State private var includeExamples = true
    @State private var includeGender = true
    @State private var withImages: Bool

    // The Create screen's persisted conjugation choices carry over silently, same as they
    // would if the deck were generated there.
    @AppStorage("home.includeConjugations") private var includeConjugations = false
    @AppStorage("home.selectedTenses") private var selectedTensesRaw = "Präsens"

    private let wordCountOptions = [5, 10, 15, 20, 30, 50]

    init(modelManager: MLXModelManager) {
        self.modelManager = modelManager
        _withImages = State(initialValue: modelManager.flashcardIllustrationsEnabled && ImageGenModel.current.isDownloaded)
    }

    private var trimmedTopic: String { topic.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. kitchen items, travel phrases...", text: $topic)
                        .textInputAutocapitalization(.never)
                        .focused($topicFocused)
                        .onSubmit { topicFocused = false }
                } header: {
                    Text("Topic").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Number of cards")
                        Picker("Number of cards", selection: $wordCount) {
                            ForEach(wordCountOptions, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    Picker("Word type", selection: $wordTypeFilter) {
                        ForEach(WordTypeFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    Toggle("Example sentences", isOn: $includeExamples)
                    if wordTypeFilter.includesNouns {
                        Toggle("Gender (der/die/das)", isOn: $includeGender)
                    }
                    if ImageGenModel.current.isDownloaded {
                        Toggle(isOn: $withImages) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI pictures")
                                Text("Drawn at the end of the queue, after all the writing jobs.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Cards").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    Button {
                        addJob()
                    } label: {
                        Label("Add to Queue", systemImage: "text.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(trimmedTopic.isEmpty)
                } footer: {
                    Text("Generates with \(modelManager.selectedMLXModel.rawValue). The whole deck is saved to your Library when it finishes.")
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Queue a Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addJob() {
        let hasVerbs = wordTypeFilter.includesVerbs
        let tenses = Set(selectedTensesRaw.split(separator: ",").map(String.init))
        let job = BatchJob.flashcards(
            topic: trimmedTopic,
            wordCount: wordCount,
            includeExamples: includeExamples,
            includeGender: includeGender,
            wordTypeFilter: wordTypeFilter,
            includeConjugations: hasVerbs && includeConjugations,
            selectedTenses: hasVerbs ? Array(tenses) : [],
            withImages: withImages && ImageGenModel.current.isDownloaded,
            generatorRaw: modelManager.selectedMLXModel.rawValue,
            sortOrder: BatchQueueService.shared.nextSortOrder(in: modelContext)
        )
        modelContext.insert(job)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Story job

struct QueueStoryJobSheet: View {
    var modelManager: MLXModelManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var topicFocused: Bool

    @State private var topic = ""
    @State private var level: CEFRLevel
    @State private var genre: StoryGenre
    @State private var questionCount: Int
    @State private var withImages: Bool
    @State private var imageCount: Int

    init(modelManager: MLXModelManager) {
        self.modelManager = modelManager
        _level = State(initialValue: modelManager.storyLevel)
        _genre = State(initialValue: modelManager.storyGenre)
        _questionCount = State(initialValue: modelManager.storyQuestionCount)
        _withImages = State(initialValue: modelManager.storyIllustrationsEnabled && ImageGenModel.current.isDownloaded)
        _imageCount = State(initialValue: modelManager.storyImageCount)
    }

    private var hero: MLXModel { StoryStudyService.requiredModel }
    private var trimmedTopic: String { topic.trimmingCharacters(in: .whitespaces) }
    private var heroReady: Bool { DeviceCapability.mayRunHero && hero.isDownloaded }

    var body: some View {
        NavigationStack {
            Form {
                if !DeviceCapability.mayRunHero {
                    Section {
                        Label("Stories need the \(hero.rawValue), and this device doesn't have enough memory to run it.", systemImage: "book.pages")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .themedListRow()
                } else if !hero.isDownloaded {
                    Section {
                        Label("Stories are written by the \(hero.rawValue). Download it once on the story screen (Reading ▸ Read a Short Story), then queue as many as you like.", systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .themedListRow()
                } else {
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
                    } header: {
                        Text("Topic").themedSectionHeader()
                    }
                    .themedListRow()

                    Section {
                        Picker("Style", selection: $genre) {
                            ForEach(StoryGenre.allCases) { g in
                                Label(g.label, systemImage: g.systemImage).tag(g)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Level")
                            Picker("Level", selection: $level) {
                                ForEach(CEFRLevel.allCases) { l in
                                    Text(l.rawValue).tag(l)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Questions")
                            Picker("Questions", selection: $questionCount) {
                                ForEach([4, 6, 8, 10], id: \.self) { n in
                                    Text("\(n)").tag(n)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Story").themedSectionHeader()
                    }
                    .themedListRow()

                    if ImageGenModel.current.isDownloaded {
                        Section {
                            Toggle("Illustrate this story", isOn: $withImages)
                            if withImages {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Pictures")
                                    Picker("Pictures", selection: $imageCount) {
                                        ForEach([1, 2, 3, 4], id: \.self) { n in
                                            Text("\(n)").tag(n)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text("Illustrations").themedSectionHeader()
                        }
                        .themedListRow()
                    }

                    Section {
                        Button {
                            addJob()
                        } label: {
                            Label("Add to Queue", systemImage: "text.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(trimmedTopic.isEmpty)
                    } footer: {
                        Text("Question types follow your story settings. The finished story lands in Library ▸ Reading.")
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Queue a Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addJob() {
        guard heroReady else { return }
        let job = BatchJob.story(
            topic: trimmedTopic,
            level: level,
            genre: genre,
            questionCount: questionCount,
            questionKinds: modelManager.storyQuestionKinds,
            withImages: withImages && ImageGenModel.current.isDownloaded,
            imageCount: imageCount,
            sortOrder: BatchQueueService.shared.nextSortOrder(in: modelContext)
        )
        modelContext.insert(job)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Deck pictures job

struct QueueDeckPicturesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    @Query private var allJobs: [BatchJob]

    @State private var selected: Set<UUID> = []

    /// Decks that can take a picture job: browsable content with at least one card missing
    /// a picture.
    private var candidates: [(deck: SavedDeck, missing: Int)] {
        decks
            .filter(\.isBrowsableContent)
            .map { ($0, $0.cards.filter { $0.imageFileName == nil }.count) }
            .filter { $0.1 > 0 }
    }

    /// Decks that already have a picture job waiting or running, so they can't be added twice.
    private var alreadyQueued: Set<UUID> {
        Set(allJobs
            .filter { $0.kind == .deckPictures && ($0.status == .queued || $0.status == .running) }
            .compactMap(\.targetDeckID))
    }

    var body: some View {
        NavigationStack {
            Form {
                if !ImageGenModel.current.isDownloaded {
                    Section {
                        Label("Pictures need the \(ImageGenModel.current.displayName). Download it in Settings ▸ Cards first.", systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .themedListRow()
                } else if candidates.isEmpty {
                    Section {
                        Label("Every deck already has pictures for all its cards. Nice.", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .themedListRow()
                } else {
                    Section {
                        ForEach(candidates, id: \.deck.id) { candidate in
                            let deckID = candidate.deck.id
                            let isQueued = alreadyQueued.contains(deckID)
                            Button {
                                guard !isQueued else { return }
                                if selected.contains(deckID) {
                                    selected.remove(deckID)
                                } else {
                                    selected.insert(deckID)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.deck.topic)
                                            .foregroundStyle(.primary)
                                        Text(isQueued
                                             ? "Already in the queue"
                                             : "\(candidate.missing) of \(candidate.deck.cards.count) cards need a picture")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isQueued {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.tertiary)
                                    } else if selected.contains(deckID) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Decks Missing Pictures").themedSectionHeader()
                    } footer: {
                        Text("Each job draws pictures only for the cards that don't have one, so rerunning a deck never redraws what's there.")
                    }
                    .themedListRow()

                    Section {
                        Button {
                            selected = Set(candidates.map(\.deck.id)).subtracting(alreadyQueued)
                        } label: {
                            Label("Select All", systemImage: "checklist.checked")
                        }
                        Button {
                            addJobs()
                        } label: {
                            Label(
                                selected.count == 1 ? "Add 1 Deck to Queue" : "Add \(selected.count) Decks to Queue",
                                systemImage: "text.badge.plus"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selected.isEmpty)
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Queue Deck Pictures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addJobs() {
        for candidate in candidates where selected.contains(candidate.deck.id) {
            let job = BatchJob.deckPictures(
                deckID: candidate.deck.id,
                topic: candidate.deck.topic,
                sortOrder: BatchQueueService.shared.nextSortOrder(in: modelContext)
            )
            modelContext.insert(job)
        }
        try? modelContext.save()
        dismiss()
    }
}
