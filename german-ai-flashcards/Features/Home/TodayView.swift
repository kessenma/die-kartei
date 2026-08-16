//
//  TodayView.swift
//  german-ai-flashcards
//
//  The "Today" plan — the top section of the Home hub. It reads the learner's profile, the SRS
//  backlog, and the streak, then recommends a short, ordered set of "next things" so the learner
//  never has to decide what to do. Each recommendation is one tap: a `router` launch, a tab
//  switch, a pushed screen, or a quick grammar lesson. This is the single biggest anti-scattershot
//  lever (see docs/FUTURE_FEATURES.md #1).
//

import SwiftUI
import SwiftData

/// How TodaySection presents the plan.
enum TodayStyle {
    /// The compact ordered list of up to three recommendations.
    case plan
    /// One big "up next" pick, with the rest of the plan as smaller rows below. Used by the
    /// Home hub's "For You" mode, where the app decides the next exercise for the learner.
    case hero
}

struct TodaySection: View {
    @Bindable var coordinator: GenerationCoordinator
    /// Forwarded to the "Generate flashcards" recommendation (mirrors the hub's own wiring).
    var onGenerationComplete: () -> Void
    var style: TodayStyle = .plan

    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    @Query private var profiles: [LearnerProfile]
    @Query private var decks: [SavedDeck]
    @Query private var studyDays: [StudyDay]

    /// Set to present a 30-second mini-lesson for a weak spot that has no drill of its own.
    @State private var lessonFocus: GrammarFocus?

    /// Grammar counts as "shaky" at or above this struggle level (matches the memory briefing).
    private let weaknessThreshold = GrammarSkill.shakyThreshold

    private var profile: LearnerProfile? { profiles.first }

    var body: some View {
        switch style {
        case .plan:
            Section {
                ForEach(recommendations) { rec in
                    row(rec)
                }
            } header: {
                header
            } footer: {
                Text("Your short, personalized plan — just do the next thing. Picked from what's due and what's shaky.")
                    .font(.caption2)
            }
            .themedListRow()

        case .hero:
            Section {
                if let pick = recommendations.first {
                    row(pick, hero: true)
                }
            } header: {
                header
            } footer: {
                Text("Picked for you from your coach's memory, what's due, and your streak.")
                    .font(.caption2)
            }
            .themedListRow()
            if recommendations.count > 1 {
                Section {
                    ForEach(recommendations.dropFirst()) { rec in
                        row(rec)
                    }
                } header: {
                    Text("Also good right now").themedSectionHeader()
                }
                .themedListRow()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(style == .hero ? "Up Next" : "Today")
                .themedSectionHeader()
            Spacer()
            if streak > 0 {
                Label("\(streak)", systemImage: "flame.fill")
                    .themedLabel(.caption.weight(.bold), size: 13)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
        .textCase(nil)
        .sheet(item: $lessonFocus) { focus in
            GrammarLessonSheet(focus: focus)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ rec: TodayRecommendation, hero: Bool = false) -> some View {
        switch rec.intent {
        case .reviewDueCards:
            Button { launchReview() } label: { rowLabel(rec, hero: hero, chevron: true) }
                .buttonStyle(.plain)
        case .grammar(let focus):
            Button { launchGrammar(focus) } label: { rowLabel(rec, hero: hero, chevron: true) }
                .buttonStyle(.plain)
        case .chat:
            NavigationLink {
                ConversationListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
            } label: {
                rowLabel(rec, hero: hero)
            }
        case .buildDrillDeck:
            NavigationLink { DrillDeckView() } label: { rowLabel(rec, hero: hero) }
        case .generateDeck:
            NavigationLink {
                HomeView(service: coordinator, onGenerationComplete: onGenerationComplete)
            } label: {
                rowLabel(rec, hero: hero)
            }
        case .resumePausedDeck:
            Button { launchResume() } label: { rowLabel(rec, hero: hero, chevron: true) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func rowLabel(_ rec: TodayRecommendation, hero: Bool, chevron: Bool = false) -> some View {
        if hero {
            TodayHeroRow(rec: rec)
        } else {
            TodayRow(rec: rec, showsChevron: chevron)
        }
    }

    // MARK: - Plan inputs

    private var recommendations: [TodayRecommendation] {
        TodayPlanner.plan(
            TodaySnapshot(
                dueCardCount: dueCards.count,
                weaknesses: weaknesses,
                hasCoachContent: hasCoachContent,
                streak: streak,
                studiedToday: StudyLogService.studiedToday(studyDays),
                hasStartedLearning: hasStartedLearning,
                dayIndex: dayIndex,
                resume: resumeInfo
            )
        )
    }

    /// SRS cards that have been scheduled and are now due (never-reviewed cards are "new", not due),
    /// soonest-due first, across every deck.
    private var dueCards: [SavedCard] {
        let now = Date()
        return decks
            .flatMap(\.cards)
            .filter { card in
                guard let next = card.nextReviewDate else { return false }
                return next <= now
            }
            .sorted { ($0.nextReviewDate ?? now) < ($1.nextReviewDate ?? now) }
    }

    /// Shaky grammar structures, worst-first (mirrors the coach's grammar sort).
    private var weaknesses: [GrammarFocus] {
        guard let profile else { return [] }
        return profile.grammar
            .compactMap { key, skill -> (GrammarFocus, Double)? in
                guard skill.struggle >= weaknessThreshold, let f = GrammarFocus(rawValue: key) else { return nil }
                return (f, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var hasCoachContent: Bool {
        !(profile?.vocab.isEmpty ?? true) || !(profile?.slips.isEmpty ?? true)
    }

    private var streak: Int { StudyLogService.currentStreak(studyDays) }

    private var hasStartedLearning: Bool {
        studyDays.contains(where: \.hasActivity)
            || (profile?.sessionCount ?? 0) > 0
            || decks.contains { !$0.cards.isEmpty }
    }

    /// Day-of-year — rotates which weak spot / drill is surfaced so the plan varies day to day.
    private var dayIndex: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
    }

    // MARK: - Resume

    /// Paused decks, most-recently-paused first.
    private var pausedDecks: [SavedDeck] {
        decks.filter { $0.pausedAt != nil }
            .sorted { ($0.pausedAt ?? .distantPast) > ($1.pausedAt ?? .distantPast) }
    }

    /// The most recent paused deck we can actually rebuild, paired with its ready-to-launch session.
    private var resumeTarget: (deck: SavedDeck, session: StudySession)? {
        for deck in pausedDecks {
            if let session = deckStore.resumeSession(for: deck) {
                return (deck, session)
            }
        }
        return nil
    }

    private var resumeInfo: TodaySnapshot.ResumeInfo? {
        guard let target = resumeTarget,
              let data = target.deck.pausedProgressData,
              let progress = try? JSONDecoder().decode(DeckSessionProgress.self, from: data)
        else { return nil }
        return .init(topic: target.deck.topic, cardIndex: progress.cardIndex, cardCount: target.session.cards.count)
    }

    // MARK: - Launchers

    private func launchResume() {
        guard let target = resumeTarget else { return }
        router.launch(.cardDeck(target.session))
    }

    private func launchReview() {
        let cards = Array(dueCards.prefix(60))
        guard !cards.isEmpty else { return }
        let session = StudySession(
            cards: cards.map(vocabCard(from:)),
            topic: "Daily Review",
            deckID: nil,
            savedCards: cards,
            flashcardStyle: .anki,
            subDeckLabel: "Daily review · \(cards.count) due"
        )
        router.launch(.cardDeck(session))
    }

    private func launchGrammar(_ focus: GrammarFocus) {
        // Akkusativ / Dativ ship with a drill (rotated by day for variety); every other
        // structure falls back to the 30-second explanation.
        if let category = GrammarExerciseService.category(for: focus, rotation: dayIndex) {
            router.launch(.grammarMultipleChoice(category: category, showHints: true))
        } else {
            lessonFocus = focus
        }
    }

    private func vocabCard(from c: SavedCard) -> VocabCard {
        VocabCard(
            germanWord: c.germanWord,
            englishTranslation: c.englishTranslation,
            wordType: c.wordType,
            article: c.article,
            exampleSentence: c.exampleSentence,
            conjugations: c.conjugations
        )
    }
}

// MARK: - Row

private struct TodayRow: View {
    let rec: TodayRecommendation
    /// Button-driven rows draw their own chevron; `NavigationLink` rows get the system one.
    var showsChevron: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            // `rec.accent` is content, not chrome — it's how the plan tells one kind of exercise
            // from another — so the theme reshapes the chip without recoloring it.
            Image(systemName: rec.systemImage)
                .font(.title3)
                .foregroundStyle(rec.accent)
                .frame(width: 38, height: 38)
                .background(rec.accent.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title)
                    .themedLabel(.subheadline, size: 15)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(rec.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Hero row

/// The single emphasized "up next" pick shown in the Home hub's For You mode: the plan's top
/// recommendation as one card with an unmistakable Start affordance.
private struct TodayHeroRow: View {
    let rec: TodayRecommendation

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: rec.systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(rec.accent,
                                in: RoundedRectangle(cornerRadius: theme.innerRadius(12), style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(rec.title)
                        .themedLabel(.headline, size: 18)
                        .foregroundStyle(.primary)
                    Text(rec.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // The Start affordance: a pill everywhere but Grundform, which squares it off. Uppercase
            // there too, so the app's loudest button carries the loudest part of that theme.
            HStack(spacing: 6) {
                Text("Start")
                Image(systemName: "arrow.right")
            }
            .themedLabel(.subheadline.weight(.semibold), size: 16)
            .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(rec.accent, in: theme.pillShape)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// (GrammarLessonSheet — the just-in-time mini-lesson this section presents — moved to
// Features/Grammar/GrammarLessonSheet.swift so the Grammar hub can share it.)
