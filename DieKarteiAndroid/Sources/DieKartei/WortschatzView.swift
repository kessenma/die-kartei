@testable import DieKarteiCore
import SwiftUI

/// The Goethe word lists (A1, A2, B1), read by the shared `GoetheVocabService`.
struct WortschatzView: View {
    /// Set when opened from a Library deck: that list only, no level picker.
    var fixedLevel: GoetheLevel? = nil
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var search = ""

    private var level: GoetheLevel { fixedLevel ?? GoetheLevel(rawValue: levelRaw) ?? .a1 }

    private var entries: [A1Entry] {
        let all = GoetheVocabService.entries(for: level)
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.word.lowercased().contains(query) || ($0.translation ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            Section {
                if fixedLevel == nil {
                    Picker("Niveau", selection: $levelRaw) {
                        ForEach(GoetheLevel.allCases) { level in
                            Text(level.rawValue).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Text("\(level.examName) · \(GoetheVocabService.entries(for: level).count) Wörter")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        GenderedWord(word: entry.word, article: entry.article)
                        if let translation = entry.translation, !translation.isEmpty {
                            Text(translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Wort suchen")
        .navigationTitle(fixedLevel.map { "Goethe \($0.rawValue)" } ?? "Wortschatz")
    }
}
