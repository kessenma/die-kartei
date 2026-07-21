//
//  TrickyPairsView.swift
//  german-ai-flashcards
//
//  The matching game's "same mistake" mirror, pushed from the deck picker's progress section.
//  Lists the pairs the learner keeps missing (`MatchingPairStat.isTricky`) with the wrong meaning
//  each one keeps being paired with. Pairs graduate off the list on their own after
//  `MatchingStatsService.graduationStreak` first-try rounds in a row; swipe removes one manually.
//

import SwiftUI
import SwiftData

struct TrickyPairsView: View {
    @Query private var stats: [MatchingPairStat]
    @Environment(\.modelContext) private var modelContext

    @State private var showResetConfirm = false

    private var trickyStats: [MatchingPairStat] {
        stats
            .filter(\.isTricky)
            .sorted {
                if $0.timesMissed != $1.timesMissed { return $0.timesMissed > $1.timesMissed }
                return ($0.lastMissedAt ?? .distantPast) > ($1.lastMissedAt ?? .distantPast)
            }
    }

    var body: some View {
        List {
            if trickyStats.isEmpty {
                ContentUnavailableView(
                    "No tricky pairs right now",
                    systemImage: "checkmark.seal",
                    description: Text("Pairs you miss in more than one round land here — and leave again once you match them first-try \(MatchingStatsService.graduationStreak) rounds in a row.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(trickyStats, id: \.key) { stat in
                        row(stat)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    MatchingStatsService.forgetPair(stat, in: modelContext)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    Text("Match a pair first-try \(MatchingStatsService.graduationStreak) rounds in a row and it graduates off this list. Swipe to remove one yourself.")
                }
            }
        }
        .navigationTitle("Tricky Pairs")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Reset matching history", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Reset matching history?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                MatchingStatsService.reset(in: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears every pair's miss history and all round records. Words already shared with the coach stay in its memory.")
        }
    }

    @ViewBuilder
    private func row(_ stat: MatchingPairStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(stat.displayGerman) — \(stat.english)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("missed ×\(stat.timesMissed)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.12), in: Capsule())
            }
            if let confusion = stat.topConfusion, stat.confusions[confusion, default: 0] >= 2 {
                Text("You keep pairing it with “\(confusion)”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lastMissed = stat.lastMissedAt {
                Text("Seen in \(stat.timesSeen) round\(stat.timesSeen == 1 ? "" : "s") · last missed \(lastMissed.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
