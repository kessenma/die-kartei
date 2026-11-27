import SwiftUI

/// A self-contained inspector driver for screens without a conversation engine (story reading).
/// The owner supplies where saved words go via `onSave`.
@Observable
@MainActor
final class WordInspectorModel: WordInspecting {
    private let mlxService: MLXGenerationService
    private let model: MLXModel
    private let isWordSaved: (String) -> Bool
    private let onSave: (_ german: String, _ english: String?) -> Void
    private let onLookup: (_ german: String, _ english: String) -> Void

    private(set) var inspectedWord: InspectedWord?

    /// The lookup in flight. Kept so a new tap replaces it and the owning screen can cancel it on
    /// the way out — a lookup can be waiting on a multi-GB model load, and there's no one left to
    /// receive it once the screen is gone.
    private var lookup: Task<Void, Never>?

    /// Translations the screen already has, keyed by the lowercased form the word appears in. The
    /// story reader fills this from the story's glossary: those words answer instantly, and without
    /// pulling a model into memory just to re-translate what's already on screen.
    var knownTranslations: [String: KnownTranslation] = [:]

    /// `onLookup` reports each word the model actually had to translate, for the owner to keep.
    init(
        mlxService: MLXGenerationService,
        model: MLXModel,
        isWordSaved: @escaping (String) -> Bool = { _ in false },
        onSave: @escaping (_ german: String, _ english: String?) -> Void,
        onLookup: @escaping (_ german: String, _ english: String) -> Void = { _, _ in }
    ) {
        self.mlxService = mlxService
        self.model = model
        self.isWordSaved = isWordSaved
        self.onSave = onSave
        self.onLookup = onLookup
    }

    func inspect(_ raw: String) {
        let word = SingleWordTranslator.cleanWord(raw)
        guard !word.isEmpty else { return }
        if let known = knownTranslations[word.lowercased()], !known.english.isEmpty {
            inspectedWord = InspectedWord(
                word: word,
                translation: known.english,
                loading: false,
                saved: isWordSaved(word),
                glossary: known
            )
            return
        }
        inspectedWord = InspectedWord(
            word: word,
            translation: nil,
            loading: true,
            loadingModel: !SingleWordTranslator.isReady(model, in: mlxService),
            saved: isWordSaved(word)
        )
        lookup?.cancel()
        lookup = Task {
            let translation = await SingleWordTranslator.translate(
                word,
                mlxService: mlxService,
                model: model,
                onModelReady: { [self] in
                    guard inspectedWord?.word == word else { return }
                    inspectedWord?.loadingModel = false
                }
            )
            guard !Task.isCancelled else { return }
            // Only apply if the inspector is still showing the same word.
            if inspectedWord?.word == word {
                inspectedWord?.translation = translation
                inspectedWord?.loading = false
                inspectedWord?.loadingModel = false
            }
            // Keep the answer: the next tap on this word is then instant and, more to the point,
            // costs no model load — including after the app has been restarted, since the owner
            // persists what it's handed.
            if let translation, !translation.isEmpty {
                knownTranslations[word.lowercased()] = KnownTranslation(
                    german: word, english: translation, source: .earlierLookup
                )
                onLookup(word, translation)
            }
        }
    }

    func saveInspectedWord() {
        guard let inspected = inspectedWord, !inspected.saved else { return }
        onSave(inspected.word, inspected.translation)
        inspectedWord?.saved = true
    }

    func dismissInspector() { inspectedWord = nil }

    /// The owning screen is going away: drop the sheet and stop waiting on a lookup. (The model
    /// load itself isn't cancelled — another screen may want it — only this screen's interest.)
    func tearDown() {
        lookup?.cancel()
        lookup = nil
        inspectedWord = nil
    }
}

/// Shown when the user taps a word — its translation, hear-it, and a save-to-library action.
struct WordInspectorSheet: View {
    let source: any WordInspecting
    /// One line under the actions explaining where saved words end up in this context.
    let footer: String

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NavigationStack {
            Group {
                if let inspected = source.inspectedWord {
                    content(inspected)
                } else {
                    Color.clear
                }
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle("Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { source.dismissInspector() }
                }
            }
            .presentationDetents([.height(340)])
        }
    }

    @ViewBuilder
    private func content(_ inspected: InspectedWord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text.gendered(inspected.word, article: inspected.article?.rawValue)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if inspected.loading {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(inspected.loadingModel ? "Getting the model ready…" : "Translating…")
                            .foregroundStyle(.secondary)
                    }
                    if inspected.loadingModel {
                        Text("The first word after opening the app waits for the model to load into memory. After that, lookups are quick.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if let translation = inspected.translation, !translation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(translation).font(.title3).foregroundStyle(.secondary)
                    if let glossary = inspected.glossary {
                        // Name the dictionary form when the text used an inflected one ("Katzen"
                        // tapped, "die Katze" listed).
                        let sameWord = glossary.german.caseInsensitiveCompare(inspected.word) == .orderedSame
                        switch glossary.source {
                        case .glossary:
                            Label(sameWord
                                  ? "From this story's glossary"
                                  : "From this story's glossary: \(glossary.german)",
                                  systemImage: "character.book.closed")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        case .earlierLookup:
                            Label("You looked this up earlier", systemImage: "clock.arrow.circlepath")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                Text("No translation found.").font(.callout).foregroundStyle(.secondary)
            }

            if let article = inspected.article {
                Text(ArticleRules.hint(for: inspected.word, article: article)?.hintLine(for: inspected.word)
                     ?? ArticleRules.noRuleHint(for: inspected.word, article: article))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                AskTeacherButton(prefill: "How do I use „\(inspected.word)“?", context: "Wort · \(inspected.word)", compact: true)
                    .buttonStyle(.bordered)
            }

            Text(footer)
                .font(.caption2).foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

/// Static stand-in so the sheet can be previewed without an engine or model.
@MainActor
private final class PreviewInspecting: WordInspecting {
    var inspectedWord: InspectedWord?
    init(_ word: InspectedWord) { inspectedWord = word }
    func saveInspectedWord() { inspectedWord?.saved = true }
    func dismissInspector() {}
}

#Preview("Inspector · gendered noun") {
    WordInspectorSheet(
        source: PreviewInspecting(InspectedWord(
            word: "Gabel",
            translation: "fork",
            loading: false,
            saved: false,
            article: .die
        )),
        footer: "Saved words become flashcards."
    )
}
