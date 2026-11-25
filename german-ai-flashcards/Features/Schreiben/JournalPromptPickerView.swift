//
//  JournalPromptPickerView.swift
//  german-ai-flashcards
//
//  Where an essay starts: a prompt. Vorschlag is the coach's pick (a bank prompt that practises a
//  shaky structure at the learner's level, else one at random); Bank browses the shipped prompts
//  by topic; Vom Tutor has the downloaded tutor write one on a topic, through the gate, with the
//  bank as fallback; Eigenes Thema is the learner's own. Whichever way, the prompt is frozen on
//  the new entry.
//

import SwiftData
import SwiftUI

struct JournalPromptPickerView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService
    /// The new essay, inserted and saved.
    var onStart: (JournalEntry) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [LearnerProfile]

    enum Tab: String, CaseIterable, Identifiable {
        case suggestion, bank, tutor, own
        var id: String { rawValue }
        var label: String {
            switch self {
            case .suggestion: "Vorschlag"
            case .bank: "Bank"
            case .tutor: "Vom Tutor"
            case .own: "Eigenes"
            }
        }
    }

    @State private var tab: Tab = .suggestion
    @State private var level: CEFRLevel = .a2
    @State private var suggestion: WritingPrompt?
    @State private var suggestionIsCoachPick = false
    @State private var shown: Set<String> = []
    @State private var topic = ""
    @State private var tutorPrompt: String?
    @State private var tutorNote: String?
    @State private var generating = false
    @State private var ownPrompt = ""
    @State private var ownTarget = true

    private var shaky: [GrammarFocus] { LearnerMemoryService.shakyFocuses(profiles.first) }

    private var tutorAvailable: Bool { WritingTutorPick.isAvailable(modelManager) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    Picker("Niveau · Level", selection: $level) {
                        ForEach([CEFRLevel.a1, .a2, .b1, .b2]) { Text($0.rawValue).tag($0) }
                    }
                }
                .themedListRow()

                switch tab {
                case .suggestion: suggestionSection
                case .bank: bankSection
                case .tutor: tutorSection
                case .own: ownSection
                }
            }
            .themedListScreen()
            .navigationTitle("Neuer Aufsatz")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                level = WritingPromptBank.bankLevel(for: modelManager.germanLevel)
                if suggestion == nil { suggest() }
            }
            .onChange(of: level) { _, _ in shown = []; suggest() }
        }
    }

    // MARK: - Vorschlag

    @ViewBuilder private var suggestionSection: some View {
        Section {
            if let suggestion {
                promptCard(de: suggestion.de, en: suggestion.en, focus: suggestion.grammarFocus,
                           target: suggestion.targetWords, scaffold: suggestion.scaffold)
                Button {
                    start(prompt: suggestion, source: suggestionIsCoachPick ? .coach : .bank)
                } label: {
                    Label("Schreiben · Write this one", systemImage: "square.and.pencil")
                }
                Button {
                    suggest()
                } label: {
                    Label("Anderer Vorschlag · Another", systemImage: "shuffle")
                }
            } else {
                Text("No prompts at this level.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Vorschlag · Suggested").themedSectionHeader()
        } footer: {
            if suggestionIsCoachPick, let focus = suggestion?.grammarFocus {
                Text("Picked for your \(focus.germanLabel): the coach counts it as shaky.")
                    .font(.caption2)
            } else {
                Text("A prompt at your level. When the coach has a shaky structure on file, the suggestion practises it.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private func suggest() {
        if let current = suggestion { shown.insert(current.id) }
        if let pick = WritingPromptBank.coachPick(level: level, kind: .aufsatz, shaky: shaky, excluding: shown) {
            suggestion = pick
            suggestionIsCoachPick = true
        } else {
            suggestion = WritingPromptBank.random(level: level, kind: .aufsatz, excluding: shown)
            suggestionIsCoachPick = false
        }
    }

    // MARK: - Bank

    @ViewBuilder private var bankSection: some View {
        let topics = WritingPromptBank.topics(level: level, kind: .aufsatz)
        ForEach(topics, id: \.self) { topicName in
            Section {
                ForEach(WritingPromptBank.prompts(level: level, kind: .aufsatz).filter { $0.topics.first == topicName }) { prompt in
                    Button {
                        start(prompt: prompt, source: .bank)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prompt.de).font(.callout).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(prompt.en)
                                if let focus = prompt.grammarFocus { Text("· \(focus.germanLabel)") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(topicName.capitalized).themedSectionHeader()
            }
            .themedListRow()
        }
    }

    // MARK: - Vom Tutor

    @ViewBuilder private var tutorSection: some View {
        Section {
            TextField("Thema · Topic (e.g. mein Haustier, Umzug, Prüfungsangst)", text: $topic)
            Button {
                Task { await generate() }
            } label: {
                HStack {
                    Label("Vorschlag holen · Ask the tutor", systemImage: "sparkles")
                    if generating { Spacer(); ProgressView() }
                }
            }
            .disabled(!tutorAvailable || generating || topic.trimmingCharacters(in: .whitespaces).isEmpty)
            if let tutorPrompt {
                promptCard(de: tutorPrompt, en: nil, focus: nil, target: nil, scaffold: nil)
                Button {
                    start(de: tutorPrompt, en: nil, id: nil, source: .tutor, focus: nil, target: level.essayWordRange)
                } label: {
                    Label("Schreiben · Write this one", systemImage: "square.and.pencil")
                }
            }
            if let tutorNote {
                Text(tutorNote).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Vom Tutor · From the tutor").themedSectionHeader()
        } footer: {
            Text(tutorAvailable
                 ? "The downloaded tutor writes one prompt on your topic. It is checked to be German, short and a question or an instruction; otherwise a bank prompt stands in."
                 : "No tutor is downloaded. Download one under Settings ▸ Model & Downloads, or pick from the bank.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func generate() async {
        generating = true
        tutorNote = nil
        defer { generating = false }
        guard let tutor = WritingTutorPick.tutor(modelManager, service: mlxService) else {
            tutorNote = "No tutor is downloaded."
            return
        }
        if let why = await tutor.prepare() {
            tutorNote = why
            return
        }
        let reply = try? await tutor.reply(system: WritingTutorCheck.promptGenerationSystem(level: level),
                                           user: WritingTutorCheck.promptGenerationUser(topic: topic, kind: .aufsatz),
                                           maxTokens: WritingTutorCheck.promptMaxTokens)
        if let accepted = reply.flatMap(WritingPromptGate.accept) {
            tutorPrompt = accepted
        } else if let fallback = WritingPromptBank.random(level: level, kind: .aufsatz) {
            tutorPrompt = fallback.de
            tutorNote = "The tutor's prompt didn't pass the check, so here is one from the bank."
        } else {
            tutorNote = "The tutor's prompt didn't pass the check. Try another topic."
        }
    }

    // MARK: - Eigenes

    @ViewBuilder private var ownSection: some View {
        Section {
            TextField("Deine Aufgabe · Your own prompt, in German", text: $ownPrompt, axis: .vertical)
                .lineLimit(2...4)
            Toggle("Ziel \(level.essayWordRange.lowerBound)–\(level.essayWordRange.upperBound) Wörter", isOn: $ownTarget)
            Button {
                start(de: ownPrompt.trimmingCharacters(in: .whitespacesAndNewlines), en: nil, id: nil, source: .own,
                      focus: nil, target: ownTarget ? level.essayWordRange : nil)
            } label: {
                Label("Schreiben · Write", systemImage: "square.and.pencil")
            }
            .disabled(ownPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Eigenes Thema · Your own").themedSectionHeader()
        } footer: {
            Text("A question from class, a letter you really have to write, anything. The target length is the level's; turn it off for free length.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Shared

    private func promptCard(de: String, en: String?, focus: GrammarFocus?, target: WritingPrompt.Target?, scaffold: [String]?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(de).font(.body.weight(.semibold))
            if let en { Text(en).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                if let target { Label("\(target.min)–\(target.max) Wörter", systemImage: "text.alignleft") }
                if let focus { Label(focus.germanLabel, systemImage: "tag") }
            }
            .font(.caption2).foregroundStyle(.secondary)
            if let scaffold, !scaffold.isEmpty {
                Text(scaffold.joined(separator: "  ·  "))
                    .font(.caption2.italic()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func start(prompt: WritingPrompt, source: JournalPromptSource) {
        start(de: prompt.de, en: prompt.en, id: prompt.id, source: source, focus: prompt.grammarFocus,
              target: prompt.targetWords.map { $0.min...$0.max })
    }

    private func start(de: String, en: String?, id: String?, source: JournalPromptSource, focus: GrammarFocus?, target: ClosedRange<Int>?) {
        let entry = JournalEntryStore.makeEssay(de: de, en: en, promptID: id, source: source, focus: focus,
                                                target: target, level: level, in: modelContext)
        onStart(entry)
        dismiss()
    }
}
