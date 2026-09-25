//
//  KasusHistoryView.swift
//  german-ai-flashcards
//
//  Verlauf · Your rounds: every scored grammar round, newest first and grouped by day, so a
//  round's result is still there after its Ergebnis has closed.
//
//    Fälle            Finden, Einsetzen and Schnellrunde (`KasusRound`); a tap opens the answers
//    Der · Die · Das  the article game (`ArticleRound`): score and count
//    Präpositionen    the Kasus drill (`PrepositionRound`): score and count
//
//  Filter pills on top (Alle · Fälle · Der · Die · Das · Präpositionen), then an all-time strip
//  with the first-try share per case. A unit screen's "Alle anzeigen" opens it for that unit only,
//  without the pills. The hub's Verlauf row and the unit screen's "Deine Runden" reuse the rows.
//

import SwiftUI
import SwiftData

// MARK: - Entries

/// Which rounds Verlauf lists.
enum GrammarHistoryFilter: String, CaseIterable, Identifiable {
    case alle, faelle, artikel, praepositionen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alle:           "Alle"
        case .faelle:         "Fälle"
        case .artikel:        "Der·Die·Das"
        case .praepositionen: "Präpositionen"
        }
    }
}

/// One Verlauf row, from whichever round model wrote it.
struct GrammarHistoryEntry: Identifiable {
    enum Source {
        case kasus(KasusRound)
        case article(ArticleRound)
        case preposition(PrepositionRound)
    }

    let source: Source

    var id: PersistentIdentifier {
        switch source {
        case .kasus(let round):       round.persistentModelID
        case .article(let round):     round.persistentModelID
        case .preposition(let round): round.persistentModelID
        }
    }

    var date: Date {
        switch source {
        case .kasus(let round):       round.date
        case .article(let round):     round.date
        case .preposition(let round): round.date
        }
    }

    var asked: Int {
        switch source {
        case .kasus(let round):       round.askedCount
        case .article(let round):     round.questionCount
        case .preposition(let round): round.questionCount
        }
    }

    var firstTry: Int {
        switch source {
        case .kasus(let round):       round.firstTryCount
        case .article(let round):     round.firstTryCount
        case .preposition(let round): round.firstTryCount
        }
    }

    var kind: GrammarHistoryFilter {
        switch source {
        case .kasus:       .faelle
        case .article:     .artikel
        case .preposition: .praepositionen
        }
    }

    /// „Der verlorene Schlüssel“ · Einsetzen, Schnellrunde · Dativ, Der · Die · Das. For the hub's
    /// one-line "last round".
    var shortLabel: String {
        switch source {
        case .kasus(let round):
            round.isQuickRound
                ? round.displayTitle(showsUnit: true)
                : "\(round.unit?.germanTitle ?? "Kasus") · \(round.step?.germanLabel ?? "")"
        case .article:     "Der · Die · Das"
        case .preposition: "Präpositionen"
        }
    }

    /// Every listed round, newest first.
    static func all(kasus: [KasusRound], articles: [ArticleRound],
                    prepositions: [PrepositionRound]) -> [GrammarHistoryEntry] {
        let entries = kasus.filter(\.isListed).map { GrammarHistoryEntry(source: .kasus($0)) }
            + articles.map { GrammarHistoryEntry(source: .article($0)) }
            + prepositions.map { GrammarHistoryEntry(source: .preposition($0)) }
        return entries.sorted { $0.date > $1.date }
    }
}

extension KasusRound {
    /// False for the synthetic rounds `-kasus.debugVerifyRecord keep` leaves behind, which no
    /// screen lists.
    var isListed: Bool {
        #if DEBUG
        return storyID != KasusService.debugVerifyStoryID
        #else
        return true
        #endif
    }

    /// „Der verlorene Schlüssel“, or Schnellrunde (· Dativ). The title is looked up from the id,
    /// so a retitled story reads right on old rounds.
    func displayTitle(showsUnit: Bool) -> String {
        if isQuickRound {
            guard showsUnit, let unit else { return "Schnellrunde" }
            return "Schnellrunde · \(unit.germanTitle)"
        }
        if let title = KasusStoryBank.bundled.story(id: storyID)?.title { return "„\(title)“" }
        return unit?.germanTitle ?? "Kasus"
    }

    /// Einsetzen · Genus-Hilfe · 3m 12s, or 10 Sätze · 1m 5s for a Schnellrunde.
    func displayDetail() -> String {
        var parts: [String] = []
        switch step {
        case .quick?: parts.append("\(askedCount) Sätze")
        case let step?: parts.append(step.germanLabel)
        case nil: break
        }
        if let hintLevel { parts.append(hintLevel.germanLabel) }
        if durationSeconds > 0 { parts.append(KasusHistoryFormat.duration(durationSeconds)) }
        return parts.joined(separator: " · ")
    }
}

enum KasusHistoryFormat {
    /// 45s, 3m 12s: the same clock Ergebnis shows.
    static func duration(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    static func percent(_ firstTry: Int, of asked: Int) -> Int {
        asked > 0 ? Int((Double(firstTry) / Double(asked) * 100).rounded()) : 0
    }

    /// Heute · Today, Gestern · Yesterday, else „Montag, 21. September“.
    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Heute · Today" }
        if calendar.isDateInYesterday(day) { return "Gestern · Yesterday" }
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        style.locale = Locale(identifier: "de_DE")
        if !calendar.isDate(day, equalTo: .now, toGranularity: .year) { style = style.year() }
        return day.formatted(style)
    }

    /// today, yesterday, or Sep 21: the hub's one line, and under a score outside Verlauf.
    static func relativeDay(_ date: Date, capitalized: Bool = false) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return capitalized ? "Today" : "today" }
        if calendar.isDateInYesterday(date) { return capitalized ? "Yesterday" : "yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Verlauf

struct KasusHistoryView: View {
    /// Set by a unit screen's "Alle anzeigen": only that unit's rounds, and no pills.
    var unit: KasusUnit? = nil

    @Query(sort: \KasusRound.date, order: .reverse) private var kasusRounds: [KasusRound]
    @Query(sort: \ArticleRound.date, order: .reverse) private var articleRounds: [ArticleRound]
    @Query(sort: \PrepositionRound.date, order: .reverse) private var prepositionRounds: [PrepositionRound]
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme

    @State private var filter: GrammarHistoryFilter = .alle

    private var entries: [GrammarHistoryEntry] {
        if let unit {
            return kasusRounds
                .filter { $0.isListed && $0.unitRaw == unit.rawValue }
                .map { GrammarHistoryEntry(source: .kasus($0)) }
        }
        let all = GrammarHistoryEntry.all(kasus: kasusRounds, articles: articleRounds,
                                          prepositions: prepositionRounds)
        return filter == .alle ? all : all.filter { $0.kind == filter }
    }

    /// The entries by calendar day, newest day first.
    private func days(_ entries: [GrammarHistoryEntry]) -> [(day: Date, entries: [GrammarHistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        let entries = entries
        List {
            if unit == nil {
                Section {
                    filterPills
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listSectionSpacing(.compact)
            }
            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Noch keine Runden · No rounds yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(emptyDescription)
                    )
                }
                .themedListRow()
            } else {
                summarySection(entries).themedListRow()
                ForEach(days(entries), id: \.day) { day in
                    daySection(day.day, entries: day.entries).themedListRow()
                }
            }
        }
        .themedListScreen()
        .navigationTitle(unit.map { "Deine Runden · \($0.germanTitle)" } ?? "Verlauf · Your rounds")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    private var emptyDescription: String {
        switch (unit, filter) {
        case (.some, _):        "Play a story or the Schnellrunde. Every scored round shows up here with its answers."
        case (nil, .artikel):   "Rounds of der · die · das show up here."
        case (nil, .praepositionen): "Rounds of the preposition drill show up here."
        default:                "Play a story, a Schnellrunde, der · die · das or the preposition drill. Every scored round shows up here."
        }
    }

    // MARK: Pills

    private var filterPills: some View {
        let accent = appTheme.accent(model: modelTheme)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GrammarHistoryFilter.allCases) { option in
                    FilterPill(label: option.label, tint: accent, isOn: filter == option,
                               showsClearGlyph: false) {
                        filter = option
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Summary

    private func summarySection(_ entries: [GrammarHistoryEntry]) -> some View {
        let asked = entries.reduce(0) { $0 + $1.asked }
        let firstTry = entries.reduce(0) { $0 + $1.firstTry }
        let perCase = entries.reduce(into: [GrammarCase: KasusRound.CaseTally]()) { totals, entry in
            guard case .kasus(let round) = entry.source else { return }
            for (kasus, tally) in round.perCase {
                totals[kasus, default: .init()].asked += tally.asked
                totals[kasus, default: .init()].firstTry += tally.firstTry
            }
        }
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 0) {
                    stat("\(entries.count)", entries.count == 1 ? "round" : "rounds")
                    stat("\(asked)", "answers")
                    stat("\(KasusHistoryFormat.percent(firstTry, of: asked))%", "right first try")
                }
                if !perCase.isEmpty {
                    CaseTallyBars(perCase: perCase)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Insgesamt · All time")
                .themedSectionHeader()
        } footer: {
            if !perCase.isEmpty {
                Text("The bars count first tries per case, over every story and Schnellrunde in this list.")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .themedLabel(.title2.weight(.bold), size: 24)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Days

    private func daySection(_ day: Date, entries: [GrammarHistoryEntry]) -> some View {
        let asked = entries.reduce(0) { $0 + $1.asked }
        let firstTry = entries.reduce(0) { $0 + $1.firstTry }
        return Section {
            ForEach(entries) { entry in
                row(entry)
            }
        } header: {
            HStack {
                Text(KasusHistoryFormat.dayTitle(day))
                Spacer()
                Text("\(firstTry)/\(asked)")
                    .monospacedDigit()
            }
            .themedSectionHeader()
        }
    }

    @ViewBuilder
    private func row(_ entry: GrammarHistoryEntry) -> some View {
        switch entry.source {
        case .kasus(let round):
            NavigationLink {
                KasusRoundDetailView(round: round)
            } label: {
                KasusRoundRow(round: round, showsUnit: unit == nil, groupedByDay: true)
            }
        case .article(let round):
            DrillRoundRow(
                title: "Der · Die · Das",
                detail: round.topic,
                counts: drillCounts(round.questionCount, noun: "nouns", seconds: round.durationSeconds),
                symbol: "textformat.abc",
                firstTry: round.firstTryCount, asked: round.questionCount
            )
        case .preposition(let round):
            DrillRoundRow(
                title: "Präpositionen",
                detail: round.topic,
                counts: drillCounts(round.questionCount, noun: "prepositions", seconds: round.durationSeconds),
                symbol: "arrow.triangle.branch",
                firstTry: round.firstTryCount, asked: round.questionCount
            )
        }
    }

    /// 10 nouns · 1m 1s
    private func drillCounts(_ count: Int, noun: String, seconds: Int) -> String {
        seconds > 0 ? "\(count) \(noun) · \(KasusHistoryFormat.duration(seconds))" : "\(count) \(noun)"
    }
}

// MARK: - Rows

/// One Kasus round: the unit's symbol, the story (or Schnellrunde), step, hint and time, a tally
/// per case, and the score.
struct KasusRoundRow: View {
    let round: KasusRound
    /// Name the unit in a Schnellrunde's title; off on a unit's own screen.
    var showsUnit = true
    /// Under a day header. Otherwise the day stands under the score, in place of the percent.
    var groupedByDay = false

    var body: some View {
        let unit = round.unit
        HStack(spacing: 12) {
            HistoryIcon(symbol: unit?.symbol ?? "checklist", color: unit?.color ?? .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(round.displayTitle(showsUnit: showsUnit))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(round.displayDetail())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                CaseTallyStrip(perCase: round.perCase)
            }
            Spacer(minLength: 8)
            HistoryScore(firstTry: round.firstTryCount, asked: round.askedCount,
                         caption: groupedByDay ? nil : KasusHistoryFormat.relativeDay(round.date, capitalized: true))
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// A der/die/das or preposition drill round: no answers kept, so no detail.
private struct DrillRoundRow: View {
    let title: String
    /// The round's topic („Goethe A1“); may be empty.
    let detail: String
    let counts: String
    let symbol: String
    let firstTry: Int
    let asked: Int

    var body: some View {
        HStack(spacing: 12) {
            HistoryIcon(symbol: symbol, color: nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(counts)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HistoryScore(firstTry: firstTry, asked: asked)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// The 34 pt chip rows lead with: a unit's symbol in its case color, or a tool's in the tint.
struct HistoryIcon: View {
    let symbol: String
    /// Nil takes the tint.
    let color: Color?

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Image(systemName: symbol)
            .font(.body)
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
            .frame(width: 34, height: 34)
            .background(
                color.map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(.tint.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// 7/9 over 78% (or over a day), trailing. Plain type, never a right/wrong color.
struct HistoryScore: View {
    let firstTry: Int
    let asked: Int
    /// What stands under the score. Nil: the first-try percent.
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(firstTry)/\(asked)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(caption ?? "\(KasusHistoryFormat.percent(firstTry, of: asked))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(firstTry) of \(asked) right first try")
    }
}

/// Nom 5/6 · Akk 9/11 · Dat 7/9, each case name in its case color.
struct CaseTallyStrip: View {
    let perCase: [GrammarCase: KasusRound.CaseTally]

    var body: some View {
        let cases = GrammarCase.allCases.filter { (perCase[$0]?.asked ?? 0) > 0 }
        if !cases.isEmpty {
            // One line when it fits, tighter when it nearly does, two lines of two otherwise
            // (four cases on a narrow phone). Never wraps inside a tally.
            ViewThatFits(in: .horizontal) {
                line(cases, spacing: 10)
                line(cases, spacing: 6)
                VStack(alignment: .leading, spacing: 2) {
                    line(Array(cases.prefix(2)), spacing: 8)
                    line(Array(cases.dropFirst(2)), spacing: 8)
                }
            }
            .font(.caption2)
        }
    }

    private func line(_ cases: [GrammarCase], spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(cases) { kasus in
                let tally = perCase[kasus] ?? .init()
                HStack(spacing: 3) {
                    Text(kasus.short)
                        .fontWeight(.semibold)
                        .foregroundStyle(kasus.color)
                    Text("\(tally.firstTry)/\(tally.asked)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(kasus.name) \(tally.firstTry) of \(tally.asked)")
            }
        }
    }
}

/// One bar per case: its first-try share in its case color, with the counts. Verlauf's all-time
/// strip and a round's own tallies.
struct CaseTallyBars: View {
    let perCase: [GrammarCase: KasusRound.CaseTally]
    /// The code word after the name (rese · nese · mrmn · srsr), as Ergebnis shows it.
    var showsCodeWord = false

    var body: some View {
        VStack(spacing: 10) {
            ForEach(GrammarCase.allCases) { kasus in
                if let tally = perCase[kasus], tally.asked > 0 {
                    HStack(spacing: 10) {
                        CaseLabel(kasus: kasus, style: .name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .frame(width: 112, alignment: .leading)
                        if showsCodeWord {
                            codeWord(kasus)
                                .font(.subheadline.weight(.heavy))
                                .lineLimit(1)
                                .fixedSize()
                                .frame(width: 54, alignment: .leading)
                        }
                        bar(kasus, share: Double(tally.firstTry) / Double(tally.asked))
                        Text("\(tally.firstTry)/\(tally.asked)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(kasus.name): \(tally.firstTry) of \(tally.asked) right first try")
                }
            }
        }
    }

    private func bar(_ kasus: GrammarCase, share: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(kasus.color.opacity(0.15))
                Capsule().fill(kasus.color)
                    .frame(width: max(share > 0 ? 6 : 0, geo.size.width * share))
            }
        }
        .frame(height: 6)
    }

    /// The code word with each letter in its column's gender color, as Ergebnis and the endings
    /// table show it.
    private func codeWord(_ kasus: GrammarCase) -> Text {
        var out = AttributedString()
        for (letter, gender) in zip(kasus.code, Gender.allCases) {
            var run = AttributedString(String(letter))
            run.foregroundColor = gender.color
            out += run
        }
        return Text(out)
    }
}

// MARK: - DEBUG

#if DEBUG
/// `-kasus.debugOpen history|round`: Verlauf, or the newest Kasus round's detail, since this
/// simulator can't tap its way there. Pair with `-kasus.debugSeedRounds 1` on a fresh store.
enum KasusHistoryDebugScreen: String, Identifiable {
    case history, round

    var id: String { rawValue }

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> KasusHistoryDebugScreen? {
        defaults.string(forKey: "kasus.debugOpen").flatMap { KasusHistoryDebugScreen(rawValue: $0.lowercased()) }
    }
}

/// What the debug sheet shows: Verlauf, or the newest round that kept its answers.
struct KasusHistoryDebugView: View {
    let screen: KasusHistoryDebugScreen

    @Query(sort: \KasusRound.date, order: .reverse) private var rounds: [KasusRound]

    var body: some View {
        switch screen {
        case .history:
            KasusHistoryView()
        case .round:
            if let round = rounds.first(where: { $0.isListed && $0.itemsData != nil }) ?? rounds.first {
                KasusRoundDetailView(round: round)
            } else {
                ContentUnavailableView("No Kasus rounds", systemImage: "clock.arrow.circlepath",
                                       description: Text("Launch with -kasus.debugSeedRounds 1 first."))
            }
        }
    }
}
#endif

// MARK: - Previews

#Preview("Verlauf · 4 themes") {
    let container = KasusHistoryPreview.container()
    return TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                KasusHistoryView()
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .modelContainer(container)
}

#Preview("Verlauf · empty") {
    NavigationStack {
        KasusHistoryView()
    }
    .modelContainer(for: [KasusRound.self, ArticleRound.self, PrepositionRound.self], inMemory: true)
}

/// A small in-memory history for the previews: two story steps, a Schnellrunde, and one round of
/// each drill.
enum KasusHistoryPreview {
    static func container() -> ModelContainer {
        let container = try! ModelContainer(
            for: KasusRound.self, ArticleRound.self, PrepositionRound.self,
            LearnerProfile.self, StudyDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let now = Date()
        context.insert(KasusRound(
            storyID: "ks-dat-a2-schluessel", unitRaw: KasusUnit.dativ.rawValue, stepRaw: KasusRoundStep.fill.rawValue,
            hintLevelRaw: KasusHintLevel.genus.rawValue, askedCount: 9, firstTryCount: 7, durationSeconds: 192,
            perCase: [.dativ: .init(asked: 9, firstTry: 7)], items: sampleItems,
            date: now.addingTimeInterval(-3_600)
        ))
        context.insert(KasusRound(
            storyID: "ks-dat-a2-schluessel", unitRaw: KasusUnit.dativ.rawValue, stepRaw: KasusRoundStep.find.rawValue,
            askedCount: 26, firstTryCount: 20, durationSeconds: 245,
            perCase: [.nominativ: .init(asked: 6, firstTry: 6), .akkusativ: .init(asked: 11, firstTry: 8),
                      .dativ: .init(asked: 9, firstTry: 6)],
            date: now.addingTimeInterval(-4_200)
        ))
        context.insert(KasusRound(
            storyID: "quick-nominativ", unitRaw: KasusUnit.nominativ.rawValue, stepRaw: KasusRoundStep.quick.rawValue,
            askedCount: 10, firstTryCount: 9, durationSeconds: 74,
            perCase: [.nominativ: .init(asked: 10, firstTry: 9)],
            date: now.addingTimeInterval(-90_000)
        ))
        let article = ArticleRound(topic: "Goethe A1", questionCount: 10, firstTryCount: 8, durationSeconds: 61)
        article.date = now.addingTimeInterval(-93_000)
        context.insert(article)
        let preposition = PrepositionRound(topic: "Akkusativ or Dativ", questionCount: 10, firstTryCount: 7,
                                           durationSeconds: 88)
        preposition.date = now.addingTimeInterval(-180_000)
        context.insert(preposition)
        return container
    }

    /// Three answers from the Dativ story: a gender slip, a case miss and a right one.
    static let sampleItems: [KasusRoundItem] = [
        KasusRoundItem(sentence: "Der Schlüssel ist nicht in der Tasche.", phraseStart: 28, phrase: "der Tasche",
                       answer: "der", pick: "dem", kasus: .dativ, genus: .die, outcome: .genderSlip,
                       explanation: "Right case, wrong gender: {m:dem} is *masculine* {dat:Dativ}. „Tasche“ is feminine, so {f:der}."),
        KasusRoundItem(sentence: "Der Hund schläft zufrieden auf dem Boden.", phraseStart: 31, phrase: "dem Boden",
                       answer: "dem", pick: "der", kasus: .dativ, genus: .der, outcome: .caseMiss,
                       explanation: "„auf“ with a place (**Wo?**) takes the {dat:Dativ}. Masculine {dat:Dativ} in „{m:m}{f:r}{n:m}{pl:n}“ is {m:m}: {m:dem}.",
                       targetIndex: 24),
        KasusRoundItem(sentence: "Er spielt mit dem Schlüssel!", phraseStart: 14, phrase: "dem Schlüssel",
                       answer: "dem", pick: "dem", kasus: .dativ, genus: .der, outcome: .right,
                       explanation: "„mit“ always takes the {dat:Dativ}. Masculine {dat:Dativ} in „{m:m}{f:r}{n:m}{pl:n}“ is {m:m}: {m:dem}."),
    ]
}
