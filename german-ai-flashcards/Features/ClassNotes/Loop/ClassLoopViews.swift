//
//  ClassLoopViews.swift
//  german-ai-flashcards
//
//  The loop around a session (roadmap section E, docs/CLASS_NOTES.md ▸ The loop around a session):
//
//  - Vor der Stunde (item 12, DLI-RESP 3): the day before, the lesson's words as a short round and
//    its handouts to read, plus the questions saved for the teacher.
//  - Nach der Stunde (item 13, DLI-RESP 5): the same day, free recall first (three things class
//    covered), then the entry's words and grammar. No entry yet: log it.
//  - Sprechen vorbereiten (item 16, DLI-STRAT 3b): a topic, an outline, phrases to the course deck,
//    then a rehearsal with the tutor.
//

import SwiftData
import SwiftUI

// MARK: - Shared

enum ClassLoop {
    /// A plain card round from an entry's words. Nothing rescheduled: these may not be cards yet.
    static func wordSession(_ words: [ClassWord], title: String) -> StudySession? {
        let cards = words.filter { !$0.german.isEmpty }.map { word -> VocabCard in
            let split = CardKind.split(word.german)
            return VocabCard(germanWord: split.word, englishTranslation: word.english,
                             wordType: split.wordType, article: split.article)
        }
        guard !cards.isEmpty else { return nil }
        var session = StudySession(cards: cards, topic: title, deckID: nil, flashcardStyle: .default,
                                   subDeckLabel: "\(title) · \(cards.count) words")
        session.autoStart = true
        return session
    }

    /// The entry a "before class" round prepares from: one dated on the next session (imported
    /// ahead), else the most recent one.
    static func prepEntry(for course: ClassCourse, now: Date = .now) -> (entry: ClassEntry, isAhead: Bool)? {
        if let next = course.nextSessionDay(from: now), let ahead = course.entry(on: next), next > Calendar.current.startOfDay(for: now) {
            return (ahead, true)
        }
        let past = course.entries.filter { $0.date <= now }.max { $0.date < $1.date }
        return past.map { ($0, false) }
    }

    static func sessionLine(_ course: ClassCourse, now: Date = .now) -> String? {
        guard let day = course.nextSessionDay(from: now) else { return nil }
        let cal = Calendar.current
        let when: String
        if cal.isDateInToday(day) { when = "Heute" }
        else if cal.isDateInTomorrow(day) { when = "Morgen" }
        else { when = day.formatted(.dateTime.weekday(.wide).day().month()) }
        return [when, ClassSchedule.timeLabel(minutes: course.meetingMinutes)].compactMap { $0 }.joined(separator: ", ")
    }
}

extension ConversationConfig {
    /// A chat with the learner's own conversation settings, for screens that start one directly
    /// (the weekly recap's pattern). Mode, scenario and focus are the caller's.
    @MainActor
    static func fromSettings(_ manager: MLXModelManager) -> ConversationConfig {
        var config = ConversationConfig(model: manager.selectedChatModel)
        config.learnerName = ConversationConfig.learnerName(from: manager.learnerName)
        config.level = manager.germanLevel
        config.formality = Formality(rawValue: manager.chatFormalityRaw) ?? .du
        config.correctionsEnabled = manager.chatCorrectionsEnabled
        config.correctionTranslationEnabled = manager.chatShowCorrectionTranslation
        config.strictness = CorrectionStrictness(rawValue: manager.chatStrictnessRaw) ?? .balanced
        config.feedbackStyle = FeedbackStyle(rawValue: manager.chatFeedbackStyleRaw) ?? .tellMe
        config.autoPlay = manager.autoPlayReplies
        config.inputMode = manager.chatInputMode
        config.eagerAssist = manager.chatEagerAssist
        config.autoShowTranslation = manager.chatAutoShowTranslation
        config.hintCount = manager.chatHintCount
        config.autoHints = manager.chatAutoHints
        config.genderColors = manager.chatGenderColors
        return config
    }
}

// MARK: - Vor der Stunde

struct BeforeClassView: View {
    @Bindable var course: ClassCourse
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(ActivityRouter.self) private var router

    var body: some View {
        let prep = ClassLoop.prepEntry(for: course)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ClassLoop.sessionLine(course).map { "Nächste Stunde: \($0)" } ?? "No session scheduled")
                        .font(.headline)
                    Text("Looking at the lesson before it starts makes the class easier to follow.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .themedListRow()

            ClassQuestionsSection(course: course, showsAnswered: false)

            if let prep {
                Section {
                    if let session = ClassLoop.wordSession(prep.entry.words, title: "Vor der Stunde") {
                        Button {
                            router.launch(.cardDeck(session))
                        } label: {
                            Label("Eine kurze Runde · \(prep.entry.words.count) words", systemImage: "rectangle.stack")
                        }
                    } else {
                        Text("No words on this entry yet. Add the lesson's words or import its handout.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(prep.entry.materials) { material in
                        NavigationLink {
                            ClassMaterialDetailView(material: material, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            Label(material.title.isEmpty ? "Handout" : material.title, systemImage: "doc.text")
                        }
                    }
                } header: {
                    Text(prep.isAhead ? "Die nächste Stunde · Next lesson" : "Zuletzt · Last lesson").themedSectionHeader()
                } footer: {
                    Text(prep.isAhead
                         ? "From the handouts and words you added to the next session's entry."
                         : "Nothing imported for the next session yet, so this warms up with the last one. Add the next lesson's handout ahead to preview it here.")
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Vor der Stunde")
    }
}

// MARK: - Nach der Stunde

struct AfterClassView: View {
    @Bindable var course: ClassCourse
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityRouter.self) private var router

    @State private var recall: [String] = ["", "", ""]
    @State private var revealed = false
    @State private var logging = false
    @State private var lessonFocus: GrammarFocus?

    private var entry: ClassEntry? { course.entry(on: .now) }

    var body: some View {
        List {
            if let entry {
                Section {
                    ForEach(0..<3, id: \.self) { i in
                        TextField("Thing \(i + 1)", text: $recall[i], axis: .vertical)
                            .disabled(revealed)
                    }
                    if !revealed {
                        Button("Vergleichen · Compare with your notes") { saveRecall(entry) }
                            .disabled(recall.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                    }
                } header: {
                    Text("Was war heute dran? · Three things").themedSectionHeader()
                } footer: {
                    Text("From memory first, before looking: recalling is what makes it stick.")
                }
                .themedListRow()

                if revealed {
                    Section {
                        if !entry.trimmedTitle.isEmpty { Text(entry.trimmedTitle).font(.headline) }
                        if !entry.grammarFoci.isEmpty {
                            Text("Grammatik: " + entry.grammarFoci.map(\.germanLabel).joined(separator: ", "))
                        }
                        if !entry.topics.isEmpty { Text("Themen: " + entry.topics.joined(separator: ", ")) }
                        if !entry.words.isEmpty {
                            Text("Wörter: " + entry.words.prefix(12).map(\.german).joined(separator: ", "))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Deine Notizen · What you logged").themedSectionHeader()
                    }
                    .themedListRow()

                    Section {
                        if let session = ClassLoop.wordSession(entry.words, title: "Nach der Stunde") {
                            Button {
                                router.launch(.cardDeck(session))
                            } label: {
                                Label("Quiz today's words (\(entry.words.count))", systemImage: "rectangle.stack")
                            }
                        }
                        ForEach(entry.grammarFoci) { focus in
                            Button {
                                practise(focus)
                            } label: {
                                Label("Practise \(focus.germanLabel)", systemImage: "checklist")
                            }
                        }
                        if entry.words.isEmpty && entry.grammarFoci.isEmpty {
                            Text("Add the words and grammar to today's entry and they can be quizzed here.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Jetzt üben · Practise").themedSectionHeader()
                    }
                    .themedListRow()
                }
            } else {
                Section {
                    Text(course.meetsToday() ? "Class was today and nothing is logged yet." : "No entry for today.")
                    Button {
                        logging = true
                    } label: {
                        Label("Log today's class", systemImage: "square.and.pencil")
                    }
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Nach der Stunde")
        .onAppear {
            if let saved = entry?.recall, !saved.isEmpty {
                recall = (saved + ["", "", ""]).prefix(3).map { $0 }
                revealed = true
            }
        }
        .sheet(isPresented: $logging) {
            ClassEntryEditorView(entry: nil, course: course) { _ in }
        }
        .sheet(item: $lessonFocus) { focus in
            GrammarLessonSheet(focus: focus)
        }
    }

    private func saveRecall(_ entry: ClassEntry) {
        entry.recall = recall.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        entry.updatedAt = .now
        try? modelContext.save()
        withAnimation { revealed = true }
    }

    private func practise(_ focus: GrammarFocus) {
        switch GrammarRoute(focus).resolve(in: modelContext, level: modelManager.germanLevel) {
        case .launch(let activity): router.launch(activity)
        case .lesson(let f): lessonFocus = f
        case .prepositionHub: lessonFocus = focus
        }
    }
}

// MARK: - Sprechen vorbereiten

struct SpeakPrepView: View {
    @Bindable var course: ClassCourse
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext

    @AppStorage("speakPrep.outline") private var outlineStore = ""
    @State private var topic = ""
    @State private var outline = ""
    @State private var phrase = ""
    @State private var savedPhrases: [String] = []
    @State private var chat: ActiveChat?

    var body: some View {
        List {
            Section {
                TextField("Topic", text: $topic, axis: .vertical)
            } header: {
                Text("Thema · Topic").themedSectionHeader()
            } footer: {
                Text("From the course goal or the last class. Change it to what you want to talk about.")
            }
            .themedListRow()

            Section {
                TextEditor(text: $outline)
                    .frame(minHeight: 120)
            } header: {
                Text("Stichpunkte · Your outline").themedSectionHeader()
            } footer: {
                Text("A few points you want to say, in German or English. Planning what to say is half the practice.")
            }
            .themedListRow()

            Section {
                HStack {
                    TextField("A phrase you want to use", text: $phrase)
                        .textInputAutocapitalization(.never)
                    Button("Add") { addPhrase() }
                        .disabled(phrase.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(savedPhrases, id: \.self) { Label($0, systemImage: "checkmark") }
            } header: {
                Text("Redemittel · Phrases").themedSectionHeader()
            } footer: {
                Text("Each one goes to the course deck.")
            }
            .themedListRow()

            Section {
                Button {
                    rehearse()
                } label: {
                    Label("Proben mit dem Tutor · Rehearse", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
            }
        }
        .themedListScreen()
        .navigationTitle("Sprechen vorbereiten")
        .onAppear {
            guard topic.isEmpty else { return }
            let last = course.sortedEntries.first
            topic = course.goal?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? last.map { e in ([e.trimmedTitle] + e.topics).filter { !$0.isEmpty }.joined(separator: ", ") }?.nilIfEmpty
                ?? ""
            outline = outlineStore
        }
        .onChange(of: outline) { _, new in outlineStore = new }
        .fullScreenCover(item: $chat) { active in
            ConversationView(conversation: active.conversation, config: active.config,
                             modelManager: modelManager, mlxService: mlxService)
        }
    }

    private func addPhrase() {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        _ = ClassDeckStore.saveWord(german: p, english: nil, course: course, context: modelContext)
        savedPhrases.append(p)
        phrase = ""
    }

    private func rehearse() {
        var config = ConversationConfig.fromSettings(modelManager)
        config.mode = .scenario
        config.scenario = .custom
        let points = outline.trimmingCharacters(in: .whitespacesAndNewlines)
        config.customScenario = "Ich bereite mich auf meinen Deutschkurs vor und möchte über dieses Thema sprechen: \(topic)."
            + (points.isEmpty ? "" : " Meine Stichpunkte: \(points)")
            + " Spiel eine freundliche Gesprächspartnerin, frag nach und lass mich die Punkte ausführen."
        if let entry = course.sortedEntries.first {
            config.focusAreas = Array(entry.grammarFoci.prefix(2))
        }
        let convo = ChatConversation(config: config)
        convo.title = "Probe · \(topic.prefix(40))"
        modelContext.insert(convo)
        try? modelContext.save()
        chat = ActiveChat(conversation: convo, config: config)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
