//
//  PlacementReviewView.swift
//  german-ai-flashcards
//
//  "See what you missed" — every question the placement probe has ever asked, across every attempt,
//  filterable and exportable.
//
//  This is the deliberate counterpart to the quiz's no-feedback rule. During a run the probe tells
//  you nothing, because feedback would turn a measurement into a lesson and let a learner tune their
//  answers partway through. Once it's over none of that applies, and the run is the single richest
//  picture of the learner's German the app ever takes — twenty-nine graded items in three minutes.
//  Throwing it away was the loss this screen exists to undo.
//
//  Reads `PlacementAttemptStore` and nothing else. The one path from here into the app's memory is
//  the explicit hand-off button, which goes through `PlacementCoachExport`.
//

import SwiftData
import SwiftUI

struct PlacementReviewView: View {
    /// Opens pre-filtered to one run — used from the result stage, where "what did I just miss" is
    /// the only question being asked.
    var initialAttemptID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var attempts: [PlacementAttempt] = []
    @State private var filter = PlacementReviewFilter()
    @State private var exportDocument: PlacementExportDocument?
    @State private var showDeleteAllConfirm = false
    @State private var handoffMessage: String?

    // MARK: - Derived

    /// Every question ever asked, newest attempt first, ask-order within an attempt. Beginner
    /// declarations contribute nothing here by construction — they asked nothing.
    private var allItems: [PlacementReviewItem] {
        attempts.flatMap { attempt in
            attempt.records.enumerated().map { index, record in
                PlacementReviewItem(
                    attemptID: attempt.id,
                    attemptAt: attempt.takenAt,
                    index: index,
                    record: record
                )
            }
        }
    }

    /// How often each question has been missed across the whole history. A repeat count is a
    /// property of the corpus, not of a row, so it's computed once here and handed to `matches`.
    private var missCounts: [String: Int] {
        allItems.reduce(into: [:]) { counts, item in
            guard !item.record.isCorrect else { return }
            counts[item.record.questionKey, default: 0] += 1
        }
    }

    private var visibleItems: [PlacementReviewItem] {
        guard filter.isActive else { return allItems }
        let counts = missCounts
        return allItems.filter { filter.matches($0, missCounts: counts) }
    }

    private var hasRepeats: Bool { missCounts.values.contains { $0 > 1 } }

    var body: some View {
        Group {
            if attempts.isEmpty {
                ContentUnavailableView(
                    "No checks yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Take the placement check and every question you answer shows up here — right and wrong, with the explanation the quiz deliberately withholds while you're taking it.")
                )
            } else {
                List {
                    if !allItems.isEmpty {
                        filterSection
                    }
                    questionsSection
                    attemptsSection
                    handoffSection
                    manageSection
                }
                .themedListScreen()
            }
        }
        .navigationTitle("Your answers")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            if !attempts.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    if let exportDocument {
                        ShareLink(
                            item: exportDocument,
                            preview: SharePreview("Placement results", image: Image(systemName: "doc.text"))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .task {
            attempts = PlacementAttemptStore.attempts()
            if let initialAttemptID, attempts.contains(where: { $0.id == initialAttemptID }) {
                filter.attemptID = initialAttemptID
            }
            rebuildExport()
        }
        .onChange(of: filter) { _, _ in rebuildExport() }
        .alert("Delete every recorded check?", isPresented: $showDeleteAllConfirm) {
            Button("Delete all", role: .destructive) {
                PlacementAttemptStore.deleteAll()
                attempts = []
                filter = PlacementReviewFilter()
                rebuildExport()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the questions and answers only. Your level estimate and everything you've built on the Lernpyramide stay exactly as they are.")
        }
    }

    // MARK: - Filters

    @ViewBuilder private var filterSection: some View {
        Section {
            PlacementFilterBar(
                filter: $filter,
                blocks: presentBlocks,
                levels: presentLevels,
                attempts: recentAttempts,
                showsRepeats: hasRepeats
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            HStack {
                Text("Filter").themedSectionHeader()
                Spacer()
                if filter.isActive {
                    Button("Clear") {
                        withAnimation(.snappy(duration: 0.25)) { filter = PlacementReviewFilter() }
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
                }
            }
        } footer: {
            if filter.levelRaw != nil {
                Text("Level filters cover the words, grammar and cloze blocks — der/die/das and cases aren't asked at a level.")
                    .font(.caption2)
            }
        }
    }

    private var presentBlocks: [PlacementRecord.Block] {
        let present = Set(allItems.map(\.record.block))
        return PlacementRecord.Block.allCases.filter(present.contains)
    }

    private var presentLevels: [CEFRLevel] {
        let present = Set(allItems.compactMap(\.record.levelRaw))
        return CEFRLevel.allCases.filter { present.contains($0.rawValue) }
    }

    /// The strip only offers the most recent handful — the Attempts section below reaches the rest,
    /// and a pill row that grows forever stops being a filter and becomes a list.
    private var recentAttempts: [PlacementAttempt] {
        Array(attempts.filter { !$0.records.isEmpty }.prefix(8))
    }

    // MARK: - Questions

    @ViewBuilder private var questionsSection: some View {
        let visible = visibleItems
        Section {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No question fits every filter you've set.")
                } actions: {
                    Button("Clear filters") {
                        withAnimation(.snappy(duration: 0.25)) { filter = PlacementReviewFilter() }
                    }
                }
                .padding(.vertical, 8)
            } else {
                ForEach(visible) { item in
                    NavigationLink {
                        PlacementQuestionDetailView(record: item.record, attempts: attempts)
                    } label: {
                        PlacementReviewRow(
                            record: item.record,
                            missCount: missCounts[item.record.questionKey] ?? 0
                        )
                    }
                }
            }
        } header: {
            HStack {
                Text("Questions").themedSectionHeader()
                Spacer()
                if filter.isActive {
                    Text("\(visible.count) of \(allItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .themedListRow()
    }

    // MARK: - Attempts

    @ViewBuilder private var attemptsSection: some View {
        Section {
            ForEach(attempts) { attempt in
                NavigationLink {
                    PlacementAttemptDetailView(attempt: attempt)
                } label: {
                    PlacementAttemptRow(attempt: attempt)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        PlacementAttemptStore.delete(id: attempt.id)
                        attempts = PlacementAttemptStore.attempts()
                        if filter.attemptID == attempt.id { filter.attemptID = nil }
                        rebuildExport()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Checks you've taken").themedSectionHeader()
        } footer: {
            Text("Each check keeps its own estimate and its own answers. Retaking never overwrites an older one.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Coach hand-off

    @ViewBuilder private var handoffSection: some View {
        let plan = PlacementCoachExport.pendingPlan(in: attempts)
        Section {
            Button {
                let summary = PlacementCoachExport.send(plan, in: modelContext)
                withAnimation { handoffMessage = summary }
            } label: {
                Label(plan.buttonTitle, systemImage: "brain.head.profile")
            }
            .disabled(plan.isEmpty)

            if let handoffMessage {
                Label(handoffMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Send to the coach").themedSectionHeader()
        } footer: {
            Text(plan.isEmpty
                 ? "Everything you've missed has already been sent. Take the check again to gather new material."
                 : "Words you missed join the ones the coach works into conversations; grammar you missed becomes a sentence to fix. Your level estimate is never sent — the coach only ever hears what you actually got wrong.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Manage

    @ViewBuilder private var manageSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label("Delete recorded answers", systemImage: "trash")
            }
        } footer: {
            Text("Separate from “Remove the estimate” on the Lernpyramide — that clears your level, this clears the questions.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Export

    /// Memoized rather than computed in `body`: the encoder would otherwise re-run over the whole
    /// history on every render pass.
    private func rebuildExport() {
        exportDocument = PlacementExport.document(
            attempts: attempts,
            visible: visibleItems,
            filter: filter
        )
    }
}

// MARK: - Rows

/// One question, in the same shape Coach's Notes uses for a slip — struck-through wrong form, arrow,
/// right form — so the two screens read as one family.
private struct PlacementReviewRow: View {
    let record: PlacementRecord
    let missCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: outcomeIcon)
                .font(.caption)
                .foregroundStyle(outcomeColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.context ?? record.prompt)
                    .font(.callout)
                    .lineLimit(2)

                if record.isCorrect {
                    Text(record.correctChoice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Text(record.chosenChoice ?? "skipped")
                            .strikethrough(!record.wasSkipped)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(record.correctChoice)
                            .foregroundStyle(.primary)
                    }
                    .font(.caption)
                }

                HStack(spacing: 6) {
                    Label(record.block.label, systemImage: record.block.systemImage)
                    if let level = record.cefrLevel {
                        Text("·")
                        Text(level.rawValue)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if missCount > 1 {
                Text("×\(missCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var outcomeIcon: String {
        if record.wasSkipped { return "minus.circle" }
        return record.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var outcomeColor: Color {
        if record.wasSkipped { return .secondary }
        return record.isCorrect ? .green : .orange
    }
}

/// One attempt in the history list.
private struct PlacementAttemptRow: View {
    let attempt: PlacementAttempt

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(attempt.takenAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !attempt.isBeginnerDeclaration {
                CEFRLevelChip(level: attempt.result.estimatedLevel)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if attempt.isBeginnerDeclaration { return "Starting from zero — no questions asked" }
        var parts = ["\(attempt.correctCount) of \(attempt.records.count) right"]
        if attempt.skippedCount > 0 { parts.append("\(attempt.skippedCount) skipped") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Preview

#Preview("Placement review · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                PlacementReviewView()
            }
            .environment(\.appTheme, theme)
        }
    }
    .tabViewStyle(.page)
}
