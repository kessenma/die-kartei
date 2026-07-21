//
//  GrammarHubView.swift
//  german-ai-flashcards
//
//  Every grammar activity on one screen: the coach's picks (from the learner profile),
//  AI-generated exercises, the bundled Akkusativ/Dativ drill categories, and the A1–B1
//  Perfekt verb decks (formerly separate Home rows). Replaces GrammarCategoryView.
//

import SwiftUI
import SwiftData

struct GrammarHubView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService
    let onStartFlipCards: (_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void
    let onStartMultipleChoice: (_ category: GrammarCategory, _ showHints: Bool) -> Void
    let onStartPastTenseStudy: (_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void

    @Query private var profiles: [LearnerProfile]

    @State private var categories: [GrammarCategory] = []
    @State private var isLoading = true
    /// Set to present the 30-second mini-lesson for a coach's pick.
    @State private var lessonFocus: GrammarFocus?

    private let caseOrder = ["akkusativ", "dativ"]

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().padding()
                    Spacer()
                }
            } else {
                coachSection
                aiSection
                articleSection
                ForEach(caseOrder.filter { grouped[$0] != nil }, id: \.self) { caseKey in
                    categorySection(caseKey)
                }
                perfektSection
            }
        }
        .navigationTitle("Grammar Exercises")
        .navigationBarTitleDisplayMode(.large)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .task {
            categories = GrammarExerciseService.loadCategories()
            isLoading = false
        }
        .sheet(item: $lessonFocus) { focus in
            GrammarLessonSheet(focus: focus)
        }
    }

    // MARK: - Learner profile inputs

    private var profile: LearnerProfile? { profiles.first }

    /// Shaky structures, worst-first (same threshold as the coach briefing / Today plan).
    private var weaknesses: [GrammarFocus] {
        guard let profile else { return [] }
        return profile.grammar
            .compactMap { key, skill -> (GrammarFocus, Double)? in
                guard skill.struggle >= GrammarSkill.shakyThreshold,
                      let f = GrammarFocus(rawValue: key) else { return nil }
                return (f, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func isWeak(_ focus: GrammarFocus) -> Bool {
        weaknesses.contains(focus)
    }

    /// Day-of-year — rotates which drill a coach's pick opens, mirroring the Today plan.
    private var dayIndex: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
    }

    // MARK: - Coach's picks

    @ViewBuilder
    private var coachSection: some View {
        if !weaknesses.isEmpty {
            Section {
                ForEach(weaknesses.prefix(3)) { focus in
                    coachRow(focus)
                }
            } header: {
                Text("Coach's Picks")
            } footer: {
                Text("Spots your conversations keep tripping on. Drilling them here updates what the coach remembers.")
            }
        }
    }

    @ViewBuilder
    private func coachRow(_ focus: GrammarFocus) -> some View {
        HStack(spacing: 12) {
            if focus == .artikel {
                // The der/die/das game is the drill for this skill.
                NavigationLink {
                    ArticleGameSetupView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    coachRowLabel(focus, subtitle: "Needs work · play a der/die/das round", chevron: false)
                }
            } else if let category = GrammarExerciseService.category(for: focus, rotation: dayIndex) {
                Button {
                    onStartMultipleChoice(category, true)
                } label: {
                    coachRowLabel(focus, subtitle: "Needs work · tap for a quick drill", chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    aiCreateView(preselectedFocus: focus)
                } label: {
                    coachRowLabel(focus, subtitle: "Needs work · create AI exercises", chevron: false)
                }
            }

            Button {
                lessonFocus = focus
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func coachRowLabel(_ focus: GrammarFocus, subtitle: String, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(focus.germanLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - AI exercises

    private var aiSection: some View {
        Section {
            NavigationLink {
                aiCreateView(preselectedFocus: nil)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create with AI")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Fresh exercises on your topic — or roll the dice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Make Your Own")
        }
    }

    private func aiCreateView(preselectedFocus: GrammarFocus?) -> some View {
        AIGrammarCreateView(
            modelManager: modelManager,
            mlxService: mlxService,
            preselectedFocus: preselectedFocus,
            onStart: onStartMultipleChoice
        )
    }

    // MARK: - Der/die/das game

    private var articleSection: some View {
        Section {
            NavigationLink {
                ArticleGameSetupView(modelManager: modelManager, mlxService: mlxService)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "textformat.abc")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Der · Die · Das")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Guess each noun's article — Goethe lists, the dictionary, or your own topic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            sectionHeader("Artikel · Noun Gender", focus: .artikel)
        }
    }

    // MARK: - Bundled categories (Akkusativ / Dativ)

    private var grouped: [String: [GrammarCategory]] {
        Dictionary(grouping: categories, by: \.grammaticalCase)
    }

    private func categorySection(_ caseKey: String) -> some View {
        Section {
            ForEach(grouped[caseKey]!) { category in
                NavigationLink {
                    GrammarCategoryDetailView(
                        category: category,
                        onStartFlipCards: onStartFlipCards,
                        onStartMultipleChoice: onStartMultipleChoice
                    )
                } label: {
                    GrammarCategoryRow(category: category)
                }
            }
        } header: {
            sectionHeader(caseKey.capitalized, focus: GrammarFocus(rawValue: caseKey))
        }
    }

    // MARK: - Perfekt verbs (A1–B1)

    private var perfektSection: some View {
        Section {
            ForEach(PastTenseLevel.allCases) { level in
                NavigationLink {
                    PastTenseLevelView(level: level, onStartStudy: onStartPastTenseStudy)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(level.rawValue) Perfekt Verbs")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(level.description) · sein/haben, participles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            sectionHeader("Perfekt · Past Tense", focus: .perfekt)
        }
    }

    // MARK: - Shared bits

    /// Section header with a "Needs work" flag when the coach considers that structure shaky.
    private func sectionHeader(_ title: String, focus: GrammarFocus?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let focus, isWeak(focus) {
                Label("Needs work", systemImage: "flame.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct GrammarCategoryRow: View {
    let category: GrammarCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(category.title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 6) {
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(category.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
