import SwiftUI
import SwiftData
import AVFoundation

/// A focused "read aloud & follow along" player for a story: the German text is read sentence by
/// sentence, the spoken word is highlighted, the view auto-scrolls to keep it in sight, and a
/// bottom transport bar gives play/pause, sentence skip, slow mode, and a voice picker. Tap any
/// sentence to start reading from there, double-tap a word to translate it, or select a phrase to
/// save it — the same gestures as the reading view. Any generated illustrations ride along at their
/// paragraph anchors and can be hidden from the toolbar. Playback drives the lock screen / Dynamic
/// Island via `SpeechService`, so it keeps going when you leave the app.
struct StoryReadAloudView: View {
    @Bindable var story: StudyStory
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var segments: [SpeechService.Segment] = []
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var currentIndex = 0
    /// Range of the word currently spoken, in full-story UTF-16 coordinates.
    @State private var spokenRange: NSRange?
    @State private var slow = false
    @State private var showVoicePicker = false
    /// A one-time nudge, the first time a story is played aloud, pointing out the voice control —
    /// the tester couldn't find where to switch voices. Anchored to the voice button in the transport
    /// bar, shown once, then never again. (Voice choice was previously only obvious in Settings.)
    @State private var showVoiceTip = false
    @AppStorage("readAloud.seenVoiceTip") private var seenVoiceTip = false

    // Word/phrase gestures, mirroring `StoryDetailView`.
    @State private var inspector: WordInspectorModel?
    @State private var phraseDraft: PhraseDraft?

    /// Illustrations to draw after each segment index, built once alongside `segments`.
    @State private var imagesBySegment: [Int: [StoryImageRecord]] = [:]
    /// Sticks across sessions so a learner who prefers plain text keeps it that way.
    @AppStorage("storyReadAloudShowImages") private var showImages = true

    private var hero: MLXModel { StoryStudyService.requiredModel }
    private var theme: ModelTheme { hero.theme }
    private var hasImages: Bool { !story.images.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                storyScroll
                Divider()
                transportBar
            }
            // Identity themes paint their ground behind the reader; Klar keeps its system background.
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle(story.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hasImages {
                    ToolbarItem(placement: .topBarLeading) { imagesToggle }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .sheet(isPresented: $showVoicePicker) {
                ReadAloudVoiceSheet(modelManager: modelManager, accent: theme.accent) {
                    // Apply a newly-picked voice immediately if we're mid-read.
                    if isPlaying { start(at: currentIndex) }
                }
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
        }
        .tint(theme.accent)
        .onAppear {
            if segments.isEmpty {
                segments = StorySpeechSegmenter.segments(for: story, modelManager: modelManager, granularity: .sentence)
                imagesBySegment = Self.imageAnchors(story: story, segments: segments)
            }
            if inspector == nil {
                // The glossary isn't listed on this screen, but it still answers a double-tap on any
                // word it covers, without loading the model mid-playback.
                var known = StoryGlossaryHighlighter
                    .highlight(for: story.glossary, in: story.storyText).wordTranslations
                // Words looked up on the reading screen answer here too, and vice versa — the list
                // lives on the story, not the screen.
                for entry in story.lookups where known[entry.german.lowercased()] == nil {
                    known[entry.german.lowercased()] = KnownTranslation(
                        german: entry.german, english: entry.english, source: .earlierLookup
                    )
                }
                inspector = StoryWordInspector.make(
                    story: story,
                    mlxService: mlxService,
                    knownTranslations: known,
                    context: modelContext
                )
            }
        }
        // Leaving this screen stops playback; backgrounding the app does not (Now Playing continues).
        .onDisappear { SpeechService.shared.stop() }
    }

    // MARK: - Story text

    private var storyScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if showImages, let header = story.headerImage {
                        illustration(header, maxHeight: 200)
                    }
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        SelectableGermanText(
                            text: segment.text,
                            textStyle: .title3,
                            highlightRange: highlight(for: index),
                            savedWords: savedWords,
                            lookedUpWords: lookedUpWords,
                            onTapWord: { inspector?.inspect($0) },
                            onTranslateSelection: { inspector?.inspect($0) },
                            onSavePhrase: { phraseDraft = PhraseDraft(german: $0) },
                            onSingleTap: { start(at: index) }
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous)
                                .fill(index == currentIndex && isPlaying ? theme.accent.opacity(0.10) : .clear)
                        )
                        .id(index)

                        if showImages {
                            ForEach(imagesBySegment[index] ?? []) { record in
                                illustration(record, maxHeight: 180)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }
            .onChange(of: currentIndex) { _, index in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private func illustration(_ record: StoryImageRecord, maxHeight: CGFloat) -> some View {
        StoryIllustrationView(record: record, storyID: story.id, accent: theme.accent, maxHeight: maxHeight)
            .padding(.horizontal, 12)
    }

    /// Lowercased German words already saved to this story's deck — highlighted in the text.
    private var savedWords: Set<String> {
        StoryDeckStore.savedWords(for: story, context: modelContext)
    }

    /// Lowercased forms of the words looked up in this story — marked in red while following along.
    private var lookedUpWords: Set<String> {
        Set(story.lookups.map { $0.german.lowercased() })
    }

    /// Map each inline illustration onto the segment it should follow, by matching the paragraph's
    /// UTF-16 range in the full story against the segment offsets the segmenter recorded.
    private static func imageAnchors(
        story: StudyStory,
        segments: [SpeechService.Segment]
    ) -> [Int: [StoryImageRecord]] {
        let inline = story.images.filter { $0.paragraphAnchorIndex != nil }
        guard !inline.isEmpty, !segments.isEmpty else { return [:] }

        // End offset (exclusive) of each paragraph, matching the read view's "\n\n" split.
        var paragraphEnds: [Int] = []
        var location = 0
        for paragraph in story.storyText.components(separatedBy: "\n\n") {
            let length = (paragraph as NSString).length
            paragraphEnds.append(location + length)
            location += length + 2 // the separator we split on
        }

        var result: [Int: [StoryImageRecord]] = [:]
        for record in inline {
            guard let anchor = record.paragraphAnchorIndex, anchor < paragraphEnds.count else { continue }
            let end = paragraphEnds[anchor]
            let index = segments.lastIndex { $0.rangeOffset < end } ?? segments.count - 1
            result[index, default: []].append(record)
        }
        return result
    }

    /// The spoken-word range translated into this segment's local coordinates, or nil.
    private func highlight(for index: Int) -> NSRange? {
        guard index == currentIndex, let r = spokenRange, index < segments.count else { return nil }
        let seg = segments[index]
        let loc = r.location - seg.rangeOffset
        guard loc >= 0, loc + r.length <= (seg.text as NSString).length else { return nil }
        return NSRange(location: loc, length: r.length)
    }

    // MARK: - Transport

    private var transportBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 40) {
                Button { goPrevious() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                .disabled(segments.isEmpty)

                Button { playPause() } label: {
                    Image(systemName: playIcon)
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 68, height: 68)
                        .background(theme.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .disabled(segments.isEmpty)

                Button { goNext() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .disabled(segments.isEmpty)
            }
            .tint(.primary)

            HStack {
                Toggle(isOn: $slow) {
                    Label("Langsam", systemImage: "tortoise.fill")
                        .font(.subheadline)
                }
                .toggleStyle(.button)
                .tint(theme.accent)
                .onChange(of: slow) { _, _ in if isPlaying { start(at: currentIndex) } }

                Spacer()

                Button { showVoicePicker = true } label: {
                    Label(currentVoiceName, systemImage: "person.wave.2.fill")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .popover(isPresented: $showVoiceTip) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Change the reading voice", systemImage: "person.wave.2.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Tap here to pick who reads the story. Natural German voices sound far better than the basic one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Choose a voice") {
                            showVoiceTip = false
                            showVoicePicker = true
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                    }
                    .padding(14)
                    .frame(width: 240)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(.bar)
    }

    private var playIcon: String {
        if !isPlaying { return "play.fill" }
        return isPaused ? "play.fill" : "pause.fill"
    }

    /// Show or hide the story's illustrations — some learners want the pictures, some just the text.
    private var imagesToggle: some View {
        Button { showImages.toggle() } label: {
            Image(systemName: showImages ? "photo" : "photo.slash")
        }
        .accessibilityLabel(showImages ? "Hide the pictures" : "Show the pictures")
    }

    private var currentVoiceName: String {
        guard let id = modelManager.selectedVoiceIdentifier,
              let voice = AVSpeechSynthesisVoice(identifier: id) else { return "Voice" }
        return voice.name
    }

    // MARK: - Actions

    private func playPause() {
        if isPlaying {
            SpeechService.shared.togglePlayPause()
            isPaused.toggle()
        } else {
            start(at: currentIndex)
        }
    }

    private func start(at index: Int) {
        guard !segments.isEmpty else { return }
        currentIndex = min(max(index, 0), segments.count - 1)
        SpeechService.shared.speak(
            segments: segments,
            startingAt: currentIndex,
            slow: slow,
            nowPlaying: .init(title: story.title, artist: "\(story.genre.label) · Die Kartei"),
            onWord: { spokenRange = $0 },
            onSegmentChange: { spokenRange = nil; currentIndex = $0 },
            onFinish: {
                isPlaying = false
                isPaused = false
                spokenRange = nil
            }
        )
        isPlaying = true
        isPaused = false

        // First time a learner ever plays a story aloud, point out the voice control once.
        if !seenVoiceTip {
            seenVoiceTip = true
            showVoiceTip = true
        }
    }

    private func goNext() {
        if isPlaying {
            SpeechService.shared.nextSegment()
        } else {
            currentIndex = min(currentIndex + 1, max(segments.count - 1, 0))
        }
    }

    private func goPrevious() {
        if isPlaying {
            SpeechService.shared.previousSegment()
        } else {
            currentIndex = max(currentIndex - 1, 0)
        }
    }
}

// MARK: - Voice picker sheet

/// A compact German-voice picker for the read-aloud player. Writes the same
/// `selectedVoiceIdentifier` that Settings ▸ Cards edits, so the choice sticks everywhere.
private struct ReadAloudVoiceSheet: View {
    @Bindable var modelManager: MLXModelManager
    let accent: Color
    /// Called after the selection changes, so the caller can restart playback in the new voice.
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(voices, id: \.identifier) { voice in
                        Button {
                            modelManager.selectedVoiceIdentifier = voice.identifier
                            onChange()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                    Text(qualityLabel(voice))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    SpeechService.shared.speak("Guten Tag! Ich lese dir die Geschichte vor.",
                                                               voiceIdentifier: voice.identifier)
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                }
                                .buttonStyle(.borderless)
                                if modelManager.selectedVoiceIdentifier == voice.identifier {
                                    Image(systemName: "checkmark").foregroundStyle(accent)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                } footer: {
                    Text("Add natural German voices in iOS Settings ▸ Accessibility ▸ Spoken Content ▸ Voices. Basic voices sound robotic.")
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Reading voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .presentationDetents([.medium, .large])
            .onAppear { voices = GermanVoiceCatalog.sorted() }
        }
    }

    private func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:  return "Premium"
        case .enhanced: return "Enhanced"
        default:        return "Basic"
        }
    }
}
