import Foundation

/// A picture model reached through the learner's own OpenRouter account. The counterpart of
/// `ImageGenModel`, which is the on-device CoreML path; kept separate because nothing here is
/// downloaded, cached or deleted, and every Settings storage sweep iterates `ImageGenModel`.
///
/// The raw value is the OpenRouter model id. Both models go through `POST /api/v1/images`:
/// Muse isn't served on chat completions at all (404 from the probe, 2026-10-01).
nonisolated enum CloudImageModel: String, CaseIterable, Identifiable, Sendable {
    /// Meta's Muse Image. The cheapest picture on OpenRouter by a distance, and slower: it plans
    /// and reviews its own output before returning. Needs a one-time 18+ confirmation on the
    /// learner's OpenRouter account (see `OpenRouterError.needsAgeConfirmation`).
    case museImage = "meta/muse-image"
    /// Google's Gemini 2.5 Flash Image, "Nano Banana". Fast, follows "no text" well, and keeps
    /// story characters consistent when handed the first picture as a reference.
    case nanoBanana = "google/gemini-2.5-flash-image"

    static let selectionDefaultsKey = "cloudImageModel.selected"

    static var current: CloudImageModel {
        get {
            UserDefaults.standard.string(forKey: selectionDefaultsKey)
                .flatMap(CloudImageModel.init(rawValue:)) ?? .museImage
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectionDefaultsKey) }
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .museImage:  "Muse Image"
        case .nanoBanana: "Nano Banana"
        }
    }

    var maker: String {
        switch self {
        case .museImage:  "Meta"
        case .nanoBanana: "Google"
        }
    }

    /// What one picture costs on the learner's account, from OpenRouter's pricing. Nano Banana
    /// measured $0.0387 per 1024² picture in the probe.
    var approxCostUSD: Double {
        switch self {
        case .museImage:  0.01
        case .nanoBanana: 0.039
        }
    }

    var approxCostLabel: String {
        switch self {
        case .museImage:  "~1¢"
        case .nanoBanana: "~4¢"
        }
    }

    /// Typical wait for one picture. Drives the progress bar, which has nothing else to go on:
    /// neither model streams. Nano Banana took 6–12 s in the probe; Muse is OpenRouter's p50.
    var typicalSeconds: Double {
        switch self {
        case .museImage:  20
        case .nanoBanana: 9
        }
    }

    /// How many earlier pictures a request can carry as references. Stories pass their first
    /// picture so the cast keeps its look; 0 means the model gets the words alone.
    var maxReferences: Int {
        switch self {
        case .museImage:  1
        case .nanoBanana: 3
        }
    }

    /// `aspect_ratio` for the request body. Square for both: it's what the on-device model draws,
    /// what the story reader's placeholder reserves, and what a card shows. Left to itself Muse
    /// picks a shape per prompt (1920×1280 for a story scene in the probe); asked, it draws 1600².
    var aspectRatio: String? { "1:1" }

    /// Whether OpenRouter gates this model behind an account-level 18+ confirmation. Until the
    /// learner ticks it once, every request fails with `OpenRouterError.needsAgeConfirmation`.
    var needsAgeConfirmation: Bool { self == .museImage }

    /// Whether this model has delivered a picture on this phone. Once it has, Muse's 18+
    /// confirmation is evidently done and Settings stops asking for it; a later
    /// `needsAgeConfirmation` failure (a different account) clears it again.
    var hasDrawnBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "cloudImageModel.drewOnce." + rawValue) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "cloudImageModel.drewOnce." + rawValue) }
    }

    /// The model's page on OpenRouter. For Muse it's where the 18+ confirmation pops up: a
    /// checkbox ("I confirm that I am 18 years of age or older") and a Confirm button.
    var openRouterPage: URL {
        URL(string: "https://openrouter.ai/\(rawValue)")!
    }
}
