//
//  ZahlenDiktatView.swift
//  german-ai-flashcards
//
//  Zahlen-Diktat: hear a number once, type the digits (docs/HOEREN.md ▸ Zahlen-Diktat). DLI's
//  objective is "transcribe (single pass) numbers", so the default plays once; a replay is
//  allowed and counted, and "first pass" in the stats means right with none.
//
//  An answer that cannot be read as the kind asked for is not graded: the field shows how to type
//  it and the attempt is kept. A format slip is not a listening slip.
//

import SwiftData
import SwiftUI

struct ZahlenDiktatView: View {
    let config: ZahlenConfig

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var items: [HoerenNumberItem]
    @State private var player = HoerenPlayer()
    @State private var index = 0
    @State private var typed = ""
    @State private var formatHint: String?
    @State private var answered: HoerenItem?
    @State private var results: [HoerenItem] = []
    @State private var startedAt = Date()
    @State private var saved = false
    @State private var slow = false
    @FocusState private var fieldFocused: Bool

    init(config: ZahlenConfig) {
        self.config = config
        _items = State(initialValue: config.items)
    }

    private var item: HoerenNumberItem? { items.indices.contains(index) ? items[index] : nil }
    private var finished: Bool { index >= items.count }

    var body: some View {
        Group {
            if finished {
                ZahlenSummaryView(config: config, results: results, onAgain: restart, onDone: { dismiss() })
            } else if let item {
                drill(item)
            }
        }
        .navigationTitle(HoerenRoundKind.zahlen.germanLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(finished ? "Done" : "End") {
                    saveIfNeeded()
                    dismiss()
                }
            }
        }
        .themedScreen()
        .onAppear { playCurrent(after: 0.4) }
        .onDisappear {
            player.stop()
            saveIfNeeded()
        }
    }

    // MARK: - Drill

    private func drill(_ item: HoerenNumberItem) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                progress
                Text(item.kind.germanLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                playButton(item)

                if let answered {
                    feedback(answered, item: item)
                } else {
                    answerField(item)
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(index), total: Double(max(1, items.count)))
                .tint(HoerenTile.tint)
            Text("\(index + 1) of \(items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func playButton(_ item: HoerenNumberItem) -> some View {
        VStack(spacing: 10) {
            Button {
                if player.isPlaying { player.stop() } else { player.play(item.spoken, slow: slow) }
            } label: {
                Image(systemName: player.isPlaying ? "stop.fill" : (player.plays == 0 ? "play.fill" : "arrow.counterclockwise"))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(HoerenTile.tint, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Stop" : (player.plays == 0 ? "Play" : "Play again"))

            Text(playCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            if config.playback == .study {
                Toggle("Langsam · Slow", isOn: $slow)
                    .toggleStyle(.button)
                    .tint(HoerenTile.tint)
                    .font(.caption)
            }
        }
    }

    private var playCaption: String {
        switch player.plays {
        case 0: return "Listen"
        case 1: return config.playback == .singlePass ? "Heard once. Replaying is allowed, and counted." : "Play it again as often as you like"
        default: return "Replayed \(player.replays)×"
        }
    }

    private func answerField(_ item: HoerenNumberItem) -> some View {
        VStack(spacing: 10) {
            TextField(Self.example(for: item.kind).components(separatedBy: " or ").first ?? "", text: $typed)
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit { check(item) }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .themedCard()

            if let formatHint {
                Label(formatHint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(item.kind.answerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                check(item)
            } label: {
                Text("Prüfen · Check").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HoerenTile.tint)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || player.plays == 0)
        }
    }

    private func feedback(_ answered: HoerenItem, item: HoerenNumberItem) -> some View {
        VStack(spacing: 14) {
            Label(answered.correct ? "Richtig" : "Nicht ganz",
                  systemImage: answered.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(answered.correct ? .green : .red)

            VStack(spacing: 6) {
                if !answered.correct {
                    Text("You typed \(answered.typed)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
                Text(item.value.display)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text(item.spelled)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if item.mode == .carrier {
                    Text(item.written)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .themedCard()

            if let confusion = answered.confusion, confusion != .other {
                Label(confusion.label, systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(HoerenTile.tint)
                    .multilineTextAlignment(.leading)
            }

            Button {
                next()
            } label: {
                Text(index + 1 < items.count ? "Weiter · Next" : "Fertig · Finish")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HoerenTile.tint)
        }
    }

    // MARK: - Flow

    private func playCurrent(after delay: Double) {
        guard let item else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.item?.id == item.id, answered == nil, player.plays == 0 else { return }
            player.play(item.spoken, slow: slow) { fieldFocused = true }
        }
    }

    private func check(_ item: HoerenNumberItem) {
        guard answered == nil, player.plays > 0 else { return }
        guard let value = HoerenNumberAnswer.parse(typed, kind: item.kind) else {
            formatHint = "Digits only, e.g. " + Self.example(for: item.kind)
            return
        }
        player.stop()
        let correct = HoerenNumberAnswer.matches(value, expected: item.value, kind: item.kind)
        var record = HoerenItem(id: item.id, expected: item.value.display, spoken: item.spoken)
        record.typed = value.display
        record.correct = correct
        record.replays = player.replays
        record.slow = player.slowUsed
        record.numberKindRaw = item.kind.rawValue
        record.numberValue = item.value
        record.typedValue = value
        if !correct {
            record.confusionRaw = HoerenConfusion.classify(typed: value, expected: item.value, kind: item.kind).rawValue
        }
        results.append(record)
        answered = record
        formatHint = nil
        fieldFocused = false
    }

    private func next() {
        answered = nil
        typed = ""
        formatHint = nil
        player.reset()
        index += 1
        if finished {
            saveIfNeeded()
        } else {
            playCurrent(after: 0.3)
        }
    }

    /// A fresh round of the same shape, in place.
    private func restart() {
        saveIfNeeded()
        var rng = SystemRandomNumberGenerator()
        items = HoerenNumberGenerator.round(kinds: config.kinds, level: config.level, mode: config.mode,
                                            count: config.items.count, rng: &rng)
        results = []
        answered = nil
        typed = ""
        formatHint = nil
        saved = false
        startedAt = Date()
        player.reset()
        index = 0
        playCurrent(after: 0.4)
    }

    private func saveIfNeeded() {
        guard !saved, !results.isEmpty else { return }
        saved = true
        let round = HoerenRound(kind: .zahlen)
        round.modeRaw = config.mode.rawValue
        round.playbackRaw = config.playback.rawValue
        round.levelRaw = config.level.rawValue
        round.sourceRaw = (config.tag.map { "\($0):" } ?? "") + config.kinds.map(\.rawValue).joined(separator: ",")
        round.askedCount = results.count
        round.correctCount = results.filter(\.correct).count
        round.firstPassCount = results.filter(\.firstPass).count
        round.replayCount = results.reduce(0) { $0 + $1.replays }
        round.durationSeconds = max(1, Int(Date().timeIntervalSince(startedAt)))
        round.items = results
        HoerenScoringService.save(round, in: modelContext)
    }

    static func example(for kind: HoerenNumberKind) -> String {
        switch kind {
        case .small, .large: "24 or 1 250"
        case .price: "3,50"
        case .time, .timeColloquial: "14:30"
        case .date: "3.5."
        case .year: "1987"
        case .phone: "030 456789"
        }
    }
}

/// The end of a Zahlen-Diktat round: the score, first-pass hearing, and the traps that caught.
struct ZahlenSummaryView: View {
    let config: ZahlenConfig
    let results: [HoerenItem]
    let onAgain: () -> Void
    let onDone: () -> Void

    private var right: Int { results.filter(\.correct).count }
    private var firstPass: Int { results.filter(\.firstPass).count }
    private var replays: Int { results.reduce(0) { $0 + $1.replays } }
    private var confusions: [(HoerenConfusion, Int)] {
        let counts = Dictionary(grouping: results.compactMap(\.confusion).filter { $0 != .other }, by: { $0 })
            .mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("\(right) / \(results.count)")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    Text("\(firstPass) heard on the first pass" + (replays > 0 ? " · \(replays) replay\(replays == 1 ? "" : "s")" : ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .themedListRow()

            if !confusions.isEmpty {
                Section {
                    ForEach(confusions, id: \.0) { confusion, count in
                        HStack {
                            Text(confusion.label)
                            Spacer()
                            Text("×\(count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text("Was dich erwischt hat · What caught you").themedSectionHeader()
                } footer: {
                    Text("German says the units before the tens: vierundzwanzig is four-and-twenty. Saying the number to yourself as you type helps.")
                }
                .themedListRow()
            }

            Section {
                ForEach(results) { item in
                    HStack {
                        Image(systemName: item.correct ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(item.correct ? .green : .red)
                        Text(item.expected).monospacedDigit()
                        if !item.correct {
                            Text(item.typed).strikethrough().foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        if item.replays > 0 {
                            Text("↻\(item.replays)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Alle · All").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Button {
                    onAgain()
                } label: {
                    Label("Noch eine Runde · Another round", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                Button("Fertig · Done", action: onDone)
                    .frame(maxWidth: .infinity)
            }
            .themedListRow()
        }
        .themedListScreen()
    }
}
