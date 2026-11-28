import Foundation
import Observation
import SkipFuse
import SwiftUI
@testable import DieKarteiCore
@testable import KarteiStore

/// The phrase library on Android (iOS `PhraseLibraryView`): phrases the learner heard out in the
/// wild, checked by the tutor, which scenario chats then work in (`PhraseRotation`, shared).
@MainActor
@Observable
final class PhraseBook {
    static let shared = PhraseBook()

    /// Newest first.
    private(set) var phrases: [LearnedPhraseRecord] = []
    @ObservationIgnored private let records: RecordStore?

    init(records: RecordStore? = AppDatabase.records) {
        self.records = records
        reload()
    }

    /// What a scenario chat would work in now.
    func sample(for scenario: ConversationScenario) -> [LearnedPhraseRecord] {
        PhraseRotation.sample(for: scenario, from: phrases)
    }

    func save(_ phrase: LearnedPhraseRecord) { write { try $0.savePhrase(phrase) } }
    func delete(_ id: UUID) { write { try $0.deletePhrase(id) } }
    func markSurfaced(_ phrases: [LearnedPhraseRecord]) { write { try $0.markSurfaced(phrases.map(\.id)) } }

    func setActive(_ phrase: LearnedPhraseRecord, _ active: Bool) {
        var p = phrase
        p.isActive = active
        save(p)
    }

    private func write(_ body: (RecordStore) throws -> Void) {
        guard let records else { return }
        do {
            try body(records)
        } catch {
            logger.error("PhraseBook: could not save: \(error)")
        }
        reload()
    }

    func reload() {
        phrases = records?.phrases() ?? []
    }
}

struct PhraseLibraryView: View {
    @State var book = PhraseBook.shared

    var body: some View {
        List {
            Section {
                Text("Phrases you hear out in the wild but don't understand — like a clerk asking „Sonst noch etwas?“. Save them here and the tutor works the active ones into matching scenario chats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                if book.phrases.isEmpty {
                    Text("Tap + to save a phrase you heard in the wild.").foregroundStyle(.secondary)
                }
                ForEach(book.phrases, id: \.id) { phrase in
                    HStack {
                        NavigationLink { PhraseEditorView(phrase: phrase) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phrase.german)
                                Text(phrase.english).font(.caption).foregroundStyle(.secondary)
                                Text(Self.places(phrase)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Toggle("", isOn: Binding(get: { phrase.isActive }, set: { book.setActive(phrase, $0) }))
                            .labelsHidden()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { book.delete(phrase.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Your phrases")
            } footer: {
                Text("Toggle a phrase off to take it out of rotation without deleting it. Swipe to delete.")
            }
        }
        .navigationTitle("Phrase library")
        .toolbar {
            NavigationLink { PhraseEditorView(phrase: nil) } label: {
                Image(systemName: "plus")
            }
        }
        .onAppear { book.reload() }
    }

    static func places(_ phrase: LearnedPhraseRecord) -> String {
        phrase.scenarioTagsRaw.compactMap { ConversationScenario(rawValue: $0)?.germanTitle }.joined(separator: " · ")
    }
}

/// Add or edit a phrase (iOS `PhraseEditorSheet`): the tutor confirms the natural German (or
/// translates English) before it's saved, and can suggest where you'd hear it and its grammar.
struct PhraseEditorView: View {
    let phrase: LearnedPhraseRecord?
    @Environment(\.dismiss) var dismiss
    @State var tutor = TutorStore.shared
    @State var inputIsGerman = true
    @State var inputText = ""
    @State var autoScenario = false
    @State var autoGrammar = false
    @State var checking = false
    @State var checkError: String?
    @State var result: ConversationPrompts.PhraseCheckResult?
    @State var checkedModelRaw: String?
    @State var scenarios: Set<ConversationScenario> = []
    @State var focus: Set<GrammarFocus> = []
    @State var isActive = true
    @State var loaded = false
    /// The learner asked the AI to pick where you'd hear it and it couldn't (iOS's banner).
    @State var aiCouldNotCategorize = false

    static let allScenarios = ConversationScenario.allCases.filter { $0 != .custom }

    var body: some View {
        Form {
            Section {
                Picker("I'm typing", selection: $inputIsGerman) {
                    Text("German").tag(true)
                    Text("English").tag(false)
                }
                .pickerStyle(.segmented)
                TextField(inputIsGerman ? "What did you hear?" : "What does it mean in English?", text: $inputText)
                Toggle("Let the AI pick where you'd hear it", isOn: $autoScenario)
                Toggle("Let the AI tag the grammar", isOn: $autoGrammar)
                Button(checking ? "Checking…" : (inputIsGerman ? "Check this German" : "Translate & check")) { check() }
                    .disabled(checking || inputText.trimmingCharacters(in: .whitespaces).isEmpty || tutor.available == nil)
                if let checkError {
                    Text(checkError).font(.caption).foregroundStyle(Color.red)
                }
            } header: {
                Text("Phrase")
            } footer: {
                Text(tutor.available == nil
                     ? "The check needs the tutor model: Settings ▸ Tutor Model."
                     : "These are phrases you hear out in the wild — usually things said to you. The tutor confirms the natural German before saving.")
            }
            if let result {
                Section("Checked") {
                    Text(result.german).font(.headline)
                    Text(result.english).foregroundStyle(.secondary)
                    if let note = result.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if aiCouldNotCategorize && scenarios.isEmpty {
                    Section {
                        Label("The AI wasn't sure where you'd hear this phrase. Pick a category below so it can be saved.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                    }
                }
                Section {
                    ForEach(Self.allScenarios) { scenario in
                        Button { toggle(scenario) } label: {
                            HStack {
                                Text(scenario.germanTitle).foregroundStyle(Color.primary)
                                Spacer()
                                if scenarios.contains(scenario) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: {
                    Text("Where you might hear it")
                } footer: {
                    Text(scenarios.isEmpty ? "Required: pick at least one place you'd hear this phrase." : "")
                }
                Section("Grammar") {
                    ForEach(GrammarFocus.allCases) { f in
                        Button { toggle(f) } label: {
                            HStack {
                                Text(f.germanLabel).foregroundStyle(Color.primary)
                                Spacer()
                                if focus.contains(f) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Section {
                    Toggle("Active — quiz me on this", isOn: $isActive)
                } footer: {
                    Text("When active, this phrase is in rotation and the AI may weave it into matching scenario chats.")
                }
            }
        }
        .navigationTitle(phrase == nil ? "New phrase" : "Edit phrase")
        .toolbar {
            Button("Save") { save() }
                .disabled(result == nil || scenarios.isEmpty)
        }
        .onAppear { load() }
    }

    func toggle(_ s: ConversationScenario) {
        if scenarios.contains(s) { scenarios.remove(s) } else { scenarios.insert(s) }
    }

    func toggle(_ f: GrammarFocus) {
        if focus.contains(f) { focus.remove(f) } else { focus.insert(f) }
    }

    /// An existing phrase opens already checked, as on iOS.
    func load() {
        guard !loaded else { return }
        loaded = true
        guard let phrase else { return }
        inputText = phrase.german
        scenarios = Set(phrase.scenarioTagsRaw.compactMap(ConversationScenario.init(rawValue:)))
        focus = Set(phrase.focusAreasRaw.compactMap(GrammarFocus.init(rawValue:)))
        isActive = phrase.isActive
        result = ConversationPrompts.PhraseCheckResult(german: phrase.german, english: phrase.english, fixed: false,
                                                       note: phrase.note)
        checkedModelRaw = phrase.creatorModelRaw.isEmpty ? nil : phrase.creatorModelRaw
    }

    /// iOS `runCheck`: the same prompts and parser, on this phone's tutor.
    func check() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        checking = true
        checkError = nil
        result = nil
        aiCouldNotCategorize = false
        Task {
            defer { checking = false }
            guard await tutor.ensureLoaded(), let model = tutor.available else {
                checkError = "Couldn't load the tutor. Try again."
                return
            }
            do {
                let raw = try await tutor.complete(
                    system: ConversationPrompts.phraseCheckSystemPrompt(
                        inputIsGerman: inputIsGerman, suggestScenarios: autoScenario, suggestGrammar: autoGrammar),
                    user: ConversationPrompts.phraseCheckUserPrompt(text),
                    maxTokens: (autoScenario || autoGrammar) ? 256 : 160)
                logger.debug("PhraseEditor: check answered: \(raw)")
                if let parsed = ConversationPrompts.parsePhraseCheck(raw) {
                    result = parsed
                    checkedModelRaw = model.rawValue
                    // iOS `applyAISuggestions`: scenarios only when the AI named some, grammar as given.
                    if autoScenario {
                        if !parsed.scenarios.isEmpty {
                            scenarios = Set(parsed.scenarios)
                        } else if scenarios.isEmpty {
                            aiCouldNotCategorize = true
                        }
                    }
                    if autoGrammar { focus = Set(parsed.focusAreas) }
                } else {
                    checkError = "Couldn't read a clear answer. Try rephrasing the phrase."
                }
            } catch {
                checkError = "The check failed. Make sure the model is loaded and try again."
            }
        }
    }

    func save() {
        guard let result, !scenarios.isEmpty else { return }
        var p = phrase ?? LearnedPhraseRecord(german: result.german, english: result.english)
        p.german = result.german
        p.english = result.english
        p.scenarioTagsRaw = Self.allScenarios.filter { scenarios.contains($0) }.map(\.rawValue)
        p.focusAreasRaw = GrammarFocus.allCases.filter { focus.contains($0) }.map(\.rawValue)
        p.isActive = isActive
        p.note = result.note
        if let checkedModelRaw { p.creatorModelRaw = checkedModelRaw }
        PhraseBook.shared.save(p)
        dismiss()
    }
}

/// Before a scenario chat with phrases in rotation (iOS `ConversationPhrasePreviewView`): the
/// phrases the tutor will work in, to keep or uncheck.
struct PhrasePreviewView: View {
    let phrases: [LearnedPhraseRecord]
    let onBegin: ([LearnedPhraseRecord]) -> Void
    @State var unchecked: Set<UUID> = []
    @State var revealGerman = false

    var body: some View {
        List {
            Section {
                Text("These phrases from your library will be woven into this chat — the tutor's character will say them so you get used to hearing them. Uncheck any you don't want this time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(phrases, id: \.id) { phrase in
                    Button {
                        if unchecked.contains(phrase.id) { unchecked.remove(phrase.id) } else { unchecked.insert(phrase.id) }
                    } label: {
                        HStack {
                            Image(systemName: unchecked.contains(phrase.id) ? "circle" : "checkmark.circle.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(revealGerman ? phrase.german : phrase.english).foregroundStyle(Color.primary)
                                if revealGerman {
                                    Text(phrase.english).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Phrases you'll hear")
                    Spacer()
                    Button(revealGerman ? "Hide German" : "Reveal German") { revealGerman.toggle() }
                        .buttonStyle(.borderless)
                }
            }
            Section {
                Button("Begin conversation") { onBegin(phrases.filter { !unchecked.contains($0.id) }) }
            }
        }
        .navigationTitle("Before you start")
    }
}
