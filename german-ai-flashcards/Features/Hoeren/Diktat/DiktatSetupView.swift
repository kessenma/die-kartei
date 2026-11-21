//
//  DiktatSetupView.swift
//  german-ai-flashcards
//
//  Diktat's setup: the level, where the sentences come from (the bundled lists or a course), single
//  pass or study mode, how many. Sentences are bundled or the learner's own class material, never
//  generated: a dictation has to be right word for word.
//

import SwiftData
import SwiftUI

struct DiktatConfig: Identifiable, Hashable {
    let id = UUID()
    var level: CEFRLevel
    var playback: HoerenPlayback
    var sentences: [DiktatSentence]
    /// "vocab,perfekt,kasus" or "course:<id>".
    var sourceRaw: String
}

struct DiktatSetupView: View {
    let modelManager: MLXModelManager

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClassCourse.name) private var courses: [ClassCourse]

    @State private var level: CEFRLevel = .a1
    @State private var sources: Set<DiktatSourceKind> = [.vocab, .perfekt, .kasus]
    @State private var course: ClassCourse?
    @State private var courseCounts: [PersistentIdentifier: Int] = [:]
    @State private var playback: HoerenPlayback = .study
    @State private var count = 5
    @State private var seeded = false
    @State private var running: DiktatConfig?

    private static let levels: [CEFRLevel] = [.a1, .a2, .b1]
    private var activeCourses: [ClassCourse] { courses.filter { !$0.isArchived } }

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
                Text("\(DiktatSentenceBank.pool(for: level, sources: sources).count) sentences at this level from the sources below.")
            }
            .themedListRow()

            Section {
                sourceToggle(.vocab, "Goethe-Beispielsätze", "Example sentences from the A1 and A2 word lists")
                sourceToggle(.perfekt, "Perfekt-Sätze", "Real sentences in the past, from Tatoeba")
                sourceToggle(.kasus, "Kasus-Geschichten", "Sentences from the case stories; their endings carry the case")
            } header: {
                Text("Sätze · Sentences").themedSectionHeader()
            }
            .themedListRow()

            if !activeCourses.isEmpty {
                Section {
                    ForEach(activeCourses) { c in
                        let n = courseCounts[c.persistentModelID] ?? 0
                        Button {
                            course = course?.persistentModelID == c.persistentModelID ? nil : c
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.name).foregroundStyle(n >= DiktatCourseSource.minimum ? .primary : .secondary)
                                    Text(n >= DiktatCourseSource.minimum ? "\(n) sentences from recent handouts and the course deck"
                                                                         : "\(n) sentences so far. Add a handout to the course for more.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if course?.persistentModelID == c.persistentModelID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(HoerenTile.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(n < DiktatCourseSource.minimum)
                    }
                } header: {
                    Text("Deutschkurs").themedSectionHeader()
                } footer: {
                    Text("Pick a course to dictate this week's class material instead of the lists above.")
                }
                .themedListRow()
            }

            Section {
                Picker("Playback", selection: $playback) {
                    ForEach(HoerenPlayback.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper("\(count) sentences", value: $count, in: 3...15)
            } header: {
                Text("Runde · Round").themedSectionHeader()
            } footer: {
                Text(playback.detail + " Write everything you understand; fill the gaps from what the grammar needs.")
            }
            .themedListRow()

            Section {
                Button(action: start) {
                    Label("Los geht's · Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(HoerenTile.tint)
                .disabled(course == nil && sources.isEmpty)
                .listRowBackground(Color.clear)
            }
        }
        .themedListScreen()
        .navigationTitle(HoerenRoundKind.diktat.germanLabel)
        .onAppear {
            if !seeded {
                seeded = true
                let declared = modelManager.germanLevel
                level = Self.levels.contains(declared) ? declared : (declared.hoerenRank > 2 ? .b1 : .a1)
            }
            countCourses()
        }
        .onChange(of: level) { _, _ in countCourses() }
        .fullScreenCover(item: $running) { config in
            NavigationStack {
                DiktatView(config: config)
            }
        }
    }

    private func sourceToggle(_ kind: DiktatSourceKind, _ title: String, _ subtitle: String) -> some View {
        Toggle(isOn: Binding(
            get: { sources.contains(kind) },
            set: { on in if on { sources.insert(kind) } else { sources.remove(kind) } }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(HoerenTile.tint)
        .disabled(course != nil)
    }

    private func countCourses() {
        var counts: [PersistentIdentifier: Int] = [:]
        for c in activeCourses {
            counts[c.persistentModelID] = DiktatCourseSource.sentences(for: c, level: level, context: modelContext).count
        }
        courseCounts = counts
    }

    private func start() {
        var rng = SystemRandomNumberGenerator()
        if let course {
            let pool = DiktatCourseSource.sentences(for: course, level: level, context: modelContext)
            running = DiktatConfig(level: level, playback: playback,
                                   sentences: Array(pool.shuffled(using: &rng).prefix(count)),
                                   sourceRaw: "course:" + course.id.uuidString)
        } else {
            running = DiktatConfig(level: level, playback: playback,
                                   sentences: DiktatSentenceBank.round(level: level, sources: sources, count: count, rng: &rng),
                                   sourceRaw: sources.map(\.rawValue).sorted().joined(separator: ","))
        }
    }
}
