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

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(FlashcardImageStyle.defaultsKey) private var imageStyle: FlashcardImageStyle = .immersive

    /// Loaded from disk by the card itself, so a picture that finishes generating mid-session
    /// appears as soon as SwiftData hands down the new file name.
    @State private var cardImage: UIImage?
    @State private var showingFullScreenImage = false

    private var theme: ModelTheme? { model?.theme }

    /// Top-right corner badge image: the generating model's logo when known, else the deck's asset
    /// badge (e.g. Goethe), else nothing.
    private var makerBadge: Image? {
        if let model { return model.logoImage }
        if let badgeLogoName { return Image(badgeLogoName) }
        return nil
    }

    private var cardColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20)
            : Color(red: 0.98, green: 0.96, blue: 0.93)
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

    private var genderBadge: (symbol: String, color: Color)? {
        guard isShowingGerman else { return nil }
        switch article?.lowercased() {
        case "der": return ("figure.stand", .blue)
        case "die": return ("figure.stand.dress", Color(.systemPink))
        case "das": return ("figure.stand.dress.line.vertical.figure", .purple)
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            // Card background — the base for the ruled (text) face; the image face covers it.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardColor)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    theme?.accent.opacity(0.35) ?? Color.gray.opacity(colorScheme == .dark ? 0.5 : 0.3),
                    lineWidth: 1
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
            cardImage = CardImageStore.loadImage(fileName: imageFileName, deckID: imageDeckID)
        }
        .shadow(
            color: theme?.accent.opacity(0.28) ?? .black.opacity(0.1),
            radius: theme == nil ? 8 : 12, x: 0, y: 4
        )
        .padding(.horizontal)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isFlipped.toggle()
            }
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let cardImage {
                FullScreenImageView(image: cardImage, caption: germanDisplay)
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

                // Word + pronunciation, floated over the picture.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(germanDisplay)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 1)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)

                    Button {
                        SpeechService.shared.speak(germanDisplay)
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 28) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(lineColor)
                        .frame(height: 0.5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 70)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                    HStack(spacing: 10) {
                        Text(isFlipped ? backText : frontText)
                            .font(.system(size: 38, weight: .bold, design: .serif))
                            .foregroundStyle(.primary)

                        if isShowingGerman {
                            Button {
                                SpeechService.shared.speak(germanDisplay)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(theme?.accent ?? .blue)
                            }
                            .buttonStyle(.plain)
                        }
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

#Preview {
    FlashCardView(isFlipped: .constant(false))
}
