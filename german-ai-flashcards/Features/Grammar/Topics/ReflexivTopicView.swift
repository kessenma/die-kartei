//
//  ReflexivTopicView.swift
//  german-ai-flashcards
//
//  A topic that isn't a case, on the Grammatik hub under Themen: the same loop as a unit screen,
//  with what a topic has.
//
//    Die Regel · The rule        the topic's rule lines and the pronoun table
//    Verstehen · Understand      the lesson (a sheet) and the drills the bundled items fill:
//                                Akkusativ oder Dativ?, Die richtige Person, each with ✓ once played
//    Deine Runden · Your rounds  the topic's last three rounds, and all of them in Verlauf
//
//  Built for Reflexive Verben; generalise `KasusUnitView` only when a second non-unit topic
//  arrives. The lesson's Üben stashes a session and launches it once the sheet has gone (a
//  full-screen cover can't come up over a sheet).
//

import SwiftUI
import SwiftData

struct ReflexivTopicView: View {
    var topic: GrammarTopic = .reflexiv

    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext

    @Query private var rounds: [KasusRound]

    /// Nil until the learner opens or closes "Die Regel" by hand. Until then it is open until the
    /// topic's first round.
    @State private var ruleExpandedChoice: Bool?
    @State private var showLesson = false
    @State private var pendingSession: GrammarDrillSession?

    var body: some View {
        List {
            headerSection.themedListRow()
            ruleSection.themedListRow()
            verstehenSection.themedListRow()
            roundsSection.themedListRow()
        }
        .themedListScreen()
        .navigationTitle(topic.germanTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLesson, onDismiss: launchPending) {
            KasusLessonView(
                topic: topic,
                onRead: { seconds in KasusService.recordLessonRead(topicKey: topic.key, seconds: seconds, in: modelContext) },
                onPractice: {
                    pendingSession = GrammarDrillSession(kind: topic.lessonPractice ?? .reflexCase, topic: topic)
                    showLesson = false
                }
            )
        }
    }

    private func launchPending() {
        guard let session = pendingSession else { return }
        pendingSession = nil
        router.launch(.grammarDrill(session))
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: topic.symbol)
                    .font(.title2)
                    .foregroundStyle(topic.color)
                    .frame(width: 44, height: 44)
                    .background(topic.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.englishRole)
                        .font(.headline)
                    Text("mich / mir · dich / dir · sich")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(topic.levelLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Level \(topic.levelLabel)")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Die Regel

    private var topicRounds: [KasusRound] {
        rounds.filter { $0.unitRaw == topic.key && $0.isListed }.sorted { $0.date > $1.date }
    }

    private var isRuleExpanded: Binding<Bool> {
        Binding(
            get: { ruleExpandedChoice ?? topicRounds.isEmpty },
            set: { ruleExpandedChoice = $0 }
        )
    }

    private var ruleSection: some View {
        Section {
            DisclosureGroup(isExpanded: isRuleExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(topic.ruleLines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(kasusRich: line)
                        }
                        .font(.subheadline)
                    }
                    ReflexivPronounTable()
                        .padding(.top, 8)
                }
                .padding(.vertical, 6)
            } label: {
                Text("Die Regel · The rule")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Verstehen

    private var progress: KasusProgress { KasusProgress(rounds: rounds) }

    private var verstehenSection: some View {
        let progress = self.progress
        return Section {
            row(symbol: "lightbulb.fill", title: "Lektion · The idea",
                caption: "What sich is, and when it becomes mir · about 2 min",
                done: progress.lessonRead(topicKey: topic.key), isLesson: true) {
                showLesson = true
            }
            ForEach(topic.exercises()) { kind in
                row(symbol: kind.meta.symbol, title: "\(kind.meta.germanTitle) · \(kind.meta.englishTitle)",
                    caption: "\(kind.meta.blurb) · about \(kind.meta.minutes) min",
                    done: progress.drillDone(kind.step, topicKey: topic.key), isLesson: false) {
                    router.launch(.grammarDrill(GrammarDrillSession(kind: kind, topic: topic)))
                }
            }
        } header: {
            Text("Verstehen · Understand")
                .themedSectionHeader()
        } footer: {
            Text("The idea first, then the two drills. A button round moves the coach's reflexive-verbs skill after six answers; the two-chip sentences are practice.")
        }
    }

    private func row(symbol: String, title: String, caption: String, done: Bool, isLesson: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(topic.color)
                    .frame(width: 34, height: 34)
                    .background(topic.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        Text(caption)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isLesson ? "book.pages" : "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(done ? "Done" : "Not yet")")
    }

    // MARK: - Deine Runden

    @ViewBuilder
    private var roundsSection: some View {
        let played = topicRounds
        if !played.isEmpty {
            Section {
                ForEach(played.prefix(3)) { round in
                    NavigationLink {
                        KasusRoundDetailView(round: round)
                    } label: {
                        KasusRoundRow(round: round, showsUnit: false)
                    }
                }
                NavigationLink {
                    KasusHistoryView(topic: topic)
                } label: {
                    Text(played.count > 3 ? "Alle anzeigen · All \(played.count)" : "Alle anzeigen · Show all")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                }
            } header: {
                Text("Deine Runden · Your rounds")
                    .themedSectionHeader()
            }
        }
    }
}

#Preview("Reflexive Verben · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                ReflexivTopicView()
            }
            .environment(ActivityRouter())
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [KasusRound.self, LearnerProfile.self, StudyDay.self])
}
