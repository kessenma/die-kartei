//
//  ClassMaterialDetailView.swift
//  german-ai-flashcards
//
//  One handout, read the way a tutor reads it with you: word by word, translating what you don't
//  know. The same text surface and inspector as a job posting; the words go into the course's
//  deck. The original file opens in Quick Look when there is one.
//

import SwiftUI
import SwiftData
import QuickLook

struct ClassMaterialDetailView: View {
    @Bindable var material: ClassMaterial
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(ActivityRouter.self) private var router

    @State private var inspector: WordInspectorModel?
    @State private var showHelp = false
    @State private var previewURL: URL?
    /// Briefly the count after "Add all to deck", to confirm.
    @State private var addedCount: Int?

    private var course: ClassCourse? { material.entry?.course }

    /// The tutor the lookups run on: the one that answered earlier lookups here, else the
    /// learner's story tutor, else whatever is on disk. Never starts a download for one word.
    private var lookupModel: MLXModel {
        StoryStudyService.followUpModel(wrote: material.model, fallback: modelManager.selectedStoryModel)
    }

    private var theme: ModelTheme { lookupModel.theme }
    private var accent: Color { appTheme.accent(model: theme) }

    var body: some View {
        List {
            headerSection
            readSection
            lookupSection
            deckSection
        }
        .themedListScreen()
        .tint(accent)
        .navigationTitle(material.title)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            GestureHelpSheet(
                intro: "Two quick gestures help you learn while you read a handout.",
                accent: theme.accent
            )
        }
        .sheet(isPresented: Binding(
            get: { inspector?.inspectedWord != nil },
            set: { if !$0 { inspector?.dismissInspector() } }
        )) {
            if let inspector {
                WordInspectorSheet(
                    source: inspector,
                    footer: "Saved words go into the flashcard deck of \(course?.name ?? "this course"). Find it under Deutschkurs or in Library ▸ Decks."
                )
            }
        }
        .quickLookPreview($previewURL)
        .onAppear(perform: setUp)
        .onDisappear {
            // A lookup still waiting on a model load has no one to report to now.
            inspector?.tearDown()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 8) {
                Label(material.sourceKind.label, systemImage: material.sourceKind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12), in: appTheme.pillShape)
                Spacer()
                Text("\(material.wordCount) Wörter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let entry = material.entry {
                VStack(alignment: .leading, spacing: 2) {
                    if let course {
                        Text(course.name).font(.subheadline)
                    }
                    Text("\(entry.displayTitle) · \(entry.dateLine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let url = material.snapshotURL {
                Button {
                    previewURL = url
                } label: {
                    Label("Open the original", systemImage: material.sourceKind == .pdf ? "doc.richtext" : "photo")
                }
            }
        }
        .themedListRow()
    }

    private var readSection: some View {
        Section {
            JobPostingTextSurface(text: material.text, decorations: decorations, callbacks: callbacks)
        } header: {
            Text("Handout").themedSectionHeader()
        } footer: {
            Text("Double-tap a word to translate it; select a phrase to translate it. Words you've saved are washed in color, words you looked up get a red dashed line.")
        }
        .themedListRow()
    }

    /// The words this learner double-tapped in this handout, kept with it.
    @ViewBuilder
    private var lookupSection: some View {
        let entries = material.lookups
        Section {
            if entries.isEmpty {
                Text("Nothing looked up yet. Double-tap a word in the handout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.german)
                            .fontWeight(.medium)
                        Spacer()
                        Text(entry.english)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                        Button {
                            SpeechService.shared.speak(entry.german)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
                .onDelete(perform: removeLookups)

                let unsaved = entries.filter { !savedWords.contains(ClassWord.key($0.german)) }.count
                Button {
                    addAllToDeck()
                } label: {
                    Label(
                        addedCount.map { "Added \($0) to the deck" }
                            ?? (unsaved == 0 ? "All in the deck" : "Add all \(unsaved) to the deck"),
                        systemImage: addedCount != nil ? "checkmark.circle.fill" : "rectangle.stack.badge.plus"
                    )
                }
                .disabled(unsaved == 0 || addedCount != nil || course == nil)
            }
        } header: {
            Text("Unbekannte Wörter").themedSectionHeader()
        } footer: {
            if !entries.isEmpty {
                Text("Words and phrases you looked up here. Double-tapping one again answers straight from this list, with no wait. Swipe to remove.")
            }
        }
        .themedListRow()
    }

    @ViewBuilder
    private var deckSection: some View {
        let deck = course.flatMap { ClassDeckStore.deck(for: $0, context: modelContext) }
        Section {
            if let deck, !deck.cards.isEmpty {
                Button {
                    router.launch(.cardDeck(DeckStore(modelContext: modelContext).session(for: deck, style: modelManager.flashcardStyle)))
                } label: {
                    Label("Study \(deck.cards.count) cards", systemImage: "rectangle.stack.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                }
                .listRowBackground(theme.linear)
            } else {
                Text("Words you save while reading go into the course's flashcard deck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Flashcards").themedSectionHeader()
        }
        .themedListRow()
    }

    // MARK: - Reading toolkit

    private var callbacks: JobReadingCallbacks {
        JobReadingCallbacks(
            onTapWord: { inspect($0) },
            onTranslateSelection: { inspect($0) },
            // A phrase worth keeping goes through the inspector too, so it can be saved as a card.
            onSavePhrase: { inspect($0) }
        )
    }

    private var decorations: JobReadingDecorations {
        JobReadingDecorations(
            savedWords: savedWords,
            lookedUpWords: Set(material.lookups.map { $0.german.lowercased() })
        )
    }

    /// Lowercased German words already in the course's deck.
    private var savedWords: Set<String> {
        guard let course else { return [] }
        return ClassDeckStore.savedWords(for: course, context: modelContext)
    }

    private func inspect(_ word: String) {
        inspector?.inspect(word)
    }

    private func setUp() {
        if inspector == nil {
            inspector = ClassWordInspector.make(
                material: material,
                course: course,
                mlxService: mlxService,
                model: lookupModel,
                feedsCoach: modelManager.storyFeedsCoach,
                context: modelContext
            )
        } else {
            inspector?.knownTranslations = ClassWordInspector.knownTranslations(for: material)
        }
    }

    private func removeLookups(at offsets: IndexSet) {
        var entries = material.lookups
        entries.remove(atOffsets: offsets)
        material.setLookups(entries)
        try? modelContext.save()
        inspector?.knownTranslations = ClassWordInspector.knownTranslations(for: material)
    }

    private func addAllToDeck() {
        let added = ClassDeckStore.saveAllLookups(for: material, feedsCoach: modelManager.storyFeedsCoach, context: modelContext)
        addedCount = added
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            addedCount = nil
        }
    }
}

// MARK: - Preview

@MainActor
private func classMaterialPreview() -> some View {
    let material = ClassMaterial(
        title: "Arbeitsblatt Wechselpräpositionen",
        text: "Wo steht die Lampe? Die Lampe steht auf dem Tisch.\n\nWohin stellst du die Lampe? Ich stelle die Lampe auf den Tisch.\n\nDie Wechselpräpositionen: an, auf, hinter, in, neben, über, unter, vor, zwischen.",
        sourceKind: .paste
    )
    material.setLookups([
        GlossaryEntry(german: "stellen", english: "to put (upright)"),
        GlossaryEntry(german: "zwischen", english: "between")
    ])
    return ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            ClassMaterialDetailView(
                material: material,
                modelManager: MLXModelManager(),
                mlxService: MLXGenerationService()
            )
        }
        .environment(ActivityRouter())
        .environment(\.appTheme, theme)
        .modelContainer(
            for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self],
            inMemory: true
        )
    }
}

#Preview("Handout · 4 themes") { classMaterialPreview() }
