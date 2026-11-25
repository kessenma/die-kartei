//
//  MeasurementsView.swift
//  german-ai-flashcards
//
//  Settings ▸ Developer ▸ Messungen: the numbers the roadmap says to look at before setting a
//  rule (docs/FSI_DLI_ROADMAP.md). Answer time (item 5) and how grammar weak spots move week to
//  week (item 9). Read-only; nothing here changes how the app behaves.
//

import SwiftUI

struct MeasurementsView: View {
    @State private var times: [AnswerTime] = []
    @State private var history: [WeakSpotHistory.Line] = []

    var body: some View {
        List {
            Section {
                if times.isEmpty {
                    Text("No answers timed yet. Flip some cards or do a grammar drill.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.key) { group in
                    spreadRow(title: group.key, values: group.values)
                }
            } header: {
                Text("Antwortzeit · Answer time").themedSectionHeader()
            } footer: {
                Text("Seconds from a card or a drill step appearing to the flip or the first pick, on this device (last \(AnswerTimeLog.cap)). The bar runs from the 10th to the 90th percentile; the mark is the median. Drills split right and wrong first picks. No rule reads these yet: they are here to choose what \"right and fast\" should mean.")
            }
            .themedListRow()

            Section {
                if history.isEmpty {
                    Text("No weekly snapshots with grammar scores yet. One is taken each week when Home opens.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(history) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(line.focus.germanLabel).font(.callout.weight(.medium))
                            Spacer()
                            Text("\(line.weeksShaky) of \(line.values.count) weeks shaky")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(line.values.map { String(format: "%.2f", $0) }.joined(separator: " · "))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Schwachstellen · Weak spots by week").themedSectionHeader()
            } footer: {
                Text("Each grammar point's struggle score in each weekly snapshot, oldest first (0 = solid, shaky from \(String(format: "%.1f", GrammarSkill.shakyThreshold))). The Förderplan is offered by hand until these show what \"stays weak\" looks like.")
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Messungen")
        .onAppear {
            times = AnswerTimeLog.all
            history = WeakSpotHistory.lines()
        }
    }

    private var groups: [(key: String, values: [AnswerTime])] {
        let grouped = Dictionary(grouping: times) { t -> String in
            switch t.kind {
            case .cardFlip: "Cards · \(t.detail)"
            case .drill: "Drill · \(t.detail)"
            }
        }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.key < $1.key }
    }

    @ViewBuilder
    private func spreadRow(title: String, values: [AnswerTime]) -> some View {
        let all = values.map(\.ms)
        let p = AnswerTimeLog.percentiles(all)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text("n = \(all.count)").font(.caption).foregroundStyle(.secondary)
            }
            SpreadBar(p10: p[0], p50: p[2], p90: p[4])
            Text("p10 \(sec(p[0])) · p25 \(sec(p[1])) · median \(sec(p[2])) · p75 \(sec(p[3])) · p90 \(sec(p[4]))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            let right = values.filter { $0.correct == true }.map(\.ms)
            let wrong = values.filter { $0.correct == false }.map(\.ms)
            if !right.isEmpty || !wrong.isEmpty {
                Text("median right \(sec(AnswerTimeLog.percentiles(right, [0.5])[0])) (n \(right.count)) · wrong \(sec(AnswerTimeLog.percentiles(wrong, [0.5])[0])) (n \(wrong.count))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func sec(_ ms: Int) -> String { String(format: "%.1fs", Double(ms) / 1000) }
}

/// A 0–15 s track with the 10th–90th percentile band and a median tick.
private struct SpreadBar: View {
    let p10: Int, p50: Int, p90: Int
    private let span = 15_000.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (ms: Int) in CGFloat(min(1, Double(ms) / span)) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                Capsule().fill(Color.accentColor.opacity(0.45))
                    .frame(width: max(4, x(p90) - x(p10)), height: 8)
                    .offset(x: x(p10))
                Rectangle().fill(Color.accentColor).frame(width: 2, height: 14).offset(x: x(p50))
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
