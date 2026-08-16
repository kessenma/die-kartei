//
//  PrepositionCardsView.swift
//  german-ai-flashcards
//
//  The preposition reference deck: one index card per preposition, swipeable, in the same
//  ruled-card look as `FlashCardView`. Front is the bare preposition — so the deck doubles as a
//  self-test — and the back carries the case, the meanings, the contractions and a worked
//  example (both sentences for a two-way preposition).
//
//  The case-colored tab down the leading edge appears on the *back* only: on the front the case
//  is the answer, so showing it there would hand it over — the same reason `FlashCardView` gates
//  its gender tab to the German side.
//

import SwiftUI

struct PrepositionCardsView: View {
    /// Optional starting filter, so a hub row can open straight into one group.
    var initialGroup: PrepositionCase?

    @Environment(\.appTheme) private var appTheme
    @AppStorage("prepositions.includeAdvanced") private var includeAdvanced = false

    @AppStorage(PrepositionPictureMode.defaultsKey) private var pictureModeRaw = PrepositionPictureMode.on.rawValue

    @State private var group: PrepositionCase?
    @State private var index = 0
    @State private var shuffleSeed = 0
    @State private var showRules = false
    /// Hoisted out of the card so the 3D canvas can react to it without living inside the
    /// card's `rotation3DEffect`.
    @State private var isFlipped = false

    init(initialGroup: PrepositionCase? = nil) {
        self.initialGroup = initialGroup
        _group = State(initialValue: initialGroup)
    }

    /// The current filter's cards. `shuffleSeed` is folded in so tapping shuffle re-derives it.
    private var cards: [Preposition] {
        let groups: Set<PrepositionCase> = group.map { [$0] } ?? Set(PrepositionCase.allCases)
        let all = PrepositionService.prepositions(groups: groups, includeAdvanced: includeAdvanced)
        guard shuffleSeed > 0 else { return all }
        var generator = SeededGenerator(seed: UInt64(shuffleSeed))
        return all.shuffled(using: &generator)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if cards.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No prepositions here",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Turn on the formal ones to see this group.")
                )
                Spacer()
            } else {
                GeometryReader { geo in
                    let layout = deckLayout(in: geo.size.height)
                    VStack(spacing: 0) {
                        sceneCanvas(height: layout.scene)

                        TabView(selection: $index) {
                            ForEach(Array(cards.enumerated()), id: \.element.word) { position, prep in
                                PrepositionCard(
                                    preposition: prep,
                                    height: layout.card,
                                    isFlipped: $isFlipped
                                )
                                .padding(.vertical, Self.cardPagePadding / 2)
                                .tag(position)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .id(deckIdentity)
                        .onChange(of: index) { isFlipped = false }
                    }
                }

                pager
            }
        }
        .background {
            if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
        }
        .navigationTitle("Preposition Cards")
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRules = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showRules) {
            PrepositionRulesSheet()
        }
    }

    // MARK: - The scene canvas
    //
    // One RealityView for the whole deck, sitting *above* the card rather than inside it. The
    // card flips with a `rotation3DEffect`, and a RealityKit surface inside a 3D-transformed
    // container is unreliable — so the illustration lives outside the transform and simply
    // re-poses as you turn the card over or page to the next word.

    private var showsPictures: Bool {
        (PrepositionPictureMode(rawValue: pictureModeRaw) ?? .on).showsSceneOnQuestion
    }

    private var current: Preposition? {
        cards.indices.contains(index) ? cards[index] : nil
    }

    /// Whether to hold a slot open for the illustration. Answered for the **deck**, not the card
    /// on screen: only 21 prepositions have a scene, and sizing per card would resize the card
    /// under your thumb every time you swiped onto one of the others.
    private var reservesSceneSlot: Bool {
        showsPictures && cards.contains { PrepositionScene.exists(for: $0.word) }
    }

    @ViewBuilder
    private func sceneCanvas(height: CGFloat) -> some View {
        if showsPictures, let prep = current, PrepositionScene.exists(for: prep.word) {
            PrepositionSceneView(
                word: prep.word,
                mode: isFlipped ? .resolved(prep.governs) : .neutral,
                loops: isFlipped && prep.governs == .wechsel
            )
            .frame(height: height)
            .padding(.top, 4)
            // Turning the card over reveals the case, so the scene resolves with it.
            .animation(.easeInOut(duration: 0.3), value: isFlipped)
        } else {
            Color.clear.frame(height: height)
        }
    }

    // MARK: - Sizing

    /// Vertical padding around each card page, split above and below.
    private static let cardPagePadding: CGFloat = 24

    private struct DeckLayout {
        var scene: CGFloat
        var card: CGFloat
    }

    /// Splits the space between the filter bar and the pager, so the two together always fit it.
    ///
    /// They used to be hard-coded at 190 and 400. On a regular-height phone that overran the
    /// space by around a hundred points: the VStack squeezed the flexible page slot, and the
    /// card's fixed frame drew *outside* it — over the illustration at the top and the pager at
    /// the bottom. The card gets first call on what's here, since it carries the text.
    private func deckLayout(in height: CGFloat) -> DeckLayout {
        guard height > 0 else { return DeckLayout(scene: 0, card: 0) }

        let usable = height - Self.cardPagePadding
        guard reservesSceneSlot else { return DeckLayout(scene: 0, card: max(0, usable)) }

        // Below this the picture stops reading as anything; above it, extra height is better
        // spent on the card.
        var scene = min(190, max(110, height * 0.24))
        var card = usable - scene
        if card < 280 {
            // Too tight for both. The card takes what it can and the picture gives way — but it
            // never takes more than there is, or we'd be back to drawing outside the slot.
            card = max(0, min(280, usable))
            scene = max(0, usable - card)
        }
        return DeckLayout(scene: scene, card: card)
    }

    /// Changes whenever the deck's contents change, so the pager resets instead of landing on a
    /// stale index (and the flip state starts fresh).
    private var deckIdentity: String {
        "\(group?.rawValue ?? "all")-\(includeAdvanced)-\(shuffleSeed)"
    }

    // MARK: - Filter

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(nil, label: "All")
                    ForEach(PrepositionCase.allCases) { candidate in
                        filterChip(candidate, label: candidate.germanLabel)
                    }
                }
                .padding(.horizontal)
            }

            Toggle("Include formal (innerhalb, jenseits…)", isOn: $includeAdvanced)
                .font(.caption)
                .padding(.horizontal)
        }
        .padding(.top, 8)
        .onChange(of: group) { index = 0; isFlipped = false }
        .onChange(of: includeAdvanced) { index = 0; isFlipped = false }
    }

    private func filterChip(_ candidate: PrepositionCase?, label: String) -> some View {
        let isOn = group == candidate
        let tint = candidate?.color ?? .accentColor
        return Button {
            group = candidate
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? tint : tint.opacity(0.12), in: appTheme.pillShape)
                .foregroundStyle(isOn ? .white : tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pager

    private var pager: some View {
        HStack {
            Button {
                withAnimation { index = max(0, index - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
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
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(index >= cards.count - 1)
        }
        .padding(.horizontal, 24)
        // Clears the app's floating tab bar — the list screens buy the same room with
        // `.contentMargins(.bottom, 120)`, which a plain VStack can't use.
        .padding(.bottom, 100)
    }
}

// MARK: - The card

/// One preposition as a flippable index card, in `FlashCardView`'s ruled-paper language.
private struct PrepositionCard: View {
    let preposition: Preposition
    /// Handed down by the deck, which is the only thing that knows how much room is left once
    /// the filter bar, the illustration and the pager have taken theirs.
    let height: CGFloat
    /// Owned by the deck, because the 3D canvas above the card has to follow it.
    @Binding var isFlipped: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var appTheme

    private var cardRadius: CGFloat { appTheme.innerRadius(16) }

    /// Klar keeps the hand-tuned index-card paper; the identity themes draw the card on their own
    /// surface. Copied deliberately from `FlashCardView` — same motif, same values.
    private var cardColor: Color {
        if appTheme != .klar { return appTheme.surface }
        return colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20)
            : Color(red: 0.98, green: 0.96, blue: 0.93)
    }

    private var cardStroke: Color {
        if appTheme.cardBorderWidth > 0 { return appTheme.cardBorderColor }
        return preposition.governs.color.opacity(0.35)
    }

    private var lineColor: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.38, blue: 0.45).opacity(0.3)
            : Color(red: 0.78, green: 0.82, blue: 0.90).opacity(0.4)
    }

    private var redRuleColor: Color {
        colorScheme == .dark
            ? Color(red: 0.70, green: 0.30, blue: 0.30).opacity(0.4)
            : Color(red: 0.85, green: 0.35, blue: 0.35).opacity(0.5)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(cardColor)
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .stroke(
                    cardStroke,
                    lineWidth: appTheme.cardBorderWidth > 0 ? appTheme.cardBorderWidth : 1
                )

            ruledLines

            // The case tab is the answer, so it only shows once the card is turned over — and it
            // rides inside the counter-rotated group, or the flip would mirror it onto the
            // trailing edge.
            Group {
                if isFlipped {
                    ZStack {
                        backFace
                        caseTab
                    }
                } else {
                    frontFace
                }
            }
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .frame(height: height)
        // Nothing may draw outside the card. The ruled lines are nine fixed rows on a fixed
        // rhythm and the back face can run long on a wordy preposition; without this both spill
        // past the edge, which is how ink ends up on top of the illustration above.
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .shadow(color: preposition.governs.color.opacity(0.22), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
        .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isFlipped.toggle()
            }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
    }

    private var ruledLines: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(redRuleColor)
                    .frame(height: 1.5)
                    .padding(.top, 60)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))

            VStack(spacing: 28) {
                ForEach(0..<9, id: \.self) { _ in
                    Rectangle()
                        .fill(lineColor)
                        .frame(height: 0.5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 70)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
    }

    private var caseTab: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(preposition.governs.color)
                .frame(width: 6)
            Spacer(minLength: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the case is already read out on the back
    }

    // MARK: Front — the bare preposition

    private var frontFace: some View {
        VStack(spacing: 0) {
            Text("PRÄPOSITION")
                .font(.caption2)
                .fontWeight(.semibold)
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            Spacer()

            HStack(spacing: 10) {
                Text(preposition.word)
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Button {
                    SpeechService.shared.speak(preposition.word)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(preposition.governs.color)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("Tap to see the case")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
    }

    // MARK: Back — case, meanings, contractions, examples

    private var backFace: some View {
        VStack(spacing: 8) {
            Text(preposition.governs.germanLabel.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(1.5)
                .foregroundStyle(preposition.governs.color)
                .padding(.top, 20)

            Text(preposition.governs.articleLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(preposition.meaningLine)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .padding(.top, 2)

            if let contractions = preposition.contractionLine {
                Text(contractions)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(preposition.governs.color)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Divider()
                .padding(.horizontal, 40)
                .padding(.vertical, 2)

            // Every sentence, the scene-depicting ones leading and the extras dimmed beneath.
            PrepositionExampleRows(examples: preposition.examples,
                                   governs: preposition.governs,
                                   density: .compact,
                                   dimsExtras: true)
                .padding(.horizontal, 18)

            if let note = preposition.note {
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
}

// `SeededGenerator` moved to `Models/SeededGenerator.swift` when the placement debug seeder needed
// the same deterministic shuffle.

#Preview("Preposition cards · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                PrepositionCardsView()
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}
