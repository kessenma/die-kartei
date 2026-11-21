//
//  MonthlyNoteSection.swift
//  german-ai-flashcards
//
//  Monatsbericht (roadmap item 10, DLI-TI: "at least once a month, this feedback will be in
//  writing"). A short written note beside the week in review: what got better over about a month
//  and what to do next. Built from the weekly snapshots ("Dein Weg"), no tutor needed. Earned fill
//  only: a blueprint estimate is never reported as progress.
//

import SwiftUI

nonisolated struct MonthlyNote: Equatable {
    var from: Date
    var to: Date
    var better: [String]
    var next: [String]
}

enum MonthlyNoteBuilder {
    /// The baseline must be at least this old, so the note covers about a month.
    static let minimumSpanDays = 25

    /// Nil until two snapshots are far enough apart.
    static func note(snapshots: [ProgressSnapshot], now: Date = .now) -> MonthlyNote? {
        let sorted = snapshots.filter { $0.takenAt <= now }.sorted { $0.takenAt < $1.takenAt }
        guard let latest = sorted.last else { return nil }
        let cutoff = latest.takenAt.addingTimeInterval(-Double(minimumSpanDays) * 86_400)
        // The newest snapshot at least a month back: the note covers one month, not all time.
        guard let base = sorted.last(where: { $0.takenAt <= cutoff }) else { return nil }

        var better: [String] = []
        for layer in PyramidLayerID.allCases {
            let before = base.earnedFill[layer.rawValue] ?? 0
            let after = latest.earnedFill[layer.rawValue] ?? 0
            let delta = Int(((after - before) * 100).rounded())
            if delta >= 2 { better.append("\(layer.germanTitle): +\(delta)% of the layer, earned") }
        }
        let a1 = latest.learnedA1 - base.learnedA1, a2 = latest.learnedA2 - base.learnedA2
        if a1 + a2 > 0 { better.append("\(a1 + a2) more Goethe words learned (A1 \(a1), A2 \(a2))") }
        let grammar = latest.solidCoreGrammar - base.solidCoreGrammar
        if grammar > 0 { better.append("\(grammar) more grammar point\(grammar == 1 ? "" : "s") solid") }
        let chats = latest.wellHeldConversations - base.wellHeldConversations
        if chats > 0 { better.append("\(chats) more conversation\(chats == 1 ? "" : "s") held well") }
        // Grammar that moved from shaky to solid, by the coach's weekly scores.
        if let then = base.grammarStruggle, let now = latest.grammarStruggle {
            let steadied = then.compactMap { key, value -> String? in
                guard value >= GrammarSkill.shakyThreshold, let current = now[key], current < GrammarSkill.shakyThreshold,
                      let focus = GrammarFocus(rawValue: key) else { return nil }
                return focus.germanLabel
            }.sorted()
            if !steadied.isEmpty { better.append("No longer shaky: " + steadied.joined(separator: ", ")) }
        }
        let xp = latest.totalXP - base.totalXP
        if xp > 0 { better.append("\(xp) XP this month") }

        var next: [String] = []
        if let shaky = latest.grammarStruggle?
            .filter({ $0.value >= GrammarSkill.shakyThreshold })
            .max(by: { $0.value < $1.value }),
           let focus = GrammarFocus(rawValue: shaky.key) {
            next.append("Practise \(focus.germanLabel): it is still the shakiest grammar point.")
        }
        if let layer = PyramidLayerID.allCases.first(where: { (latest.earnedFill[$0.rawValue] ?? 0) < 0.95 }) {
            next.append("Keep building \(layer.germanTitle), the lowest layer not yet full.")
        }
        if better.isEmpty {
            next.append("A quiet month. Ten minutes a day is enough to move again.")
        }
        return MonthlyNote(from: base.takenAt, to: latest.takenAt, better: better, next: next)
    }
}

struct MonthlyNoteSection: View {
    @State private var note: MonthlyNote?
    @State private var expanded = false

    var body: some View {
        Group {
            if let note {
                Section {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            if !note.better.isEmpty {
                                Text("Besser geworden · What got better").font(.subheadline.weight(.semibold))
                                ForEach(note.better, id: \.self) { Label($0, systemImage: "arrow.up.right").font(.callout) }
                            }
                            Text("Als Nächstes · What to do next").font(.subheadline.weight(.semibold))
                                .padding(.top, 4)
                            ForEach(note.next, id: \.self) { Label($0, systemImage: "arrow.right").font(.callout) }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monatsbericht · Your month").font(.headline)
                            Text("\(note.from.formatted(date: .abbreviated, time: .omitted)) – \(note.to.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Written from your weekly snapshots: only progress you earned, never an estimate.")
                        .font(.caption2)
                }
                .themedListRow()
            }
        }
        .task { note = MonthlyNoteBuilder.note(snapshots: ProgressSnapshotStore.document().snapshots) }
    }
}
