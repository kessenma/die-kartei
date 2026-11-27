//
//  JobVocabSaveSheet.swift
//  german-ai-flashcards
//
//  „Add to deck“ for many words at once: the words picked in a job ad (or ticked in the word
//  count), each with its English where the app already knows it, the tutor for the rest in one
//  batch, a deck to put them in, and one button. Every row stays editable — the German (the
//  tutor offers the dictionary form), the English, whether it goes in at all — and a phrase can
//  still be split into a card per word here.
//

import SwiftUI
import SwiftData

struct JobVocabSaveSheet: View {
    let picks: [JobVocabPick]
    /// The ad the words came from, when there is one: its own deck is offered first.
    var posting: JobPosting?
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// After saving: how many cards were added, and the picks that went in (to clear them).
    var onSaved: (_ added: Int, _ deckTitle: String, _ savedKeys: Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    @Query(sort: \JobPosting.updatedAt, order: .reverse) private var postings: [JobPosting]

    @State private var rows: [JobVocabRow] = []
    @State private var choice: JobVocabDeckChoice = .new
    @State private var newDeckName = ""
    @State private var translator: JobVocabTranslator?
    @State private var loaded = false
    /// For splitting compounds („Softwareentwicklung“ → Software + Entwicklung).
    @State private var lexicon = GermanCompoundLexicon()

    /// Decks a learner would add words to, job decks first.
    private var targetDecks: [SavedDeck] {
        let browsable = decks.filter { $0.isBrowsableContent && $0.id != posting?.deckID }
        return browsable.filter { $0.kind == .job } + browsable.filter { $0.kind != .job }
    }

    private var tutor: MLXModel {
        StoryStudyService.followUpModel(wrote: posting?.model, fallback: modelManager.selectedStoryModel)
    }

    private var included: [JobVocabRow] { rows.filter(\.include) }
    private var cardCount: Int { included.filter(\.makesCard).count }
    private var missingEnglish: Int { included.filter { $0.english.trimmingCharacters(in: .whitespaces).isEmpty }.count }

    var body: some View {
        NavigationStack {
            List {
                deckSection
                rowsSection
                if missingEnglish > 0 || translator?.isRunning == true {
                    tutorSection
                }
            }
            .themedListScreen()
            .navigationTitle("Add to a deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(cardCount == 0 ? "Add" : "Add \(cardCount)") { save() }
                        .disabled(cardCount == 0 || translator?.isRunning == true)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Sections

    private var deckSection: some View {
        Section {
            Picker("Deck", selection: $choice) {
                if let posting {
                    Text(JobDeckStore.deck(for: posting, context: modelContext)?.topic ?? "Job: \(posting.title)")
                        .tag(JobVocabDeckChoice.posting(posting.id))
                }
                ForEach(targetDecks) { deck in
                    Text(deck.topic).tag(JobVocabDeckChoice.existing(deck.id))
                }
                Text("New deck…").tag(JobVocabDeckChoice.new)
            }
            if choice == .new {
                TextField("Deck name", text: $newDeckName)
            }
        } header: {
            Text("Deck").themedSectionHeader()
        } footer: {
            if posting != nil, case .posting = choice {
                Text("This ad's own deck, also under Job prep ▸ Job decks.")
            }
        }
        .themedListRow()
    }

    private var rowsSection: some View {
        Section {
            ForEach($rows) { $row in
                let parts = splitParts(of: row)
                JobVocabRowEditor(row: $row, tutorReady: tutor.isDownloaded, compoundParts: compoundParts(of: row))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        if parts.count > 1 {
                            Button {
                                split(row, into: parts)
                            } label: {
                                Label("Split", systemImage: "scissors")
                            }
                            .tint(.indigo)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if parts.count > 1, !row.isPhrase {
                            Button {
                                addParts(of: row, parts: parts)
                            } label: {
                                Label("Add parts", systemImage: "plus.square.on.square")
                            }
                            .tint(.teal)
                        }
                    }
            }
        } header: {
            HStack {
                Text("Wörter").themedSectionHeader()
                Spacer()
                Text("\(included.count) of \(rows.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tap the circle to leave a word out. Swipe a phrase or a compound left to split it into a card per word, or a compound right to add its parts too. The sentence from the ad goes on the card as its example.")
                if missingEnglish > 0 {
                    Text("\(missingEnglish) without English \(missingEnglish == 1 ? "is" : "are") left out unless you type one or let the tutor translate.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .themedListRow()
    }

    @ViewBuilder
    private var tutorSection: some View {
        Section {
            if let translator, translator.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: translator.progress)
                    Text(translator.statusText).font(.caption).foregroundStyle(.secondary)
                }
            } else if tutor.isDownloaded {
                Button {
                    translate()
                } label: {
                    Label("Translate \(missingEnglish) with \(tutor.rawValue)", systemImage: "character.book.closed")
                }
                if let failure = translator?.failure {
                    Text(failure).font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("No tutor is downloaded, so type the English yourself — or download one in Settings ▸ Models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tutor").themedSectionHeader()
        } footer: {
            Text("The tutor also turns each word into its dictionary form: „Kenntnissen“ becomes „die Kenntnis“.")
        }
        .themedListRow()
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        var extra: [(word: String, noun: Bool, asWhole: Bool)] = []
        for deck in decks where deck.isBrowsableContent {
            for card in deck.cards { extra.append((card.germanWord, card.article != nil || card.wordType == "noun", true)) }
        }
        for token in JobVocabAnalyzer.tokens(in: posting?.text ?? "") {
            extra.append((token.text, token.text.first?.isUppercase == true, false))
        }
        lexicon = GermanCompoundLexicon.standard(extra: extra)
        let fresh = picks.map { JobVocabRow(german: $0.german, example: $0.example) }
        rows = JobVocabKnown.fill(fresh, from: JobVocabKnown.index(postings: postings, decks: decks))
        if let posting {
            choice = .posting(posting.id)
        } else if let firstJob = targetDecks.first(where: { $0.kind == .job }) {
            choice = .existing(firstJob.id)
        } else {
            choice = .new
        }
        if newDeckName.isEmpty { newDeckName = posting.map { "Job: \($0.title)" } ?? "Job-Wortschatz" }
    }

    /// A compound's parts, for its caption: from the word as it stood in the ad, so a tutor's
    /// dictionary form doesn't change the answer.
    private func compoundParts(of row: JobVocabRow) -> [String]? {
        guard !row.isPhrase else { return nil }
        return GermanCompound.split(CardKind.split(row.fromText).word, lexicon: lexicon)
            ?? GermanCompound.split(CardKind.split(row.german).word, lexicon: lexicon)
    }

    /// What „Split“ makes of a row: a phrase's content words, or a compound's parts.
    private func splitParts(of row: JobVocabRow) -> [String] {
        if row.isPhrase { return JobVocabAnalyzer.contentWords(of: row.german) }
        return compoundParts(of: row) ?? []
    }

    private func newRows(_ words: [String], example: String?) -> [JobVocabRow] {
        let existing = Set(rows.map { CardKind.matchKey($0.german) })
        let fresh = words.filter { !existing.contains(CardKind.matchKey($0)) }
        return JobVocabKnown.fill(fresh.map { JobVocabRow(german: $0, example: example) },
                                  from: JobVocabKnown.index(postings: postings, decks: decks))
    }

    private func split(_ row: JobVocabRow, into parts: [String]) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows.replaceSubrange(index...index, with: newRows(parts, example: row.example))
    }

    /// Keep the compound and add its parts after it.
    private func addParts(of row: JobVocabRow, parts: [String]) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows.insert(contentsOf: newRows(parts, example: row.example), at: index + 1)
    }

    private func translate() {
        let translator = translator ?? JobVocabTranslator(mlxService: mlxService)
        self.translator = translator
        let model = tutor
        Task {
            rows = await translator.translate(rows, model: model)
        }
    }

    private func save() {
        let deck: SavedDeck
        switch choice {
        case .posting:
            guard let posting else { return }
            deck = JobDeckStore.orCreateDeck(for: posting, context: modelContext)
        case .existing(let id):
            guard let found = decks.first(where: { $0.id == id }) else { return }
            deck = found
        case .new:
            deck = JobVocabSaver.makeDeck(named: newDeckName, context: modelContext)
        }
        let added = JobVocabSaver.save(rows, into: deck, feedsCoach: modelManager.storyFeedsCoach, context: modelContext)
        posting?.updatedAt = .now
        try? modelContext.save()
        // What went in, by the spelling it was picked as and the form it was saved as.
        var keys = Set<String>()
        for row in rows where row.include && row.makesCard {
            keys.insert(CardKind.matchKey(row.fromText))
            keys.insert(CardKind.matchKey(row.german))
        }
        onSaved(added, deck.topic, keys)
        dismiss()
    }
}

// MARK: - Row

/// One word on its way to a card: the tick, the German and English fields, and the sentence.
private struct JobVocabRowEditor: View {
    @Binding var row: JobVocabRow
    let tutorReady: Bool
    var compoundParts: [String]? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                row.include.toggle()
            } label: {
                Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.include ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(row.include ? "Included" : "Left out")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Deutsch", text: $row.german)
                        .font(.body.weight(.medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if row.isPhrase {
                        Text("Phrase")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                }
                HStack(spacing: 6) {
                    TextField(tutorReady ? "Tutor translates" : "English", text: $row.english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.never)
                    if let label = row.origin.label, !row.english.isEmpty {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let compoundParts {
                    Text(compoundParts.joined(separator: " + "))
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
                if row.german != row.fromText {
                    Text("In the ad: \(row.fromText)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let example = row.example, example.caseInsensitiveCompare(row.fromText) != .orderedSame {
                    Text(example)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .opacity(row.include ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}

// MARK: - Phrase or words

extension View {
    /// The question a stretch of several words asks: one phrase card, a card per word, or both.
    /// The answer goes into `basket`.
    func jobVocabSpanDialog(_ choice: Binding<JobVocabSpanChoice?>, basket: JobVocabBasket) -> some View {
        confirmationDialog(
            choice.wrappedValue.map { "„\($0.span)“" } ?? "",
            isPresented: Binding(get: { choice.wrappedValue != nil }, set: { if !$0 { choice.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: choice.wrappedValue
        ) { pending in
            Button("One phrase card") {
                basket.add(pending.span, example: pending.example)
            }
            if !pending.words.isEmpty {
                Button(pending.words.count == 1 ? "Just „\(pending.words[0])“" : "\(pending.words.count) word cards") {
                    for word in pending.words { basket.add(word, example: pending.example) }
                }
                if pending.words.count > 1 || CardKind.matchKey(pending.words[0]) != CardKind.matchKey(pending.span) {
                    Button("Both") {
                        basket.add(pending.span, example: pending.example)
                        for word in pending.words { basket.add(word, example: pending.example) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            if pending.words.count > 1 {
                Text("Word cards: \(pending.words.joined(separator: " · "))")
            }
        }
    }
}
