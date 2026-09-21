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

    /// Two ways in, because there are two questions a learner asks here and they want different
    /// shapes. *Checks* is the default: one row per run, opening onto that run's own results — the
    /// way you'd think about "how did I do in March vs. now". *Questions* flattens every run into
    /// one filterable list, which is the only shape that can answer "what do I keep getting wrong",
    /// since that's a fact about the history rather than about any single check.
    private enum Tab: String, CaseIterable, Identifiable {
        case checks, questions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .checks:    "Checks"
            case .questions: "Questions"
            }
        }
    }

    /// Needed to take a new check from here, and to adopt an older one's estimate as the content
    /// level — the two things that make this screen the home of the assessment rather than a
    /// read-only log hanging off it.
    var modelManager: MLXModelManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var tab: Tab = .checks
    @State private var attempts: [PlacementAttempt] = []
    @State private var filter = PlacementReviewFilter()
    @State private var exportDocument: PlacementExportDocument?
    @State private var showDeleteAllConfirm = false
    @State private var handoffMessage: String?
    @State private var showQuiz = false
    /// Bumped after anything that changes which estimate is live, since it lives in UserDefaults
    /// and SwiftUI can't observe it.
    @State private var estimateRevision = 0

    /// The check whose estimate is currently steering the pyramid and the content levels.
    /// `PlacementResult` is `Equatable`, so this is an exact match rather than a date heuristic.
    private var currentResult: PlacementResult? {
        _ = estimateRevision
        return PlacementService.current
    }

    private func isCurrent(_ attempt: PlacementAttempt) -> Bool {
        currentResult == attempt.result
    }

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

    /// The rows the Questions tab shows. On the Checks tab the filter is irrelevant, so the export
    /// there covers everything — "export what's on screen" still holds, the screen is just wider.
    private var visibleItems: [PlacementReviewItem] {
        guard tab == .questions, filter.isActive else { return allItems }
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
                    switch tab {
                    case .checks:
                        takeCheckSection
                        attemptsSection
                        handoffSection
                        manageSection
                    case .questions:
                        if !allItems.isEmpty { filterSection }
                        questionsSection
                    }
                }
                .themedListScreen()
            }
        }
        .navigationTitle("Your answers")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            if !attempts.isEmpty, allItems.isEmpty == false {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
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
        .sheet(isPresented: $showQuiz) {
            PlacementQuizView(modelManager: modelManager) { _ in
                // The quiz records and adopts on its own; this just pulls the new run into the list
                // so it lands at the top with the others still under it.
                attempts = PlacementAttemptStore.attempts()
                estimateRevision += 1
                rebuildExport()
            }
        }
        .task {
            attempts = PlacementAttemptStore.attempts()
            rebuildExport()
        }
        .onChange(of: filter) { _, _ in rebuildExport() }
        .onChange(of: tab) { _, _ in rebuildExport() }
        .alert("Delete every recorded check?", isPresented: $showDeleteAllConfirm) {
            Button("Delete all", role: .destructive) {
                PlacementAttemptStore.deleteAll()
                attempts = []
                filter = PlacementReviewFilter()
                rebuildExport()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the questions and answers only. Your level, the blueprint, and everything you've built on the Lernpyramide stay exactly as they are.")
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

    // MARK: - Take another

    @ViewBuilder private var takeCheckSection: some View {
        Section {
            Button {
                showQuiz = true
            } label: {
                Label(attempts.isEmpty ? "Take the check" : "Take the check again",
                      systemImage: "person.crop.circle.badge.questionmark")
                    .font(.callout.weight(.medium))
            }
        } footer: {
            Text("Three minutes, offline. A new check joins the list below — it never replaces the ones you've already taken.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Attempts

    @ViewBuilder private var attemptsSection: some View {
        Section {
            ForEach(Array(attempts.enumerated()), id: \.element.id) { index, attempt in
                NavigationLink {
                    PlacementAttemptDetailView(
                        attempt: attempt,
                        allAttempts: attempts,
                        isCurrent: isCurrent(attempt),
                        onAdopt: { adopt(attempt) }
                    )
                } label: {
                    PlacementAttemptRow(
                        attempt: attempt,
                        // The next one down the list is the older one — the thing this check is
                        // naturally read against.
                        previous: attempts.indices.contains(index + 1) ? attempts[index + 1] : nil,
                        isCurrent: isCurrent(attempt),
                        missCounts: missCounts
                    )
                }
                .swipeActions(edge: .leading) {
                    if !isCurrent(attempt) {
                        Button {
                            adopt(attempt)
                        } label: {
                            Label("Use this", systemImage: "checkmark.seal")
                        }
                        .tint(.green)
                    }
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
            Text(currentResult == nil
                 ? "No blueprint is applied right now. Swipe a check and choose “Use this” to apply its blueprint again."
                 : "Tap a check to see how it went question by question. The one marked *Now in use* sets your level and draws the pyramid's blueprint; swipe an older one to switch back to it.")
                .font(.caption2)
        }
        .themedListRow()
    }

    /// Adopt a check's estimate — the same two writes the quiz itself makes when it finishes.
    /// Nothing is deleted and nothing is recomputed: the stored result *is* what the quiz concluded
    /// at the time, so switching between checks is lossless in both directions.
    private func adopt(_ attempt: PlacementAttempt) {
        PlacementService.save(attempt.result)
        modelManager.germanLevel = attempt.result.estimatedLevel
        modelManager.germanLevelIsDeclared = attempt.result.declaredBeginner
        withAnimation { estimateRevision += 1 }
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
                 : "Words you missed join the ones the coach works into conversations; grammar you missed becomes a sentence to fix. Your level and blueprint are never sent — the coach only ever hears what you actually got wrong.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Manage

    @ViewBuilder private var manageSection: some View {
        Section {
            // Not destructive any more, and deliberately not labelled as though it were. It used to
            // be the only way to "undo" a check, which made the estimate feel like a single slot you
            // had to clear. Now that every check is kept, this just stops applying one — and any
            // check in the list can be switched back on.
            if currentResult != nil {
                Button {
                    PlacementService.clear()
                    withAnimation { estimateRevision += 1 }
                } label: {
                    Label("Put the blueprint away", systemImage: "eye.slash")
                }
            }

            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label("Delete recorded answers", systemImage: "trash")
            }
        } footer: {
            Text("Putting the blueprint away empties the pyramid's dashed outline and leaves everything you've proven untouched — your checks stay in the list, so you can apply one again whenever you like. Deleting is the only thing here that actually loses anything.")
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
                    // The symbol is decoration beside its own name — without this VoiceOver reads
                    // "Text On A Closed Book, Words".
                    Image(systemName: record.block.systemImage).accessibilityHidden(true)
                    Text(record.block.label)
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

/// One check in the history list — the screen's front door, so it carries a little more than a
/// date: the score as a bar you can compare down the column, and how many of its misses are ones
/// the learner keeps making.
private struct PlacementAttemptRow: View {
    let attempt: PlacementAttempt
    /// The next-older check, for the "how did this compare" line. Nil on the very first one.
    let previous: PlacementAttempt?
    let isCurrent: Bool
    let missCounts: [String: Int]

    private var fraction: Double {
        guard !attempt.records.isEmpty else { return 0 }
        return Double(attempt.correctCount) / Double(attempt.records.count)
    }

    private func fraction(of attempt: PlacementAttempt) -> Double {
        guard !attempt.records.isEmpty else { return 0 }
        return Double(attempt.correctCount) / Double(attempt.records.count)
    }

    /// Level movement and score movement against the previous check. Both nil when there's nothing
    /// to compare against, or when either side was the "starting from zero" door — that isn't a
    /// score and pretending it is would manufacture a drop.
    private var comparison: (text: String, systemImage: String, color: Color)? {
        guard let previous,
              !attempt.isBeginnerDeclaration, !previous.isBeginnerDeclaration,
              !attempt.records.isEmpty, !previous.records.isEmpty
        else { return nil }

        let ladder = CEFRLevel.allCases
        let now = ladder.firstIndex(of: attempt.result.estimatedLevel) ?? 0
        let before = ladder.firstIndex(of: previous.result.estimatedLevel) ?? 0
        let points = Int(((fraction - fraction(of: previous)) * 100).rounded())

        var parts: [String] = []
        if now != before {
            parts.append("\(previous.result.estimatedLevel.rawValue) → \(attempt.result.estimatedLevel.rawValue)")
        }
        if points != 0 {
            parts.append("\(points > 0 ? "+" : "")\(points) pts")
        }
        guard !parts.isEmpty else {
            return ("same as last time", "equal", .secondary)
        }

        let rising = now > before || (now == before && points > 0)
        return (
            parts.joined(separator: " · "),
            rising ? "arrow.up.right" : "arrow.down.right",
            rising ? .green : .orange
        )
    }

    private var repeatMisses: Int {
        attempt.records.filter { !$0.isCorrect && (missCounts[$0.questionKey] ?? 0) > 1 }.count
    }

    private var color: Color {
        switch fraction {
        case ..<0.4: .orange
        case ..<0.7: .yellow
        default:     .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(attempt.takenAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout.weight(.medium))
                        if isCurrent {
                            Text("Now in use")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !attempt.isBeginnerDeclaration {
                    CEFRLevelChip(level: attempt.result.estimatedLevel)
                }
            }
            if !attempt.records.isEmpty {
                ScoreBar(fraction: fraction, color: color)
            }
            if let comparison {
                HStack(spacing: 4) {
                    Image(systemName: comparison.systemImage).accessibilityHidden(true)
                    Text(comparison.text)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(comparison.color)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if attempt.isBeginnerDeclaration { return "Starting from zero — no questions asked" }
        var parts = ["\(attempt.correctCount) of \(attempt.records.count) right"]
        if attempt.skippedCount > 0 { parts.append("\(attempt.skippedCount) skipped") }
        if repeatMisses > 0 { parts.append("\(repeatMisses) you keep missing") }
        return parts.joined(separator: " · ")
    }
}

/// A thin capsule filled to `fraction`, matching the confidence bars in Coach's Notes.
private struct ScoreBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule().fill(color)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Preview

#Preview("Placement review · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                PlacementReviewView(modelManager: MLXModelManager())
            }
            .environment(\.appTheme, theme)
        }
    }
    .tabViewStyle(.page)
}
