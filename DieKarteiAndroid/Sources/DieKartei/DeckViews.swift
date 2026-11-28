import SwiftUI
import GermanVoice
@testable import DieKarteiCore
@testable import KarteiStore

// MARK: - Library section

/// Library ▸ My decks: the learner's own decks, as iOS's Library lists them. Tap to study (in the
/// card style from Settings, as iOS), swipe left to delete, right to share; ⓘ shows past results.
struct UserDecksSection: View {
    @State var library = DeckLibrary.shared
    @State var studying: DeckRecord?
    @State var statsFor: DeckRecord?

    var body: some View {
        Section {
            if library.decks.isEmpty {
                Text("No saved decks yet. Open a .kartei file sent from the iPhone, or import one.")
                    .foregroundStyle(.secondary)
            }
            ForEach(library.decks, id: \.id) { deck in
                HStack {
                    Button { studying = deck } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deck.topic).foregroundStyle(Color.primary)
                            let count = library.cards(of: deck).count
                            Text("\(count) cards · \(library.dueCount(of: deck)) due")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    if !library.results(of: deck).isEmpty {
                        Button { statsFor = deck } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { library.delete(deck) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { library.share(deck) } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
            Button {
                if !DeckFiles.shared.pick() { library.problem = "Files can't be opened here." }
            } label: {
                Label("Import deck", systemImage: "tray.and.arrow.down")
            }
        } header: {
            Text("My decks")
        }
        .sheet(item: $studying) { deck in
            NavigationStack { DeckSessionView(deck: deck) }
        }
        .sheet(item: $statsFor) { deck in
            NavigationStack { DeckResultsView(deck: deck) }
        }
    }
}

extension DeckRecord: Identifiable {}

// MARK: - Import

/// A `.kartei` file waiting to come in (iOS `DeckImportSheet`): what it holds, then Add, or
/// Replace / Keep both when the deck is already here.
struct DeckImportSheet: View {
    let request: DeckLibrary.PendingImport
    @Environment(\.dismiss) var dismiss

    var deck: DeckTransferEnvelope.Deck { request.envelope.deck }

    var body: some View {
        List {
            Section {
                LabeledContent("Topic", value: deck.topic)
                LabeledContent("Cards", value: "\(deck.cards.count)")
                if request.envelope.includesProgress {
                    LabeledContent("Progress") {
                        Label("Included", systemImage: "checkmark.circle.fill").foregroundStyle(Color.green)
                    }
                }
                LabeledContent("Shared", value: request.envelope.exportedAt.formatted(date: .abbreviated, time: .omitted))
            } header: {
                Text("Deck importieren · Import deck")
            }
            if !request.envelope.includesImages && !deck.cards.isEmpty {
                Section {
                    Label("Card pictures stay on the device that drew them.", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if request.existing != nil {
                Section {
                    Button { take(.replace) } label: {
                        Label("Replace my copy", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { take(.keepBoth) } label: {
                        Label("Keep both", systemImage: "rectangle.stack.badge.plus")
                    }
                } header: {
                    Text("You already have this deck")
                } footer: {
                    Text("Replacing takes the arriving deck's cards and progress. Keeping both leaves your copy untouched and adds a second one.")
                }
            } else {
                Section {
                    Button { take(.keepBoth) } label: {
                        Label("Add to my decks", systemImage: "tray.and.arrow.down")
                    }
                }
            }
        }
        .navigationTitle("Import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    DeckLibrary.shared.pending = nil
                    dismiss()
                }
            }
        }
    }

    func take(_ mode: DeckTransferRecords.Mode) {
        DeckLibrary.shared.importPending(mode)
        dismiss()
    }
}

// MARK: - Studying

/// One session over a deck, in the card style Settings ▸ Cards picks (Classic by default, as on
/// iOS): Classic plays every card once, marked known or not; Anki plays the due cards with the
/// four ratings, a missed card coming back three cards later. Ends with a result on the deck.
struct DeckSessionView: View {
    let deck: DeckRecord
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    @State var cards: [CardRecord] = []
    @State var style: FlashcardStyle = .default
    @State var anki = AnkiRound(order: [])
    @State var classic = ClassicRound(order: [])
    @State var flipped = false
    @State var startedAt = Date()
    @State var finished: (correct: Int, total: Int)?
    /// Today's log: a finished session counts its cards; one left early still banks its time.
    @State var studyRound = StudyRound { .cards($0) }
    @State var counted: Set<Int> = []
    @State var started = false

    var current: Int? { style == .anki ? anki.current : classic.current }
    var sessionSize: Int { style == .anki ? anki.dueCount : classic.order.count }

    var body: some View {
        VStack(spacing: 16) {
            if let finished {
                Spacer()
                Text("\(finished.correct) of \(finished.total) known").font(.title2)
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                Spacer()
            } else if let index = current, cards.indices.contains(index) {
                Text("Card \(min(counted.count + 1, sessionSize)) of \(sessionSize)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                StudyCardFace(word: cards[index].germanWord, article: cards[index].article,
                              translation: cards[index].englishTranslation, example: cards[index].exampleSentence,
                              flipped: flipped)
                    .onTapGesture { flipped.toggle() }
                if !flipped {
                    Button("Umdrehen") { flipped = true }.buttonStyle(.borderedProminent)
                } else if style == .anki {
                    ankiButtons(cards[index])
                } else {
                    HStack(spacing: 40) {
                        Button { answer(index, knewIt: false) } label: {
                            Image(systemName: "xmark.circle").font(.largeTitle).foregroundStyle(Color.red)
                        }
                        Button { answer(index, knewIt: true) } label: {
                            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(Color.green)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            } else if started {
                Spacer()
                Text(style == .anki ? "Nothing due in this deck." : "This deck has no cards.")
                Button("Done") { dismiss() }.buttonStyle(.bordered)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(deck.topic)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            // The card style, as iOS's player offers it; saved where Settings ▸ Cards keeps it.
            ToolbarItem(placement: .primaryAction) {
                Menu(style == .anki ? "Anki" : "Classic") {
                    Button("Classic") { switchStyle(.default) }
                    Button("Anki") { switchStyle(.anki) }
                }
                .disabled(!counted.isEmpty || finished != nil)
            }
        }
        .onAppear { if !started { begin() } }
        .onDisappear { studyRound.finish() }
    }

    func ankiButtons(_ card: CardRecord) -> some View {
        var previews: [AnkiRating: String] = [:]
        for preview in SRSScheduling.previewIntervals(for: StudyCard(card)) { previews[preview.rating] = preview.label }
        return VStack(spacing: 6) {
            Text("Only Didn't know counts as a miss. Hard, Good and Easy all mean you knew it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(AnkiRating.allCases, id: \.rawValue) { rating in
                    Button { rate(rating) } label: {
                        VStack(spacing: 2) {
                            Text(rating.label).font(.caption).lineLimit(1)
                            Text(previews[rating] ?? "").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    func begin() {
        started = true
        cards = DeckLibrary.shared.cards(of: deck)
        // Leitner isn't on Android yet: its boxes need the deck's session count; Anki stands in.
        let chosen = AnkiSessionRules.flashcardStyle()
        style = chosen == .leitner ? .anki : chosen
        let shuffle = AnkiSessionRules.shuffle()
        anki = AnkiRound(order: AnkiSessionRules.dueOrder(cards.map(\.nextReviewDate), now: Date(), shuffle: shuffle))
        classic = ClassicRound(order: AnkiSessionRules.classicOrder(count: cards.count, shuffle: shuffle))
        startedAt = Date()
        studyRound.start()
    }

    func switchStyle(_ chosen: FlashcardStyle) {
        SharedDefaults.store.set(chosen.rawValue, forKey: AnkiSessionRules.flashcardStyleKey)
        begin()
    }

    func rate(_ rating: AnkiRating) {
        guard let index = anki.current else { return }
        cards[index] = DeckLibrary.shared.rate(cards[index], rating)
        if counted.insert(index).inserted { studyRound.add() }
        anki.rate(rating, repeatMissed: AnkiSessionRules.repeatMissed())
        flipped = false
        if anki.isFinished {
            let t = anki.tally
            finish(correct: t.correct, total: t.total, missed: t.missed, ratings: anki.firstRatings)
        }
    }

    func answer(_ index: Int, knewIt: Bool) {
        classic.answer(knewIt: knewIt)
        if counted.insert(index).inserted { studyRound.add() }
        flipped = false
        if classic.isFinished {
            // As iOS: a Classic session stamps each card's last answer once it ends.
            for (i, knew) in classic.results where cards.indices.contains(i) {
                DeckLibrary.shared.note(cards[i], knewIt: knew)
            }
            let t = classic.tally
            finish(correct: t.correct, total: t.total, missed: t.missed, ratings: nil)
        }
    }

    func finish(correct: Int, total: Int, missed: [Int], ratings: [Int: AnkiRating]?) {
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        DeckLibrary.shared.saveResult(.cardSession(deck: deck.id, correct: correct, total: total, missed: missed,
                                                   seconds: seconds, mode: style, ankiRatings: ratings,
                                                   subDeckLabel: nil))
        studyRound.finish()
        finished = (correct, total)
    }
}

/// A deck's past sessions (iOS `DeckStatsSheet`, in short).
struct DeckResultsView: View {
    let deck: DeckRecord
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List(DeckLibrary.shared.results(of: deck), id: \.id) { result in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.correctCount) of \(result.totalCards) · \(FlashcardStyle(rawValue: result.studyModeRaw)?.rawValue ?? result.studyModeRaw)")
                Text(result.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(deck.topic)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
    }
}

/// A card's face: the word (with its gender colour), read aloud on tap of the speaker, the
/// translation and example once flipped.
struct StudyCardFace: View {
    let word: String
    let article: String?
    let translation: String?
    let example: String?
    let flipped: Bool
    @Environment(\.colorScheme) var scheme

    var tint: Color {
        guard let article, let gender = Gender(article: article) else { return Color.gray }
        return AndroidPalette.gender(gender, dark: scheme == .dark)
    }

    var body: some View {
        VStack(spacing: 12) {
            GenderedWord(word: word, article: article).font(.largeTitle)
            Button {
                GermanVoice.shared.speak([article, word].compactMap { $0 }.joined(separator: " "), slow: false)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            if flipped {
                Text(translation ?? "–").font(.title2)
                if let example, !example.isEmpty {
                    Text(example)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Tippen zum Umdrehen").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint, lineWidth: 2))
    }
}

// MARK: - Phrases to flashcards

/// Saved phrases as flashcards (iOS `PhraseToDeckSheet`): pick phrases, then a new deck or one of
/// the learner's; the cards are `PhraseCards`' (shared).
struct PhraseDeckSheet: View {
    let phrases: [LearnedPhraseRecord]
    @Environment(\.dismiss) var dismiss
    @State var selected: Set<UUID> = []
    @State var deckID: UUID?
    @State var newDeckName = PhraseCards.newDeckName
    @State var summary: String?

    var decks: [DeckRecord] { DeckLibrary.shared.decks }
    var allSelected: Bool { !phrases.isEmpty && selected.count == phrases.count }

    var body: some View {
        Form {
            if let summary {
                Section {
                    Label(summary, systemImage: "checkmark.circle.fill").foregroundStyle(Color.green)
                    Button("Done") { dismiss() }
                }
            } else {
                Section {
                    ForEach(phrases, id: \.id) { phrase in
                        Button { toggle(phrase.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(phrase.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(phrase.german).foregroundStyle(Color.primary)
                                    if !phrase.english.isEmpty {
                                        Text(phrase.english).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    HStack {
                        Text("Phrases (\(selected.count) selected)")
                        Spacer()
                        Button(allSelected ? "Deselect all" : "Select all") {
                            selected = allSelected ? [] : Set(phrases.map(\.id))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section {
                    Picker("Add to", selection: $deckID) {
                        Text("New deck").tag(UUID?.none)
                        ForEach(decks, id: \.id) { deck in
                            Text("\(deck.topic) (\(DeckLibrary.shared.cards(of: deck).count))").tag(Optional(deck.id))
                        }
                    }
                    if deckID == nil {
                        TextField("Deck name", text: $newDeckName)
                    }
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Each phrase becomes one card. Merging skips phrases already in the deck.")
                }
                Section {
                    Button { save() } label: {
                        Label(deckID == nil ? "Create deck" : "Add to deck", systemImage: "rectangle.stack.badge.plus")
                    }
                    .disabled(selected.isEmpty || (deckID == nil && newDeckName.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
        }
        .navigationTitle("Add to flashcards")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        // A fresh start each time: Skip keeps a sheet's state between presentations.
        .onAppear {
            summary = nil
            deckID = nil
            newDeckName = PhraseCards.newDeckName
            selected = Set(phrases.map(\.id))
        }
    }

    func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func save() {
        let chosen = phrases.filter { selected.contains($0.id) }
            .map { PhraseCards.Phrase(german: $0.german, english: $0.english) }
        guard !chosen.isEmpty else { return }
        if let deckID, let deck = decks.first(where: { $0.id == deckID }) {
            summary = DeckLibrary.shared.addPhrases(chosen, to: deck)
        } else {
            summary = DeckLibrary.shared.newPhraseDeck(chosen, name: newDeckName)
        }
    }
}
