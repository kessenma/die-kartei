import Foundation

/// How much work Stable Diffusion puts into each picture — the one quality knob exposed to the
/// learner, shared by story illustrations and flashcard pictures.
///
/// Only the diffusion **step count** varies: output resolution is baked into the compiled CoreML
/// model (512×512) and can't be changed at runtime, so steps are the whole trade-off. More steps
/// means a cleaner, better-composed picture and a proportionally longer wait.
///
/// Stored in `UserDefaults` rather than on `MLXModelManager` because both the Settings UI (via
/// `@AppStorage`) and `StoryImageService` (via `current`, off in a service with no manager
/// reference) need it — the shared key is the coupling, and there's nothing to thread through.
nonisolated enum ImageGenQuality: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case best

    static let defaultsKey = "imageGenQuality"

    /// The learner's current choice. Read fresh per image, so changing the tier mid-run applies
    /// from the next picture onward.
    static var current: ImageGenQuality {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(ImageGenQuality.init(rawValue:)) ?? .balanced
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var id: String { rawValue }

    /// Diffusion steps per image — the only thing that actually changes.
    var stepCount: Int {
        switch self {
        case .fast:     15
        case .balanced: 25
        case .best:     40
        }
    }

    var label: String {
        switch self {
        case .fast:     "Fast"
        case .balanced: "Balanced"
        case .best:     "Best"
        }
    }

    /// Times are rough, per picture, on a recent iPhone — the honest range across devices is wide.
    var caption: String {
        switch self {
        case .fast:
            "15 steps — roughly half a minute a picture. Softer detail, good enough for flashcards."
        case .balanced:
            "25 steps — roughly a minute a picture. The default."
        case .best:
            "40 steps — two minutes or more a picture. Cleaner detail and composition."
        }
    }
}
