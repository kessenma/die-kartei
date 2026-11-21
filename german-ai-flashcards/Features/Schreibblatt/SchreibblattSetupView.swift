//
//  SchreibblattSetupView.swift
//  german-ai-flashcards
//
//  The knobs, after the words have been picked. There is deliberately no word-count stepper:
//  rows per table *is* the number of words the learner selected, and a second control saying
//  otherwise would contradict the screen they just came from.
//
//  Shaped like `TabelleSetupView`: a `List` of sections each bound to an `@AppStorage` key, and a
//  Start section at the bottom.
//
//  Aufteilen: more words than one sheet should hold are written in parts, a sheet of
//  `schreibblatt.partSize` words at a time (balanced, `SchreibblattParts.sizes`), all made at once
//  and listed in the hub as one set. A selection bigger than a page is always split, never cut.
//

import SwiftData
import SwiftUI

struct SchreibblattSetupView: View {
    let words: [SchreibblattWord]
    let sourceDeckIDs: [UUID]
    /// Each word's deck, so each part names only its own decks. Empty: every part gets all of them.
    var deckOfWord: [UUID: UUID] = [:]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("schreibblatt.repetitions") private var repetitions = 5
    @AppStorage("schreibblatt.prefillEnglish") private var prefillEnglish = true
    @AppStorage("schreibblatt.orientation") private var orientation: SchreibblattOrientation = .portrait
    @AppStorage("schreibblatt.arrangement") private var arrangement: SchreibblattArrangement = .pages
    @AppStorage("schreibblatt.notebookLines") private var notebookLines = true
    @AppStorage("schreibblatt.partSize") private var partSize = 10

    @State private var sheet: SchreibblattSheet?

    private var format: Binding<SchreibblattFormat> {
        Binding {
            SchreibblattFormat(orientation: orientation, arrangement: arrangement)
        } set: { format in
            orientation = format.orientation
            arrangement = format.arrangement
        }
    }

    /// The most words a part holds: the picker's own limit, a page upright.
    private var pageLimit: Int { SchreibblattLayout.maxWordCount() }

    /// Splitting is on offer once there are words for two parts of the smallest size.
    private var canSplit: Bool { words.count > SchreibblattParts.minPartSize }

    /// The stepper's range: the smallest part up to a full page, or all the words if fewer.
    private var partRange: ClosedRange<Int> {
        SchreibblattParts.minPartSize...max(SchreibblattParts.minPartSize, min(pageLimit, words.count))
    }

    /// The stored size, held to what this selection allows.
    private var effectivePartSize: Binding<Int> {
        Binding {
            min(max(partSize, partRange.lowerBound), partRange.upperBound)
        } set: { partSize = $0 }
    }

    /// How the words are shared out: one sheet, or several.
    private var parts: [[SchreibblattWord]] {
        canSplit ? SchreibblattParts.split(words, partSize: effectivePartSize.wrappedValue) : [words]
    }

    /// The largest part: what the format picture and the repetition limit are measured on.
    private var sampleWords: [SchreibblattWord] { parts.max { $0.count < $1.count } ?? words }

    /// What a sheet will be, measured the way `SchreibblattSheet.init` measures it.
    private var layout: SchreibblattLayout {
        SchreibblattLayout(
            words: sampleWords, repetitions: min(repetitions, maxRepetitions), prefillEnglish: prefillEnglish,
            englishColumnWidth: SchreibblattRenderer.englishColumnWidth(for: sampleWords, prefillEnglish: prefillEnglish),
            paper: format.wrappedValue.paper(wordCount: sampleWords.count, repetitions: min(repetitions, maxRepetitions)))
    }

    private var maxRepetitions: Int {
        format.wrappedValue.maxRepetitions(wordCount: sampleWords.count)
    }

    var body: some View {
        List {
            Section {
                Stepper(value: $repetitions, in: 1...maxRepetitions) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Wiederholungen")
                        Text(repetitions == 1
                             ? "Write each word once"
                             : "Write each word \(repetitions) times")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $prefillEnglish) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Englisch vorgedruckt")
                        Text(prefillEnglish
                             ? "The English is printed; you write the German"
                             : "Both columns are blank; you write both")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $notebookLines) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Heftlinien")
                        Text(notebookLines
                             ? "Ruled like an exercise book around the tables"
                             : "Plain white paper around the tables")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Das Blatt").themedSectionHeader()
            } footer: {
                Text("A Vorlage with both columns filled in sits at the top of every page, so the "
                     + "word you are copying is always in front of you.")
            }
            .themedListRow()

            if canSplit {
                Section {
                    Stepper(value: effectivePartSize, in: partRange) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Wörter pro Blatt · \(effectivePartSize.wrappedValue)")
                            Text(partsSummary)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityValue(partsSummary)
                } header: {
                    Text("Aufteilen · In parts").themedSectionHeader()
                } footer: {
                    Text(parts.count > 1
                         ? "Write one part at a time; Schreibblatt keeps your place. Each part you finish "
                           + "is a checkpoint: practice it, the last two parts, or everything so far as flashcards."
                         : (words.count > pageLimit
                            ? "A sheet holds at most \(pageLimit) words, so this many are written in parts."
                            : "All on one sheet. Fewer words per sheet splits them into parts to write one at a time."))
                }
                .themedListRow()
            }

            Section {
                SchreibblattFormatPicker(format: format, wordCount: layout.wordCount,
                                         repetitions: min(repetitions, maxRepetitions))
                    .padding(.vertical, 4)
            } header: {
                Text("Format").themedSectionHeader()
            } footer: {
                Text("Long German phrases get the widest rows upright, or in an endless list.")
            }
            .themedListRow()

            Section {
                Button {
                    start()
                } label: {
                    Label(startTitle, systemImage: "hand.draw")
                }
                .disabled(words.isEmpty)
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Schreibblatt")
        .navigationDestination(item: $sheet) { SchreibblattSheetView(sheet: $0) }
    }

    /// "50 words → 5 sheets of 10".
    private var partsSummary: String {
        let sizes = parts.map(\.count)
        guard sizes.count > 1 else { return "All \(words.count) words on one sheet" }
        return "\(words.count) words → \(sizes.count) sheets of \(SchreibblattParts.sizeLabel(sizes))"
    }

    private var startTitle: String {
        if parts.count > 1 {
            return ThisDevice.kind == .iPad ? "Schreiben · Teil 1 von \(parts.count)" : "\(parts.count) Blätter erstellen"
        }
        return ThisDevice.kind == .iPad ? "Schreiben" : "Blatt erstellen"
    }

    private func start() {
        let groups = parts
        let reps = min(repetitions, maxRepetitions)
        guard groups.count > 1 else {
            let made = makeSheet(title: Self.defaultTitle(for: words), words: words,
                                 repetitions: reps, deckIDs: sourceDeckIDs)
            modelContext.insert(made)
            try? modelContext.save()
            sheet = made
            return
        }

        // Every part at once, so the set's row knows its whole length and any part can be opened.
        let seriesID = UUID()
        let base = seriesTitle
        let now = Date()
        let made = groups.enumerated().map { index, group in
            let part = makeSheet(title: "\(base) · Teil \(index + 1) von \(groups.count)", words: group,
                                 repetitions: reps, deckIDs: decks(of: group),
                                 // A second apart, newest last, so a list by date reads in order.
                                 createdAt: now.addingTimeInterval(Double(index - groups.count)))
            part.seriesID = seriesID
            part.partIndex = index
            part.partCount = groups.count
            part.seriesTitle = base
            return part
        }
        made.forEach(modelContext.insert)
        try? modelContext.save()
        sheet = made.first
    }

    private func makeSheet(title: String, words: [SchreibblattWord], repetitions: Int, deckIDs: [UUID],
                           createdAt: Date = Date()) -> SchreibblattSheet {
        SchreibblattSheet(
            title: title,
            words: words,
            repetitions: repetitions,
            prefillEnglish: prefillEnglish,
            orientation: orientation,
            arrangement: arrangement,
            notebookLines: notebookLines,
            sourceDeckIDs: deckIDs,
            createdAt: createdAt
        )
    }

    /// The decks one part's words came from.
    private func decks(of group: [SchreibblattWord]) -> [UUID] {
        guard !deckOfWord.isEmpty else { return sourceDeckIDs }
        var seen = Set<UUID>()
        return group.compactMap { deckOfWord[$0.id] }.filter { seen.insert($0).inserted }
    }

    /// A set from one deck is named after it; from several, after its first word.
    private var seriesTitle: String {
        if sourceDeckIDs.count == 1, let id = sourceDeckIDs.first,
           let deck = try? modelContext.fetch(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })).first,
           !deck.topic.isEmpty {
            return deck.topic
        }
        return Self.defaultTitle(for: words)
    }

    /// The first word, so a list of sheets reads as something rather than a row of dates.
    static func defaultTitle(for words: [SchreibblattWord]) -> String {
        guard let first = words.first else { return "Schreibblatt" }
        let noun = ArticleGameService.bareNoun(first.german)
        return words.count == 1 ? noun : "\(noun) +\(words.count - 1)"
    }
}
