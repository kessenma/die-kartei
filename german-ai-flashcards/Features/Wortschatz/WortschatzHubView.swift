//
//  WortschatzHubView.swift
//  german-ai-flashcards
//
//  The Goethe word box. One screen for all three lists: what is due today and one Start button,
//  the levels and word classes in scope, the Karteikasten chart, the options, and the doors to
//  browsing, previewing, Perfekt verbs, matching and der/die/das. The hub is the session's setup
//  screen, so Start goes straight into the cards.
//
//  Progress lives on one merged SRS deck (`DeckStore.fetchOrCreateWortschatzDeck`), one card per
//  headword across the cumulative lists; the scope only decides which of those cards are in play.
//

import SwiftUI
import SwiftData

struct WortschatzHubView: View {
    @Bindable var coordinator: GenerationCoordinator
    /// Preselect these levels on first appear (the pyramid's A1 and A2 layers land here).
    var initialLevels: Set<GoetheLevel>? = nil

    @Environment(ActivityRouter.self) private var router
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query(filter: #Predicate<SavedDeck> { $0.generatorRaw == "goethe-srs" }) private var srsDecks: [SavedDeck]
    @Query private var studyDays: [StudyDay]

    @AppStorage(WortschatzScope.levelsKey) private var levelsRaw = ""
    @AppStorage(WortschatzScope.wordTypesKey) private var wordTypesRaw = ""
    @AppStorage(WortschatzPrefs.styleKey) private var styleRaw = FlashcardStyle.anki.rawValue
    @AppStorage(WortschatzPrefs.newPerDayKey) private var newPerDay = WortschatzPrefs.newPerDayDefault
    @AppStorage(WortschatzPrefs.sessionCapKey) private var sessionCap = WortschatzPrefs.sessionCapDefault
    @AppStorage(CardStudyPrefs.germanFirstKey) private var germanFirst = true
    @AppStorage(CardStudyPrefs.articleQuizKey) private var articleQuiz = true

    @State private var isOptionsExpanded = false
    @State private var showingInfo = false
    @State private var appliedInitialLevels = false

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    private var deck: SavedDeck? { srsDecks.first { $0.topic == DeckStore.wortschatzTopic } }

    private var scope: WortschatzScope {
        WortschatzScope.decode(levelsRaw: levelsRaw, wordTypesRaw: wordTypesRaw)
    }

    private var scopeBinding: Binding<WortschatzScope> {
        Binding(get: { scope }, set: { setScope($0) })
    }

    private func setScope(_ new: WortschatzScope) {
        levelsRaw = new.levelsRaw
        wordTypesRaw = new.wordTypesRaw
    }

    private var style: FlashcardStyle {
        guard let s = FlashcardStyle(rawValue: styleRaw), s != .default else { return .anki }
        return s
    }

    private var leitnerSession: Int { deck?.quizResults.count ?? 0 }

    private var budgetRemaining: Int {
        StudyLogService.newWordBudgetRemaining(studyDays, newPerDay: newPerDay)
    }

    private var inScopeCards: [SavedCard] {
        (deck?.cards ?? []).filter { WortschatzService.inScope($0, scope) }
    }

    /// Before the deck exists every word in scope is unseen; after, the service counts.
    private var summary: WortschatzService.Summary {
        if let deck {
            return WortschatzService.summary(
                cards: deck.cards, scope: scope, style: style,
                leitnerSession: leitnerSession, budgetRemaining: budgetRemaining
            )
        }
        let unseen = GoetheVocabService.words(in: scope).count
        return .init(due: 0, new: min(unseen, budgetRemaining), unseen: unseen, known: 0, total: unseen)
    }

    private var pausedProgress: DeckSessionProgress? {
        guard let deck, let data = deck.pausedProgressData else { return nil }
        return try? JSONDecoder().decode(DeckSessionProgress.self, from: data)
    }

    var body: some View {
        List {
            logoSection
            heroSection
            todaySection
            scopeSection
            karteikastenSection
            optionsSection
            moreSection
        }
        .themedListScreen()
        .navigationTitle("Wortschatz")
        .navigationBarTitleDisplayMode(.large)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingInfo) {
            WortschatzInfoSheet()
        }
        .task {
            if let initialLevels, !appliedInitialLevels {
                appliedInitialLevels = true
                var updated = scope
                updated.levels = initialLevels
                setScope(updated)
            }
            if deck == nil {
                _ = deckStore.fetchOrCreateWortschatzDeck()
            }
        }
    }

    // MARK: - Sections

    private var logoSection: some View {
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
    }

    private var heroSection: some View {
        let current = summary
        let offersMore: Bool = current.new == 0 && current.unseen > 0
        let paused = pausedProgress
        return Section {
            if let paused {
                pausedRow(paused)
            }
            WortschatzHeroRow(
                summary: current,
                scopeSummary: scope.summary,
                onStart: { launchStart() },
                onLearnMore: offersMore ? { learnMore() } : nil
            )
        } header: {
            Text("Fällig heute · Due today").themedSectionHeader()
        } footer: {
            Text("Reviews come first, then up to \(newPerDay) new words a day. Every rating is saved as you go, so stopping early is fine.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func pausedRow(_ progress: DeckSessionProgress) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Paused session")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Card \(progress.cardIndex + 1) of \(progress.cardGermanWords?.count ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Resume") { resumePaused() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    /// What you went through today, word by word: right or missed, and when it comes back.
    @ViewBuilder
    private var todaySection: some View {
        let cards = todaysCards
        if !cards.isEmpty {
            let today = WortschatzService.today(cards)
            Section {
                ForEach(cards.prefix(todayPreviewCount), id: \.persistentModelID) { card in
                    if let word = GoetheVocabService.index[card.germanWord] {
                        WortschatzTodayRow(word: word, card: card, style: style, leitnerSession: leitnerSession)
                    }
                }
                if cards.count > todayPreviewCount {
                    NavigationLink {
                        WortschatzBrowseView(initialScope: scope, style: style, initialStatus: .today)
                    } label: {
                        Text("See all \(cards.count) from today")
                            .font(.subheadline)
                    }
                }
            } header: {
                HStack {
                    Text("Heute · Today").themedSectionHeader()
                    Spacer()
                    Text("\(today.right) right · \(today.missed) missed" + (today.met > 0 ? " · \(today.met) new" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Every word you rated today, missed ones first. Missed words come back tomorrow; the rest when their bar says.")
                    .font(.caption2)
            }
            .themedListRow()
        }
    }

    private var scopeSection: some View {
        Section {
            WortschatzScopeChips(scope: scopeBinding)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 0))
        } header: {
            HStack {
                Text("Scope").themedSectionHeader()
                Spacer()
                Text("\(summary.total) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Progress on a level you switch off is kept; its words simply wait.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var karteikastenSection: some View {
        Section {
            KarteikastenChart(buckets: WortschatzService.karteikasten(inScopeCards, style: style))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        } header: {
            Text("Der Karteikasten · Your word box").themedSectionHeader()
        } footer: {
            Text(style == .leitner
                 ? "Each bar is a box. Right moves a word up a box, wrong sends it back to Box 1. Known: \(summary.known) of \(summary.total) in scope."
                 : "Each bar is how many days until those words come up again. A word counts as known after three weeks of spacing or three correct reviews in a row. Known: \(summary.known) of \(summary.total) in scope.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var optionsSummary: String {
        "\(style.rawValue) · \(newPerDay) new a day · \(sessionCap) per session"
    }

    private var optionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isOptionsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study with")
                    Picker("Study with", selection: $styleRaw) {
                        Text(FlashcardStyle.anki.rawValue).tag(FlashcardStyle.anki.rawValue)
                        Text(FlashcardStyle.leitner.rawValue).tag(FlashcardStyle.leitner.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Text(style.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("New words per day")
                    Picker("New words per day", selection: $newPerDay) {
                        ForEach(WortschatzPrefs.newPerDayOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cards per session")
                    Picker("Cards per session", selection: $sessionCap) {
                        ForEach(WortschatzPrefs.sessionCapOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                Picker("Front side", selection: $germanFirst) {
                    Text("German").tag(true)
                    Text("English").tag(false)
                }

                Toggle("Ask der / die / das first", isOn: $articleQuiz)

                if let settingsRouter {
                    Button {
                        settingsRouter.route = .cards
                    } label: {
                        Label("More in Settings ▸ Cards", systemImage: "slider.horizontal.3")
                            .font(.subheadline)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Options")
                    Text(optionsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .themedListRow()
    }

    private var moreSection: some View {
        Section {
            NavigationLink {
                WortschatzBrowseView(initialScope: scope, style: style)
            } label: {
                ActivityRow("Browse all words", "Every word with its status", "magnifyingglass")
            }

            Button(action: launchPreview) {
                ActivityRow("Vorschau · Preview", "Flip through \(min(sessionCap, summary.total)) words, nothing is scored", "rectangle.on.rectangle")
            }
            .buttonStyle(.plain)

            NavigationLink {
                PastTenseLevelView(level: pastTenseLevel, onStartStudy: launchPastTense)
            } label: {
                ActivityRow("Perfekt Verbs", "sein or haben, participles, separable prefixes", "clock.arrow.circlepath")
            }

            NavigationLink {
                MatchingDeckPickerView(modelManager: coordinator.modelManager)
            } label: {
                ActivityRow("Card Matching", "Fast form ↔ meaning warm-up", "square.grid.2x2.fill")
            }

            NavigationLink {
                ArticleGameSetupView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                ActivityRow("Der · Die · Das", "Guess each noun's gender", "textformat.abc")
            }
        } header: {
            Text("More").themedSectionHeader()
        }
        .themedListRow()
    }

    private var pastTenseLevel: PastTenseLevel {
        switch scope.orderedLevels.first ?? .a1 {
        case .a1: .a1
        case .a2: .a2
        case .b1: .b1
        }
    }

    // MARK: - Launchers

    private func launchStart() {
        launch(newBudget: budgetRemaining)
    }

    private func learnMore() {
        // Read the budget before widening it: the query reflects the bonus at once, so reading
        // after would count the ten twice.
        let budget = budgetRemaining + WortschatzPrefs.bonusStep
        StudyLogService.addNewWordBonus(WortschatzPrefs.bonusStep, in: modelContext)
        launch(newBudget: budget)
    }

    /// The words rated today, missed ones first. The hub shows the first few; Browse has them all.
    private var todaysCards: [SavedCard] { WortschatzService.todaysCards(deck?.cards ?? []) }
    private let todayPreviewCount = 6

    private func launch(newBudget: Int) {
        guard let session = deckStore.wortschatzSession(
            scope: scope, style: style, newBudget: newBudget, sessionCap: sessionCap
        ) else { return }
        router.launch(.cardDeck(session))
    }

    private func launchPreview() {
        guard let session = deckStore.wortschatzPreviewSession(scope: scope, count: sessionCap) else { return }
        router.launch(.cardDeck(session))
    }

    private func resumePaused() {
        guard let deck, let session = deckStore.resumeSession(for: deck) else { return }
        router.launch(.cardDeck(session))
    }

    private func launchPastTense(_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ label: String) {
        router.launch(.cardDeck(deckStore.pastTenseSession(cards: cards, topic: topic, style: style, label: label)))
    }
}

// MARK: - Today row

/// One word from today's session: the word, its meaning, how it went, and when it is back.
private struct WortschatzTodayRow: View {
    let word: GoetheWord
    let card: SavedCard
    let style: FlashcardStyle
    let leitnerSession: Int

    @Environment(\.appTheme) private var theme

    private var wasRight: Bool { card.lastReviewWasCorrect ?? true }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: wasRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(wasRight ? .green : .red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text.gendered(word.word, article: word.article)
                        .font(.subheadline.weight(.medium))
                    if WortschatzService.metToday(card) {
                        Text("new")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12), in: theme.pillShape)
                    }
                }
                if let translation = word.translation {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(WortschatzService.badgeText(card, style: style, leitnerSession: leitnerSession))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Hero row

/// The box's one number and one button: how much is waiting today, and Start. Same shape as the
/// Today plan's hero pick, so the loudest button in both places is the same button.
private struct WortschatzHeroRow: View {
    let summary: WortschatzService.Summary
    let scopeSummary: String
    let onStart: () -> Void
    /// Offered when today's budget is spent but the box still has unseen words.
    var onLearnMore: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    private var allDone: Bool { summary.todo == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(summary.todo)")
                    .themedNumber(44)
                    .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(allDone ? .secondary : .primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(allDone ? "All done for today" : "\(summary.due) reviews + \(summary.new) new")
                        .themedLabel(.headline, size: 17)
                        .foregroundStyle(.primary)
                    Text(scopeSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if allDone {
                if let onLearnMore {
                    Button(action: onLearnMore) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Learn \(WortschatzPrefs.bonusStep) more new words")
                        }
                        .themedLabel(.subheadline.weight(.semibold), size: 15)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(theme.pillShape.stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Nothing is due and every word in scope has been seen. Come back tomorrow, or widen the scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: onStart) {
                    HStack(spacing: 6) {
                        Text("Start")
                        Image(systemName: "arrow.right")
                    }
                    .themedLabel(.subheadline.weight(.semibold), size: 16)
                    .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue, in: theme.pillShape)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

@MainActor
private func hubPreview(_ theme: AppTheme) -> some View {
    NavigationStack {
        WortschatzHubView(coordinator: GenerationCoordinator(modelManager: MLXModelManager()))
    }
    .environment(ActivityRouter())
    .environment(SettingsRouter())
    .environment(\.appTheme, theme)
    .modelContainer(for: [SavedDeck.self, SavedCard.self, QuizResult.self, StudyDay.self], inMemory: true)
}

#Preview("Wortschatz · System")   { hubPreview(.klar) }
#Preview("Wortschatz · Soft")     { hubPreview(.sanft) }
#Preview("Wortschatz · Notebook") { hubPreview(.kritzel) }
#Preview("Wortschatz · Bauhaus")  { hubPreview(.grundform) }
