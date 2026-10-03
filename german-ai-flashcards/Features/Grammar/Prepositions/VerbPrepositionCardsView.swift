//
//  VerbPrepositionCardsView.swift
//  german-ai-flashcards
//
//  The Verben-mit-Präpositionen reference deck: one card per pair, swipeable, in the same
//  ruled-card look and the same scene-above-the-deck layout as `PrepositionCardsView`.
//
//  Front: the pair with its preposition taken out („warten ___“) and its meaning, the scene
//  frozen on its key pose with the object uncolored, so the deck doubles as a self-test.
//  Back: the preposition and case, the example with the prepositional phrase picked out in the
//  case color, and the scene coloring the object and playing.
//
//  Filtering by one preposition is the bridge between the hub's two tracks: the deck then says
//  what that preposition does on its own (auf: two-way) above the pairs that fix it (all six
//  auf pairs: Akkusativ).
//

import SwiftUI

struct VerbPrepositionCardsView: View {
    @Environment(\.appTheme) private var appTheme
    @AppStorage(PrepositionPictureMode.defaultsKey) private var pictureModeRaw = PrepositionPictureMode.on.rawValue

    /// nil = every pair. A case or a preposition, never both: the chips are one row of choices.
    @State private var caseFilter: PrepositionCase?
    @State private var prepositionFilter: String?
    @State private var index = 0
    @State private var shuffleSeed = 0
    /// Hoisted out of the card so the canvas above can follow it without living inside the
    /// card's `rotation3DEffect`, the same arrangement as `PrepositionCardsView`.
    @State private var isFlipped = false

    private var cards: [VerbPreposition] {
        var pool = VerbPrepositionService.all()
        if let caseFilter { pool = pool.filter { $0.governs == caseFilter } }
        if let prepositionFilter { pool = pool.filter { $0.preposition == prepositionFilter } }
        guard shuffleSeed > 0 else { return pool }
        var generator = SeededGenerator(seed: UInt64(shuffleSeed))
        return pool.shuffled(using: &generator)
    }

    /// The prepositions the pairs use, most pairs first: über (8), auf, an, …
    private var prepositions: [String] {
        let counts = Dictionary(grouping: VerbPrepositionService.all(), by: \.preposition).mapValues(\.count)
        return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }

    private var current: VerbPreposition? { cards.indices.contains(index) ? cards[index] : nil }

    private var showsPictures: Bool {
        (PrepositionPictureMode(rawValue: pictureModeRaw) ?? .on).showsSceneOnQuestion
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if let prepositionFilter { bridge(prepositionFilter) }

            GeometryReader { geo in
                let layout = deckLayout(in: geo.size.height)
                VStack(spacing: 0) {
                    sceneCanvas(height: layout.scene)
                    TabView(selection: $index) {
                        ForEach(Array(cards.enumerated()), id: \.element.verb) { position, pair in
                            VerbPrepositionCard(pair: pair, height: layout.card, isFlipped: $isFlipped)
                                .padding(.vertical, 12)
                                .tag(position)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .id("\(caseFilter?.rawValue ?? "-")-\(prepositionFilter ?? "-")-\(shuffleSeed)")
                    .onChange(of: index) { isFlipped = false }
                }
            }

            pager
        }
        .background {
            if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
        }
        .navigationTitle("Verb-Karten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shuffleSeed += 1
                    index = 0
                } label: {
                    Image(systemName: "shuffle")
                }
            }
        }
    }

    // MARK: - Scene

    /// One canvas for the whole deck, re-posed per card. A canvas per page would build a render
    /// context per page (PREPOSITION_3D.md, "One RealityKit canvas per screen").
    @ViewBuilder
    private func sceneCanvas(height: CGFloat) -> some View {
        if showsPictures, let pair = current, PrepositionScene.exists(for: pair.sceneKey) {
            PrepositionSceneView(
                word: pair.sceneKey,
                mode: isFlipped ? .resolved(pair.governs) : .neutral
            )
            .frame(height: height)
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.3), value: isFlipped)
        } else {
            Color.clear.frame(height: showsPictures ? height : 0)
        }
    }

    private struct DeckLayout {
        var scene: CGFloat
        var card: CGFloat
    }

    /// The scene takes a larger share than on the preposition deck: a verb scene is a whole
    /// tableau (two people, a desk, a bubble) where a preposition scene is one relation, and at
    /// 200pt it read as a thumbnail over a mostly empty card. The card keeps a floor, and never
    /// takes more than there is.
    private func deckLayout(in height: CGFloat) -> DeckLayout {
        guard height > 0 else { return DeckLayout(scene: 0, card: 0) }
        let usable = height - 24
        guard showsPictures else { return DeckLayout(scene: 0, card: max(0, usable)) }
        var scene = min(340, max(140, height * 0.44))
        var card = usable - scene
        if card < 280 {
            card = max(0, min(280, usable))
            scene = max(0, usable - card)
        }
        return DeckLayout(scene: scene, card: card)
    }

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Alle", tint: .accentColor, isOn: caseFilter == nil && prepositionFilter == nil) {
                    caseFilter = nil; prepositionFilter = nil
                }
                ForEach([PrepositionCase.akkusativ, .dativ]) { group in
                    chip(group.germanLabel, tint: group.color, isOn: caseFilter == group) {
                        caseFilter = group; prepositionFilter = nil
                    }
                }
                Divider().frame(height: 20)
                ForEach(prepositions, id: \.self) { word in
                    chip(word, tint: .accentColor, isOn: prepositionFilter == word) {
                        prepositionFilter = word; caseFilter = nil
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .onChange(of: caseFilter) { index = 0; isFlipped = false }
        .onChange(of: prepositionFilter) { index = 0; isFlipped = false }
    }

    private func chip(_ label: String, tint: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? tint : tint.opacity(0.12), in: appTheme.pillShape)
                .foregroundStyle(isOn ? .white : tint)
        }
        .buttonStyle(.plain)
    }

    /// One preposition's two lives: what it does as a place, and what its pairs fix.
    @ViewBuilder
    private func bridge(_ word: String) -> some View {
        let pairs = VerbPrepositionService.verbs(using: word)
        let cases = Set(pairs.map(\.governs))
        let own = PrepositionService.preposition(word)?.governs
        VStack(alignment: .leading, spacing: 4) {
            if let own {
                Text("\(word) on its own: \(own.germanLabel)\(own == .wechsel ? " (Wo? Dativ · Wohin? Akkusativ)" : "")")
            }
            Text(cases.count == 1
                 ? "In these \(pairs.count) pairs the verb fixes it: always \(cases.first!.germanLabel)."
                 : "In these pairs the verb fixes it, and not always the same way. Learn each pair's case.")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Pager

    private var pager: some View {
        HStack {
            Button {
                withAnimation { index = max(0, index - 1) }
            } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(index == 0)
            Spacer()
            Text("\(min(index + 1, cards.count)) / \(cards.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation { index = min(cards.count - 1, index + 1) }
            } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(index >= cards.count - 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

// MARK: - The card

private struct VerbPrepositionCard: View {
    let pair: VerbPreposition
    let height: CGFloat
    @Binding var isFlipped: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var appTheme

    private var cardRadius: CGFloat { appTheme.innerRadius(16) }

    /// Klar keeps the index-card paper, the identity themes their own surface. The same values as
    /// `PrepositionCardsView`, so the two decks are one family.
    private var cardColor: Color {
        if appTheme != .klar { return appTheme.surface }
        return colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20)
            : Color(red: 0.98, green: 0.96, blue: 0.93)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous).fill(cardColor)
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .stroke(appTheme.cardBorderWidth > 0 ? appTheme.cardBorderColor : pair.governs.color.opacity(0.35),
                        lineWidth: appTheme.cardBorderWidth > 0 ? appTheme.cardBorderWidth : 1)

            Group {
                if isFlipped { back } else { front }
            }
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .shadow(color: pair.governs.color.opacity(0.22), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
        .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { isFlipped.toggle() }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
    }

    private var front: some View {
        VStack(spacing: 10) {
            Text("VERB + PRÄPOSITION")
                .font(.caption2).fontWeight(.semibold).tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
            Spacer()
            HStack(spacing: 10) {
                Text(pair.gappedVerb)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Button {
                    SpeechService.shared.speak(pair.verb)
                } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            Text(pair.english)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
            Text("Tap for the preposition and case")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
    }

    private var back: some View {
        VStack(spacing: 8) {
            Text(pair.governs.germanLabel.uppercased())
                .font(.caption2).fontWeight(.bold).tracking(1.5)
                .foregroundStyle(pair.governs.color)
                .padding(.top, 20)

            Text(pair.verb)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 16)

            Text(pair.answerLine)
                .font(.headline)
                .foregroundStyle(pair.governs.color)

            Text(pair.governs.articleLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 40).padding(.vertical, 2)

            if let example = pair.example {
                Text(highlighted(example))
                    .font(.system(size: 18, design: .serif))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 18)
                Text(example.english)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            if let note = pair.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
            Text("Tap to flip back")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 14)
        }
    }

    /// The sentence with its prepositional phrase in the case color: the piece to learn.
    private func highlighted(_ example: VerbPrepositionExample) -> AttributedString {
        var text = AttributedString(example.german)
        if let range = text.range(of: example.object) {
            text[range].foregroundColor = pair.governs.color
            text[range].font = .system(size: 18, weight: .bold, design: .serif)
        }
        return text
    }
}

#Preview("Verb cards") {
    NavigationStack {
        VerbPrepositionCardsView()
    }
}
