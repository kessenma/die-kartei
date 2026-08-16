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

    @Environment(\.appTheme) private var appTheme

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

    @ViewBuilder private var breakdownSection: some View {
        Section {
            ForEach(blockTallies, id: \.block) { tally in
                HStack(spacing: 10) {
                    Image(systemName: tally.block.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(tally.block.label)
                        .font(.callout)
                    Spacer()
                    Text("\(tally.correct)/\(tally.asked)")
                        .font(.caption)
                        .foregroundStyle(tally.correct == tally.asked ? .green : .secondary)
                }
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
                    PlacementQuestionDetailView(record: record, attempts: [attempt])
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
