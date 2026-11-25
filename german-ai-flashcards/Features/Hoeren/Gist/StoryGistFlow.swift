//
//  StoryGistFlow.swift
//  german-ai-flashcards
//
//  Stories ▸ Hören as DLI teaches listening (docs/HOEREN.md ▸ Worum geht's?):
//
//  1. Erst raten (DLI-STRAT 1a, 1d): "don't listen to an audio cold". The title and topic show,
//     and the learner names words they expect.
//  2. Hören, with the text hidden. "Text zeigen" reveals it early and the attempt says so.
//  3. Worum geht's? (DLI-FLO): one or two sentences in English, before any question.
//  4. Vergleichen: the summary beside the story's key points, ticked ja / teilweise / nein by the
//     learner, and which predicted words came up. The app computes the score; no tutor grades it
//     in Release (the judge is DEBUG-only until its probe has been read).
//
//  The flow lives here; `StoryDetailView` hosts its sections in listen mode. The cards take the
//  story screen's own tint, not the Hören room's, so they read as part of the story.
//

import SwiftData
import SwiftUI

@MainActor
@Observable
final class StoryGistSession {
    enum Phase: Equatable { case predict, listening, summary, compare, done }

    var phase: Phase = .predict
    var predictions: [String] = []
    var draftWord = ""
    var summary = ""
    /// Per key point: 0 nein, 1 teilweise, 2 ja; nil until ticked.
    var ticks: [Int?] = []
    var revealedEarly = false
    var plays = 0
    var hits: [String: [String]] = [:]
    var startedAt = Date()
    var saved = false
    #if DEBUG
    var judged: [GistVerdict?] = []
    #endif

    /// The transcript shows once the summary is written or skipped, or when the learner asked.
    var transcriptVisible: Bool { revealedEarly || phase == .compare || phase == .done }

    func addPrediction() {
        let word = draftWord.trimmingCharacters(in: .whitespacesAndNewlines)
        draftWord = ""
        guard word.count >= 2, !predictions.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        predictions.append(word)
    }

    func startListening() {
        addPrediction()
        if phase == .predict { phase = .listening }
    }

    /// The story played to its end, or the learner said they were done.
    func finishListening(story: StudyStory) {
        guard phase == .listening || phase == .predict else { return }
        hits = StoryGlossaryHighlighter.hits(for: predictions, in: story.storyText)
        phase = .summary
    }

    func compare(points: Int) {
        ticks = Array(repeating: nil, count: points)
        phase = .compare
    }

    /// Halves of a point the learner ticked (ja 2, teilweise 1).
    var halves: Int { ticks.compactMap { $0 }.reduce(0, +) }

    /// Writes the attempt once. Credits one Hören item for the summary.
    func save(story: StudyStory, points: [String], context: ModelContext) {
        guard !saved, phase == .compare || phase == .done else { return }
        saved = true
        let round = HoerenRound(kind: .gist)
        round.levelRaw = story.levelRaw
        round.sourceRaw = "story:" + story.id.uuidString
        round.playbackRaw = HoerenPlayback.study.rawValue
        round.askedCount = 1
        round.correctCount = halves
        round.replayCount = max(0, plays - 1)
        round.durationSeconds = max(1, Int(Date().timeIntervalSince(startedAt)))
        var item = HoerenItem(id: 0, expected: story.title, spoken: "")
        item.predictions = predictions
        item.predictionHits = predictions.filter { hits[$0] != nil }
        item.summary = summary
        item.keyPoints = points
        item.selfTicks = ticks.map { $0 ?? 0 }
        item.revealedEarly = revealedEarly
        item.replays = max(0, plays - 1)
        // "Correct" here means every point caught; the stats read the halves, not this.
        item.correct = !points.isEmpty && halves == points.count * 2
        round.items = [item]
        HoerenScoringService.save(round, in: context)
    }
}

// MARK: - 1. Predict

struct GistPredictCard: View {
    let story: StudyStory
    @Bindable var session: StoryGistSession
    let onListen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Erst raten · Predict first", systemImage: "lightbulb")
                .font(.headline)
                .foregroundStyle(.tint)
            Text("„\(story.title)“")
                .font(.title3.weight(.semibold))
            if story.topic != story.title {
                Text(story.topic).font(.callout).foregroundStyle(.secondary)
            }
            Text("Which German words do you expect to hear? Name a few; after listening you'll see which came up.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("ein Wort", text: $session.draftWord)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { session.addPrediction() }
                    .textFieldStyle(.roundedBorder)
                Button {
                    session.addPrediction()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(session.draftWord.trimmingCharacters(in: .whitespaces).count < 2)
            }

            if !session.predictions.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(session.predictions, id: \.self) { word in
                        Button {
                            session.predictions.removeAll { $0 == word }
                        } label: {
                            HStack(spacing: 4) {
                                Text(word)
                                Image(systemName: "xmark").font(.caption2)
                            }
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.tint.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(word)")
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    session.startListening()
                    onListen()
                } label: {
                    Label("Los, hören · Listen", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Überspringen") {
                    session.startListening()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 2. Text hidden

struct GistHiddenTranscript: View {
    @Bindable var session: StoryGistSession
    let onDoneListening: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("The text stays hidden while you listen", systemImage: "eye.slash")
                .font(.callout.weight(.medium))
            Text("Listen as often as you need. When you've got the gist, say what it was about.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    onDoneListening()
                } label: {
                    Label("Fertig gehört · Done listening", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.phase != .listening && session.phase != .predict)

                Button("Text zeigen") { session.revealedEarly = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 3. Summary

struct GistSummaryCard: View {
    @Bindable var session: StoryGistSession
    let onCompare: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Worum geht's? · What was it about?", systemImage: "text.bubble")
                .font(.headline)
                .foregroundStyle(.tint)
            Text("In one or two sentences, in English. Who, what happened, how it ended.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("It was about…", text: $session.summary, axis: .vertical)
                .lineLimit(3...6)
                .focused($focused)
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 12) {
                Button {
                    focused = false
                    onCompare()
                } label: {
                    Label("Vergleichen", systemImage: "list.bullet.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Überspringen") {
                    focused = false
                    onCompare()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
        .onAppear { focused = true }
    }
}

// MARK: - 4. Compare

struct GistCompareCard: View {
    let story: StudyStory
    @Bindable var session: StoryGistSession
    /// True while the tutor writes key points for an older story.
    let makingPoints: Bool
    let canMakePoints: Bool
    let onMakePoints: () -> Void
    let onFinish: () -> Void
    #if DEBUG
    let onJudge: (() -> Void)?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !session.summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your summary").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(session.summary).font(.callout)
                }
            }

            if !session.predictions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your guesses: \(session.predictions.filter { session.hits[$0] != nil }.count) of \(session.predictions.count) came up")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    WrapLayout(spacing: 6) {
                        ForEach(session.predictions, id: \.self) { word in
                            let forms = session.hits[word]
                            HStack(spacing: 4) {
                                Image(systemName: forms == nil ? "circle" : "checkmark.circle.fill")
                                Text(forms.map { f in f.contains(where: { $0.lowercased() != word.lowercased() }) ? "\(word) (\(f.joined(separator: ", ")))" : word } ?? word)
                            }
                            .font(.callout)
                            .foregroundStyle(forms == nil ? Color.secondary : Color.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                }
            }

            if story.hasKeyPoints {
                pointsList
            } else {
                noPoints
            }

            Button {
                onFinish()
            } label: {
                Text(session.phase == .done ? "Saved" : "Fertig · Save")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.phase == .done)
        }
        .padding(.vertical, 6)
    }

    private var pointsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Key points: did your summary have each one?")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if session.ticks.contains(where: { $0 != nil }) {
                    Text("\(HoerenStats.halfString(session.halves)) of \(story.keyPoints.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            ForEach(Array(story.keyPoints.enumerated()), id: \.offset) { index, point in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(point)").font(.callout)
                    Picker("Point \(index + 1)", selection: Binding(
                        get: { session.ticks.indices.contains(index) ? (session.ticks[index] ?? -1) : -1 },
                        set: { value in
                            if session.ticks.count < story.keyPoints.count {
                                session.ticks = Array(repeating: nil, count: story.keyPoints.count)
                            }
                            session.ticks[index] = value
                        }
                    )) {
                        Text("Ja").tag(2)
                        Text("Teilweise").tag(1)
                        Text("Nein").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .disabled(session.phase == .done)
                    #if DEBUG
                    if session.judged.indices.contains(index) {
                        Text("Tutor (debug): \(session.judged[index]?.label ?? "unsure")")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    #endif
                }
            }
            Text("You decide; the score is yours to check. A point you said differently still counts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #if DEBUG
            if let onJudge, !session.summary.isEmpty {
                Button("Ask the tutor (debug)", action: onJudge)
                    .font(.caption)
            }
            #endif
        }
    }

    @ViewBuilder
    private var noPoints: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This story has no key points yet.")
                .font(.callout.weight(.medium))
            if makingPoints {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Writing key points…").font(.caption).foregroundStyle(.secondary)
                }
            } else if canMakePoints {
                Button("Make key points", action: onMakePoints)
                    .buttonStyle(.bordered)
            }
            if let english = story.englishText, !english.isEmpty {
                Text("Compare with the English translation instead:")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(english).font(.callout)
            }
        }
    }
}
