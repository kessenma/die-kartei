//
//  KasusUnitView.swift
//  german-ai-flashcards
//
//  One case on the Grammatik path. Every unit runs the same loop, top to bottom:
//
//    Die Regel · The rule        a few lines, the endings table with this case lit, the Kasus-Check
//    Geschichten · Stories       the bundled stories for this unit (Lesen → Finden → Einsetzen)
//    Schnellrunde · Quick round  the endings drill, limited to the unit's cases
//
//  Rows that start a round end in a play glyph; rows that navigate get the list's chevron (the
//  same rule as `PrepositionHubView.sourceRow`).
//

import SwiftUI
import SwiftData

struct KasusUnitView: View {
    let unit: KasusUnit

    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme

    @Query private var rounds: [KasusRound]

    /// Nil until the learner opens or closes "Die Regel" by hand. Until then it is open until the
    /// unit's first round, so a returning learner lands on the exercises instead of the rule.
    @State private var ruleExpandedChoice: Bool?
    @State private var showKasusCheck = false

    /// Questions in one Schnellrunde.
    private let quickRoundCount = 10

    var body: some View {
        List {
            headerSection.themedListRow()
            ruleSection.themedListRow()
            storiesSection
            quickRoundSection.themedListRow()
        }
        .themedListScreen()
        .navigationTitle(unit.germanTitle)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: unit.symbol)
                    .font(.title2)
                    .foregroundStyle(unit.color)
                    .frame(width: 44, height: 44)
                    .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.englishRole)
                        .font(.headline)
                    if let forms = unit.exampleForms {
                        Text(forms)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(unit.levelLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Level \(unit.levelLabel)")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Die Regel

    private var hasPlayedUnit: Bool {
        rounds.contains { $0.unitRaw == unit.rawValue }
    }

    private var isRuleExpanded: Binding<Bool> {
        Binding(
            get: { ruleExpandedChoice ?? !hasPlayedUnit },
            set: { ruleExpandedChoice = $0 }
        )
    }

    private var ruleSection: some View {
        Section {
            DisclosureGroup(isExpanded: isRuleExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unit.ruleLines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(unit.color)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(line)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)

                CaseEndingsTable(cases: unit.casesInPlay, highlight: unit.focusCase)
                    .padding(.vertical, 6)

                Button {
                    showKasusCheck = true
                } label: {
                    Label("Der Kasus-Check · Which case?", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            } label: {
                Text("Die Regel · The rule")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Geschichten

    private var stories: [KasusStory] { KasusStoryBank.bundled.stories(for: unit) }

    /// One row per bundled story for this unit, launched through the router as `.kasusStory`.
    /// Units without a story show nothing here.
    @ViewBuilder
    private var storiesSection: some View {
        let stories = self.stories
        if !stories.isEmpty {
            let progress = KasusProgress(rounds: rounds)
            Section {
                ForEach(stories) { story in
                    storyRow(story, progress: progress)
                }
            } header: {
                Text("Geschichten · Stories")
                    .themedSectionHeader()
            } footer: {
                Text("Read the story, mark the cases, then fill in the articles. About 8 minutes.")
            }
            .themedListRow()
        }
    }

    private func storyRow(_ story: KasusStory, progress: KasusProgress) -> some View {
        let found = progress.isDone(storyID: story.id, unit: unit, step: .find)
        let filled = progress.isDone(storyID: story.id, unit: unit, step: .fill)
        return Button {
            // Pick up where it was left: Einsetzen once Finden is done, otherwise from the top.
            let start: KasusStep = found && !filled ? .einsetzen : .lesen
            router.launch(.kasusStory(KasusSession(storyID: story.id, unit: unit, startStep: start)))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.title3)
                    .foregroundStyle(unit.color)
                    .frame(width: 34, height: 34)
                    .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("„\(story.title)“")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("\(story.level) · Finden \(stepMark(found)) · Einsetzen \(stepMark(filled))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(story.title), \(story.level). Finden \(found ? "done" : "not yet"), Einsetzen \(filled ? "done" : "not yet").")
    }

    /// ✓ once the step has been played, ○ before.
    private func stepMark(_ done: Bool) -> Image {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
    }

    // MARK: - Schnellrunde

    private var quickRoundSection: some View {
        Section {
            Button {
                router.launch(.caseEndings(CaseEndingsSession(unit: unit)))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Schnellrunde · Quick round")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text("\(quickRoundCount) Sätze · \(unit.casesInPlay.map(\.short).joined(separator: " + "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Pick the article that fits the sentence. Every miss shows which case it is and why.")
        }
    }
}

// MARK: - Previews

#Preview("Kasus unit · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                KasusUnitView(unit: .dativ)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(for: [LearnerProfile.self, StudyDay.self, KasusRound.self], inMemory: true)
}

#Preview("Kasus unit · Finden played") {
    let container = try! ModelContainer(
        for: LearnerProfile.self, StudyDay.self, KasusRound.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(KasusRound(
        storyID: "ks-dat-a2-schluessel", unitRaw: KasusUnit.dativ.rawValue, stepRaw: KasusRoundStep.find.rawValue,
        askedCount: 26, firstTryCount: 21, durationSeconds: 190
    ))
    return NavigationStack {
        KasusUnitView(unit: .dativ)
    }
    .environment(ActivityRouter())
    .modelContainer(container)
}
