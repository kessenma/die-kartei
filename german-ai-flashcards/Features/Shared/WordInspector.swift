import SwiftUI

/// A word the learner tapped to inspect (translate + optionally save).
struct InspectedWord: Identifiable, Equatable {
    let id = UUID()
    let word: String
    var translation: String?
    var loading: Bool
    var saved: Bool
}

/// Anything that can drive the word inspector sheet: the conversation engine and the story
/// reader's `WordInspectorModel` both conform, so `WordInspectorSheet` works over either.
@MainActor
protocol WordInspecting: AnyObject {
    var inspectedWord: InspectedWord? { get }
    func saveInspectedWord()
    func dismissInspector()
}

/// The shared core of "double-tap a word": trim it and translate it 1:1 on-device.
enum SingleWordTranslator {
    /// Trim surrounding punctuation/whitespace but keep umlauts and hyphens.
    static func cleanWord(_ s: String) -> String {
        var allowed = CharacterSet.letters
        allowed.insert(charactersIn: "-'’")
        return s.trimmingCharacters(in: allowed.inverted)
    }

    /// Translate a single German word, loading `model` first if it isn't in memory.
    @MainActor
    static func translate(_ word: String, mlxService: MLXGenerationService, model: MLXModel) async -> String? {
        if !(mlxService.isModelLoaded && mlxService.currentModel == model) {
            await mlxService.loadModel(model)
            guard mlxService.isModelLoaded && mlxService.currentModel == model else { return nil }
        }
        do {
            let raw = try await mlxService.generateText(
                system: ConversationPrompts.translationSystemPrompt,
                user: ConversationPrompts.translationUserPrompt(german: word),
                model: model,
                maxTokens: 48
            )
            let cleaned = ConversationPrompts.cleanTranslation(raw)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }
}

/// A self-contained inspector driver for screens without a conversation engine (story reading).
/// The owner supplies where saved words go via `onSave`.
@Observable
@MainActor
final class WordInspectorModel: WordInspecting {
    private let mlxService: MLXGenerationService
    private let model: MLXModel
    private let isWordSaved: (String) -> Bool
    private let onSave: (_ german: String, _ english: String?) -> Void

    private(set) var inspectedWord: InspectedWord?

    init(
        mlxService: MLXGenerationService,
        model: MLXModel,
        isWordSaved: @escaping (String) -> Bool = { _ in false },
        onSave: @escaping (_ german: String, _ english: String?) -> Void
    ) {
        self.mlxService = mlxService
        self.model = model
        self.isWordSaved = isWordSaved
        self.onSave = onSave
    }

    func inspect(_ raw: String) {
        let word = SingleWordTranslator.cleanWord(raw)
        guard !word.isEmpty else { return }
        inspectedWord = InspectedWord(
            word: word,
            translation: nil,
            loading: true,
            saved: isWordSaved(word)
        )
        Task {
            let translation = await SingleWordTranslator.translate(word, mlxService: mlxService, model: model)
            // Only apply if the inspector is still showing the same word.
            if inspectedWord?.word == word {
                inspectedWord?.translation = translation
                inspectedWord?.loading = false
            }
        }
    }

    func saveInspectedWord() {
        guard let inspected = inspectedWord, !inspected.saved else { return }
        onSave(inspected.word, inspected.translation)
        inspectedWord?.saved = true
    }

    func dismissInspector() { inspectedWord = nil }
}

/// Shown when the user taps a word — its translation, hear-it, and a save-to-library action.
struct WordInspectorSheet: View {
    let source: any WordInspecting
    /// One line under the actions explaining where saved words end up in this context.
    let footer: String

    var body: some View {
        NavigationStack {
            Group {
                if let inspected = source.inspectedWord {
                    content(inspected)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { source.dismissInspector() }
                }
            }
            .presentationDetents([.height(300)])
        }
    }

    @ViewBuilder
    private func content(_ inspected: InspectedWord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(inspected.word)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if inspected.loading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Translating…").foregroundStyle(.secondary)
                }
            } else if let translation = inspected.translation, !translation.isEmpty {
                Text(translation).font(.title3).foregroundStyle(.secondary)
            } else {
                Text("No translation found.").font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button { SpeechService.shared.speak(inspected.word) } label: {
                    Label("Hear it", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                if inspected.saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button { source.saveInspectedWord() } label: {
                        Label("Save to flashcard library", systemImage: "rectangle.stack.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inspected.loading)
                }
            }

            Text(footer)
                .font(.caption2).foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
