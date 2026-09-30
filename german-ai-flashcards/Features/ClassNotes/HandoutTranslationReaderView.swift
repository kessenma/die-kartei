//
//  HandoutTranslationReaderView.swift
//  german-ai-flashcards
//
//  A handout in German, in English, or both at once. Both at once scrolls as one text by default,
//  sentence beside sentence: side by side where the screen is wide (an iPad, especially in
//  landscape), each German sentence over its English where it is narrow (a phone). With "Scroll
//  together" off, each language gets its own pane and the panes follow each other by sentence,
//  because the translation is stored sentence for sentence; a toggle lights up the sentence at the
//  top of the screen, and a tap on any sentence brings both panes to it. The German is the handout
//  page's own surface: double-tap a word or select a phrase to translate it. Without a translation
//  yet, the screen is where one is made.
//

import SwiftUI
import SwiftData

struct HandoutTranslationReaderView: View {
    @Bindable var material: ClassMaterial
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum ReadingMode: String, CaseIterable, Identifiable {
        case german, both, english
        var id: String { rawValue }
        var label: String {
            switch self {
            case .german:  "Deutsch"
            case .both:    "Beide"
            case .english: "English"
            }
        }
    }

    private enum Language { case german, english }

    /// One reading preference for every handout, like the inline glosses.
    @AppStorage("handout.translation.mode") private var modeRaw = ReadingMode.both.rawValue
    @AppStorage("handout.translation.highlightTop") private var highlightTop = false
    /// Both languages in one scroll, sentence beside sentence, rather than two panes that follow
    /// each other a sentence at a time.
    @AppStorage("handout.translation.scrollTogether") private var scrollTogether = true
    /// The sentence at the top of the screen. Every layout binds it, so switching keeps the place;
    /// in two panes it is also what ties them: scrolling one moves the other.
    @State private var topID: String?
    /// The pane the learner last put a finger on. Only it reports its top sentence, so the pane
    /// being moved to match never reports back and pulls the first one around.
    @State private var leader: Language = .german
    /// Counts the leader coming to rest, the follower's cue to settle on the same sentence.
    @State private var leaderSettled = 0
    /// Each scroll view's visible height, keyed by `scrollerKey`: the last sentence gets exactly
    /// that much room, enough to reach the top and no more.
    @State private var visibleHeights: [String: CGFloat] = [:]
    @State private var service: HandoutTranslationService?
    @State private var showRetranslateConfirm = false

    /// The handout page's double-tap: the same inspector, lookups, vocab list and course deck.
    @State private var inspector: WordInspectorModel?
    @State private var glossary: GlossaryHighlight = .none
    @State private var savedWords: Set<String> = []

    private let accent = ClassNotesTile.tint

    private var mode: ReadingMode { ReadingMode(rawValue: modeRaw) ?? .both }
    private var translation: HandoutTranslation? { material.translation }
    private var isRunning: Bool { service?.isRunning == true }
    private var course: ClassCourse? { material.entry?.course }

    /// The same picker and choice as the flashcard builder (`DocumentTutorChoice`).
    private var downloadedTutors: [MLXModel] { DocumentTutorChoice.downloaded }
    private var tutor: MLXModel { DocumentTutorChoice.current(modelManager) }

    /// The tutor word lookups run on, picked as the handout page picks it, so a word looked up in
    /// either place is answered the same way.
    private var lookupModel: MLXModel {
        StoryStudyService.followUpModel(wrote: material.model, fallback: modelManager.selectedStoryModel)
    }

    var body: some View {
        // Decoded once per update: scrolling moves `topID`, which updates this.
        let translation = material.translation
        let readable = (translation?.translatedCount ?? 0) > 0 && !isRunning
        Group {
            if let translation, readable {
                reader(translation)
            } else {
                setupScreen
            }
        }
        .navigationTitle(material.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let translation, readable {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if mode == .both {
                            Toggle(isOn: $scrollTogether) {
                                Label("Scroll together", systemImage: "link")
                            }
                        }
                        Toggle(isOn: $highlightTop) {
                            Label("Highlight the top sentence", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        if !translation.isComplete {
                            Button {
                                startTranslation()
                            } label: {
                                Label("Finish translating", systemImage: "arrow.clockwise")
                            }
                        }
                        Button {
                            showRetranslateConfirm = true
                        } label: {
                            Label("Translate again", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Translate the whole text again?", isPresented: $showRetranslateConfirm, titleVisibility: .visible) {
            Button("Translate again", role: .destructive) {
                material.setTranslation(nil)
                try? modelContext.save()
                startTranslation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current English is replaced. Takes a few minutes for a long text.")
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
        .onAppear {
            setUpWordTools()
            // The highlight and the sync need a current sentence before the first scroll.
            if topID == nil, let first = translation?.paragraphs.first, !first.german.isEmpty {
                topID = "p\(first.id)-s0"
            }
        }
        // A word just looked up answers from the handout's list the next time, with no model.
        .onChange(of: material.lookupsData) { refreshKnownWords() }
        .onDisappear {
            service?.cancel()
            // A lookup still waiting on a model load has no one to report to now.
            inspector?.tearDown()
        }
    }

    // MARK: - Reader

    @ViewBuilder
    private func reader(_ translation: HandoutTranslation) -> some View {
        let words = JobReadingDecorations(
            savedWords: savedWords,
            lookedUpWords: Set(material.lookups.map { $0.german.lowercased() }),
            glossary: glossary
        )
        VStack(spacing: 0) {
            Picker("Language", selection: $modeRaw) {
                ForEach(ReadingMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch mode {
            case .german:
                pane(.german, translation, words: words)
            case .english:
                pane(.english, translation, words: words)
            case .both:
                if scrollTogether {
                    together(translation, words: words)
                } else if sizeClass == .regular {
                    HStack(spacing: 0) {
                        pane(.german, translation, words: words, header: "Deutsch")
                        Divider()
                        pane(.english, translation, words: words, header: "English")
                    }
                } else {
                    VStack(spacing: 0) {
                        pane(.english, translation, words: words, header: "English")
                        Divider()
                        pane(.german, translation, words: words, header: "Deutsch")
                    }
                }
            }
        }
        .background {
            if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
        }
    }

    /// Both languages in one scroll, so they cannot drift apart: each German sentence beside its
    /// English where there is room for two columns, above it where there is not.
    private func together(_ translation: HandoutTranslation, words: JobReadingDecorations) -> some View {
        let columns = sizeClass == .regular
        let lastID = lastSentenceID(translation, .german)
        // Only the highlight needs the last sentence to reach the top here.
        let room = highlightTop ? roomForLast(in: "both") : nil
        return VStack(spacing: 0) {
            if columns {
                HStack(spacing: 0) {
                    columnHeader("Deutsch")
                    columnHeader("English")
                }
                .padding(.horizontal, 10)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(translation.paragraphs) { paragraph in
                        ForEach(paragraph.german.indices, id: \.self) { index in
                            let id = "p\(paragraph.id)-s\(index)"
                            let english = index < paragraph.english.count ? paragraph.english[index] : ""
                            pairRow(german: paragraph.german[index], english: english, id: id, columns: columns,
                                    words: words, minHeight: id == lastID ? room : nil)
                        }
                        Color.clear.frame(height: 14)
                    }
                    tail(needed: room == nil)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 10)
            }
            .scrollPosition(id: $topID, anchor: .top)
            .onScrollGeometryChange(for: CGFloat.self, of: visibleHeight) { _, height in
                visibleHeights["both"] = height
            }
        }
        .overlay {
            if columns {
                // One rule down the middle, header included, rather than a broken one per row.
                HStack { Divider() }
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pairRow(german: String, english: String, id: String, columns: Bool, words: JobReadingDecorations, minHeight: CGFloat?) -> some View {
        let englishText = Text(english.isEmpty ? "· · ·" : english)
            .foregroundStyle(english.isEmpty ? .tertiary : (columns ? .primary : .secondary))
        return Group {
            if columns {
                HStack(alignment: .top, spacing: 0) {
                    germanText(german, words: words)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    englishText
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                .padding(.vertical, 5)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    germanText(german, words: words)
                    englishText
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .background(topFill(id), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous))
        .frame(minHeight: minHeight, alignment: .top)
        .id(id)
    }

    /// One language, one scroll view. Both panes bind the same `topID`, which is what keeps them
    /// together: the pane being scrolled reports the sentence at its top, the other jumps to it.
    private func pane(_ language: Language, _ translation: HandoutTranslation, words: JobReadingDecorations, header: String? = nil) -> some View {
        // A header means a pane with a partner to follow, which needs every sentence able to
        // reach the top: a pane stuck at its bottom would leave the end of the text unmatched.
        let paired = header != nil
        let key = scrollerKey(language)
        let lastID = lastSentenceID(translation, language)
        let room = paired || highlightTop ? roomForLast(in: key) : nil
        return VStack(spacing: 0) {
            if let header {
                columnHeader(header)
                    .padding(.horizontal, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(translation.paragraphs) { paragraph in
                            let sentences = language == .german ? paragraph.german : paragraph.english
                            ForEach(sentences.indices, id: \.self) { index in
                                let id = "p\(paragraph.id)-s\(index)"
                                sentenceRow(sentences[index], id: id, language: language, words: words,
                                            minHeight: id == lastID ? room : nil)
                            }
                            Color.clear.frame(height: 14)
                        }
                        tail(needed: room == nil)
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 10)
                }
                .scrollPosition(id: follow(language), anchor: .top)
                .onScrollPhaseChange { _, phase in
                    if phase == .tracking || phase == .interacting { leader = language }
                    if phase == .idle, leader == language { leaderSettled += 1 }
                }
                // Jumping far into rows the lazy stack has not laid out yet can stop short of the
                // sentence, near the end especially. Once the leader is at rest, land on it again.
                .onChange(of: leaderSettled) {
                    guard leader != language, let topID else { return }
                    proxy.scrollTo(topID, anchor: .top)
                }
                .onScrollGeometryChange(for: CGFloat.self, of: visibleHeight) { _, height in
                    visibleHeights[key] = height
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A pane's hold on `topID`: it always scrolls to it, but only the pane being scrolled writes
    /// it. The other pane's report after jumping to match is an echo, and past the last sentence
    /// (the room under it) there is no sentence to report at all.
    private func follow(_ language: Language) -> Binding<String?> {
        Binding(
            get: { topID },
            set: { id in
                guard let id, leader == language else { return }
                topID = id
            }
        )
    }

    @ViewBuilder
    private func sentenceRow(_ text: String, id: String, language: Language, words: JobReadingDecorations, minHeight: CGFloat?) -> some View {
        if language == .german, !text.isEmpty {
            // The text view's own single tap, which waits out a double-tap on a word.
            rowChrome(germanText(text, words: words, onSingleTap: { jump(to: id) }), id: id, minHeight: minHeight)
                .id(id)
        } else {
            rowChrome(
                Text(text.isEmpty ? "· · ·" : text)
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary),
                id: id,
                minHeight: minHeight
            )
            .contentShape(Rectangle())
            .onTapGesture { jump(to: id) }
            .id(id)
        }
    }

    private func rowChrome(_ content: some View, id: String, minHeight: CGFloat?) -> some View {
        content
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(topFill(id), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous))
            .frame(minHeight: minHeight, alignment: .top)
    }

    /// A German sentence on the handout page's surface: double-tap a word or select a phrase to
    /// translate it; saved, looked-up and vocab-list words are marked as they are there.
    private func germanText(_ text: String, words: JobReadingDecorations, onSingleTap: (() -> Void)? = nil) -> some View {
        SelectableGermanText(
            text: text,
            textStyle: .body,
            savedWords: words.savedWords,
            glossary: words.glossary,
            lookedUpWords: words.lookedUpWords,
            onTapWord: { inspector?.inspect($0) },
            onTranslateSelection: { inspector?.inspect($0) },
            // A phrase worth keeping goes through the inspector too, so it can be saved as a card.
            onSavePhrase: { inspector?.inspect($0) },
            onSingleTap: onSingleTap
        )
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func topFill(_ id: String) -> Color {
        highlightTop && topID == id ? accent.opacity(0.16) : .clear
    }

    /// Breathing room after the text, unless the last sentence already carries its own.
    private func tail(needed: Bool) -> some View {
        Color.clear.frame(height: needed ? 40 : 0)
    }

    private func scrollerKey(_ language: Language) -> String {
        language == .german ? "de" : "en"
    }

    private func lastSentenceID(_ translation: HandoutTranslation, _ language: Language) -> String? {
        guard let last = translation.paragraphs.last else { return nil }
        let count = language == .german ? last.german.count : last.english.count
        return count > 0 ? "p\(last.id)-s\(count - 1)" : nil
    }

    /// The height that lets the last sentence scroll up to the top and stop there: the visible
    /// height, less the paragraph gap that follows it.
    private func roomForLast(in key: String) -> CGFloat? {
        visibleHeights[key].map { max($0 - 14, 0) }
    }

    /// What a scroll view shows of its content, bars and safe area taken off.
    private func visibleHeight(_ geometry: ScrollGeometry) -> CGFloat {
        geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
    }

    private func jump(to id: String) {
        withAnimation(.snappy(duration: 0.3)) { topID = id }
    }

    // MARK: - Word lookups

    private func setUpWordTools() {
        if inspector == nil {
            inspector = ClassWordInspector.make(
                material: material,
                course: course,
                mlxService: mlxService,
                model: lookupModel,
                feedsCoach: modelManager.storyFeedsCoach,
                onSaved: { refreshSavedWords() },
                context: modelContext
            )
        }
        glossary = glossaryDeck().map { HandoutGlossary.highlight(deck: $0, in: material.text).highlight } ?? .none
        refreshSavedWords()
        refreshKnownWords()
    }

    /// The vocab list picked for this handout on its page.
    private func glossaryDeck() -> SavedDeck? {
        guard let id = material.glossaryDeckID else { return nil }
        var descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func refreshSavedWords() {
        savedWords = course.map { ClassDeckStore.savedWords(for: $0, context: modelContext) } ?? []
    }

    /// The list's English wins over an earlier lookup for the same word: it is the teacher's.
    private func refreshKnownWords() {
        inspector?.knownTranslations = ClassWordInspector.knownTranslations(for: material)
            .merging(glossary.wordTranslations) { _, fromList in fromList }
    }

    // MARK: - Setup

    private var setupScreen: some View {
        List {
            Section {
                if let service, service.isRunning {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: service.progress)
                            .tint(accent)
                        Text(service.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Stop") { service.cancel() }
                    }
                    .padding(.vertical, 4)
                } else {
                    let count = translation?.sentenceCount ?? HandoutTranslation.skeleton(for: material.text).sentenceCount
                    let done = translation?.translatedCount ?? 0
                    DocumentTutorPicker(modelManager: modelManager, title: "Translate with")
                    Button {
                        startTranslation()
                    } label: {
                        Label(done > 0 ? "Continue translating (\(done) of \(count) done)" : "Translate \(count) sentences",
                              systemImage: "text.book.closed")
                    }
                    .disabled(downloadedTutors.isEmpty)
                    if let service, case .failed(let message) = service.phase {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Übersetzung · Translation").themedSectionHeader()
            } footer: {
                Text(downloadedTutors.isEmpty
                     ? "Download a tutor in Settings ▸ Model to translate a text. Everything stays on this device."
                     : "The tutor translates the text sentence by sentence, on this device, so you can read German and English side by side. A long handout takes a few minutes; you can stop and continue later.")
                    .font(.caption2)
            }
            .themedListRow()
        }
        .themedListScreen()
    }

    private func startTranslation() {
        let svc = HandoutTranslationService(mlxService: mlxService, modelContext: modelContext)
        service = svc
        Task {
            await svc.translate(material, model: tutor)
        }
    }
}

// MARK: - Preview

@MainActor
private func translationReaderPreview(_ theme: AppTheme) -> some View {
    let material = ClassMaterial(
        title: "Hänsel und Gretel",
        text: "Vor einem großen Walde wohnte ein armer Holzhacker mit seiner Frau und seinen zwei Kindern. Er hatte wenig zu beißen und zu brechen.\n\nDie zwei Kinder hatten vor Hunger auch nicht einschlafen können.",
        sourceKind: .pdf
    )
    var translation = HandoutTranslation.skeleton(for: material.text)
    translation.paragraphs[0].english = ["At the edge of a great forest lived a poor woodcutter with his wife and his two children.", "He had little to bite and to break."]
    translation.paragraphs[1].english = ["The two children had not been able to fall asleep for hunger either."]
    material.setTranslation(translation)
    return NavigationStack {
        HandoutTranslationReaderView(material: material, modelManager: MLXModelManager(), mlxService: MLXGenerationService())
    }
    .environment(\.appTheme, theme)
    .inMemoryModelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self])
}

#Preview("Translation · System")  { translationReaderPreview(.klar) }
#Preview("Translation · Bauhaus") { translationReaderPreview(.grundform) }
