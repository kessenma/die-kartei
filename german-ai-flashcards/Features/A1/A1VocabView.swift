import DieKarteiCore
import SwiftUI
import SwiftData

struct GoetheLevelPickerView: View {
    var onStartStudy: (_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void

    @State private var selectedLevel: GoetheLevel = .a1

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        Image("logo-goethe")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 48)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Select Level") {
                    ForEach(GoetheLevel.allCases) { level in
                        Button {
                            selectedLevel = level
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(level.examName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(level.description)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if selectedLevel == level {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        GoetheVocabListView(level: selectedLevel, onStartStudy: onStartStudy)
                    } label: {
                        Label("Browse \(selectedLevel.rawValue) Words", systemImage: "text.magnifyingglass")
                    }
                }
            }
            .navigationTitle("Goethe Vocabulary")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct GoetheVocabListView: View {
    let level: GoetheLevel
    var onStartStudy: (_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void
    var onStartPastTenseStudy: ((_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedWordType: A1WordTypeFilter = .all
    @State private var cardCount = 20
    @State private var selectedStyle: FlashcardStyle = .default
    @State private var showingPDFInfo = false
    @State private var showPastTenseGuide = false
    @State private var pausedSession: (deck: SavedDeck, progress: DeckSessionProgress)? = nil
    @State private var allEntries: [A1Entry] = []
    @State private var isLoading = true

    private let cardCountOptions = [10, 20, 30, 50, 100]

    private var matchingPastTenseLevel: PastTenseLevel {
        switch level {
        case .a1: return .a1
        case .a2: return .a2
        case .b1: return .b1
        }
    }

    private var filteredEntries: [A1Entry] {
        allEntries.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.word.localizedCaseInsensitiveContains(searchText) ||
                (entry.translation?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesType: Bool
            switch selectedWordType {
            case .all: matchesType = true
            case .nouns: matchesType = entry.article != nil
            case .verbs: matchesType = entry.wordType == "verb"
            case .other: matchesType = entry.article == nil && entry.wordType != "verb"
            }
            return matchesSearch && matchesType
        }
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        Image("logo-goethe")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 36)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                studySection
                pastTenseSection
                wordListSection
            }
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .searchable(text: $searchText, prompt: "Search words or translations")
        .navigationTitle("\(level.rawValue) Vocabulary")
        .navigationBarTitleDisplayMode(.large)
        .task {
            let entries = GoetheVocabService.entries(for: level)
            allEntries = entries
            isLoading = false
            loadPausedSession()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPDFInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingPDFInfo) {
            pdfInfoSheet
        }
        .sheet(isPresented: $showPastTenseGuide) {
            SeinHabenGuideView()
        }
    }

    @ViewBuilder
    private var studySection: some View {
        Section {
            if let (_, progress) = pausedSession {
                HStack(spacing: 12) {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paused session")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Card \(progress.cardIndex + 1) of \(progress.cardGermanWords?.count ?? 0) · \(formattedElapsed(progress.elapsedSeconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Resume") {
                        resumePausedSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }

            Picker("Word types", selection: $selectedWordType) {
                ForEach(A1WordTypeFilter.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Picker("Cards to study", selection: $cardCount) {
                ForEach(cardCountOptions, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
                Text("All (\(filteredEntries.count))").tag(filteredEntries.count)
            }

            Picker("Study mode", selection: $selectedStyle) {
                ForEach(FlashcardStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            Button(action: startStudy) {
                Label("Study \(min(cardCount, filteredEntries.count)) Cards", systemImage: "rectangle.stack.fill")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(filteredEntries.isEmpty)
        } header: {
            HStack {
                Text("Study")
                Spacer()
                Text("\(filteredEntries.count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Official Goethe-Institut \(level.rawValue) word list (\(level.examName)).")
        }
    }

    @ViewBuilder
    private var pastTenseSection: some View {
        Section {
            Button {
                showPastTenseGuide = true
            } label: {
                Label("Grammar Guide: sein vs. haben", systemImage: "book.closed.fill")
                    .foregroundStyle(.purple)
            }

            NavigationLink {
                PastTenseLevelView(level: matchingPastTenseLevel) { cards, topic, style, label in
                    onStartPastTenseStudy?(cards, topic, style, label)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(level.rawValue) Perfekt Verbs")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(matchingPastTenseLevel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Perfekt Verbs")
        } footer: {
            Text("Practice auxiliary verbs (sein/haben), past participles, and separable prefixes.")
        }
    }

    @ViewBuilder
    private var wordListSection: some View {
        Section("Word List") {
            ForEach(filteredEntries, id: \.word) { entry in
                A1EntryRow(entry: entry)
            }
        }
    }

    private func loadPausedSession() {
        let topic = "\(level.rawValue) Vocabulary"
        let all = (try? modelContext.fetch(FetchDescriptor<SavedDeck>())) ?? []
        guard let deck = all.first(where: {
            ($0.generatorRaw == "goethe" || $0.generatorRaw == "goethe-srs") &&
            $0.topic == topic &&
            $0.hasPausedSession
        }),
        let data = deck.pausedProgressData,
        let progress = try? JSONDecoder().decode(DeckSessionProgress.self, from: data)
        else { pausedSession = nil; return }
        pausedSession = (deck, progress)
    }

    private func resumePausedSession() {
        guard let (deck, progress) = pausedSession else { return }
        let style = FlashcardStyle(rawValue: progress.studyModeRaw) ?? .default
        let topic = "\(level.rawValue) Vocabulary"

        let cards: [VocabCard]
        if deck.generatorRaw == "goethe-srs" {
            cards = deck.vocabCards
        } else if let words = progress.cardGermanWords, !words.isEmpty {
            let lookup = Dictionary(GoetheVocabService.entries(for: level).map { ($0.word, $0) },
                                    uniquingKeysWith: { first, _ in first })
            let ordered = words.compactMap { lookup[$0] }
            cards = GoetheVocabService.toVocabCards(ordered)
        } else {
            return
        }

        guard !cards.isEmpty else { return }
        let label = "\(cards.count) cards"
        onStartStudy(cards, topic, style, label)
    }

    private func formattedElapsed(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func startStudy() {
        let pool = filteredEntries.shuffled().prefix(cardCount)
        let cards = GoetheVocabService.toVocabCards(Array(pool))
        guard !cards.isEmpty else { return }
        let label = selectedWordType == .all
            ? "\(cards.count) cards"
            : "\(cards.count) \(selectedWordType.label.lowercased())"
        onStartStudy(cards, "\(level.rawValue) Vocabulary", selectedStyle, label)
    }

    @ViewBuilder
    private var pdfInfoSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("logo-goethe")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)

                VStack(spacing: 8) {
                    Text("Official Word List")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(level.examName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("This deck is based on the vocabulary list published by the Goethe-Institut for the \(level.examName) exam. The original PDF is linked below.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Link(destination: level.pdfURL) {
                    Label("Open Official PDF", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("About \(level.rawValue) Word List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingPDFInfo = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct A1EntryRow: View {
    let entry: A1Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let article = entry.article {
                    Text(article)
                        .font(.subheadline)
                        .foregroundStyle(articleColor(article))
                        .fontWeight(.medium)
                }
                Text(entry.word)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let wordType = entry.wordType {
                    Text(wordType)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(wordTypeColor(wordType), in: Capsule())
                }
            }
            if let translation = entry.translation {
                Text(translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func articleColor(_ article: String) -> Color {
        switch article {
        case "der": .blue
        case "die": .pink
        case "das": .green
        default: .secondary
        }
    }

    private func wordTypeColor(_ type: String) -> Color {
        switch type {
        case "verb": .blue
        case "adj": .purple
        case "noun": .green
        default: .gray
        }
    }
}

enum A1WordTypeFilter: CaseIterable {
    case all, nouns, verbs, other

    var label: String {
        switch self {
        case .all: "All"
        case .nouns: "Nouns"
        case .verbs: "Verbs"
        case .other: "Other"
        }
    }
}
