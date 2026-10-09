//
//  VerbPrepositionReviewView.swift
//  german-ai-flashcards
//
//  Wiederholen: the verb pairs' spaced-repetition review. Due pairs first, then a handful of new
//  ones (VerbPrepositionService.reviewQueue), each on the verb card: „warten ___“ with its scene
//  frozen, then flipped to „auf + Akkusativ“ with the scene playing, then rated with the same
//  four buttons and interval previews as the card player's Anki mode.
//
//  Its own screen rather than a card-player session because the player shows the German side
//  verbatim (the answer would sit on the card's face) and has no per-deck front side. The
//  scheduling is the app's: `SpacedRepetitionService` on the synced review box, so due pairs
//  also surface on Today.
//

import SwiftUI
import SwiftData

struct VerbPrepositionReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrepositionPictureMode.defaultsKey) private var pictureModeRaw = PrepositionPictureMode.on.rawValue

    /// Verbs in play order. A pair rated „Didn't know“ comes back once at the end.
    @State private var queue: [String] = []
    @State private var cardsByVerb: [String: SavedCard] = [:]
    @State private var position = 0
    @State private var isFlipped = false
    @State private var ratings = 0
    @State private var missed: [String] = []
    @State private var startedAt = Date()
    @State private var phase: Phase = .loading

    private enum Phase { case loading, reviewing, finished, empty }

    private static let pairs = Dictionary(
        VerbPrepositionService.all().map { ($0.verb, $0) }, uniquingKeysWith: { first, _ in first }
    )

    private var currentPair: VerbPreposition? {
        queue.indices.contains(position) ? Self.pairs[queue[position]] : nil
    }

    private var showsPictures: Bool {
        (PrepositionPictureMode(rawValue: pictureModeRaw) ?? .on).showsSceneOnQuestion
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .empty:
                caughtUp
            case .finished:
                summary
            case .reviewing:
                if let pair = currentPair { reviewer(pair) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
        }
        .navigationTitle("Wiederholen")
        .navigationBarTitleDisplayMode(.inline)
        .task { if phase == .loading { start() } }
    }

    // MARK: - Session

    private func start() {
        let deck = VerbPrepositionService.fetchOrCreateDeck(in: modelContext)
        cardsByVerb = Dictionary(deck.cards.map { ($0.germanWord, $0) }, uniquingKeysWith: { first, _ in first })
        queue = VerbPrepositionService.reviewQueue(deck.cards).map(\.germanWord)
        position = 0
        isFlipped = false
        ratings = 0
        missed = []
        startedAt = Date()
        phase = queue.isEmpty ? .empty : .reviewing
    }

    private func rate(_ rating: AnkiRating) {
        guard queue.indices.contains(position), let card = cardsByVerb[queue[position]] else { return }
        SpacedRepetitionService.apply(rating: rating, to: card)
        try? modelContext.save()
        ratings += 1
        // One second look at a miss, the way the card player re-queues; not an endless loop.
        if rating == .again, !missed.contains(card.germanWord) {
            missed.append(card.germanWord)
            queue.append(card.germanWord)
        }
        isFlipped = false
        position += 1
        if position >= queue.count { finish() }
    }

    private func finish() {
        StudyLogService.record(
            .cards(ratings), seconds: Int(Date().timeIntervalSince(startedAt)), in: modelContext
        )
        phase = .finished
    }

    // MARK: - Reviewing

    private func reviewer(_ pair: VerbPreposition) -> some View {
        VStack(spacing: 0) {
            Text("\(min(position + 1, queue.count)) / \(queue.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            GeometryReader { geo in
                let scene = showsPictures ? min(300, max(130, geo.size.height * 0.4)) : 0
                VStack(spacing: 0) {
                    if showsPictures, PrepositionScene.exists(for: pair.sceneKey) {
                        PrepositionSceneView(word: pair.sceneKey,
                                             mode: isFlipped ? .resolved(pair.governs) : .neutral)
                            .frame(height: scene)
                            .animation(.easeInOut(duration: 0.3), value: isFlipped)
                    }
                    VerbPrepositionCard(pair: pair, height: max(240, geo.size.height - scene - 24),
                                        isFlipped: $isFlipped)
                        .padding(.vertical, 12)
                        // A fresh card per pair, so a flip never carries over from the last one.
                        .id(position)
                }
            }

            controls
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isFlipped, queue.indices.contains(position), let card = cardsByVerb[queue[position]] {
            let previews = SpacedRepetitionService.previewIntervals(for: card)
            VStack(spacing: 8) {
                Text("Only Didn't know counts as a miss. Hard, Good and Easy all mean you knew it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    ForEach(AnkiRating.allCases, id: \.rawValue) { rating in
                        Button { rate(rating) } label: {
                            VStack(spacing: 4) {
                                Text(rating.label).font(.subheadline.weight(.medium))
                                Text(previews.first { $0.rating == rating }?.label ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Self.color(rating).opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Self.color(rating).opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Self.color(rating))
                    }
                }
            }
            .padding(.horizontal)
        } else {
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { isFlipped = true }
            } label: {
                Text("Show answer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
    }

    /// The card player's rating colors (CardDeckView+Anki), so the two reviews read alike.
    private static func color(_ rating: AnkiRating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    // MARK: - End states

    private var nextDue: Date? {
        cardsByVerb.values.compactMap(\.nextReviewDate).filter { $0 > .now }.min()
    }

    private var newLeft: Int { cardsByVerb.values.filter { VerbPrepositionService.isNew($0) }.count }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Fertig")
                .font(.title2.weight(.bold))
            Text("\(ratings) reviews" + (missed.isEmpty ? ", none missed." : "."))
                .foregroundStyle(.secondary)
            if !missed.isEmpty {
                VStack(spacing: 4) {
                    Text("Worth another look")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(missed, id: \.self) { verb in
                        if let pair = Self.pairs[verb] {
                            Text("\(pair.verb) · \(pair.answerLine)")
                                .font(.subheadline)
                                .foregroundStyle(pair.governs.color)
                        }
                    }
                }
            }
            if let nextDue {
                Text("Next review \(nextDue.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                if newLeft > 0 {
                    Button {
                        start()
                    } label: {
                        Text("\(min(newLeft, VerbPrepositionService.newPerSession)) more new pairs")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding()
    }

    private var caughtUp: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Nothing due")
                .font(.title3.weight(.semibold))
            Text(nextDue.map { "All 42 pairs are in. The next one comes back \($0.formatted(.relative(presentation: .named)))." }
                 ?? "All 42 pairs are in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding(32)
    }
}

#Preview("Wiederholen") {
    NavigationStack {
        VerbPrepositionReviewView()
    }
    .inMemoryModelContainer(for: [SavedDeck.self, SavedCard.self, StudyDay.self])
}
