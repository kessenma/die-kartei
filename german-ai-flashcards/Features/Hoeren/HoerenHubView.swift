//
//  HoerenHubView.swift
//  german-ai-flashcards
//
//  The Hören room (docs/HOEREN.md): listening as a skill of its own. DLI's tests are mostly
//  listening tasks, so the room borrows three of their objectives: numbers heard once, a
//  dictation, and the gist of a story in your own words. The first two need no tutor model.
//

import SwiftData
import SwiftUI

struct HoerenHubView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Query(sort: \HoerenRound.date, order: .reverse) private var rounds: [HoerenRound]

    private var recent: [HoerenRound] { Array(rounds.prefix(5)) }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ZahlenSetupView(modelManager: modelManager)
                } label: {
                    row(.zahlen, "Prices, times, dates and phone numbers, heard once. You type the digits.")
                }
                NavigationLink {
                    DiktatSetupView(modelManager: modelManager)
                } label: {
                    row(.diktat, "Hear a sentence, write it, and see which endings you missed.")
                }
                NavigationLink {
                    HoerenStoryPickerView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    row(.gist, "Guess the words first, listen to a story, then say what it was about.")
                }
            } header: {
                Text("Hören").themedSectionHeader()
            } footer: {
                Text("Listening is its own skill: the ear has to keep up without the text. These follow how the US Defense Language Institute tests it.")
            }
            .themedListRow()

            if !recent.isEmpty {
                Section {
                    ForEach(recent) { round in
                        HoerenRoundRow(round: round)
                    }
                } header: {
                    Text("Zuletzt · Recent").themedSectionHeader()
                }
                .themedListRow()
            }

            Section {
                NavigationLink {
                    HoerenStatsView()
                } label: {
                    Label {
                        Text("Statistik · What you hear well")
                    } icon: {
                        Image(systemName: "chart.bar").foregroundStyle(HoerenTile.tint)
                    }
                }
            } footer: {
                Text("Rounds reach your other devices through iCloud Sync when it is on.")
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle(HoerenTile.title)
    }

    private func row(_ kind: HoerenRoundKind, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(HoerenTile.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(kind.germanLabel) · \(kind.englishLabel)").font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct HoerenRoundRow: View {
    let round: HoerenRound

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: round.kind?.systemImage ?? "headphones")
                .foregroundStyle(HoerenTile.tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(round.summaryLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(round.date, format: .dateTime.day().month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var title: String {
        let label = round.kind?.germanLabel ?? "Hören"
        if round.kind == .gist, let story = round.items.first?.expected, !story.isEmpty { return "\(label) · \(story)" }
        return round.levelRaw.isEmpty ? label : "\(label) · \(round.levelRaw)"
    }
}

/// Worum geht's?: pick a story to hear without its text. Opens the story in Hören mode, where the
/// predict, listen, summarise and compare steps live.
struct HoerenStoryPickerView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Query(sort: \StudyStory.createdAt, order: .reverse) private var stories: [StudyStory]

    var body: some View {
        List {
            if stories.isEmpty {
                ContentUnavailableView("No stories yet", systemImage: "book.pages",
                                       description: Text("Make a story in Stories first. A Dialog or a News report works best for listening."))
            } else {
                Section {
                    ForEach(stories) { story in
                        NavigationLink {
                            StoryDetailView(story: story, modelManager: modelManager, mlxService: mlxService,
                                            initialMode: .listen)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(story.title).font(.body.weight(.medium))
                                Text([story.levelRaw, story.genre.label, story.hasKeyPoints ? "key points" : nil]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("You'll guess some words first, hear the story with the text hidden, write the gist in English, then compare it with the story's key points.")
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle(HoerenRoundKind.gist.germanLabel)
    }
}

/// What the ear does well and where it slips, from every stored round.
struct HoerenStatsView: View {
    @Query(sort: \HoerenRound.date, order: .reverse) private var rounds: [HoerenRound]

    var body: some View {
        let stats = HoerenStats(rounds: Array(rounds.prefix(200)))
        List {
            if stats.isEmpty {
                ContentUnavailableView("Nothing heard yet", systemImage: "headphones",
                                       description: Text("Finish a Zahlen-Diktat or a Diktat and the numbers show up here."))
            }
            if !stats.kinds.isEmpty {
                Section {
                    ForEach(stats.kinds) { line in
                        HStack {
                            Label(line.kind.germanLabel, systemImage: line.kind.systemImage)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(percent(line.right, line.asked)) right").monospacedDigit()
                                Text("\(percent(line.firstPass, line.asked)) first pass")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    if stats.bareAsked > 0 && stats.carrierAsked > 0 {
                        HStack {
                            Text("Alone vs. in a sentence")
                            Spacer()
                            Text("\(percent(stats.bareRight, stats.bareAsked)) · \(percent(stats.carrierRight, stats.carrierAsked))")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Zahlen").themedSectionHeader()
                }
                .themedListRow()
            }
            if !stats.pairs.isEmpty {
                Section {
                    ForEach(stats.pairs) { pair in
                        HStack {
                            Text(pair.expected).monospacedDigit()
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            Text(pair.typed).monospacedDigit().foregroundStyle(.red)
                            Spacer()
                            Text("×\(pair.count)").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("\(pair.expected) heard as \(pair.typed), \(pair.count) times")
                    }
                } header: {
                    Text("Verwechslungen · Mix-ups").themedSectionHeader()
                } footer: {
                    Text(stats.confusions.sorted { $0.value > $1.value }.prefix(2).map { "\($0.key.label): \($0.value)" }.joined(separator: " · "))
                }
                .themedListRow()
            }
            if stats.diktatWords > 0 {
                Section {
                    HStack {
                        Text("Words heard right")
                        Spacer()
                        Text(percent(stats.diktatRight, stats.diktatWords)).monospacedDigit()
                    }
                    ForEach(DiktatClass.allCases.filter { $0 != .right && (stats.diktatMisses[$0] ?? 0) > 0 }, id: \.self) { cls in
                        HStack {
                            Text(label(cls))
                            Spacer()
                            Text("\(stats.diktatMisses[cls] ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    ForEach(stats.endingByFocus.sorted { $0.value > $1.value }, id: \.key) { focus, n in
                        HStack {
                            Text("Endings · \(focus.germanLabel)").font(.callout)
                            Spacer()
                            Text("\(n)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text("Diktat").themedSectionHeader()
                }
                .themedListRow()
            }
            if stats.gistRounds > 0 {
                Section {
                    HStack {
                        Text("Stories summarised")
                        Spacer()
                        Text("\(stats.gistRounds)").monospacedDigit()
                    }
                    if stats.predictionsMade > 0 {
                        HStack {
                            Text("Predicted words that came up")
                            Spacer()
                            Text("\(stats.predictionsHit) of \(stats.predictionsMade)").monospacedDigit()
                        }
                    }
                } header: {
                    Text("Worum geht's?").themedSectionHeader()
                }
                .themedListRow()
            }
            if !rounds.isEmpty {
                Section {
                    ForEach(rounds.prefix(30)) { HoerenRoundRow(round: $0) }
                } header: {
                    Text("Verlauf · History").themedSectionHeader()
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Statistik")
    }

    private func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "–" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }

    private func label(_ cls: DiktatClass) -> String {
        switch cls {
        case .right: "Right"
        case .capital: "Capital letter only"
        case .umlautEszett: "Umlaut or ß"
        case .ending: "Ending only"
        case .word: "Word missed"
        case .extra: "Extra words"
        }
    }
}
