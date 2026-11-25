//
//  ConversationQualityView.swift
//  german-ai-flashcards
//
//  Fortschritt ▸ Gespräche — what the learner's conversation history actually looks like, and the
//  measurement behind the Spitze's quality bar.
//
//  The Spitze is the only layer gated on a number that couldn't be settled by simulation:
//  correction density depends on how the coach model actually corrects real speech. So rather than
//  hard-code a bar and hope, this screen shows the real distribution and exactly how many
//  conversations would count at each candidate bar — the same "build the missing measurement"
//  discipline the placement cutoffs went through.
//

import SwiftUI
import SwiftData

struct ConversationQualityView: View {
    @Environment(\.appTheme) private var theme

    @Query(sort: \ChatConversation.createdAt, order: .reverse)
    private var conversations: [ChatConversation]

    private var distribution: ConversationQualityService.Distribution {
        ConversationQualityService.distribution(conversations)
    }

    var body: some View {
        List {
            let stats = distribution

            if stats.isEmpty {
                Section {
                    Text("No finished conversations yet. Hold a few chats and this fills in.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .themedListRow()
            } else {
                summarySection(stats)
                barsSection(stats)
            }
        }
        .navigationTitle("Gespräche · Conversations")
        .navigationBarTitleDisplayMode(.inline)
        .themedListScreen()
    }

    private func summarySection(_ stats: ConversationQualityService.Distribution) -> some View {
        Section {
            row("Conversations", "\(stats.total)")
            row("Long enough to judge", "\(stats.judged)")
            if stats.tooShort > 0 {
                row("Too short (under \(ConversationQualityService.minimumTurns) turns)", "\(stats.tooShort)")
            }
            if let lower = stats.lowerQuartile, let median = stats.median, let upper = stats.upperQuartile {
                row("Corrections per turn", "\(fmt(lower)) · \(fmt(median)) · \(fmt(upper))")
            }
        } header: {
            Text("Deine Zahlen · Your Numbers").themedSectionHeader()
        } footer: {
            Text("Corrections per turn shown as lower quartile · median · upper quartile. Lower is better held.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func barsSection(_ stats: ConversationQualityService.Distribution) -> some View {
        Section {
            ForEach(stats.clearing, id: \.bar) { entry in
                HStack {
                    Text("≤ \(fmt(entry.bar)) per turn")
                        .font(.subheadline)
                        .fontWeight(entry.bar == ConversationQualityService.qualityDensityBar ? .semibold : .regular)
                    Spacer()
                    Text("\(entry.count) of \(stats.judged)")
                        .font(.subheadline)
                        .foregroundStyle(entry.bar == ConversationQualityService.qualityDensityBar ? .primary : .secondary)
                }
            }
        } header: {
            Text("Mögliche Messlatte · Candidate Bars").themedSectionHeader()
        } footer: {
            Text("The Spitze currently counts a conversation as well held at ≤ \(fmt(ConversationQualityService.qualityDensityBar)) corrections per turn, and asks for \(ConversationQualityService.qualityGoal) of them. If that reads too strict or too easy against your own numbers above, it's one constant in ConversationQualityService.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func fmt(_ value: Double) -> String { String(format: "%.2f", value) }
}
