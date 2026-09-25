//
//  PyramidCoachSection.swift
//  german-ai-flashcards
//
//  "Wo du stehst · Where You Stand" — the pyramid screen's holistic read of the learner: one row
//  per skill area, each pairing the app's two evidence sources. The *check* chip is the placement
//  snapshot (what you brought with you); the verdict line is what the coach keeps measuring as you
//  practice. Where the two disagree, measured wins — the same rule the pyramid's credit math
//  follows, surfaced in words.
//
//  Deliberately a pure read: this section writes nothing, and owns its own queries the way
//  StreakCalendarSection does, so it drops into the pyramid's List as one self-contained piece.
//

import SwiftUI
import SwiftData

struct PyramidCoachSection: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// The applied check, passed in rather than read here: it lives in UserDefaults, which SwiftUI
    /// can't observe, so the parent re-passes it when its `placementRevision` bumps.
    var placement: PlacementResult?

    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query private var profiles: [LearnerProfile]
    @Query private var cards: [SavedCard]
    @Query private var prepositionStats: [PrepositionStat]
    @Query private var articleStats: [ArticleWordStat]
    @Query private var matchingStats: [MatchingPairStat]

    var body: some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    areaRow(row)
                }
                NavigationLink {
                    CoachNotesView(modelManager: modelManager)
                } label: {
                    Label("The coach's full notes", systemImage: "brain.head.profile")
                        .font(.subheadline)
                }
                if hasCheck {
                    NavigationLink {
                        PlacementReviewView(modelManager: modelManager)
                    } label: {
                        Label("What the check saw", systemImage: "list.bullet.rectangle")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Wo du stehst · Where You Stand").themedSectionHeader()
            } footer: {
                Text(hasCheck
                     ? "»Check« is your placement snapshot; the rest is what the coach keeps measuring as you practice. Where they disagree, measured wins."
                     : "What the coach keeps measuring as you practice. Take the placement check to add a snapshot of what you brought with you.")
                    .font(.caption2)
            }
            .themedListRow()
        }
    }

    // MARK: - Row model

    private struct AreaRow: Identifiable {
        enum Verdict {
            case solid, needsWork, watching, unmeasured

            var systemImage: String {
                switch self {
                case .solid:      "checkmark.circle.fill"
                case .needsWork:  "flame.fill"
                case .watching:   "eye"
                case .unmeasured: "circle.dashed"
                }
            }

            var tint: Color {
                switch self {
                case .solid:      .green
                case .needsWork:  .orange
                case .watching:   .orange
                case .unmeasured: .secondary
                }
            }

            /// Growth areas first — that's what the learner came to see.
            var sortRank: Int {
                switch self {
                case .needsWork:  0
                case .watching:   1
                case .unmeasured: 2
                case .solid:      3
                }
            }
        }

        enum Route {
            case articleGame
            case prepositionHub
            case grammarHub
            /// A focus's exercise or quick lesson, opened on tap (`GrammarRoute`). The preposition
            /// hub is a push, so it goes through `.prepositionHub` instead.
            case grammar(GrammarRoute)
            case trickyPairs
            case drillDeck
            case none
        }

        let id: String
        let systemImage: String
        let tint: Color
        let title: String
        let checkChip: String?
        let verdictText: String
        let verdict: Verdict
        let route: Route
    }

    // MARK: - Rendering

    @ViewBuilder
    private func areaRow(_ row: AreaRow) -> some View {
        switch row.route {
        case .articleGame:
            NavigationLink { ArticleGameSetupView(modelManager: modelManager, mlxService: mlxService) } label: {
                areaLabel(row)
            }
        case .prepositionHub:
            NavigationLink { PrepositionHubView(modelManager: modelManager) } label: {
                areaLabel(row)
            }
        case .grammarHub:
            NavigationLink { GrammarHubView(modelManager: modelManager, mlxService: mlxService) } label: {
                areaLabel(row)
            }
        case .grammar(let route):
            if case .lesson(let focus) = route {
                LessonRowButton(focus: focus) { areaLabel(row, chevron: true) }
            } else {
                Button { open(route) } label: {
                    areaLabel(row, chevron: true)
                }
                .buttonStyle(.plain)
            }
        case .trickyPairs:
            NavigationLink { TrickyPairsView() } label: { areaLabel(row) }
        case .drillDeck:
            NavigationLink { DrillDeckView() } label: { areaLabel(row) }
        case .none:
            areaLabel(row)
        }
    }

    private func areaLabel(_ row: AreaRow, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.systemImage)
                .font(.title3)
                .foregroundStyle(row.tint)
                .frame(width: 38, height: 38)
                .background(row.tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .themedLabel(.subheadline, size: 15)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Label(row.verdictText, systemImage: row.verdict.systemImage)
                    .font(.caption)
                    .foregroundStyle(row.verdict.tint)
            }
            Spacer(minLength: 8)
            if let chip = row.checkChip {
                Text(chip)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title). \(row.verdictText)\(row.checkChip.map { ". \($0)" } ?? "")")
    }

    // MARK: - Inputs

    private var profile: LearnerProfile? { profiles.first }
    private var grammar: [String: GrammarSkill] { profile?.grammar ?? [:] }

    private var hasCheck: Bool {
        guard let placement else { return false }
        return !placement.declaredBeginner
    }

    /// The structure areas above pull these focuses out; everything else is "Strukturen".
    private static let caseFocuses: [GrammarFocus] = [.akkusativ, .dativ, .genitiv,
                                                      .praepositionen, .wechselpraepositionen]

    /// Which row reads a grammar focus. `GrammarRoute`'s DEBUG report prints it.
    enum Area { case artikel, faelle, strukturen }

    static func area(for focus: GrammarFocus) -> Area {
        if focus == .artikel { return .artikel }
        return caseFocuses.contains(focus) ? .faelle : .strukturen
    }

    /// The shakiest measured focus of a set, if any is shaky.
    private func worstShaky(_ focuses: [GrammarFocus]) -> GrammarFocus? {
        focuses
            .compactMap { focus in grammar[focus.rawValue].map { (focus, $0.struggle) } }
            .filter { $0.1 >= GrammarSkill.shakyThreshold }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// A focus's practice as a row route: the preposition hub is a push, the rest a tap.
    private func areaRoute(for focus: GrammarFocus) -> AreaRow.Route {
        let route = GrammarRoute(focus)
        return route.presentation == .push ? .prepositionHub : .grammar(route)
    }

    /// A launch route's tap. The hub and the lesson have their own row views (`areaRow`).
    private func open(_ route: GrammarRoute) {
        if case .launch(let activity) = route.resolve(in: modelContext, level: modelManager.germanLevel) {
            router.launch(activity)
        }
    }

    // MARK: - The areas

    private var rows: [AreaRow] {
        [wortschatzRow, artikelRow, faelleRow, strukturenRow, ausrutscherRow]
            .compactMap { $0 }
            .sorted { $0.verdict.sortRank < $1.verdict.sortRank }
    }

    private var wortschatzRow: AreaRow? {
        let learned = PyramidService.learnedWords(
            cards: cards, articleStats: articleStats, matchingStats: matchingStats
        ).count
        let tricky = matchingStats.filter(\.isTricky).count + articleStats.filter(\.isTricky).count

        let chip: String? = hasCheck ? placement.flatMap { p in
            let held = GoetheLevel.allCases.filter { p.vocabKnown($0) > 0 }.map(\.rawValue)
            return held.isEmpty ? nil : "Check \(held.joined(separator: "·"))"
        } : nil

        let verdict: AreaRow.Verdict
        let text: String
        switch (learned, tricky) {
        case (0, 0):
            guard chip != nil else { return nil }
            verdict = .unmeasured; text = "Not yet measured in the app"
        case (_, 0):
            verdict = .solid; text = "\(learned) words proven"
        case (0, _):
            verdict = .needsWork; text = "\(tricky) tricky right now"
        default:
            verdict = .needsWork; text = "\(learned) words proven · \(tricky) tricky right now"
        }

        return AreaRow(
            id: "wortschatz", systemImage: "text.book.closed", tint: .blue,
            title: "Wortschatz · Vocabulary",
            checkChip: chip, verdictText: text, verdict: verdict,
            route: tricky > 0 ? .trickyPairs : .none
        )
    }

    private var artikelRow: AreaRow? {
        let chip = hasCheck ? placement.map { "Check \(percent($0.articleAccuracy))" } : nil
        let trickyNouns = articleStats.filter(\.isTricky).count
        let (verdict, text) = measuredVerdict(
            focuses: [.artikel],
            trickyCount: trickyNouns, trickyNoun: "tricky nouns"
        )
        guard chip != nil || verdict != .unmeasured else { return nil }
        return AreaRow(
            id: "artikel", systemImage: "a.square", tint: .purple,
            title: "Artikel · der, die, das",
            checkChip: chip, verdictText: text, verdict: verdict,
            route: .articleGame
        )
    }

    private var faelleRow: AreaRow? {
        let chip = hasCheck ? placement.map { "Check \(percent($0.prepositionAccuracy))" } : nil
        let trickyPreps = prepositionStats.filter(\.isTricky).count
        let (verdict, measuredText) = measuredVerdict(
            focuses: Self.caseFocuses,
            trickyCount: trickyPreps, trickyNoun: "tricky prepositions"
        )
        guard chip != nil || verdict != .unmeasured else { return nil }
        var text = measuredText

        // The shakiest case opens its own practice (a story, a Schnellrunde, the preposition
        // hub); tricky prepositions alone open the hub; otherwise the Grammatik path.
        let route: AreaRow.Route
        if let worst = worstShaky(Self.caseFocuses) {
            text = "Needs work: \(worst.germanLabel)" + (trickyPreps > 0 ? " · \(trickyPreps) tricky prepositions" : "")
            route = areaRoute(for: worst)
        } else {
            route = trickyPreps > 0 ? .prepositionHub : .grammarHub
        }
        return AreaRow(
            id: "faelle", systemImage: "arrow.triangle.branch", tint: .orange,
            title: "Fälle & Präpositionen · Cases",
            checkChip: chip, verdictText: text, verdict: verdict,
            route: route
        )
    }

    private var strukturenRow: AreaRow? {
        let rest = GrammarFocus.allCases.filter { $0 != .artikel && !Self.caseFocuses.contains($0) }
        let measured = rest.compactMap { focus -> (GrammarFocus, GrammarSkill)? in
            grammar[focus.rawValue].map { (focus, $0) }
        }
        let worst = measured
            .filter { $0.1.struggle >= GrammarSkill.shakyThreshold }
            .max { $0.1.struggle < $1.1.struggle }

        let chip = hasCheck ? placement?.grammarLevel.map { "Check \($0.rawValue) held" } : nil

        let verdict: AreaRow.Verdict
        let text: String
        var route = AreaRow.Route.none
        if let worst {
            verdict = .needsWork
            text = "Needs work: \(worst.0.germanLabel)"
            route = areaRoute(for: worst.0)
        } else if !measured.isEmpty {
            verdict = .solid
            text = "Measured structures look solid"
        } else {
            guard chip != nil else { return nil }
            verdict = .unmeasured
            text = "Not yet measured in the app"
        }

        return AreaRow(
            id: "strukturen", systemImage: "checklist", tint: .indigo,
            title: "Strukturen · Grammar structures",
            checkChip: chip, verdictText: text, verdict: verdict,
            route: route
        )
    }

    private var ausrutscherRow: AreaRow? {
        let slips = profile?.slips.count ?? 0
        guard slips > 0 else { return nil }
        return AreaRow(
            id: "ausrutscher", systemImage: "bandage", tint: .pink,
            title: "Ausrutscher · Slip-ups",
            checkChip: nil,
            verdictText: "Watching \(slips) recurring slip\(slips == 1 ? "" : "s")",
            verdict: .watching,
            route: .drillDeck
        )
    }

    /// The coach's word on a set of grammar focuses: the worst measured one speaks for the area,
    /// unmeasured stays honestly unmeasured, and a tricky-word count rides along either way.
    private func measuredVerdict(
        focuses: [GrammarFocus], trickyCount: Int, trickyNoun: String
    ) -> (AreaRow.Verdict, String) {
        let measured = focuses.compactMap { grammar[$0.rawValue] }
        let trickySuffix = trickyCount > 0 ? " · \(trickyCount) \(trickyNoun)" : ""

        guard !measured.isEmpty else {
            return trickyCount > 0
                ? (.needsWork, "\(trickyCount) \(trickyNoun)")
                : (.unmeasured, "Not yet measured in the app")
        }
        if measured.contains(where: { $0.struggle >= GrammarSkill.shakyThreshold }) {
            return (.needsWork, "The coach says: needs work" + trickySuffix)
        }
        return trickyCount > 0
            ? (.needsWork, "Solid, but \(trickyCount) \(trickyNoun)")
            : (.solid, "The coach says: solid")
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}

// MARK: - Lesson row

/// A row that opens a structure's quick lesson. The sheet hangs on the row itself, which is on
/// screen when it's tapped; the Section's header may already have scrolled away.
private struct LessonRowButton<RowLabel: View>: View {
    let focus: GrammarFocus
    @ViewBuilder var label: RowLabel

    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { label }
            .buttonStyle(.plain)
            .sheet(isPresented: $isPresented) {
                GrammarLessonSheet(focus: focus)
            }
    }
}

// MARK: - Core-structure dots (Grammatik-Kern layer row)

/// The Grammatik-Kern layer's four structures as compact state chips: green = the coach rates it
/// solid, flame = shaky, dashed hollow = not yet measured. Shared with `PyramidView`'s layer row.
struct CoreStructureDots: View {
    let grammar: [String: GrammarSkill]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PyramidService.coreGrammar) { focus in
                let state = state(for: focus)
                HStack(spacing: 3) {
                    Image(systemName: state.systemImage)
                        .font(.system(size: 8))
                        .foregroundStyle(state.tint)
                    Text(abbreviation(for: focus))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private enum State {
        case solid, shaky, unmeasured

        var systemImage: String {
            switch self {
            case .solid:      "circle.fill"
            case .shaky:      "flame.fill"
            case .unmeasured: "circle.dashed"
            }
        }

        var tint: Color {
            switch self {
            case .solid:      .green
            case .shaky:      .orange
            case .unmeasured: .secondary
            }
        }

        var label: String {
            switch self {
            case .solid:      "solid"
            case .shaky:      "needs work"
            case .unmeasured: "not yet measured"
            }
        }
    }

    private func state(for focus: GrammarFocus) -> State {
        guard let skill = grammar[focus.rawValue] else { return .unmeasured }
        return skill.struggle >= GrammarSkill.shakyThreshold ? .shaky : .solid
    }

    private func abbreviation(for focus: GrammarFocus) -> String {
        String(focus.germanLabel.prefix(4))
    }

    private var accessibilitySummary: String {
        PyramidService.coreGrammar
            .map { "\($0.germanLabel): \(state(for: $0).label)" }
            .joined(separator: ", ")
    }
}
