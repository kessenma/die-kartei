import SwiftUI

/// The posting as extracted text, paragraph by paragraph, through the same `SelectableGermanText`
/// the stories use: double-tap a word, select a phrase, saved words washed in the accent, looked-up
/// words underlined in red. The surface that always works, and the baseline the other two are
/// compared against.
struct JobPostingTextSurface: View {
    let text: String
    let decorations: JobReadingDecorations
    let callbacks: JobReadingCallbacks

    /// Split on blank lines; a posting pasted with single newlines still reads as one block, which
    /// the text view handles fine.
    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                SelectableGermanText(
                    text: paragraph,
                    textStyle: .body,
                    savedWords: decorations.savedWords,
                    glossary: decorations.glossary,
                    inlineGlosses: decorations.inlineGlosses,
                    lookedUpWords: decorations.lookedUpWords,
                    onTapWord: callbacks.onTapWord,
                    onTranslateSelection: callbacks.onTranslateSelection,
                    onSavePhrase: callbacks.onSavePhrase
                )
            }
        }
        .padding(.vertical, 4)
    }
}
