//
//  PlacementQuestionDetailView.swift
//  german-ai-flashcards
//
//  One question, opened up: every option with the right answer and your pick marked, the authored
//  explanation, and the record of every time the probe has asked it.
//
//  The explanations are the point. `placement_grammar.json` carries an `english` gloss and a `why`
//  for all 42 items and all 12 cloze gaps, and until this screen existed nothing in the app ever
//  showed them — the quiz can't, by design. They're looked up live through `PlacementGrammarBank`
//  rather than copied into the record, so re-authoring the bank improves reviews of old attempts
//  instead of leaving a stale explanation frozen in history.
//

import SwiftUI

struct PlacementQuestionDetailView: View {
    let record: PlacementRecord
    /// The whole history, so the "every time you were asked this" section can find the others.
    let attempts: [PlacementAttempt]

    @Environment(\.appTheme) private var appTheme

    /// This same question across every attempt, newest first.
    private var occurrences: [(attempt: PlacementAttempt, record: PlacementRecord)] {
        attempts.compactMap { attempt in
            attempt.records
                .first { $0.questionKey == record.questionKey }
                .map { (attempt: attempt, record: $0) }
        }
    }

    private var bankItem: PlacementGrammarItem? {
        guard record.block == .grammar, let sourceID = record.sourceID else { return nil }
        return PlacementGrammarBank.item(id: sourceID)
    }

    private var clozeGap: PlacementClozeGap? {
        guard record.block == .cloze, let sourceID = record.sourceID, let gap = record.gap else { return nil }
        return PlacementGrammarBank.clozeGap(paragraphID: sourceID, gap: gap)
    }

    /// Nil for the word blocks, which have no authored explanation — a vocabulary item's answer
    /// *is* its explanation.
    private var explanation: (english: String?, why: String?)? {
        if let bankItem { return (bankItem.english, bankItem.why) }
        if let clozeGap { return (nil, clozeGap.why) }
        return nil
    }

    /// True when this question came from the bank but the bank no longer has it.
    private var explanationMissing: Bool {
        (record.block == .grammar || record.block == .cloze) && explanation == nil
    }

    var body: some View {
        List {
            questionSection
            choicesSection
            explanationSection
            historySection
        }
        .themedListScreen()
        .navigationTitle(record.block.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    @ViewBuilder private var questionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.context ?? record.prompt)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = record.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Label(record.block.label, systemImage: record.block.systemImage)
                    if let level = record.cefrLevel {
                        Text("·")
                        Text("\(level.rawValue) · \(level.englishLabel)")
                    }
                    if record.isAnchor {
                        Text("·")
                        Text("asked every check")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("The question").themedSectionHeader()
        }
        .themedListRow()
    }

    @ViewBuilder private var choicesSection: some View {
        Section {
            ForEach(Array(record.choices.enumerated()), id: \.offset) { index, choice in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: index))
                        .foregroundStyle(color(for: index))
                        .frame(width: 20)
                    Text(choice)
                        .font(.callout)
                        .fontWeight(index == record.correctIndex ? .semibold : .regular)
                    Spacer()
                    if index == record.chosenIndex {
                        Text("you picked")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 1)
            }
            if record.wasSkipped {
                Text("You skipped this one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Options").themedSectionHeader()
        }
        .themedListRow()
    }

    @ViewBuilder private var explanationSection: some View {
        if let explanation, explanation.english != nil || explanation.why != nil {
            Section {
                if let english = explanation.english, !english.isEmpty {
                    Text(english)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let why = explanation.why, !why.isEmpty {
                    Text(why)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Why").themedSectionHeader()
            }
            .themedListRow()
        } else if explanationMissing {
            Section {
                Text("Explanation unavailable — this question came from question bank v\(bankVersionShown).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .themedListRow()
        }
    }

    private var bankVersionShown: Int {
        occurrences.first?.attempt.bankVersion ?? PlacementGrammarBank.version
    }

    @ViewBuilder private var historySection: some View {
        if occurrences.count > 1 {
            Section {
                ForEach(occurrences, id: \.attempt.id) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.record.wasSkipped
                              ? "minus.circle"
                              : (entry.record.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"))
                            .font(.caption)
                            .foregroundStyle(entry.record.wasSkipped
                                             ? Color.secondary
                                             : (entry.record.isCorrect ? .green : .orange))
                            .frame(width: 18)
                        Text(entry.attempt.takenAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout)
                        Spacer()
                        Text(entry.record.chosenChoice ?? "skipped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Every time you were asked this").themedSectionHeader()
            } footer: {
                Text("The two anchor questions open every check, so they show up on every line.")
                    .font(.caption2)
            }
            .themedListRow()
        }
    }

    // MARK: - Helpers

    private func icon(for index: Int) -> String {
        if index == record.correctIndex { return "checkmark.circle.fill" }
        if index == record.chosenIndex { return "xmark.circle.fill" }
        return "circle"
    }

    private func color(for index: Int) -> Color {
        if index == record.correctIndex { return .green }
        if index == record.chosenIndex { return .orange }
        return Color(.tertiaryLabel)
    }
}
