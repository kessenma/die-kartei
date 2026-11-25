import SwiftUI

/// A quick review shown right before a scenario chat that has saved phrases in rotation. It lists the
/// few phrases the AI will try to work in (English-forward, so you confirm you want them), lets you
/// drop any for this session, and warms up (loads) the model in the background while you read.
struct ConversationPhrasePreviewView: View {
    let phrases: [LearnedPhrase]
    let model: MLXModel
    var mlxService: MLXGenerationService
    /// Called with the phrases the user kept for this session.
    let onBegin: ([LearnedPhrase]) -> Void

    @State private var selected: Set<UUID>
    @State private var revealGerman = false

    init(
        phrases: [LearnedPhrase],
        model: MLXModel,
        mlxService: MLXGenerationService,
        onBegin: @escaping ([LearnedPhrase]) -> Void
    ) {
        self.phrases = phrases
        self.model = model
        self.mlxService = mlxService
        self.onBegin = onBegin
        _selected = State(initialValue: Set(phrases.map(\.id)))
    }

    private var modelReady: Bool {
        mlxService.isModelLoaded && mlxService.currentModel == model
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text("These phrases from your library will be woven into this chat — the AI's character will say them so you get used to hearing them. Uncheck any you don't want this time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "ear.badge.waveform").foregroundStyle(.tint)
                }
            }
            .themedListRow()

            Section {
                ForEach(phrases) { phrase in
                    row(phrase)
                }
            } header: {
                HStack {
                    Text("Phrases you'll hear").themedSectionHeader()
                    Spacer()
                    Button(revealGerman ? "Hide German" : "Reveal German") {
                        withAnimation { revealGerman.toggle() }
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Before you start")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if modelReady {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(model.rawValue) ready").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                        Text(mlxService.downloadInfo ?? "Warming up \(model.rawValue)…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let progress = mlxService.downloadProgress, progress > 0, !modelReady {
                    ProgressView(value: progress).tint(model.theme.accent)
                }
                Button {
                    onBegin(phrases.filter { selected.contains($0.id) })
                } label: {
                    Text("Begin conversation")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.theme.accent)
            }
            .padding()
            .background(.bar)
        }
        .task {
            if !modelReady { await mlxService.loadModel(model) }
        }
    }

    private func row(_ phrase: LearnedPhrase) -> some View {
        let on = selected.contains(phrase.id)
        return Button {
            if on { selected.remove(phrase.id) } else { selected.insert(phrase.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 3) {
                    Text(phrase.english)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if revealGerman {
                        Text(phrase.german)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    SpeechService.shared.speak(phrase.german)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
            }
            .opacity(on ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
