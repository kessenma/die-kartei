import Foundation
import SwiftUI
@testable import DieKarteiCore
@testable import KarteiStore

/// Settings ▸ Coach's Notes: what the coach remembers (iOS `CoachNotesView`): grammar
/// confidence, the learner's own notes, the words it weaves back in, the slip-ups it watches for,
/// and the archive. Pin keeps an item from being cleaned out; remove moves it to the archive.
struct CoachNotesView: View {
    @State var coach = CoachMemory.shared
    @State var confirmReset = false

    var memory: LearnerMemory { coach.memory }

    var grammarRows: [(focus: GrammarFocus, skill: GrammarSkill)] {
        memory.grammar
            .compactMap { key, skill in GrammarFocus(rawValue: key).map { (focus: $0, skill: skill) } }
            .sorted { $0.skill.struggle > $1.skill.struggle }
    }

    var body: some View {
        List {
            if coach.isEmpty {
                Section {
                    Text("Have a conversation and end it with a summary: the coach will start noting what you're strong on, the words you're learning, and the slip-ups to watch.")
                        .foregroundStyle(.secondary)
                }
            } else {
                stats
                grammar
                notes
                words
                slips
                archived
                Section {
                    Button("Reset everything", role: .destructive) { confirmReset = true }
                }
            }
        }
        .navigationTitle("Coach's Notes")
        .onAppear { coach.reload() }
        .alert("Reset Coach's Notes?", isPresented: $confirmReset) {
            Button("Reset everything", role: .destructive) { coach.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears everything the coach remembers about you — strengths, words, slip-ups, and the archive. It can't be undone.")
        }
    }

    @ViewBuilder var stats: some View {
        Section {
            Text("\(memory.sessionCount) coached conversation\(memory.sessionCount == 1 ? "" : "s")")
        } footer: {
            Text("The coach quietly uses these notes to steer and sharpen your conversations. Everything stays on your device.")
        }
    }

    @ViewBuilder var grammar: some View {
        if !grammarRows.isEmpty {
            Section {
                ForEach(grammarRows, id: \.focus) { row in
                    HStack {
                        Text(row.focus.germanLabel)
                        Spacer()
                        Text(row.skill.struggle >= GrammarSkill.shakyThreshold ? "needs work"
                             : row.skill.struggle < LearnerMemory.solidThreshold ? "solid" : "getting there")
                            .font(.caption)
                            .foregroundStyle(row.skill.struggle >= GrammarSkill.shakyThreshold ? Color.orange : Color.secondary)
                    }
                }
            } header: {
                Text("Grammar")
            }
        }
    }

    @ViewBuilder var notes: some View {
        if !memory.selfReports.isEmpty {
            Section {
                ForEach(memory.selfReports) { note in
                    MemoryRow(title: "„\(note.text)“", detail: note.grammarFocus?.germanLabel, count: note.timesNoted,
                              pinned: note.pinned,
                              pin: { coach.setNotePinned(note.id, !note.pinned) },
                              remove: { coach.removeNote(note.id) })
                }
            } header: {
                Text("Selbstbericht · In your own words")
            } footer: {
                Text("What you told the coach yourself. It steers conversations; it never changes your grammar confidence.")
            }
        }
    }

    @ViewBuilder var words: some View {
        if !memory.vocab.isEmpty {
            Section {
                ForEach(memory.vocab.sorted { $0.lastSeen > $1.lastSeen }) { word in
                    MemoryRow(title: word.german, detail: Self.wordDetail(word), count: word.timesUsed, pinned: word.pinned,
                              pin: { coach.setVocabPinned(word.id, !word.pinned) },
                              remove: { coach.removeVocab(word.id) })
                }
            } header: {
                Text("Words you're building")
            } footer: {
                Text("Words the coach weaves back into future chats. Pin to keep one; the newest \(LearnerMemory.vocabCap) stay.")
            }
        }
    }

    static func wordDetail(_ word: VocabTouch) -> String? {
        let source: String? = switch word.source {
        case MemorySource.placement: "from your placement check"
        case MemorySource.diktat: "missed in a Diktat"
        default: nil
        }
        let parts = [word.english.isEmpty ? nil : word.english, source].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder var slips: some View {
        if !memory.slips.isEmpty {
            Section {
                ForEach(memory.slips.sorted { $0.lastSeen > $1.lastSeen }) { slip in
                    MemoryRow(title: "\(slip.wrong) → \(slip.right)", detail: slip.note.isEmpty ? nil : slip.note,
                              count: slip.timesSeen, pinned: slip.pinned,
                              pin: { coach.setSlipPinned(slip.id, !slip.pinned) },
                              remove: { coach.removeSlip(slip.id) })
                }
            } header: {
                Text("Slip-ups it's watching")
            } footer: {
                Text("Repeated word-level mistakes. The coach pays extra attention to these when correcting, and drops one once you use it correctly.")
            }
        }
    }

    @ViewBuilder var archived: some View {
        if !coach.archive.isEmpty {
            Section {
                ForEach(coach.archive, id: \.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.reason.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { coach.restore(item) } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        Button { coach.forget(item) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Archive")
            } footer: {
                Text("What the coach let go of. Restore puts it back, pinned.")
            }
        }
    }
}

/// One remembered item: a pin and a remove button.
struct MemoryRow: View {
    let title: String
    let detail: String?
    let count: Int
    let pinned: Bool
    let pin: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if count > 1 {
                Text("×\(count)").font(.caption2).foregroundStyle(.secondary)
            }
            Button(action: pin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            Button(action: remove) {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.borderless)
        }
    }
}
