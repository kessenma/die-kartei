import Foundation

/// When a new deck's pictures get drawn, relative to the "Keep which cards?" review.
///
/// Both settings finish the pictures before the deck opens — the difference is only whether the
/// review happens before or after the drawing, which decides who pays for a discarded card:
///
/// - `.everyCard` draws all of them first, so the review shows the pictures and you can throw out
///   a card because its drawing came out wrong. Cards you discard cost drawing time.
/// - `.keptCards` reviews first and draws only what survived. Nothing is wasted, but you're
///   picking cards sight-unseen.
///
/// Stored in `UserDefaults` alongside `CardImageStyle` and read the same way: the pickers use
/// `@AppStorage`, the flow reads `current`.
///
/// The batch queue ignores this — it has no review step, so every card it generates is kept and
/// illustrated regardless.
nonisolated enum CardImageTiming: String, CaseIterable, Identifiable {
    /// Draw for every generated card, before the review.
    case everyCard
    /// Draw only for the cards kept in the review.
    case keptCards

    static let defaultsKey = "cardImageTiming"

    /// `.keptCards` is the default: it never spends a minute of diffusion on a card that's about
    /// to be thrown away.
    static var current: CardImageTiming {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(CardImageTiming.init(rawValue:)) ?? .keptCards
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyCard: "Every card"
        case .keptCards: "Cards I keep"
        }
    }

    var caption: String {
        switch self {
        case .everyCard:
            "Pictures are drawn right after the words, so you can see them while picking which cards to keep. Cards you discard still cost drawing time."
        case .keptCards:
            "You pick the cards first, then only those get drawn. Nothing is wasted, but the review has no pictures in it."
        }
    }
}
