//
//  GrammarHubView.swift
//  german-ai-flashcards
//
//  Grammatik · Grammar: the case path as the spine, every other domain a room. The Grammatik tab
//  is this screen's root; Home's Grammar tile brings that tab forward, and the Pyramid's
//  Grammatik-Kern layer still pushes its own copy.
//
//  Two modes, switched by the picker at the top (`grammar.showProgress`), the way Home switches
//  For You and All Activities.
//
//  Üben · Practice — where to go:
//    Weiter · Up next              one row: where to pick up (`KasusPath.next`, never stored)
//    Dein Verwechslungs-Paar       one card, only while one mix-up stands out (`KasusConfusion`)
//    Die vier Fälle · The cases    ① Nominativ → ⑤ Alle Fälle, dots + flame + level per row
//    Weitere Bereiche · Areas      one row per `GrammarArea`: Präpositionen (its own hub),
//                                  Artikel & Endungen and Verben (`GrammarBereichView`) — a new
//                                  area is one enum case, never a hub edit
//    Nachschlagen · Look it up     the endings table direct, then the library (explainers,
//                                  Merkhilfen, Kasus-Check, Endungs-Werkstatt, rule sheets)
//
//  Fortschritt · Progress — what the rounds add up to: `GrammarProgressPane`, which owns the
//  grammar day strip, time per exercise, the per-case bars and the Verlauf row (that row used to
//  live here). Its queries are its own, so Üben never fetches them.
//
//  The toolbar's question mark opens Der Kasus-Check, the decision order every case explanation
//  in the app follows. Flames come from the coach's profile (`LearnerMemoryService.shakyFocuses`),
//  so "needs work" means the same thing here as on Today; an area row's flame is any of its
//  structures shaky.
//

import SwiftUI
import SwiftData

struct GrammarHubView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Query private var profiles: [LearnerProfile]
    /// Story and Schnellrunde history: the hero's pick and the unit rows' dots.
    @Query private var rounds: [KasusRound]
    /// The hero row launches its story or Schnellrunde through the router.
    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    /// Off = „Üben“ (the path and the rooms), on = „Fortschritt“ (what the rounds add up to).
    /// Namespaced and device-local, the way Home's own mode flag is.
    @AppStorage("grammar.showProgress") private var showsProgress = false

    @State private var showKasusCheck = false
    /// The hero's „Lektion“: a sheet, since the lesson isn't an activity.
    @State private var lessonUnit: KasusUnit?
    /// The exercise the lesson's Üben asked for, launched once the sheet has gone.
    @State private var pendingConcept: GrammarDrillSession?

    var body: some View {
        List {
            Section {
                modePicker
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if showsProgress {
                GrammarProgressPane()
            } else {
                heroSection.themedListRow()
                confusionSection.themedListRow()
                unitsSection.themedListRow()
                bereicheSection.themedListRow()
                nachschlagenSection.themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Grammatik · Grammar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showKasusCheck = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Der Kasus-Check")
            }
        }
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
        .sheet(item: $lessonUnit, onDismiss: launchPendingConcept) { unit in
            KasusLessonView(
                unit: unit,
                onRead: { seconds in KasusService.recordLessonRead(unit: unit, seconds: seconds, in: modelContext) },
                onPractice: {
                    pendingConcept = GrammarDrillSession(kind: .roles, topic: .kasus(unit))
                    lessonUnit = nil
                }
            )
        }
    }

    private func launchPendingConcept() {
        guard let session = pendingConcept else { return }
        pendingConcept = nil
        router.launch(.grammarDrill(session))
    }

    /// Mounted as its own clear row so the grouped list's card inset doesn't double up on it —
    /// the same treatment `HomeHubView` gives its For You / All Activities picker.
    private var modePicker: some View {
        Picker("Grammar mode", selection: $showsProgress) {
            Text("Üben").tag(false)
            Text("Fortschritt").tag(true)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Learner profile inputs

    /// Shaky structures, worst-first, by the coach's shared threshold.
    private var shaky: [GrammarFocus] { LearnerMemoryService.shakyFocuses(profiles.first) }

    private func isShaky(_ focus: GrammarFocus?) -> Bool {
        guard let focus else { return false }
        return shaky.contains(focus)
    }

    // MARK: - Weiter · Up next

    /// A story's steps take about this long end to end, for the hero's subtitle.
    private static let storyMinutes: [KasusStep: Int] = [.lesen: 8, .finden: 6, .einsetzen: 4]

    /// Where to pick up: a shaky case's story, an unplayed story, the first unfinished step from
    /// the learner's start unit, or the story played longest ago. Derived on every render.
    private var hero: KasusHero {
        KasusPath.next(profile: profiles.first, level: modelManager.germanLevel,
                       rounds: rounds, bank: KasusStoryBank.bundled, concepts: KasusConceptBank.bundled)
    }

    private var heroSection: some View {
        let hero = hero
        return Section {
            Button {
                if let session = hero.storySession {
                    router.launch(.kasusStory(session))
                } else if let session = hero.drillSession {
                    router.launch(.grammarDrill(session))
                } else {
                    lessonUnit = hero.unit
                }
            } label: {
                HStack(spacing: 12) {
                    if let art = heroArt(hero) {
                        GrammarTaskArtView(art: art, tint: hero.unit.color)
                    } else {
                        GrammarRowChip(symbol: heroSymbol(hero), tint: hero.unit.color, size: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(heroTitle(hero))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(heroSubtitle(hero))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if case .shaky(let focus) = hero.reason {
                            Label("Coach: \(GrammarCase(focus: focus)?.name ?? hero.unit.germanTitle) braucht Übung",
                                  systemImage: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: { if case .lesson = hero.action { "book.pages" } else { "play.circle.fill" } }())
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Weiter · Up next")
                .themedSectionHeader()
        }
    }

    /// The unit's symbol, or the lesson's and an exercise's own. Only a story still reaches this:
    /// every other hero action has a task drawing (`heroArt`).
    private func heroSymbol(_ hero: KasusHero) -> String {
        switch hero.action {
        case .lesson:                  KasusRoundStep.lesson.meta.symbol
        case .concept(let exercise):   exercise.symbol
        case .story, .quickRound:      hero.unit.symbol
        }
    }

    /// The hero's task drawing, where the row is one task: the lesson, a Verstehen exercise, the
    /// Schnellrunde. A story is three steps rather than one shape, so it keeps the unit's chip.
    private func heroArt(_ hero: KasusHero) -> GrammarTaskArt? {
        switch hero.action {
        case .lesson:                 KasusRoundStep.lesson.meta.art
        case .concept(let exercise):  exercise.art
        case .quickRound:             KasusRoundStep.quick.meta.art
        case .story:                  nil
        }
    }

    /// Dativ · „Der verlorene Schlüssel“, Akkusativ · Schnellrunde, Dativ · Lektion, Dativ · Rollen.
    private func heroTitle(_ hero: KasusHero) -> String {
        if let title = hero.storyTitle {
            return "\(hero.unit.germanTitle) · „\(title)“"
        }
        switch hero.action {
        case .lesson:                 return "\(hero.unit.germanTitle) · Lektion"
        case .concept(let exercise):  return "\(hero.unit.germanTitle) · \(exercise.germanTitle)"
        case .story, .quickRound:     return "\(hero.unit.germanTitle) · Schnellrunde"
        }
    }

    /// The steps still ahead in the story and roughly how long they take, or the Schnellrunde's
    /// cases, or the Verstehen piece and its minutes.
    private func heroSubtitle(_ hero: KasusHero) -> String {
        switch hero.action {
        case .lesson:
            return "Verstehen · What this case is · about 2 min"
        case .concept(let exercise):
            return "Verstehen · \(exercise.englishTitle) · about \(exercise.minutes) min"
        case .story, .quickRound:
            break
        }
        guard let step = hero.step else {
            return "10 Sätze · \(hero.unit.casesInPlay.map(\.short).joined(separator: " + "))"
        }
        let steps = [KasusStep.lesen, .finden, .einsetzen].drop { $0 != step }
        let path = steps.map(\.germanLabel).joined(separator: " → ")
        let minutes = Self.storyMinutes[step] ?? 8
        let line = "\(path) · about \(minutes) min"
        return hero.reason == .review ? "Wiederholen · \(line)" : line
    }

    /// Reference below study, history last: the endings table directly (the one time-critical
    /// lookup), then the library that indexes everything else. Both paths reach the same screens.
    private var nachschlagenSection: some View {
        Section {
            NavigationLink {
                CaseEndingsView()
            } label: {
                GrammarShelfRow(title: "Die Endungstabelle · The endings table",
                                subtitle: "Formen · Sinn · Takt, every cell in 3D") {
                    GrammarRowChip(symbol: "tablecells")
                }
            }
            NavigationLink {
                KasusExplainerLibraryView()
            } label: {
                GrammarShelfRow(title: "Warum dieser Fall? · Why this case?",
                                subtitle: "Explainers, memory aids, the Kasus-Check & rule sheets") {
                    GrammarRowChip(symbol: "text.magnifyingglass")
                }
            }
        } header: {
            Text("Nachschlagen · Look it up").themedSectionHeader()
        }
    }

    // MARK: - Die vier Fälle

    private var unitsSection: some View {
        Section {
            ForEach(KasusUnit.allCases) { unit in
                NavigationLink {
                    KasusUnitView(unit: unit, modelManager: modelManager, mlxService: mlxService)
                } label: {
                    unitRow(unit)
                }
            }
        } header: {
            Text("Die vier Fälle · The four cases")
                .themedSectionHeader()
        } footer: {
            Text("Go top to bottom or jump in anywhere. The levels are a guide, not a gate.")
        }
    }

    /// ①–⑤: the path reads as a path, even entered mid-way through a deep link.
    private func waypoint(_ unit: KasusUnit) -> String {
        let marks = ["①", "②", "③", "④", "⑤"]
        guard let index = KasusUnit.allCases.firstIndex(of: unit), index < marks.count else { return "" }
        return marks[index]
    }

    private func unitRow(_ unit: KasusUnit) -> some View {
        GrammarShelfRow(title: "\(waypoint(unit)) \(unit.germanTitle) · \(unit.englishRole)",
                        subtitle: unit.exampleForms,
                        shaky: isShaky(unit.focus), level: unit.levelLabel) {
            GrammarRowChip(symbol: unit.symbol, tint: unit.color)
        } trailing: {
            progressDots(unit)
        }
    }

    /// One dot for Verstehen (the lesson read and every offered drill played), one per story
    /// (filled once its Markieren and Endungen are both played) and one for the Schnellrunde.
    /// Keyed on (storyID, unit, step), never on a title.
    private func progressDots(_ unit: KasusUnit) -> some View {
        let progress = KasusProgress(rounds: rounds)
        let done = [progress.verstehenDone(unit, offered: KasusConceptBank.bundled.offered(for: unit))]
            + KasusStoryBank.bundled.stories(for: unit).map { story in
                progress.isDone(storyID: story.id, unit: unit, step: .find)
                    && progress.isDone(storyID: story.id, unit: unit, step: .fill)
            } + [progress.quickRoundDone(unit)]
        return HStack(spacing: 3) {
            ForEach(Array(done.enumerated()), id: \.offset) { _, filled in
                Circle()
                    .strokeBorder(unit.color, lineWidth: 1.2)
                    .background(Circle().fill(filled ? unit.color : .clear))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done.filter { $0 }.count) of \(done.count) done")
    }

    // MARK: - Verwechslungs-Paar

    /// The two forms the learner mixes up most, once one pair stands out (`KasusConfusion`).
    @ViewBuilder
    private var confusionSection: some View {
        if let pair = KasusConfusion.standout(rounds: rounds), let session = KasusConfusion.drill(for: pair) {
            Section {
                KasusConfusionCard(pair: pair, session: session) {
                    router.launch(.grammarDrill(session))
                }
            } header: {
                Text("Dein Verwechslungs-Paar · Your mix-up")
                    .themedSectionHeader()
            }
        }
    }

    // MARK: - Weitere Bereiche

    /// One row per room (`GrammarArea`). Präpositionen keeps its grown hub; the rest share
    /// `GrammarBereichView`. A new area lands here without a hub edit.
    private var bereicheSection: some View {
        Section {
            ForEach(GrammarArea.allCases) { area in
                NavigationLink {
                    if area.hasOwnHub {
                        PrepositionHubView(modelManager: modelManager, mlxService: mlxService)
                    } else {
                        GrammarBereichView(area: area, modelManager: modelManager, mlxService: mlxService)
                    }
                } label: {
                    GrammarShelfRow(title: area.germanTitle, subtitle: area.englishRole,
                                     shaky: area.isShaky(shaky), level: area.levelLabel) {
                        if area.hasOwnHub {
                            prepositionStill
                        } else {
                            GrammarRowChip(symbol: area.symbol)
                        }
                    }
                }
            }
        } header: {
            Text("Weitere Bereiche · More areas")
                .themedSectionHeader()
        } footer: {
            Text("Each area: learn, practice, look up.")
        }
    }

    /// A still of one scene, never a live canvas: the hub is a list, and the app keeps one live
    /// RealityKit view per screen. Falls back to a plain chip if the render is missing.
    @ViewBuilder
    private var prepositionStill: some View {
        if let image = PrepositionScene.image(for: "auf", state: "dat") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            GrammarRowChip(symbol: "arrow.triangle.branch")
        }
    }

}

// MARK: - Previews

#Preview("Grammar hub · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                GrammarHubView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(
        for: [SavedDeck.self, StudyDay.self, LearnerProfile.self, ChatConversation.self, KasusRound.self,
              ArticleRound.self, PrepositionRound.self],
        inMemory: true
    )
}
