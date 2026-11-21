//
//  ZahlenSetupView.swift
//  german-ai-flashcards
//
//  Zahlen-Diktat's setup: the level, which kinds of number, bare or in a sentence, single pass or
//  study mode, how many. The round is built here, so the drill opens with its items ready.
//

import SwiftUI

struct ZahlenConfig: Identifiable, Hashable {
    let id = UUID()
    var level: CEFRLevel
    var kinds: [HoerenNumberKind]
    var mode: HoerenNumberMode
    var playback: HoerenPlayback
    var items: [HoerenNumberItem]
}

struct ZahlenSetupView: View {
    let modelManager: MLXModelManager

    @State private var level: CEFRLevel = .a1
    @State private var picked: Set<HoerenNumberKind> = []
    @State private var mode: HoerenNumberMode = .bare
    @State private var playback: HoerenPlayback = .singlePass
    @State private var count = 10
    @State private var seeded = false
    @State private var running: ZahlenConfig?

    private static let levels: [CEFRLevel] = [.a1, .a2, .b1]

    private var available: [HoerenNumberKind] { HoerenNumberKind.kinds(for: level) }
    private var chosen: [HoerenNumberKind] {
        let kept = available.filter(picked.contains)
        return kept.isEmpty ? available : kept
    }

    var body: some View {
        List {
            Section {
                Picker("Level", selection: $level) {
                    ForEach(Self.levels) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Niveau · Level").themedSectionHeader()
            } footer: {
                Text("Higher levels add bigger numbers, everyday clock times (halb drei), dates and years.")
            }
            .themedListRow()

            Section {
                ForEach(available) { kind in
                    Button {
                        if picked.contains(kind) { picked.remove(kind) } else { picked.insert(kind) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(HoerenTile.tint)
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.germanLabel).foregroundStyle(.primary)
                                Text(kind.englishLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if chosen.contains(kind) {
                                Image(systemName: picked.isEmpty ? "checkmark.circle" : "checkmark.circle.fill")
                                    .foregroundStyle(HoerenTile.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Was für Zahlen · Which numbers").themedSectionHeader()
            } footer: {
                Text(picked.isEmpty ? "A mix of every kind at this level. Tap one to practise only that." : "Tap again to remove one. None picked means all of them.")
            }
            .themedListRow()

            Section {
                Picker("Numbers", selection: $mode) {
                    ForEach(HoerenNumberMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Playback", selection: $playback) {
                    ForEach(HoerenPlayback.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper("\(count) numbers", value: $count, in: 5...30, step: 5)
            } header: {
                Text("Runde · Round").themedSectionHeader()
            } footer: {
                Text(playback.detail + " You type the digits; how you write them (14:30, 14.30) doesn't matter.")
            }
            .themedListRow()

            Section {
                Button {
                    var rng = SystemRandomNumberGenerator()
                    let items = HoerenNumberGenerator.round(kinds: chosen, level: level, mode: mode, count: count, rng: &rng)
                    running = ZahlenConfig(level: level, kinds: chosen, mode: mode, playback: playback, items: items)
                } label: {
                    Label("Los geht's · Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(HoerenTile.tint)
                .listRowBackground(Color.clear)
            }
        }
        .themedListScreen()
        .navigationTitle(HoerenRoundKind.zahlen.germanLabel)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            let declared = modelManager.germanLevel
            level = Self.levels.contains(declared) ? declared : (declared.hoerenRank > 2 ? .b1 : .a1)
        }
        .onChange(of: level) { _, _ in picked = picked.filter(available.contains) }
        .fullScreenCover(item: $running) { config in
            NavigationStack {
                ZahlenDiktatView(config: config)
            }
        }
    }
}
