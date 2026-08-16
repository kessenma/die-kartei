import SwiftUI

// MARK: - Visual identity

/// Kept out of `CardImageStyle` so the model file stays SwiftUI-free, the same split
/// `StoryGenre+Style` makes. Colors stay in the app's blue/indigo/violet/teal/rose/amber family.
extension CardImageStyle {
    var systemImage: String {
        switch self {
        case .stickFigure: "figure.stand"
        case .lineArt:     "scribble"
        case .flatIcon:    "square.on.circle"
        case .cartoon:     "face.smiling"
        case .storybook:   "book.closed.fill"
        case .watercolor:  "paintpalette.fill"
        case .chalkboard:  "pencil.tip"
        case .photo:       "camera.fill"
        }
    }

    /// Ordered light → deep, like `ModelTheme.palette`.
    var styleColors: [Color] {
        switch self {
        case .stickFigure: [Color(hex: 0x9AA5B1), Color(hex: 0x4B5563)]
        case .lineArt:     [Color(hex: 0x8AB4F8), Color(hex: 0x4285F4)]
        case .flatIcon:    [Color(hex: 0x7C86F0), Color(hex: 0x5B4FD6)]
        case .cartoon:     [Color(hex: 0xFFD54F), Color(hex: 0xFB8C00)]
        case .storybook:   [Color(hex: 0xFF9EC0), Color(hex: 0xEC407A)]
        case .watercolor:  [Color(hex: 0x4DB6AC), Color(hex: 0x00897B)]
        case .chalkboard:  [Color(hex: 0x66BB6A), Color(hex: 0x2E5B34)]
        case .photo:       [Color(hex: 0x4FC3F7), Color(hex: 0x2196F3)]
        }
    }

    var styleAccent: Color { styleColors.last ?? .accentColor }

    var styleGradient: LinearGradient {
        LinearGradient(colors: styleColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - The row that opens the sheet

/// "Picture style · Flat Icon ›" — the one entry point, dropped anywhere the learner is already
/// thinking about card pictures (deck setup, the create-a-deck options, Settings ▸ Cards).
///
/// `mlxService` is optional and only used for the sample picture: the language model and the
/// diffusion pipeline don't fit together on 6 GB devices, so where a service is at hand it gets
/// unloaded first, exactly as `DeckIllustrationService` does before a run.
struct CardImageStyleRow: View {
    var mlxService: MLXGenerationService? = nil

    @AppStorage(CardImageStyle.defaultsKey) private var style: CardImageStyle = .flatIcon
    @AppStorage(CardImageDetail.defaultsKey) private var detail: CardImageDetail = .justTheWord
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: style.systemImage)
                    .foregroundStyle(style.styleAccent)
                    .frame(width: 26)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Picture style")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(style.label) · \(detail.label)")
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            CardImageStyleSheet(mlxService: mlxService)
        }
    }
}

// MARK: - The sheet

/// Picks the look of flashcard pictures, and how much the model is allowed to put in the frame.
/// Both settings apply to every picture drawn from here on; existing pictures only change if the
/// deck is redrawn from its start screen.
struct CardImageStyleSheet: View {
    var mlxService: MLXGenerationService? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CardImageStyle.defaultsKey) private var style: CardImageStyle = .flatIcon
    @AppStorage(CardImageDetail.defaultsKey) private var detail: CardImageDetail = .justTheWord

    @State private var sample = CardStyleSample.all[0]
    @State private var sampleImage: UIImage?
    @State private var sampleProgress: Double = 0
    @State private var isDrawing = false
    @State private var sampleError: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// One picture at a time: the pipeline is a single shared resource, and a deck run owns it
    /// while it lasts.
    private var canDrawSample: Bool {
        ImageGenModel.current.isDownloaded
            && !DeckIllustrationService.shared.isRunning
            && !StoryImageService.shared.isDownloading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailPicker
                    styleGrid
                    samplePanel
                }
                .padding(16)
            }
            .themedListScreen()
            .navigationTitle("Picture Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isDrawing)
        // Same reason as switching style: the sample on screen was drawn under the old setting.
        .onChange(of: detail) { _, _ in sampleImage = nil }
    }

    // MARK: Detail

    private var detailPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's in the picture")
                .font(.subheadline)
                .fontWeight(.medium)
            Picker("What's in the picture", selection: $detail) {
                ForEach(CardImageDetail.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Text(detail.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Styles

    private var styleGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Look")
                .font(.subheadline)
                .fontWeight(.medium)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CardImageStyle.allCases) { option in
                    CardStyleCard(style: option, isSelected: option == style) {
                        style = option
                        // The old sample is of a different style now; keeping it on screen next
                        // to a new selection would be a lie.
                        sampleImage = nil
                        sampleError = nil
                    }
                }
            }
        }
    }

    // MARK: Sample

    /// A style picker whose effect you can't see is a guess, so one sample word can be drawn here
    /// at Fast quality on a fixed seed: switching style changes the look, not the composition.
    @ViewBuilder
    private var samplePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Try it")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Menu {
                    ForEach(CardStyleSample.all) { option in
                        Button(option.english) { sample = option; sampleImage = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sample.english)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                }
                .disabled(isDrawing)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                if let sampleImage {
                    Image(uiImage: sampleImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if isDrawing {
                    VStack(spacing: 8) {
                        ProgressView(value: sampleProgress)
                            .frame(maxWidth: 160)
                        Text("Drawing a \(style.label.lowercased()) sample…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: style.systemImage)
                            .font(.title)
                            .foregroundStyle(style.styleAccent)
                        Text("No sample yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)

            if let sampleError {
                Label(sampleError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await drawSample() }
            } label: {
                Label(sampleImage == nil ? "Draw a sample" : "Draw it again",
                      systemImage: "wand.and.stars")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isDrawing || !canDrawSample)

            Text(sampleFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sampleFootnote: String {
        if !ImageGenModel.current.isDownloaded {
            return "Download the image model in Settings ▸ Model to draw samples."
        }
        if DeckIllustrationService.shared.isRunning {
            return "A deck is being illustrated right now. Samples wait their turn."
        }
        return "Drawn at Fast quality, so it's quicker than a real card picture. Your style applies to every picture drawn from now on."
    }

    private func drawSample() async {
        guard canDrawSample else { return }
        isDrawing = true
        sampleProgress = 0
        sampleError = nil
        defer { isDrawing = false; sampleProgress = 0 }

        // Same trade the deck run makes: the language model and the diffusion pipeline don't fit
        // together on smaller devices. It reloads lazily next time it's needed.
        mlxService?.unloadModel()

        let imageService = StoryImageService.shared
        guard await imageService.loadPipeline() else {
            sampleError = imageService.loadError ?? "Couldn't load the image model."
            return
        }
        defer { imageService.unloadPipeline() }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("card-style-sample.png")
        do {
            let written = try await imageService.generateImage(
                prompt: CardIllustrationPrompts.positivePrompt(
                    englishTranslation: sample.english, wordType: sample.wordType,
                    style: style, detail: detail
                ),
                negativePrompt: CardIllustrationPrompts.negativePrompt(style: style, detail: detail),
                saveTo: destination,
                stepCount: ImageGenQuality.fast.stepCount,
                seed: sample.seed,
                onStepProgress: { fraction in sampleProgress = fraction }
            )
            guard written, let image = UIImage(contentsOfFile: destination.path) else {
                sampleError = "The sample didn't come out. Try again."
                return
            }
            sampleImage = image
        } catch {
            sampleError = error.localizedDescription
        }
    }
}

// MARK: - Sample words

/// The words offered in the style picker's sample. Deliberately one of each shape the prompt
/// builder branches on, plus the kind of abstract compound that tempts the model into drawing a
/// cluttered poster instead of an object.
struct CardStyleSample: Identifiable, Equatable {
    let english: String
    let wordType: String?
    /// Fixed per word, so switching style redraws the same idea in a different look.
    let seed: UInt32

    var id: String { english }

    static let all: [CardStyleSample] = [
        CardStyleSample(english: "the bicycle", wordType: "noun", seed: 42),
        CardStyleSample(english: "the membership card", wordType: "noun", seed: 7),
        CardStyleSample(english: "to run", wordType: "verb", seed: 128),
        CardStyleSample(english: "happy", wordType: "adjective", seed: 2024),
    ]
}

// MARK: - Style card

/// One tappable style card: icon + label + subtitle on the style's gradient, with a selection ring.
/// Mirrors `StoryStyleSheet`'s card so the two pickers read as the same control.
private struct CardStyleCard: View {
    let style: CardImageStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: style.systemImage)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.label)
                        .font(.headline)
                        .lineLimit(1)
                    Text(style.subtitle)
                        .font(.caption)
                        .opacity(0.9)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(style.styleGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white, lineWidth: isSelected ? 3 : 0)
            }
            .shadow(color: style.styleAccent.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
