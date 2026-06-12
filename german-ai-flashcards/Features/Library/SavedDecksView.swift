import DieKarteiCore
import SwiftUI
import SwiftData

struct SavedDecksView: View {
    @Query(sort: \SavedDeck.createdAt, order: .reverse)
    private var decks: [SavedDeck]

    private var visibleDecks: [SavedDeck] {
        decks.filter {
            $0.generatorRaw != "goethe-srs" &&
            $0.generatorRaw != "goethe" &&
            $0.generatorRaw != "past-tense" &&
            $0.generatorRaw != "past-tense-srs"
        }
    }

    /// Combined quiz results per Goethe level, merging "goethe" (default mode) and "goethe-srs" (SRS mode) decks.
    private var goetheStats: [GoetheLevel: [QuizResult]] {
        var map: [GoetheLevel: [QuizResult]] = [:]
        for deck in decks {
            guard deck.generatorRaw == "goethe" || deck.generatorRaw == "goethe-srs" else { continue }
            let level: GoetheLevel?
            switch deck.topic {
            case "A1 Vocabulary": level = .a1
            case "A2 Vocabulary": level = .a2
            case "B1 Vocabulary": level = .b1
            default: level = nil
            }
            guard let level else { continue }
            map[level, default: []].append(contentsOf: deck.quizResults)
        }
        return map
    }

    @Environment(\.modelContext) private var modelContext
    @State private var deckForStats: SavedDeck?
    @State private var selectedGoetheLevel: GoetheLevel?
    @State private var goetheStatsLevel: GoetheLevel?

    var onSelectDeck: (SavedDeck) -> Void
    var onSelectGoetheLevel: ((_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void)?
    var onSelectPastTenseLevel: ((_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void)?
    var onSelectGrammarFlipCards: ((_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void)?
    var onSelectGrammarMultipleChoice: ((_ category: GrammarCategory, _ showHints: Bool) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                goetheSectionView
                grammarSectionView

                if visibleDecks.isEmpty {
                    Section("My Decks") {
                        ContentUnavailableView(
                            "No Saved Decks",
                            systemImage: "tray",
                            description: Text("Generate vocabulary and it will be saved here automatically.")
                        )
                    }
                } else {
                    Section("My Decks") {
                        DeckIconLegend()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        ForEach(visibleDecks, id: \.id) { deck in
                            HStack(spacing: 0) {
                                Button {
                                    onSelectDeck(deck)
                                } label: {
                                    SavedDeckRow(deck: deck)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 4)
                                    .padding(.trailing, 16)

                                if !deck.quizResults.isEmpty {
                                    Rectangle()
                                        .fill(Color(uiColor: .separator))
                                        .frame(width: 0.5)
                                        .padding(.vertical, 8)
                                    Button {
                                        deckForStats = deck
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(.tint)
                                            .frame(width: 60)
                                            .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
                        }
                        .onDelete(perform: deleteDecks)
                    }
                }
            }
            .contentMargins(.bottom, 120, for: .scrollContent)
            .navigationTitle("Library")
            .navigationDestination(item: $selectedGoetheLevel) { level in
                GoetheVocabListView(
                    level: level,
                    onStartStudy: { cards, topic, style, label in
                        onSelectGoetheLevel?(cards, topic, style, label)
                    },
                    onStartPastTenseStudy: onSelectPastTenseLevel
                )
            }
            .sheet(item: $deckForStats) { deck in
                DeckStatsSheet(
                    deck: deck,
                    sortedResults: deck.quizResults.sorted { $0.date > $1.date }
                )
            }
            .sheet(isPresented: Binding(
                get: { goetheStatsLevel != nil },
                set: { if !$0 { goetheStatsLevel = nil } }
            )) {
                if let level = goetheStatsLevel {
                    GoetheStatsSheet(
                        level: level,
                        sortedResults: (goetheStats[level] ?? []).sorted { $0.date > $1.date }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var grammarSectionView: some View {
        Section {
            NavigationLink {
                GrammarCategoryView(
                    onStartFlipCards: onSelectGrammarFlipCards,
                    onStartMultipleChoice: onSelectGrammarMultipleChoice
                )
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Grammar Exercises")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Akkusativ · Articles & Pronouns")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Grammar")
        } footer: {
            Text("Fill-in-the-blank grammar exercises with multiple choice or flip card study modes.")
        }
    }

    @ViewBuilder
    private var goetheSectionView: some View {
        Section {
            ForEach(GoetheLevel.allCases) { level in
                let results = goetheStats[level] ?? []
                HStack(spacing: 0) {
                    Button {
                        selectedGoetheLevel = level
                    } label: {
                        GoetheLevelRow(level: level, quizResults: results, hasPausedSession: goetheLevelHasPausedSession(level))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                        .padding(.trailing, 16)

                    if !results.isEmpty {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(width: 0.5)
                            .padding(.vertical, 8)
                        Button {
                            goetheStatsLevel = level
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.tint)
                                .frame(width: 60)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
            }
        } header: {
            HStack(spacing: 8) {
                Image("logo-goethe-square-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 16)
                Text("Official Goethe Decks")
            }
        } footer: {
            Text("Pre-built vocab from the Goethe-Institut word lists")
        }
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visibleDecks[index])
        }
    }

    private func goetheLevelHasPausedSession(_ level: GoetheLevel) -> Bool {
        decks.contains {
            ($0.generatorRaw == "goethe" || $0.generatorRaw == "goethe-srs") &&
            $0.topic == "\(level.rawValue) Vocabulary" &&
            $0.hasPausedSession
        }
    }
}

private struct DeckIconLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            Label("Examples", systemImage: "text.quote")
            Label("Verbs", systemImage: "character.book.closed")
            Label("Conjugations", systemImage: "tablecells")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.vertical, 2)
    }
}

private struct SavedDeckRow: View {
    let deck: SavedDeck

    private var latestResult: QuizResult? {
        deck.quizResults.max(by: { $0.date < $1.date })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(deck.topic)
                    .font(.headline)
                Spacer()
                GeneratorBadge(deck: deck)
            }
            HStack(spacing: 10) {
                Label("\(deck.cards.count) cards", systemImage: "rectangle.stack")
                if deck.includeExamples {
                    Label("Examples", systemImage: "text.quote")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Examples")
                }
                if deck.wordTypeFilter.includesVerbs && deck.wordTypeFilter != .all {
                    Label("Verbs", systemImage: "character.book.closed")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Verbs")
                }
                if deck.includeConjugations {
                    Label("Conjugations", systemImage: "tablecells")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Conjugations")
                }
                if deck.hasPausedSession {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Paused session")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let latest = latestResult {
                HStack(spacing: 4) {
                    ModeIcon(mode: latest.studyMode)
                    Text("Last: \(latest.correctCount)/\(latest.totalCards) — \(latest.scorePercentage)%\(latest.durationSeconds > 0 ? " — \(latest.formattedDuration)" : "")")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(deck.createdAt, format: .dateTime.month(.abbreviated).day().year())
                if deck.generationTimeSeconds > 0 {
                    Text("·")
                    Label(generationTimeLabel(deck), systemImage: "timer")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func generationTimeLabel(_ deck: SavedDeck) -> String {
        let s = deck.generationTimeSeconds
        let cards = deck.cards.count
        if s < 60 {
            return cards > 0 ? "\(Int(s))s (\(String(format: "%.1f", s / Double(cards)))s/card)" : "\(Int(s))s"
        }
        let m = Int(s) / 60
        let rem = Int(s) % 60
        return "\(m)m \(rem)s"
    }
}

private struct DeckStatsSheet: View {
    let deck: SavedDeck
    let sortedResults: [QuizResult]
    @Environment(\.dismiss) private var dismiss

    private var averageScore: Int? {
        guard !sortedResults.isEmpty else { return nil }
        return sortedResults.reduce(0) { $0 + $1.scorePercentage } / sortedResults.count
    }

    private var bestScore: Int? {
        sortedResults.map(\.scorePercentage).max()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    LabeledContent("Cards", value: "\(deck.cards.count)")
                    LabeledContent("Quizzes taken", value: "\(sortedResults.count)")
                    if let avg = averageScore {
                        LabeledContent("Average score", value: "\(avg)%")
                    }
                    if let best = bestScore {
                        LabeledContent("Best score", value: "\(best)%")
                    }
                }

                Section("Quiz History") {
                    ForEach(sortedResults, id: \.id) { result in
                        HStack(spacing: 10) {
                            ModeIcon(mode: result.studyMode)
                                .frame(width: 16)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                modeDetail(result)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(result.correctCount)/\(result.totalCards)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(result.scorePercentage)%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(deck.topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func modeDetail(_ result: QuizResult) -> some View {
        switch result.studyMode {
        case .anki:
            if let counts = result.ankiRatingCounts, counts.again + counts.hard + counts.good + counts.easy > 0 {
                Text(ankiBreakdownText(counts))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if result.incorrectCount > 0 {
                Text("\(result.incorrectCount) missed")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        case .leitner:
            if result.incorrectCount > 0 {
                Text("\(result.incorrectCount) reset")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        case .default:
            if result.incorrectCount > 0 {
                Text("\(result.incorrectCount) missed")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func ankiBreakdownText(_ counts: (again: Int, hard: Int, good: Int, easy: Int)) -> String {
        var parts: [String] = []
        if counts.easy > 0  { parts.append("\(counts.easy)E") }
        if counts.good > 0  { parts.append("\(counts.good)G") }
        if counts.hard > 0  { parts.append("\(counts.hard)H") }
        if counts.again > 0 { parts.append("\(counts.again)A") }
        return parts.joined(separator: " ")
    }
}

private struct GoetheLevelRow: View {
    let level: GoetheLevel
    let quizResults: [QuizResult]
    var hasPausedSession: Bool = false

    private var latestResult: QuizResult? {
        quizResults.max(by: { $0.date < $1.date })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(level.rawValue)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(levelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.examName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasPausedSession {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .accessibilityLabel("Paused session")
                }
            }
            .padding(.vertical, 2)

            if let latest = latestResult {
                HStack(spacing: 4) {
                    ModeIcon(mode: latest.studyMode)
                    let labelPart = latest.subDeckLabel.map { " · \($0)" } ?? ""
                    Text("Last\(labelPart): \(latest.correctCount)/\(latest.totalCards) — \(latest.scorePercentage)%\(latest.durationSeconds > 0 ? " — \(latest.formattedDuration)" : "")")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var levelColor: Color {
        switch level {
        case .a1: .green
        case .a2: .blue
        case .b1: .orange
        }
    }
}

private struct GoetheStatsSheet: View {
    let level: GoetheLevel
    let sortedResults: [QuizResult]
    @Environment(\.dismiss) private var dismiss

    private var averageScore: Int? {
        guard !sortedResults.isEmpty else { return nil }
        return sortedResults.reduce(0) { $0 + $1.scorePercentage } / sortedResults.count
    }

    private var bestScore: Int? {
        sortedResults.map(\.scorePercentage).max()
    }

    private var totalSeconds: Int {
        sortedResults.reduce(0) { $0 + $1.durationSeconds }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    LabeledContent("Sessions", value: "\(sortedResults.count)")
                    if let avg = averageScore {
                        LabeledContent("Average score", value: "\(avg)%")
                    }
                    if let best = bestScore {
                        LabeledContent("Best score", value: "\(best)%")
                    }
                    if totalSeconds > 0 {
                        LabeledContent("Total time spent", value: formattedTotal(totalSeconds))
                    }
                }

                Section("Study History") {
                    ForEach(sortedResults, id: \.id) { result in
                        HStack(spacing: 10) {
                            ModeIcon(mode: result.studyMode)
                                .frame(width: 16)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let label = result.subDeckLabel {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(result.correctCount)/\(result.totalCards)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                HStack(spacing: 4) {
                                    Text("\(result.scorePercentage)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if result.durationSeconds > 0 {
                                        Text(result.formattedDuration)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("\(level.rawValue) Study History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formattedTotal(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds % 60)s"
        }
        return "\(seconds)s"
    }
}

private struct ModeIcon: View {
    let mode: FlashcardStyle

    var body: some View {
        switch mode {
        case .default:
            Image(systemName: "rectangle.on.rectangle")
        case .anki:
            Image(systemName: "brain")
        case .leitner:
            Image(systemName: "tray.2")
        }
    }
}

private struct GeneratorBadge: View {
    let deck: SavedDeck

    var body: some View {
        if let logoName = deck.generatorLogoName {
            Image(logoName)
                .resizable()
                .scaledToFit()
                .frame(height: 18)
        }
    }
}
