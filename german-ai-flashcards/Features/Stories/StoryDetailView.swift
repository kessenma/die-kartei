import SwiftUI
import SwiftData

/// One story: read it with the tap/select gestures or listen to it exam-style, check the
/// glossary, reveal the English translation, then start the comprehension questions.
struct StoryDetailView: View {
    @Bindable var story: StudyStory
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    enum StudyMode: String, CaseIterable {
        case read = "Lesen"
        case listen = "Hören"
    }

    enum StoryLanguage: String, CaseIterable {
        case german = "Deutsch"
        case english = "Englisch"
    }

    @State private var service: StoryStudyService?
    @State private var inspector: WordInspectorModel?
    @State private var phraseDraft: PhraseDraft?
    @State private var showHelp = false
    @State private var showQuiz = false
    @State private var mode: StudyMode = .read
    @State private var language: StoryLanguage = .german
    @State private var translationFailed = false

    // Listening mode
    @State private var isPlaying = false
    @State private var playSlow = false
    @State private var manualStop = false
    @State private var spokenRange: NSRange?
    @State private var showVoicesInfo = false
    /// Presents the full read-aloud follow-along player.
    @State private var showReadAloud = false

    // Time-on-story tracking. The timer runs while this screen is up and the app is in the
    // foreground (including with the read-aloud player covering it — that's still studying) and
    // is flushed into a `StoryReadingSession` whenever the screen or the app goes away.
    @State private var readingTimer = StoryReadingTimer()
    /// Words translated and words saved during the current stretch, logged alongside the time as
    /// the "how much help did this story need" signal.
    @State private var lookups = 0
    @State private var wordsSaved = 0
    /// Time already logged against this story before this visit, shown in the header.
    @State private var previousSeconds = 0

    private var hero: MLXModel { StoryStudyService.requiredModel }
    private var theme: ModelTheme { hero.theme }

    var body: some View {
        List {
            headerSection
            modeSection
            if mode == .read {
                readSection
                glossarySection
            } else {
                listenSection
                transcriptSection
            }
            questionSection
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
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
                intro: "Two quick gestures help you learn while you read.",
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
                    footer: "Saved words go into a flashcard deck for this story — find it under Library ▸ Decks."
                )
            }
        }
        .sheet(item: $phraseDraft) { draft in
            AddEditPhraseSheet(
                modelManager: modelManager,
                mlxService: mlxService,
                anchorScenario: nil,
                phrase: nil,
                initialGerman: draft.german
            )
        }
        .sheet(isPresented: $showVoicesInfo) {
            DialogueVoicesInfoSheet(modelManager: modelManager, accent: theme.accent)
        }
        .fullScreenCover(isPresented: $showReadAloud) {
            StoryReadAloudView(story: story, modelManager: modelManager, mlxService: mlxService)
        }
        .navigationDestination(isPresented: $showQuiz) {
            if let service {
                StoryQuizView(story: story, service: service, modelManager: modelManager, isListening: mode == .listen)
            }
        }
        .onAppear {
            setUp()
            readingTimer.start()
        }
        .onDisappear {
            SpeechService.shared.stop()
            // Covers every way out: back, the quiz push, and the app being closed from here.
            // The read-aloud player is the exception — it covers this screen rather than
            // replacing it, and following along there is still time with the story.
            guard !showReadAloud else { return }
            flushReading()
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush rather than merely pause on the way out: a suspended app can be killed
            // without another chance to save.
            if phase == .active { readingTimer.start() } else { flushReading() }
        }
        .onChange(of: language) { _, newValue in
            if newValue == .english { ensureTranslation() }
        }
        .onChange(of: mode) { oldMode, _ in
            manualStop = true
            SpeechService.shared.stop()
            spokenRange = nil
            // Close the stretch under the mode it was actually spent in, so reading and
            // listening time stay separable.
            flushReading(asListening: oldMode == .listen)
            readingTimer.start()
        }
    }

    // MARK: - Header & mode

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    CEFRLevelChip(level: story.level)
                    Text(story.genre.label)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    Spacer()
                    hero.logoImage
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                }
                if let record = story.headerImage {
                    StoryIllustrationView(record: record, storyID: story.id, accent: theme.accent, maxHeight: 200)
                }
                HStack(spacing: 12) {
                    Label("\(story.wordCount) Wörter", systemImage: "text.alignleft")
                    if let best = story.bestScore {
                        Label("Best: \(best)%", systemImage: "checkmark.seal")
                    }
                    Label(StoryProgressService.formatClock(previousSeconds + readingTimer.seconds),
                          systemImage: "timer")
                        .monospacedDigit()
                        .accessibilityLabel("Time spent with this story")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(StudyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Read mode

    @ViewBuilder
    private var readSection: some View {
        Section {
            if language == .german {
                VStack(alignment: .leading, spacing: 14) {
                    readAloudButton
                    illustratedStoryText
                }
            } else if let english = story.englishText, !english.isEmpty {
                translatedStoryText(english)
            } else if isTranslating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Translating…")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if translationFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Translation failed.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Button("Try Again") { ensureTranslation() }
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text("Geschichte")
                Spacer()
                Picker("Language", selection: $language) {
                    ForEach(StoryLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
        } footer: {
            if language == .german {
                if isTranslating {
                    Text("Double-tap a word to translate it; select a phrase to save it. The English translation is being written in the background.")
                } else {
                    Text("Double-tap a word to translate it; select a phrase to save it.")
                }
            } else {
                Text("The English is a check after reading — the gestures work on the German text.")
            }
        }
    }

    /// Opens the full-screen read-aloud player (follow-along highlight, auto-scroll, controls).
    private var readAloudButton: some View {
        Button {
            showReadAloud = true
        } label: {
            Label("Vorlesen & mitlesen", systemImage: "play.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(theme.linear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read the story aloud and follow along")
    }

    private var interactiveStoryText: some View {
        SelectableGermanText(
            text: story.storyText,
            textStyle: .body,
            highlightRange: mode == .listen ? spokenRange : nil,
            savedWords: savedWords,
            onTapWord: { inspect($0) },
            onTranslateSelection: { inspect($0) },
            onSavePhrase: { phraseDraft = PhraseDraft(german: $0) }
        )
        .padding(.vertical, 4)
    }

    /// The read-mode story text: paragraphs with any generated illustrations interleaved at
    /// their anchors. The listen-mode transcript keeps `interactiveStoryText` — its read-along
    /// highlight is an NSRange over the whole story string, which paragraph-splitting would break.
    private var illustratedStoryText: some View {
        let paragraphs = story.storyText.components(separatedBy: "\n\n")
        let inline = Dictionary(
            grouping: story.images.filter { $0.paragraphAnchorIndex != nil },
            by: { $0.paragraphAnchorIndex! }
        )
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(paragraphs.indices, id: \.self) { index in
                SelectableGermanText(
                    text: paragraphs[index],
                    textStyle: .body,
                    highlightRange: nil,
                    savedWords: savedWords,
                    onTapWord: { inspect($0) },
                    onTranslateSelection: { inspect($0) },
                    onSavePhrase: { phraseDraft = PhraseDraft(german: $0) }
                )
                ForEach(inline[index] ?? []) { record in
                    StoryIllustrationView(record: record, storyID: story.id, accent: theme.accent, maxHeight: 180)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The English translation with the same illustrations interleaved, so switching language keeps
    /// the pictures. (The header image sits in `headerSection` and shows in both languages already.)
    private func translatedStoryText(_ english: String) -> some View {
        let paragraphs = englishParagraphs(english)
        // Anchors are indices into the German paragraphs; clamp so a translation that merged
        // paragraphs still shows every picture rather than dropping the tail ones.
        let inline = Dictionary(
            grouping: story.images.filter { $0.paragraphAnchorIndex != nil },
            by: { min($0.paragraphAnchorIndex!, paragraphs.count - 1) }
        )
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(paragraphs[index])
                    .font(.body)
                ForEach(inline[index] ?? []) { record in
                    StoryIllustrationView(record: record, storyID: story.id, accent: theme.accent, maxHeight: 180)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Split the translation into paragraphs that line up with the German ones where possible, so
    /// the illustrations land in the same places. Models sometimes separate paragraphs with a single
    /// newline; that only counts as a break when it reproduces the German structure.
    private func englishParagraphs(_ english: String) -> [String] {
        let germanCount = story.storyText.components(separatedBy: "\n\n").count
        let byBlankLine = english.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if byBlankLine.count >= germanCount { return byBlankLine }
        let byLine = english.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return byLine.count == germanCount ? byLine : byBlankLine
    }

    @ViewBuilder
    private var glossarySection: some View {
        let entries = story.glossary
        if !entries.isEmpty {
            Section("Glossar") {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.german)
                            .fontWeight(.medium)
                        Spacer()
                        Text(entry.english)
                            .foregroundStyle(.secondary)
                        Button {
                            SpeechService.shared.speak(entry.german)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Listen mode

    private var listenSection: some View {
        Section {
            VStack(spacing: 14) {
                readAloudButton

                HStack(spacing: 28) {
                    Toggle(isOn: $playSlow) {
                        Image(systemName: "tortoise.fill")
                    }
                    .toggleStyle(.button)
                    .disabled(isPlaying)
                    .accessibilityLabel("Slow playback")

                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.title)
                            .frame(width: 64, height: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())

                    // Symmetry spacer matching the tortoise button.
                    Toggle(isOn: .constant(false)) { Image(systemName: "tortoise.fill") }
                        .toggleStyle(.button)
                        .hidden()
                }
                .frame(maxWidth: .infinity)

                if story.genre.hasNamedSpeakers {
                    Button {
                        showVoicesInfo = true
                    } label: {
                        Label("Voices for each speaker", systemImage: "person.2.wave.2")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Hören")
        } footer: {
            Text("Listen as often as you like. Tap Vorlesen & mitlesen to follow along with each word highlighted as it's read, or use the round button to just listen.")
        }
    }

    private var transcriptSection: some View {
        Section {
            interactiveStoryText
        } header: {
            Text("Zum Text")
        } footer: {
            Text("Double-tap a word to translate it; select a phrase to save it.")
        }
    }

    private func togglePlay() {
        if isPlaying {
            manualStop = true
            SpeechService.shared.stop()
        } else {
            isPlaying = true
            manualStop = false
            spokenRange = nil
            SpeechService.shared.speak(
                segments: buildSegments(),
                slow: playSlow,
                onWord: { range in spokenRange = range },
                onFinish: {
                    manualStop = false
                    isPlaying = false
                    spokenRange = nil
                }
            )
        }
    }

    /// Voice-tagged, line-level segments for the inline listen control — delegated to the shared
    /// `StorySpeechSegmenter` (the read-aloud player uses the same builder at sentence granularity).
    private func buildSegments() -> [SpeechService.Segment] {
        StorySpeechSegmenter.segments(for: story, modelManager: modelManager, granularity: .line)
    }

    // MARK: - Questions

    @ViewBuilder
    private var questionSection: some View {
        let questions = story.questions
        Section {
            if questions.isEmpty {
                Label("No questions were generated for this story.", systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    story.lastStudiedAsListening = (mode == .listen)
                    try? modelContext.save()
                    showQuiz = true
                } label: {
                    Label("Start Questions (\(questions.count))", systemImage: "checklist")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                }
                .listRowBackground(theme.linear)
            }
        } footer: {
            if !questions.isEmpty {
                Text(mode == .listen
                     ? "Answer from what you heard — you can replay the audio during the questions."
                     : "The story stays within reach during the questions, like the real exam.")
            }
        }
    }

    // MARK: - Setup & saved words

    private func setUp() {
        if service == nil {
            service = StoryStudyService(mlxService: mlxService, modelContext: modelContext)
        }
        if inspector == nil {
            inspector = StoryWordInspector.make(
                story: story,
                mlxService: mlxService,
                feedsCoach: modelManager.storyFeedsCoach,
                onSaved: { wordsSaved += 1 },
                context: modelContext
            )
        }
        previousSeconds = StoryProgressService.secondsRead(storyID: story.id, in: modelContext)
    }

    // MARK: - Time on story

    /// Translate a word and count it: lookups are the "how much help did this story need" signal
    /// logged with the session.
    private func inspect(_ word: String) {
        lookups += 1
        inspector?.inspect(word)
    }

    /// Close the current stretch of reading and log it. Safe to call repeatedly — the timer hands
    /// its seconds over once, and stretches under `minRecordedSeconds` are dropped.
    private func flushReading(asListening: Bool? = nil) {
        let seconds = readingTimer.take()
        let recorded = StoryProgressService.recordReading(
            story: story,
            seconds: seconds,
            wasListening: asListening ?? (mode == .listen),
            lookups: lookups,
            wordsSaved: wordsSaved,
            countsTowardStreak: modelManager.storyTimeCountsTowardStreak,
            in: modelContext
        )
        if recorded != nil {
            previousSeconds += seconds
            lookups = 0
            wordsSaved = 0
        } else {
            // Too short to keep on its own — hand it back so it can join the next stretch
            // instead of evaporating on every trip through the background.
            readingTimer.giveBack(seconds)
        }
    }

    /// Lowercased German words already saved to this story's deck — highlighted in the text.
    private var savedWords: Set<String> {
        StoryDeckStore.savedWords(for: story, context: modelContext)
    }

    /// True while *anyone* is translating this story — either this screen or the background pass
    /// the setup screen starts when "Translate into English" was on.
    private var isTranslating: Bool {
        service?.isTranslating == true || StoryTranslationTracker.shared.isTranslating(story.id)
    }

    private func ensureTranslation() {
        guard story.englishText?.isEmpty != false else { return }
        guard let service, !isTranslating else { return }
        translationFailed = false
        Task {
            let ok = await service.translateIfNeeded(for: story)
            translationFailed = !ok
        }
    }

}

/// Builds the word inspector both story screens use: double-tapped words are translated 1:1 and
/// can be saved into the story's own deck.
enum StoryWordInspector {
    /// `feedsCoach` gates the learner-profile hand-off; `onSaved` lets the caller count saves
    /// against the current reading session.
    @MainActor
    static func make(
        story: StudyStory,
        mlxService: MLXGenerationService,
        feedsCoach: Bool = true,
        onSaved: @escaping () -> Void = {},
        context: ModelContext
    ) -> WordInspectorModel {
        WordInspectorModel(
            mlxService: mlxService,
            model: StoryStudyService.requiredModel,
            isWordSaved: { word in StoryDeckStore.isWordSaved(word, story: story, context: context) },
            onSave: { german, english in
                StoryDeckStore.saveWord(
                    german: german, english: english, story: story,
                    feedsCoach: feedsCoach, context: context
                )
                onSaved()
            }
        )
    }
}
