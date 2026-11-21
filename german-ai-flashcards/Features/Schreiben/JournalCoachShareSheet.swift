//
//  JournalCoachShareSheet.swift
//  german-ai-flashcards
//
//  "Mit dem Coach teilen": what this entry would hand to the coach, each item a toggle, before
//  anything is written. The notes section is the learner's own words about what they find hard:
//  the tutor can read them out of the entry (never inferred from mistakes), or the learner types
//  one, and every note is editable before it goes. The footer says what never travels.
//

import SwiftData
import SwiftUI

struct JournalCoachShareSheet: View {
    @Bindable var entry: JournalEntry
    @Bindable var modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    struct DraftNote: Identifiable {
        let id = UUID()
        var text: String
        var focus: GrammarFocus?
        var include = true
        /// The tutor wrote it (as opposed to the learner).
        var fromTutor = false
    }

    @State private var pending = JournalCoachExport.Plan()
    @State private var includeSlips: Set<Int> = []
    @State private var includeWords: Set<String> = []
    @State private var notes: [DraftNote] = []
    @State private var extracting = false
    @State private var extracted = false
    @State private var status: String?
    @State private var sent: String?

    private var tutorAvailable: Bool { WritingTutorPick.isAvailable(modelManager) }

    private var plan: JournalCoachExport.Plan {
        var p = JournalCoachExport.Plan()
        p.slips = pending.slips.enumerated().filter { includeSlips.contains($0.offset) }.map(\.element)
        p.words = pending.words.filter { includeWords.contains($0.german.lowercased()) }
        p.notes = notes.filter { $0.include && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { SelfReportNote(text: String($0.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SelfReportNote.maxLength)),
                                  focus: $0.focus?.rawValue, notedAt: .now) }
        return p
    }

    var body: some View {
        NavigationStack {
            List {
                if let sent {
                    Section {
                        Label(sent, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .themedListRow()
                } else {
                    slipsSection
                    wordsSection
                    notesSection
                    sendSection
                }
            }
            .themedListScreen()
            .navigationTitle("Mit dem Coach teilen")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(sent == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        pending = JournalCoachExport.pendingPlan(for: entry)
        includeSlips = Set(pending.slips.indices)
        includeWords = Set(pending.words.map { $0.german.lowercased() })
    }

    // MARK: - Sections

    @ViewBuilder private var slipsSection: some View {
        Section {
            if pending.slips.isEmpty {
                Text(entry.hasCheck ? "No new one-word fixes since the last hand-off." : "Check the entry first and the tutor's one-word fixes appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(pending.slips.enumerated()), id: \.offset) { index, pair in
                    Toggle(isOn: Binding(
                        get: { includeSlips.contains(index) },
                        set: { if $0 { includeSlips.insert(index) } else { includeSlips.remove(index) } }
                    )) {
                        if let swap = WritingDiff.singleSwap(pair.original, pair.corrected) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(swap.wrong).strikethrough().foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                    Text(swap.right)
                                }
                                .font(.callout)
                                Text(pair.corrected).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        } else {
                            Text(pair.corrected).font(.callout)
                        }
                    }
                }
            }
        } header: {
            Text("Ausrutscher · Slips").themedSectionHeader()
        } footer: {
            Text("One-word fixes become slip-ups the coach watches for, each with your sentence, so it can make a fill-in-the-blank card from it.")
                .font(.caption2)
        }
        .themedListRow()
    }

    @ViewBuilder private var wordsSection: some View {
        if !pending.words.isEmpty {
            Section {
                ForEach(pending.words, id: \.german) { word in
                    Toggle(isOn: Binding(
                        get: { includeWords.contains(word.german.lowercased()) },
                        set: { if $0 { includeWords.insert(word.german.lowercased()) } else { includeWords.remove(word.german.lowercased()) } }
                    )) {
                        HStack {
                            Text(word.german)
                            Spacer()
                            Text(word.english).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            } header: {
                Text("Nachgeschlagen · Looked up").themedSectionHeader()
            } footer: {
                Text("Words you looked up while writing join the words the coach weaves into conversations.")
                    .font(.caption2)
            }
            .themedListRow()
        }
    }

    @ViewBuilder private var notesSection: some View {
        Section {
            ForEach($notes) { $note in
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: $note.include).labelsHidden()
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("What you find hard, in your words", text: $note.text, axis: .vertical)
                            .font(.callout)
                        HStack(spacing: 8) {
                            Menu {
                                Button("No structure") { note.focus = nil }
                                ForEach(GrammarFocus.allCases) { focus in
                                    Button(focus.germanLabel) { note.focus = focus }
                                }
                            } label: {
                                Label(note.focus?.germanLabel ?? "Structure…", systemImage: "tag")
                                    .font(.caption)
                            }
                            if note.fromTutor {
                                Text("read by the tutor").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text("\(note.text.count)/\(SelfReportNote.maxLength)")
                                .font(.caption2).monospacedDigit()
                                .foregroundStyle(note.text.count > SelfReportNote.maxLength ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                        }
                    }
                }
            }
            .onDelete { offsets in notes.remove(atOffsets: offsets) }

            if tutorAvailable, !extracted {
                Button {
                    Task { await extract() }
                } label: {
                    HStack {
                        Label("Ask the tutor what I said I find hard", systemImage: "text.magnifyingglass")
                        if extracting { Spacer(); ProgressView() }
                    }
                }
                .disabled(extracting || entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button {
                notes.append(DraftNote(text: "", focus: nil))
            } label: {
                Label("Add a note", systemImage: "plus.circle")
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Selbstbericht · In your own words").themedSectionHeader()
        } footer: {
            Text("Only what you say about yourself, never what the tutor infers from a mistake. At most \(SelfReportNote.maxLength) characters a note; the coach keeps the \(LearnerProfile.selfReportCap) newest and lets older ones go unless you pin them.")
                .font(.caption2)
        }
        .themedListRow()
    }

    @ViewBuilder private var sendSection: some View {
        Section {
            Button {
                send()
            } label: {
                Label(plan.buttonTitle, systemImage: "paperplane")
            }
            .disabled(plan.isEmpty || notes.contains { $0.include && $0.text.count > SelfReportNote.maxLength })
        } footer: {
            Text("What never travels: your text, your level, and your grammar confidence. The coach's bars move only through conversations and drills.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Actions

    private func extract() async {
        extracting = true
        status = nil
        defer { extracting = false }
        guard let tutor = WritingTutorPick.tutor(modelManager, service: mlxService) else {
            status = "No tutor is downloaded."
            return
        }
        if let why = await tutor.prepare() {
            status = why
            return
        }
        do {
            let reply = try await tutor.reply(system: WritingTutorCheck.struggleSystem,
                                              user: WritingTutorCheck.strugglePrompt(text: entry.text),
                                              maxTokens: WritingTutorCheck.struggleMaxTokens)
            let found = WritingTutorCheck.parseStruggles(reply, entryText: entry.text)
            extracted = true
            if found.isEmpty {
                status = "The tutor found nothing you said about what is hard. Add a note yourself if there is one."
            } else {
                for item in found where !notes.contains(where: { $0.text.lowercased() == item.text.lowercased() }) {
                    notes.append(DraftNote(text: item.text, focus: item.focus, fromTutor: true))
                }
                status = "Read \(found.count) note\(found.count == 1 ? "" : "s"). Edit or untick before sending."
            }
        } catch {
            status = "The tutor didn't answer. Add a note yourself."
        }
    }

    private func send() {
        let p = plan
        guard !p.isEmpty else { return }
        sent = JournalCoachExport.send(p, for: entry, in: modelContext)
    }
}
