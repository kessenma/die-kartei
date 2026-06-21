import SwiftUI

/// Review step shown after text extraction (PDF, link, or photo scan), before generation:
/// check the extracted text, choose how many cards to generate, or hand-pick the exact words.
struct ExtractedTextReviewView: View {
    let title: String
    let text: String
    /// Brand accent of the model that will generate the cards.
    var accent: Color = .accentColor
    /// Called when the user confirms. `selectedWords` is nil when the AI should pick the words itself.
    var onGenerate: (_ deckCount: Int, _ selectedWords: [String]?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var deckCount = 15
    @State private var pickWords = false
    @State private var selectedKeys = Set<String>()
    @State private var filter = ""
    @State private var words: [String] = []

    private var filteredWords: [String] {
        guard !filter.isEmpty else { return words }
        return words.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    /// Selected words in the order they appear in the text.
    private var orderedSelection: [String] {
        words.filter { selectedKeys.contains($0.lowercased()) }
    }

    private var totalWordCount: Int {
        text.split { $0 == " " || $0 == "\n" }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                deckSizeSection
                wordPickerSection
                extractedTextSection
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        let chosen = (pickWords && !selectedKeys.isEmpty) ? orderedSelection : nil
                        onGenerate(deckCount, chosen)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if words.isEmpty { words = Self.uniqueWords(in: text) }
            }
        }
    }

    // MARK: - Sections

    private var deckSizeSection: some View {
        Section {
            Stepper(value: $deckCount, in: 3...40) {
                HStack {
                    Text("Cards to generate")
                    Spacer()
                    Text("\(deckCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .disabled(pickWords && !selectedKeys.isEmpty)
        } header: {
            Text("Vocabulary deck")
        } footer: {
            if pickWords && !selectedKeys.isEmpty {
                Text("The deck will contain your \(selectedKeys.count) hand-picked words — the count above is ignored.")
                    .font(.caption2)
            } else {
                Text("The AI picks \(deckCount) useful words from the text. Or hand-pick exactly the words you want below.")
                    .font(.caption2)
            }
        }
    }

    private var wordPickerSection: some View {
        Section {
            Toggle("Hand-pick words", isOn: $pickWords.animation())
            if pickWords {
                TextField("Filter words…", text: $filter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(filteredWords, id: \.self) { word in
                        chip(word)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            if pickWords {
                Text("Words (\(selectedKeys.count) selected of \(words.count) unique)")
            } else {
                Text("Words")
            }
        } footer: {
            if pickWords {
                Text("Repeated forms are listed once. Each picked word becomes one card; picking many words takes longer to translate.")
                    .font(.caption2)
            }
        }
    }

    private var extractedTextSection: some View {
        Section("Extracted text · \(totalWordCount) words") {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func chip(_ word: String) -> some View {
        let key = word.lowercased()
        let isSelected = selectedKeys.contains(key)
        return Button {
            if isSelected { selectedKeys.remove(key) } else { selectedKeys.insert(key) }
        } label: {
            Text(word)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(isSelected ? accent : Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tokenizing

    /// Unique words in reading order, case-insensitively deduplicated
    /// (so conjugation tables don't repeat the same form four times).
    static func uniqueWords(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
            let word = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard word.count >= 2 else { continue }
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(word)
        }
        return result
    }
}
