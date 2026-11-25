//
//  WorksheetWordsSheet.swift
//  german-ai-flashcards
//
//  "Wörter · the nouns of this lesson" into the course's flashcard deck. The words come from the
//  sheet itself (`LessonWordExtractor`: its "Nomen:" lines and vocabulary slides); the English is
//  the teacher's where she gave it, else the dictionary's, else the tutor's on request. Where the
//  dictionary disagrees with an article on the sheet the row says so and starts unticked rather
//  than being changed: the sheet may be right on purpose (her "das Café / der Café" note).
//

import SwiftUI
import SwiftData

struct WorksheetWordsSheet: View {
    let material: ClassMaterial
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var rows: [Row] = []
    /// Chunks from the exercises filled with her answer key (`KeyPhraseExtractor`).
    @State private var phrases: [PhraseRow] = []
    @State private var loading = true
    @State private var translating = false
    @State private var added: Int?

    private var course: ClassCourse? { material.entry?.course }
    private var accent: Color { ClassNotesTile.tint }

    struct Row: Identifiable {
        var word: LessonWord
        var english: String
        var picked: Bool
        var saved: Bool
        /// What the dictionary says instead, when it disagrees with the sheet.
        var dictionaryArticle: String?
        var id: String { word.id }
    }

    struct PhraseRow: Identifiable {
        var phrase: KeyPhrase
        var english: String
        var picked: Bool
        var saved: Bool
        var id: String { phrase.id }
    }

    private var pickedCount: Int {
        rows.filter { $0.picked && !$0.saved }.count + phrases.filter { $0.picked && !$0.saved }.count
    }

    private var missingEnglish: Bool {
        rows.contains { $0.english.isEmpty && $0.picked } || phrases.contains { $0.english.isEmpty && $0.picked && !$0.saved }
    }

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding the lesson's words…").foregroundStyle(.secondary)
                    }
                    .themedListRow()
                } else if rows.isEmpty && phrases.isEmpty {
                    Text("No noun list or vocabulary slide found in this PDF. Words you double-tap while reading the handout can still be saved one by one.")
                        .font(.subheadline)
                        .themedListRow()
                } else {
                    if !rows.isEmpty {
                    Section {
                        ForEach($rows) { $row in
                            wordRow($row)
                        }
                    } header: {
                        Text("Wörter · \(rows.count) in this lesson").themedSectionHeader()
                    } footer: {
                        Text("From the sheet's noun lists and vocabulary slides. English from the sheet where it gives one, else the dictionary.")
                            .font(.caption2)
                    }
                    .themedListRow()
                    }

                    if !phrases.isEmpty {
                        Section {
                            ForEach($phrases) { $row in
                                phraseRow($row)
                            }
                        } header: {
                            Text("Wortgruppen · \(phrases.count) from her answers").themedSectionHeader()
                        } footer: {
                            Text("Exercise lines filled in with her answer key. Each becomes a phrase card that hides its verb or preposition. Whole sentences start unticked.")
                                .font(.caption2)
                        }
                        .themedListRow()
                    }

                    if missingEnglish, !DocumentTutorChoice.downloaded.isEmpty {
                        Section {
                            DocumentTutorPicker(modelManager: modelManager)
                            Button {
                                Task { await fillEnglish() }
                            } label: {
                                HStack {
                                    Label("Fill in the missing English", systemImage: "character.book.closed")
                                    if translating { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(translating)
                        }
                        .themedListRow()
                    }
                }
            }
            .themedListScreen()
            .navigationTitle("Wörter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(added.map { "Added \($0)" } ?? "Add \(pickedCount)") { addToDeck() }
                        .fontWeight(.semibold)
                        .disabled(pickedCount == 0 || course == nil || added != nil)
                }
            }
            .task { await load() }
        }
    }

    private func wordRow(_ row: Binding<Row>) -> some View {
        let value = row.wrappedValue
        return HStack(spacing: 10) {
            Button {
                row.picked.wrappedValue.toggle()
            } label: {
                Image(systemName: value.saved ? "checkmark.circle.fill" : (value.picked ? "checkmark.circle.fill" : "circle"))
                    .foregroundStyle(value.saved ? Color.secondary : (value.picked ? accent : .secondary))
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(value.saved)
            VStack(alignment: .leading, spacing: 2) {
                Text.gendered(value.word.noun, article: value.word.article)
                    .font(.body.weight(.medium))
                if value.saved {
                    Text("Already in the deck").font(.caption2).foregroundStyle(.secondary)
                } else if let other = value.dictionaryArticle {
                    Text("The dictionary says \(other) \(value.word.noun)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            TextField("English", text: row.english)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 160)
                .disabled(value.saved)
        }
    }

    private func phraseRow(_ row: Binding<PhraseRow>) -> some View {
        let value = row.wrappedValue
        return HStack(spacing: 10) {
            Button {
                row.picked.wrappedValue.toggle()
            } label: {
                Image(systemName: value.saved || value.picked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(value.saved ? Color.secondary : (value.picked ? accent : .secondary))
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(value.saved)
            VStack(alignment: .leading, spacing: 2) {
                Text(value.phrase.german)
                    .font(.body.weight(.medium))
                if value.saved {
                    Text("Already in the deck").font(.caption2).foregroundStyle(.secondary)
                }
                TextField("English", text: row.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(value.saved)
            }
        }
    }

    // MARK: - Work

    private func load() async {
        guard loading else { return }
        defer { loading = false }
        guard let url = material.snapshotURL, let data = try? Data(contentsOf: url) else { return }
        let document = WorksheetDocumentActor(data: data)
        let pages = await document.allPages()
        let words = LessonWordExtractor.words(from: pages)
        let saved = course.map { ClassDeckStore.savedWords(for: $0, context: modelContext) } ?? []
        // Her key as the worksheet already read it, else read now (a handout never set up as homework).
        let key: [String: String]
        let samples: [String: String]
        if let setup = material.worksheet, let stored = setup.key {
            (key, samples) = (stored, setup.samples ?? [:])
        } else {
            let reading = await document.answerKey()
            (key, samples) = (reading.key, reading.samples)
        }
        phrases = KeyPhraseExtractor.phrases(from: pages, key: key, samples: samples).map { phrase in
            let isSaved = saved.contains(CardKind.matchKey(phrase.german))
            return PhraseRow(phrase: phrase, english: phrase.english ?? "", picked: !phrase.isSentence && !isSaved,
                             saved: isSaved)
        }
        rows = words.map { word in
            let dictionary = WiktionaryValidator.shared.nounArticle(for: word.noun)
            let disagrees = dictionary.map { $0.article.rawValue != word.article } ?? false
            // "die" for a plural noun isn't a disagreement with a singular entry.
            let plural = word.article == "die" && disagrees
            let flagged = disagrees && !plural
            let isSaved = saved.contains(ClassWord.key(word.german))
            return Row(word: word, english: word.english ?? dictionary?.english ?? "",
                       picked: !flagged && !isSaved, saved: isSaved,
                       dictionaryArticle: flagged ? dictionary?.article.rawValue : nil)
        }
    }

    private func fillEnglish() async {
        translating = true
        defer { translating = false }
        let service = DocumentDeckService(mlxService: mlxService, modelContext: modelContext)
        let missing = rows.filter { $0.english.isEmpty && $0.picked }.map(\.word.german)
            + phrases.filter { $0.english.isEmpty && $0.picked && !$0.saved }.map(\.phrase.german)
        let filled = await service.translate(missing.map { VocabListRow(german: $0, english: "") },
                                             model: DocumentTutorChoice.current(modelManager))
        for row in filled where !row.english.isEmpty {
            if let index = rows.firstIndex(where: { $0.word.german == row.german }) {
                rows[index].english = row.english
            } else if let index = phrases.firstIndex(where: { $0.phrase.german == row.german }) {
                phrases[index].english = row.english
            }
        }
    }

    private func addToDeck() {
        guard let course else { return }
        var count = 0
        for index in rows.indices where rows[index].picked && !rows[index].saved {
            let english = rows[index].english.trimmingCharacters(in: .whitespacesAndNewlines)
            if ClassDeckStore.saveWord(german: rows[index].word.german, english: english.isEmpty ? nil : english,
                                       course: course, feedsCoach: modelManager.storyFeedsCoach, context: modelContext) {
                count += 1
            }
            rows[index].saved = true
        }
        for index in phrases.indices where phrases[index].picked && !phrases[index].saved {
            let english = phrases[index].english.trimmingCharacters(in: .whitespacesAndNewlines)
            if ClassDeckStore.saveWord(german: phrases[index].phrase.german, english: english.isEmpty ? nil : english,
                                       course: course, feedsCoach: modelManager.storyFeedsCoach, context: modelContext) {
                count += 1
            }
            phrases[index].saved = true
        }
        try? modelContext.save()
        added = count
    }
}
