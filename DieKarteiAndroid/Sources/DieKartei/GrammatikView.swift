@testable import DieKarteiCore
import SwiftUI

/// The grammar drills that need no language model: the iOS app's own content and rules.
struct GrammatikView: View {
    var body: some View {
        List {
            Section("Artikel & Fälle") {
                NavigationLink("Kasus-Lektionen") { KasusLessonsView() }
                NavigationLink("der, die oder das?") { ArtikelView() }
                NavigationLink("Präpositionen: welcher Fall?") { PraepositionenView() }
                NavigationLink("Die vier Fälle") { FaelleView() }
            }
            Section("Lückensätze") {
                ForEach(GrammarExerciseService.loadCategories()) { category in
                    NavigationLink {
                        LueckenView(category: category)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title)
                            Text("\(category.exercises.count) Sätze · \(category.subtitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Verben") {
                NavigationLink("Perfekt: haben oder sein?") { PerfektView() }
            }
        }
        .navigationTitle("Grammatik")
    }
}

/// A row of answer buttons that colour themselves once the round is answered.
struct AnswerButtons: View {
    let options: [String]
    let correct: String
    @Binding var picked: String?
    var tint: (String) -> Color = { _ in Color.accentColor }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    if picked == nil { picked = option }
                } label: {
                    Text(option)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(color(for: option))
            }
        }
    }

    func color(for option: String) -> Color {
        guard let picked else { return tint(option) }
        if option == correct { return Color.green }
        if option == picked { return Color.red }
        return Color.gray
    }
}

/// The running score line shared by the drills.
struct ScoreLine: View {
    let done: Int
    let right: Int
    let total: Int

    var body: some View {
        Text("\(min(done + 1, total)) von \(total) · richtig: \(right)")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

// MARK: - der, die, das

/// The der/die/das game on the Goethe nouns, with the same pattern hints as iOS (`ArticleRules`).
struct ArtikelView: View {
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var round: [A1Entry] = []
    /// Logged when the round is done, as iOS logs its grammar rounds.
    @State var studyRound = StudyRound { .grammar($0) }
    @State var index = 0
    @State var right = 0
    @State var picked: String?
    @Environment(\.colorScheme) var scheme

    var level: GoetheLevel { GoetheLevel(rawValue: levelRaw) ?? .a1 }

    var body: some View {
        VStack(spacing: 20) {
            if index < round.count {
                let entry = round[index]
                let article = GermanArticle(text: entry.article) ?? .der
                ScoreLine(done: index, right: right, total: round.count)
                Spacer()
                Text(entry.word).font(.largeTitle)
                Text(entry.translation ?? "").foregroundStyle(.secondary)
                Spacer()
                AnswerButtons(options: GermanArticle.allCases.map(\.rawValue),
                              correct: article.rawValue, picked: $picked,
                              tint: { AndroidPalette.gender(GermanArticle(rawValue: $0)!.gender, dark: scheme == .dark) })
                if let picked {
                    feedback(entry: entry, article: article, wasRight: picked == article.rawValue)
                }
            } else {
                Spacer()
                Text("\(right) von \(round.count) richtig").font(.title2)
                Button("Neue Runde") { newRound() }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("der, die, das")
        .onAppear { if round.isEmpty { newRound() } }
    }

    func feedback(entry: A1Entry, article: GermanArticle, wasRight: Bool) -> some View {
        VStack(spacing: 8) {
            Text(wasRight ? "Richtig!" : "\(article.rawValue) \(entry.word)")
                .font(.headline)
                .foregroundStyle(wasRight ? Color.green : AndroidPalette.gender(article.gender, dark: scheme == .dark))
            if let rule = ArticleRules.hint(for: entry.word, article: article) {
                Text("\(rule.title) · \(rule.examples)")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            } else {
                Text(ArticleRules.noRuleHint(for: entry.word, article: article))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            Button("Weiter") {
                if wasRight { right += 1 }
                picked = nil
                studyRound.add()
                if index + 1 == round.count { studyRound.finish() }
                index += 1
            }
            .buttonStyle(.borderedProminent)
        }
    }

    func newRound() {
        studyRound.start()
        let nouns = GoetheVocabService.entries(for: level).filter { GermanArticle(text: $0.article) != nil }
        round = Array(nouns.shuffled().prefix(15))
        index = 0
        right = 0
        picked = nil
    }
}

// MARK: - Präpositionen

/// Which case does the preposition take? The iOS drill's question, from prepositions.json.
struct PraepositionenView: View {
    @State var round: [Preposition] = []
    /// Logged when the round is done, as iOS logs its grammar rounds.
    @State var studyRound = StudyRound { .grammar($0) }
    @State var index = 0
    @State var right = 0
    @State var picked: String?
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 20) {
            if index < round.count {
                let prep = round[index]
                ScoreLine(done: index, right: right, total: round.count)
                Spacer()
                Text(prep.word).font(.largeTitle)
                Text(prep.meaningLine).foregroundStyle(.secondary)
                Spacer()
                AnswerButtons(options: PrepositionCase.allCases.map(\.germanLabel),
                              correct: prep.governs.germanLabel, picked: $picked,
                              tint: { label in caseColor(PrepositionCase.allCases.first { $0.germanLabel == label }) })
                if let picked {
                    VStack(spacing: 8) {
                        Text("\(prep.word): \(prep.governs.germanLabel) (\(prep.governs.englishLabel))")
                            .font(.headline)
                        ForEach(prep.revealExamples()) { example in
                            VStack(spacing: 2) {
                                Text(example.german)
                                Text(example.english).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let line = prep.contractionLine {
                            Text(line).font(.footnote)
                        }
                        Button("Weiter") {
                            if picked == prep.governs.germanLabel { right += 1 }
                            self.picked = nil
                            studyRound.add()
                            if index + 1 == round.count { studyRound.finish() }
                            index += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .multilineTextAlignment(.center)
                }
            } else {
                Spacer()
                Text("\(right) von \(round.count) richtig").font(.title2)
                Button("Neue Runde") { newRound() }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Präpositionen")
        .onAppear { if round.isEmpty { newRound() } }
    }

    func caseColor(_ group: PrepositionCase?) -> Color {
        switch group {
        case .akkusativ: AndroidPalette.kasus(.akkusativ, dark: scheme == .dark)
        case .dativ: AndroidPalette.kasus(.dativ, dark: scheme == .dark)
        case .genitiv: AndroidPalette.kasus(.genitiv, dark: scheme == .dark)
        case .wechsel: AndroidPalette.hex(scheme == .dark ? 0xA98BF5 : 0x7B4FD6)
        case nil: Color.accentColor
        }
    }

    func newRound() {
        studyRound.start()
        let core = PrepositionService.all().filter { $0.tier != .advanced }
        round = Array(core.shuffled().prefix(10))
        index = 0
        right = 0
        picked = nil
    }
}

// MARK: - Lückensätze

/// One category of grammar_exercises.json: a sentence with a gap and the category's options.
struct LueckenView: View {
    let category: GrammarCategory
    @State var round: [GrammarExercise] = []
    /// Logged when the round is done, as iOS logs its grammar rounds.
    @State var studyRound = StudyRound { .grammar($0) }
    @State var index = 0
    @State var right = 0
    @State var picked: String?

    var body: some View {
        VStack(spacing: 20) {
            if index < round.count {
                let exercise = round[index]
                ScoreLine(done: index, right: right, total: round.count)
                Spacer()
                Text(exercise.sentence)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                if let english = exercise.english {
                    Text(english).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                AnswerButtons(options: exercise.options ?? category.options,
                              correct: exercise.correctAnswer, picked: $picked)
                if let picked {
                    VStack(spacing: 8) {
                        Text(exercise.sentence.replacingOccurrences(of: "______", with: exercise.correctAnswer))
                            .font(.headline)
                        if let why = exercise.why {
                            Text(why).font(.footnote)
                        }
                        Button("Weiter") {
                            if picked == exercise.correctAnswer { right += 1 }
                            self.picked = nil
                            studyRound.add()
                            if index + 1 == round.count { studyRound.finish() }
                            index += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .multilineTextAlignment(.center)
                }
            } else {
                Spacer()
                Text("\(right) von \(round.count) richtig").font(.title2)
                Text(category.ruleNote).font(.footnote).multilineTextAlignment(.center)
                Button("Nochmal") { newRound() }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding()
        .navigationTitle(category.title)
        .onAppear { if round.isEmpty { newRound() } }
    }

    func newRound() {
        studyRound.start()
        round = category.exercises.shuffled()
        index = 0
        right = 0
        picked = nil
    }
}

// MARK: - Perfekt

/// haben or sein, then the Partizip II: the past_tense_verbs.json list the iOS Perfekt drill uses.
struct PerfektView: View {
    @State var level = PastTenseLevel.a1
    @State var round: [PastTenseVerbEntry] = []
    /// Logged when the round is done, as iOS logs its grammar rounds.
    @State var studyRound = StudyRound { .grammar($0) }
    @State var index = 0
    @State var right = 0
    @State var picked: String?

    var body: some View {
        VStack(spacing: 20) {
            Picker("Niveau", selection: $level) {
                ForEach(PastTenseLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            if index < round.count {
                let verb = round[index]
                ScoreLine(done: index, right: right, total: round.count)
                Spacer()
                Text(verb.infinitive).font(.largeTitle)
                Text(verb.translation).foregroundStyle(.secondary)
                Spacer()
                AnswerButtons(options: ["haben", "sein"], correct: verb.auxiliary, picked: $picked)
                if let picked {
                    VStack(spacing: 8) {
                        Text("er \(verb.auxiliary == "sein" ? "ist" : "hat") \(verb.pastParticiple)")
                            .font(.title2)
                        if let example = verb.example, verb.exampleSource == "tatoeba" {
                            Text(example).font(.footnote)
                        }
                        Button("Weiter") {
                            if picked == verb.auxiliary { right += 1 }
                            self.picked = nil
                            studyRound.add()
                            if index + 1 == round.count { studyRound.finish() }
                            index += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .multilineTextAlignment(.center)
                }
            } else {
                Spacer()
                Text("\(right) von \(round.count) richtig").font(.title2)
                Button("Neue Runde") { newRound() }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Perfekt")
        .onAppear { if round.isEmpty { newRound() } }
        .onChange(of: level) { _, _ in newRound() }
    }

    func newRound() {
        studyRound.start()
        round = Array(PastTenseVerbService.entries(for: level).shuffled().prefix(12))
        index = 0
        right = 0
        picked = nil
    }
}
