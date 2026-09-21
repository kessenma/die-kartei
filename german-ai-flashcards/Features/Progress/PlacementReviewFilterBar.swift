//
//  PlacementReviewFilterBar.swift
//  german-ai-flashcards
//
//  The placement review's filters and the pill strip that drives them. Same shape as
//  `StoryListFilterBar` — an `Equatable` filter struct that knows how to match a row, and a bar of
//  horizontally scrolling pills whose every mutation goes through one animated `set` — and it shares
//  that screen's `FilterPill`. The strips themselves stay separate: each speaks its own screen's
//  vocabulary, and a "general" filter bar would end up a worse version of both.
//

import SwiftUI

// MARK: - Filter

/// The review list's filters. Every field nil (and `repeatMisses` nil) means "show everything", so
/// a fresh `PlacementReviewFilter()` is the whole history.
struct PlacementReviewFilter: Equatable {

    enum Outcome: String, CaseIterable, Identifiable {
        case wrong, right, skipped

        var id: String { rawValue }

        var label: String {
            switch self {
            case .wrong:   "Missed"
            case .right:   "Right"
            case .skipped: "Skipped"
            }
        }

        var systemImage: String {
            switch self {
            case .wrong:   "xmark.circle"
            case .right:   "checkmark.circle"
            case .skipped: "minus.circle"
            }
        }

        var tint: Color {
            switch self {
            case .wrong:   .orange
            case .right:   .green
            case .skipped: .secondary
            }
        }
    }

    var outcome: Outcome?
    var block: PlacementRecord.Block?
    /// One axis over both ladders: `GoetheLevel` supplies A1–B1 for vocabulary, the grammar
    /// staircase adds B2. They share the raw-value namespace, so one filter covers both.
    var levelRaw: String?
    /// The date filter — attempts are the only dates a question has.
    var attemptID: UUID?
    /// "Missed 2+ / 3+ times" across the whole history.
    var repeatMisses: Int?

    var isActive: Bool {
        outcome != nil || block != nil || levelRaw != nil || attemptID != nil || repeatMisses != nil
    }

    /// Unlike `StoryListFilter.matches`, this needs a fact about the whole corpus: how often a
    /// question has been missed. Caller computes `missCounts` once per render — doing it per row
    /// would be quadratic in the history.
    func matches(_ item: PlacementReviewItem, missCounts: [String: Int]) -> Bool {
        let record = item.record

        if let outcome {
            switch outcome {
            case .wrong:   if record.isCorrect || record.wasSkipped { return false }
            case .right:   if !record.isCorrect { return false }
            case .skipped: if !record.wasSkipped { return false }
            }
        }
        if let block, record.block != block { return false }
        // A record with no level drops out under a level filter — gender and prepositions aren't
        // asked at a level at all. The screen's footer says so rather than leaving it a mystery.
        if let levelRaw, record.levelRaw != levelRaw { return false }
        if let attemptID, item.attemptID != attemptID { return false }
        if let repeatMisses {
            // The *misses* themselves, not every encounter of a repeatedly-missed question. A row
            // you got right is not a "missed 2+" row however often you've fumbled it elsewhere —
            // the improvement arc belongs in the question detail's "every time you were asked
            // this", where it reads as progress instead of contradicting the pill's label.
            if record.isCorrect { return false }
            if (missCounts[record.questionKey] ?? 0) < repeatMisses { return false }
        }
        return true
    }
}

// MARK: - Bar

struct PlacementFilterBar: View {
    @Binding var filter: PlacementReviewFilter

    /// Only what the history actually contains, so no pill can lead to an empty list.
    let blocks: [PlacementRecord.Block]
    let levels: [CEFRLevel]
    let attempts: [PlacementAttempt]
    let showsRepeats: Bool

    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme

    private var accent: Color { appTheme.accent(model: modelTheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            strip {
                ForEach(PlacementReviewFilter.Outcome.allCases) { outcome in
                    FilterPill(
                        label: outcome.label,
                        systemImage: outcome.systemImage,
                        tint: outcome.tint,
                        isOn: filter.outcome == outcome
                    ) {
                        set { $0.outcome = $0.outcome == outcome ? nil : outcome }
                    }
                }

                if showsRepeats {
                    groupDivider
                    ForEach([2, 3], id: \.self) { threshold in
                        FilterPill(
                            label: "Missed \(threshold)+",
                            systemImage: "repeat",
                            tint: .pink,
                            isOn: filter.repeatMisses == threshold
                        ) {
                            set { $0.repeatMisses = $0.repeatMisses == threshold ? nil : threshold }
                        }
                    }
                }
            }

            if !blocks.isEmpty || !levels.isEmpty {
                strip {
                    ForEach(blocks) { block in
                        FilterPill(
                            label: block.label,
                            systemImage: block.systemImage,
                            tint: accent,
                            isOn: filter.block == block
                        ) {
                            set { $0.block = $0.block == block ? nil : block }
                        }
                    }

                    if !blocks.isEmpty && !levels.isEmpty { groupDivider }

                    ForEach(levels) { level in
                        FilterPill(
                            label: level.rawValue,
                            tint: level.chipColor,
                            isOn: filter.levelRaw == level.rawValue
                        ) {
                            set { $0.levelRaw = $0.levelRaw == level.rawValue ? nil : level.rawValue }
                        }
                    }
                }
            }

            if attempts.count > 1 {
                strip {
                    ForEach(attempts) { attempt in
                        FilterPill(
                            label: attempt.takenAt.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar",
                            tint: .purple,
                            isOn: filter.attemptID == attempt.id
                        ) {
                            set { $0.attemptID = $0.attemptID == attempt.id ? nil : attempt.id }
                        }
                    }
                }
            }
        }
    }

    /// One horizontally scrolling line of pills, inset to sit under the section header's text.
    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }

    /// Every pill mutates through here so the rows animate in and out with the pill's own state.
    private func set(_ change: (inout PlacementReviewFilter) -> Void) {
        var updated = filter
        change(&updated)
        withAnimation(.snappy(duration: 0.25)) { filter = updated }
    }
}
