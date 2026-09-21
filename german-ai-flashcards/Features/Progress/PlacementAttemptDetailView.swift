//
//  PlacementAttemptDetailView.swift
//  german-ai-flashcards
//
//  One check, opened up: what it concluded, how each block went, and every question in ask-order.
//
//  Deliberately not built on `PlacementResultStage`. That view's pinned "Done" button and full-bleed
//  scroll are sheet chrome for the end of a run; in a pushed screen they'd render as a phantom
//  button that dismisses the wrong thing. Its `Footer` generic is the reuse point, and that's used
//  by the entry link in `PlacementQuizView`, not here.
//

import SwiftUI

struct PlacementAttemptDetailView: View {
    let attempt: PlacementAttempt
    /// The whole history, passed through so a question opened from *inside* one check can still
    /// show every other time it was asked. Defaults to just this check for callers that don't
    /// have the rest.
    var allAttempts: [PlacementAttempt]?
    /// Whether this check's estimate is the one currently steering the app.
    var isCurrent: Bool = false
    /// Adopt this check's estimate. Nil when the caller has no way to (the post-quiz link, where
    /// the run just finished *is* the current one).
    var onAdopt: (() -> Void)?

    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    private var history: [PlacementAttempt] { allAttempts ?? [attempt] }

    private var blockTallies: [(block: PlacementRecord.Block, correct: Int, asked: Int)] {
        PlacementRecord.Block.allCases.compactMap { block in
            let inBlock = attempt.records.filter { $0.block == block }
            guard !inBlock.isEmpty else { return nil }
            return (block: block, correct: inBlock.filter(\.isCorrect).count, asked: inBlock.count)
        }
    }

    private var exportDocument: PlacementExportDocument? {
        PlacementExport.document(attempt: attempt)
    }

    var body: some View {
        List {
            summarySection
            adoptSection
            if !blockTallies.isEmpty { breakdownSection }
            if !attempt.records.isEmpty { questionsSection }
        }
        .themedListScreen()
        .navigationTitle(attempt.takenAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let exportDocument {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: exportDocument,
                        preview: SharePreview("Placement check", image: Image(systemName: "doc.text"))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var summarySection: some View {
        Section {
            if attempt.isBeginnerDeclaration {
                Label("Starting from zero", systemImage: "leaf")
                    .font(.callout)
            } else {
                HStack {
                    stat(attempt.result.estimatedLevel.rawValue, "Estimate")
                    Divider()
                    stat("\(attempt.correctCount)/\(attempt.records.count)", "Right")
                    if attempt.skippedCount > 0 {
                        Divider()
                        stat("\(attempt.skippedCount)", "Skipped")
                    }
                }
                .padding(.vertical, 2)
            }
        } footer: {
            Text(attempt.isBeginnerDeclaration
                 ? "You chose the “I'm starting from zero” door, so nothing was asked and nothing was credited."
                 : "\(attempt.result.estimatedLevel.englishLabel). This estimate only ever outlined the Lernpyramide — it was never counted as built.")
                .font(.caption2)
        }
        .themedListRow()
    }

    /// Switching the live estimate to this check. Nothing is lost either way — the result stored on
    /// each check is exactly what that run concluded, so moving between them is reversible.
    @ViewBuilder private var adoptSection: some View {
        if let onAdopt {
            Section {
                if isCurrent {
                    Label("This check is setting your level", systemImage: "checkmark.seal.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        onAdopt()
                        dismiss()
                    } label: {
                        Label("Use this check's blueprint", systemImage: "checkmark.seal")
                            .font(.callout.weight(.medium))
                    }
                }
            } footer: {
                Text(isCurrent
                     ? "This check sets the level for stories and conversations, and draws the Lernpyramide's blueprint."
                     : "Switches your level and the pyramid's blueprint back to what this check found. Your other checks stay exactly where they are.")
                    .font(.caption2)
            }
            .themedListRow()
        }
    }

    @ViewBuilder private var breakdownSection: some View {
        Section {
            ForEach(blockTallies, id: \.block) { tally in
                HStack(spacing: 10) {
                    Image(systemName: tally.block.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)   // decoration beside its own name
                    Text(tally.block.label)
                        .font(.callout)
                    Spacer()
                    Text("\(tally.correct)/\(tally.asked)")
                        .font(.caption)
                        .foregroundStyle(tally.correct == tally.asked ? .green : .secondary)
                }
                // One element with a real sentence. `.accessibilityHidden` on the symbol isn't
                // enough on a plain (non-tappable) row — SwiftUI only folds children into one
                // element automatically when the row is interactive, so without this the row
                // announces as three fragments led by the SF Symbol's name ("Text On A Closed
                // Book", "Words", "4/8").
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(tally.block.label): \(tally.correct) of \(tally.asked) right")
            }
        } header: {
            Text("By block").themedSectionHeader()
        }
        .themedListRow()
    }

    @ViewBuilder private var questionsSection: some View {
        Section {
            ForEach(Array(attempt.records.enumerated()), id: \.offset) { _, record in
                NavigationLink {
                    PlacementQuestionDetailView(record: record, attempts: history)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: record.wasSkipped
                              ? "minus.circle"
                              : (record.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"))
                            .font(.caption)
                            .foregroundStyle(record.wasSkipped
                                             ? Color.secondary
                                             : (record.isCorrect ? .green : .orange))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.context ?? record.prompt)
                                .font(.callout)
                                .lineLimit(2)
                            Text(record.isCorrect
                                 ? record.correctChoice
                                 : "\(record.chosenChoice ?? "skipped") → \(record.correctChoice)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Questions in order").themedSectionHeader()
        }
        .themedListRow()
    }

    // MARK: - Helpers

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
