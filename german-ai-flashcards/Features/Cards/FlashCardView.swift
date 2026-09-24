// FlashCardView.swift
// Classic index card flash card UI component

import SwiftUI

/// How a card's AI picture is presented on the German side. Persisted (shared with the deck's
/// toolbar toggle) via `FlashcardImageStyle.defaultsKey`.
enum FlashcardImageStyle: String, CaseIterable, Identifiable {
    /// Full-bleed picture, minimal bottom gradient, white word floated over it.
    case immersive
    /// Full-bleed picture with a solid dark bar behind the word — less arty, maximum legibility.
    case highContrast

    var id: String { rawValue }
    static let defaultsKey = "flashcardImageStyle"
    var label: String { self == .immersive ? "Immersive" : "High contrast" }
    var systemImage: String { self == .immersive ? "photo.fill" : "rectangle.bottomthird.inset.filled" }
}

struct FlashCardView: View {
    @Binding var isFlipped: Bool
    var germanWord: String = "Haus"
    var englishWord: String = "House"
    var article: String? = nil
    var showGermanFirst: Bool = true
    var badgeLogoName: String? = nil
    /// The model that generated this card's deck, when known — drives subtle brand accents and the
    /// corner logo badge. `nil` keeps the plain index-card look.
    var model: MLXModel? = nil

    // Optional verb grammar fields — when set, the back shows rich Perfekt info
    var auxiliaryVerb: String? = nil
    var pastParticiple: String? = nil
    var isSeparable: Bool? = nil
    var verbPrefix: String? = nil
    var isRegular: Bool? = nil
    var exampleSentence: String? = nil

    /// This card's AI-generated picture (`SavedCard.imageFileName`) and the deck it's filed under.
    /// Both are needed to find the file; either being nil means the card has no picture.
    var imageFileName: String? = nil
    var imageDeckID: UUID? = nil

    /// "der / die / das?": keep a noun's article off the German side until the flip, so the card
    /// asks for the gender before it shows it. Nothing else on the card may give it away either.
    var hidesArticleUntilFlipped: Bool = false
    /// A noun's plural or a verb's forms, shown under the German word once it is revealed.
    var forms: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    /// Named `appTheme` because `theme` is already this view's `ModelTheme` (the two coexist by design).
    @Environment(\.appTheme) private var appTheme
    @AppStorage(FlashcardImageStyle.defaultsKey) private var imageStyle: FlashcardImageStyle = .immersive

    /// Loaded from disk by the card itself, so a picture that finishes generating mid-session
    /// appears as soon as SwiftData hands down the new file name.
    @State private var cardImage: UIImage?
    @State private var showingFullScreenImage = false
    /// Set on the first flip, so turning the card back over shows the article the learner just
    /// checked instead of asking again. The player recreates the view per card, so it resets.
    @State private var revealed = false

    private var theme: ModelTheme? { model?.theme }

    /// Top-right corner badge image: the generating model's logo when known, else the deck's asset
    /// badge (e.g. Goethe), else nothing.
    private var makerBadge: Image? {
        if let model { return model.logoImage }
        if let badgeLogoName { return Image(badgeLogoName) }
        return nil
    }

    /// Klar keeps the hand-tuned index-card paper; the identity themes draw the card on their own
    /// surface so it belongs to the same world as the chrome around it. The ruled lines stay in
    /// every theme — they're the index-card motif, not chrome.
    private var cardColor: Color {
        if appTheme != .klar { return appTheme.surface }
        return colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20)
            : Color(red: 0.98, green: 0.96, blue: 0.93)
    }

    private var cardRadius: CGFloat { appTheme.innerRadius(16) }

    /// Klar keeps the model's brand hairline (or plain grey); the bordered themes assert their own
    /// ink line / black rule, which is stronger than a 35%-opacity accent would be.
    private var cardStroke: Color {
        if appTheme.cardBorderWidth > 0 { return appTheme.cardBorderColor }
        return theme?.accent.opacity(0.35) ?? Color.gray.opacity(colorScheme == .dark ? 0.5 : 0.3)
    }

    private var hasGender: Bool { article.flatMap(Gender.init(article:)) != nil }

    /// The article is being withheld right now: quiz on, German side up, not yet flipped on this
    /// card, and there is an article to withhold.
    private var articleHidden: Bool {
        hidesArticleUntilFlipped && showGermanFirst && !isFlipped && !revealed && hasGender
    }

    /// The English side of a quizzed noun carries the answer, since with German first the flip is
    /// the only place the learner can check the gender they just guessed.
    private var revealsGenderOnBack: Bool {
        hidesArticleUntilFlipped && showGermanFirst && isFlipped && hasGender
    }

    /// This card's grammatical gender, when it's a noun with a readable article. Nil while the
    /// article is withheld, which is the one switch that silences the tab and the badge too.
    private var gender: Gender? { articleHidden ? nil : article.flatMap(Gender.init(article:)) }

    /// The noun without any article, including one baked into the word by an older deck
    /// ("der Absender" stored as the word), so the question never contains its own answer.
    private var bareGerman: String {
        let trimmed = germanWord.trimmingCharacters(in: .whitespaces)
        for candidate in ["der ", "die ", "das "] where trimmed.lowercased().hasPrefix(candidate) {
            return String(trimmed.dropFirst(candidate.count))
        }
        return trimmed
    }

    /// What the card says out loud and captions with: the bare noun while the article is withheld.
    private var spokenGerman: String { articleHidden ? bareGerman : germanDisplay }

    /// The German word as the card shows it: gender-colored article + noun, or the bare noun under
    /// the "der · die · das?" prompt.
    private var germanText: Text {
        articleHidden ? Text(bareGerman) : Text.gendered(germanWord, article: article)
    }

    /// The question, on its own line so it cannot be read as part of the word.
    private var articlePrompt: some View {
        Text("der · die · das?")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: appTheme.pillShape)
            .accessibilityLabel("Which article?")
    }

    /// The forms caption belongs to the answer, so it waits with the article.
    private var showsForms: Bool { isShowingGerman && !articleHidden && forms != nil }
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

    private var germanDisplay: String {
        germanWord.withArticle(article)
    }
    private var frontText: String { showGermanFirst ? germanDisplay : englishWord }
    private var backText: String { showGermanFirst ? englishWord : germanDisplay }
    private var frontLabel: String { showGermanFirst ? "GERMAN" : "ENGLISH" }
    private var backLabel: String { showGermanFirst ? "ENGLISH" : "GERMAN" }

    /// Whether the German side is currently showing.
    private var isShowingGerman: Bool {
        (showGermanFirst && !isFlipped) || (!showGermanFirst && isFlipped)
    }

    /// The picture is a memory hook for the German word, so it only takes over the card on the
    /// German side; showing it on the answer side would hand over the answer.
    private var showsImageFace: Bool { isShowingGerman && cardImage != nil }

    /// Keyed off whether the card *has* a picture (not whether it's currently visible) so the card
    /// doesn't resize halfway through the flip.
    private var cardHeight: CGFloat { cardImage != nil ? 360 : 280 }

    @ViewBuilder
    private var verbBackContent: some View {
        VStack(spacing: 6) {
            Text(englishWord)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let aux = auxiliaryVerb, let pp = pastParticiple {
                Text("\(aux == "sein" ? "ist" : "hat") \(pp)")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            HStack(spacing: 6) {
                if let aux = auxiliaryVerb {
                    Text(aux)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(aux == "sein" ? Color.green : Color.blue, in: Capsule())
                }
                if isSeparable == true {
                    let label = verbPrefix.map { "trennbar: \($0)-" } ?? "trennbar"
                    Text(label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                }
                if isRegular == false {
                    Text("unregelmäßig")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.8), in: Capsule())
                }
            }
            .padding(.top, 2)

            if let example = exampleSentence {
                Text(example)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
    }

    /// The figure glyph stays, but its color now comes from `GenderPalette` instead of the old
    /// blue/pink/purple — those read as a *third* gender coding next to the article text and the
    /// corner tab. One palette, three places.
    private var genderBadge: (symbol: String, color: Color)? {
        guard isShowingGerman, let gender else { return nil }
        guard gender != .plural else { return nil }
        return (gender.symbol, gender.color)
    }

    /// A slim colored tab down the card's leading edge — der blue, die red, das green — so gender is
    /// legible at a glance even while the word itself is being read.
    ///
    /// German side only: on the answer side of an English→German card it would hand over half the
    /// answer, which is the same reason `genderBadge` is gated.
    @ViewBuilder
    private var genderTab: some View {
        if isShowingGerman, let gender {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(gender.color)
                    .frame(width: 6)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)   // the article is already spoken as part of the word
        }
    }

    var body: some View {
        ZStack {
            // Card background — the base for the ruled (text) face; the image face covers it.
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(cardColor)
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .stroke(
                    cardStroke,
                    lineWidth: appTheme.cardBorderWidth > 0 ? appTheme.cardBorderWidth : 1
                )

            // The two faces, counter-rotated together so text/word reads correctly on the flip.
            Group {
                if showsImageFace {
                    imageFace
                } else {
                    textFace
                }
            }
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            // Above both faces so it reads over the picture too.
            genderTab

            // Maker badge in the top-right corner: the generating model's logo when known,
            // otherwise the deck's asset badge (e.g. Goethe).
            if let badge = makerBadge {
                VStack {
                    HStack {
                        Spacer()
                        badge
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                            .padding(7)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .opacity(0.55)
                                    .blur(radius: 6)
                            )
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .frame(height: cardHeight)
        .task(id: imageFileName) {
            guard let imageFileName, let imageDeckID else {
                cardImage = nil
                return
            }
            // Off the main actor: this used to be a synchronous PNG decode on every card advance.
            // The card fills a wide frame, so the cap is the file's own size — no downsampling
            // is possible here, only the thread it happens on. The full-screen viewer shares the
            // same bitmap rather than decoding a second copy.
            let decoded = await Task.detached(priority: .userInitiated) {
                CardImageStore.loadImage(fileName: imageFileName, deckID: imageDeckID, maxPixelSize: 512)
            }.value
            guard !Task.isCancelled else { return }
            cardImage = decoded
        }
        .onDisappear { cardImage = nil }
        .shadow(
            color: theme?.accent.opacity(0.28) ?? .black.opacity(0.1),
            radius: theme == nil ? 8 : 12, x: 0, y: 4
        )
        .padding(.horizontal)
        .contentShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isFlipped.toggle()
            }
        }
        .onChange(of: isFlipped) { _, flipped in
            if flipped { revealed = true }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let cardImage {
                FullScreenImageView(image: cardImage, caption: spokenGerman)
            }
        }
    }

    // MARK: - Image face (German side, full-bleed picture)

    @ViewBuilder
    private var imageFace: some View {
        if let cardImage {
            ZStack(alignment: .bottom) {
                Image(uiImage: cardImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                scrim

                // Word + pronunciation, floated over the picture. The article keeps its gender color
                // here too — only the noun takes the white the photo needs.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if articleHidden {
                            articlePrompt
                                .environment(\.colorScheme, .dark)
                        }
                        germanText
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 1)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        if showsForms, let forms {
                            Text(forms)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.5), radius: 3)
                                .lineLimit(1)
                        }
                    }

                    Button {
                        SpeechService.shared.speak(spokenGerman)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    if let badge = genderBadge {
                        Image(systemName: badge.symbol)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

                // Expand-to-fullscreen affordance, top-left (clear of the maker badge).
                VStack {
                    HStack {
                        Button {
                            showingFullScreenImage = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(.ultraThinMaterial, in: Circle())
                                .environment(\.colorScheme, .dark)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        }
    }

    /// Legibility scrim under the word. Immersive keeps the picture clear except for a soft bottom
    /// fade; high-contrast lays down a near-solid dark bar.
    @ViewBuilder
    private var scrim: some View {
        switch imageStyle {
        case .immersive:
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.7), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .highContrast:
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.62),
                    .init(color: .black.opacity(0.86), location: 0.74),
                    .init(color: .black.opacity(0.86), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Text face (ruled index card: answer side, or cards without a picture)

    private var textFace: some View {
        ZStack {
            // Ruled lines
            VStack(spacing: 0) {
                Rectangle()
                    .fill(redRuleColor)
                    .frame(height: 1.5)
                    .padding(.top, 60)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))

            VStack(spacing: 28) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(lineColor)
                        .frame(height: 0.5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 70)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))

            VStack(spacing: 0) {
                Text(isFlipped ? backLabel : frontLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)

                Spacer()

                if isFlipped && auxiliaryVerb != nil {
                    verbBackContent
                } else {
                    if articleHidden {
                        articlePrompt
                            .padding(.bottom, 8)
                    }

                    HStack(spacing: 10) {
                        // Only the German side carries an article to color; the English side is a
                        // plain word, so it renders through the same helper unchanged.
                        (isShowingGerman
                            ? germanText
                            : Text(isFlipped ? backText : frontText))
                            .font(.system(size: 38, weight: .bold, design: .serif))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        if isShowingGerman {
                            Button {
                                SpeechService.shared.speak(spokenGerman)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(theme?.accent ?? .blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if showsForms, let forms {
                        Text(forms)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                    }

                    // The answer to "der · die · das?", where the flip lands.
                    if revealsGenderOnBack {
                        Text.gendered(bareGerman, article: article)
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }

                    if let badge = genderBadge {
                        Image(systemName: badge.symbol)
                            .font(.title2)
                            .foregroundStyle(badge.color)
                            .padding(.bottom, 4)
                    }
                }

                Spacer()

                Text(isFlipped ? "Tap to see Question" : "Tap to see Answer")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            }
        }
    }
}

#Preview("Default") {
    FlashCardView(isFlipped: .constant(false))
}

#Preview("der / die / das?") {
    VStack(spacing: 20) {
        FlashCardView(isFlipped: .constant(false), germanWord: "Wohnung", englishWord: "flat",
                      article: "die", hidesArticleUntilFlipped: true, forms: "Plural: -en")
        FlashCardView(isFlipped: .constant(true), germanWord: "Wohnung", englishWord: "flat",
                      article: "die", showGermanFirst: false, hidesArticleUntilFlipped: true, forms: "Plural: -en")
    }
}

#Preview("Gender colors · 4 themes") {
    // One noun per theme so the four grounds/faces and the der(blue)/die(red)/das(green) article
    // coloring + the leading gender tab all show at once.
    let samples: [(de: String, en: String, article: String)] = [
        ("Tisch", "table", "der"),
        ("Blume", "flower", "die"),
        ("Haus", "house", "das"),
        ("Hund", "dog", "der"),
    ]
    return ScrollView {
        VStack(spacing: 20) {
            ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { i, appTheme in
                VStack(spacing: 6) {
                    Text(appTheme.label.uppercased())
                        .font(.caption2).tracking(1).foregroundStyle(.secondary)
                    FlashCardView(
                        isFlipped: .constant(false),
                        germanWord: samples[i].de,
                        englishWord: samples[i].en,
                        article: samples[i].article
                    )
                }
                .environment(\.appTheme, appTheme)
            }
        }
        .padding(.vertical)
    }
}
