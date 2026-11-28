@testable import DieKarteiCore
import GermanVoice
import SwiftUI

/// The Wortschatz deck with spaced repetition: what's due, then a few new words. Rated with the
/// iOS app's four buttons, scheduled by the shared SM-2 code (`SRSScheduling`), run as iOS runs an
/// Anki session (`AnkiRound`: a missed card comes back three cards later), and saved on device
/// with a result on the Wortschatz deck when it ends.
struct KartenView: View {
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var store = StudyStore.shared
    @State var deck: [A1Entry] = []
    @State var round = AnkiRound(order: [])
    @State var plan = (due: 0, fresh: 0)
    @State var flipped = false
    @State var startedAt = Date()
    /// Distinct cards rated this session.
    @State var counted: Set<Int> = []
    /// The session's place in today's log. iOS logs a finished session and pauses the rest to
    /// resume later; Android has no pause yet, so a session left early is logged on leaving.
    @State var studyRound = StudyRound { .cards($0) }

    var level: GoetheLevel { GoetheLevel(rawValue: levelRaw) ?? .a1 }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Niveau", selection: $levelRaw) {
                ForEach(GoetheLevel.allCases) { level in
                    Text(level.rawValue).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)

            let stats = store.stats(for: level)
            Text("\(stats.seen) von \(stats.total) gelernt · \(stats.due) fällig")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let index = round.current, deck.indices.contains(index) {
                let entry = deck[index]
                StudyCardFace(word: entry.word, article: entry.article, translation: entry.translation,
                              example: entry.example, flipped: flipped)
                    .onTapGesture { withAnimation { flipped.toggle() } }

                Text("Karte \(min(counted.count + 1, round.dueCount)) von \(round.dueCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if flipped {
                    ratingButtons(for: entry, index: index)
                } else {
                    Button("Umdrehen") { withAnimation { flipped = true } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Spacer()
                Text(round.dueCount == 0 ? "Nichts fällig." : "Fertig für jetzt: \(round.dueCount) Karten.")
                    .font(.title3)
                Button("Weiter lernen") { reload() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Karteikarten")
        .onAppear { if deck.isEmpty { reload() } }
        .onDisappear { studyRound.finish() }
        .onChange(of: levelRaw) { _, _ in reload() }
    }

    func ratingButtons(for entry: A1Entry, index: Int) -> some View {
        let previews = store.previews(for: entry, level: level, index: index)
        return HStack(spacing: 8) {
            ForEach(AnkiRating.allCases, id: \.rawValue) { rating in
                Button {
                    rate(entry, index: index, rating: rating)
                } label: {
                    VStack(spacing: 2) {
                        Text(rating.label).font(.caption).lineLimit(1)
                        Text(previews[rating] ?? "").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(ratingColor(rating))
            }
        }
    }

    func rate(_ entry: A1Entry, index: Int, rating: AnkiRating) {
        store.rate(entry, level: level, index: index, rating: rating)
        if counted.insert(index).inserted { studyRound.add() }
        round.rate(rating, repeatMissed: AnkiSessionRules.repeatMissed())
        flipped = false
        if round.isFinished { finish() }
    }

    /// As iOS's `saveQuizResult` for a Wortschatz session: a result on the Wortschatz deck,
    /// labelled with what the session held, and the cards in today's log.
    func finish() {
        let tally = round.tally
        let scope = WortschatzScope(levels: [level], wordTypes: WortschatzScope.all.wordTypes)
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        DeckLibrary.shared.saveResult(.cardSession(
            deck: SyncSingletonDecks.wortschatzDeckID, correct: tally.correct, total: tally.total,
            missed: tally.missed, seconds: seconds, mode: .anki, ankiRatings: round.firstRatings,
            subDeckLabel: "\(plan.due) due · \(plan.fresh) new · \(scope.summary)"))
        studyRound.finish()
    }

    func ratingColor(_ rating: AnkiRating) -> Color {
        switch rating {
        case .again: Color.red
        case .hard: Color.orange
        case .good: Color.green
        case .easy: Color.blue
        }
    }

    func reload() {
        studyRound.finish()
        studyRound.start()
        let chosen = store.plan(for: level)
        deck = chosen.due + chosen.fresh
        plan = (chosen.due.count, chosen.fresh.count)
        // Every card in a Wortschatz session is due or new (iOS's player deals them the same way).
        round = AnkiRound(order: AnkiSessionRules.dueOrder(deck.map { _ in nil }, now: Date(),
                                                           shuffle: AnkiSessionRules.shuffle()))
        counted = []
        startedAt = Date()
        flipped = false
    }
}
