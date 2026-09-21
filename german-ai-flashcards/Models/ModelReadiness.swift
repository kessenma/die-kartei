import Foundation

/// What a feature needs on disk before it can run.
///
/// Split out because the app kept re-deriving the same question. `ModelPickerButton`,
/// `StoryStudyService`, `StorySetupView`, `JobPostingDetailView` and half a dozen others each
/// answered "do I have a usable model?" with their own inline `isDownloaded` filter, and each
/// printed its own untappable "go to Settings → Model". One vocabulary means a feature can state
/// its requirement once and let ``ModelReadiness`` decide.
enum ModelRequirement {
    /// Bundled content: the drills, der·die·das, the prepositions, the placement check. Runs on a
    /// phone that has downloaded nothing at all.
    case none
    /// Any language model, the built-in Apple one included.
    case anyModel
    /// One of the in-house German tutors. Stories hard-gate on this — see
    /// ``StoryStudyService/eligibleModels``.
    case germanTutor
    /// The Core ML image model. Always optional; nothing in the app is blocked by its absence.
    case imageModel
}

/// A snapshot of what this phone can do right now.
///
/// A value type rather than `@Observable` on purpose: every input is a filesystem or system read
/// (`MLXModel.isDownloaded` walks the hub cache for `refs/main`), so there is nothing to observe and
/// nothing to keep in sync. Views build one on demand and re-read it behind a refresh token, the way
/// `ModelSettingsView` already does with its `cacheRefreshID`. Don't cache one in a stored property:
/// it goes stale the moment a download lands.
struct ModelReadiness {
    /// What the learner can actually do, best tier first. Deliberately three cases and not a
    /// `Bool`: "has a model" flattens the distinction Kyle cares about, which is that Apple
    /// Intelligence is a glimpse of the app rather than the app.
    enum Tier {
        /// Nothing downloaded and no Apple Intelligence. The bundled half of the app still works.
        case offline
        /// Apple Intelligence only. Flashcards and basic chat; no stories.
        case builtIn
        /// An in-house German tutor is on disk. Everything the AI writes is available.
        case tutor
    }

    /// Whether the built-in model is usable on this device right now. Not a download — Apple
    /// Intelligence can go away between launches (eligibility, Siri settings), so this is read
    /// fresh alongside everything else.
    let appleIntelligence: Bool

    /// The best German tutor actually on disk, or nil. What "set up" means.
    let tutor: MLXModel?

    /// The best tutor this device *could* run, downloaded or not.
    ///
    /// The guard against pitching a download the hardware can't hold. Onboarding already learned
    /// this lesson the hard way — a hard-wired hero meant a 4 GB phone was offered a 5 GB model it
    /// could never load — so every upgrade nudge checks this before it offers anything.
    let fittingTutor: MLXModel?

    /// Whether the picture model is on disk.
    let hasImageModel: Bool

    /// Reads the world. Cheap enough to call from a view body behind a refresh token, but it does
    /// touch the filesystem once per tutor, so don't call it in a loop.
    static var current: ModelReadiness {
        #if DEBUG
        if let forced = debugOverride { return forced }
        #endif
        return ModelReadiness(
            appleIntelligence: AppleIntelligenceService.currentlyAvailable(),
            // `germanTutors` is ordered best-first, so `first` is the best one present.
            tutor: MLXModel.germanTutors.first(where: \.isDownloaded),
            fittingTutor: MLXModel.leadTutor(ramGB: DeviceCapability.ramGB),
            hasImageModel: ImageGenModel.current.isDownloaded
        )
    }

    #if DEBUG
    /// `-onboarding.debugTier none|apple|tutor` forces the answer.
    ///
    /// Every surface that reacts to readiness — the Home card, the conversation nudge, the pictures
    /// nudge — is otherwise unreachable on a simulator, which can't run MLX and can't be tapped
    /// through a multi-gigabyte download. `fittingTutor` stays real so the "never pitch a model this
    /// phone can't hold" guard is exercised rather than bypassed.
    private static var debugOverride: ModelReadiness? {
        guard let raw = UserDefaults.standard.string(forKey: "onboarding.debugTier") else { return nil }
        let fitting = MLXModel.leadTutor(ramGB: DeviceCapability.ramGB)
        switch raw.lowercased() {
        case "none":
            return ModelReadiness(appleIntelligence: false, tutor: nil, fittingTutor: fitting, hasImageModel: false)
        case "apple":
            return ModelReadiness(appleIntelligence: true, tutor: nil, fittingTutor: fitting, hasImageModel: false)
        case "tutor":
            return ModelReadiness(
                appleIntelligence: false,
                tutor: fitting ?? .hero,
                fittingTutor: fitting,
                hasImageModel: false
            )
        default:
            return nil
        }
    }
    #endif

    var tier: Tier {
        if tutor != nil { return .tutor }
        return appleIntelligence ? .builtIn : .offline
    }

    func satisfies(_ requirement: ModelRequirement) -> Bool {
        switch requirement {
        case .none:        true
        case .anyModel:    tutor != nil || appleIntelligence
        case .germanTutor: tutor != nil
        case .imageModel:  hasImageModel
        }
    }

    /// Whether offering a tutor download here makes sense: the learner hasn't got one, and this
    /// phone could actually run the one we'd pitch. Both halves matter — without the second, a
    /// device too small for every tutor gets nagged forever about a download that would fail.
    var canOfferTutor: Bool { tutor == nil && fittingTutor != nil }

    /// The tutor an upgrade prompt should name. Never the raw hero: a 6 GB phone is pitched the E2B
    /// tutor, a 4 GB phone a Granite one.
    var offerableTutor: MLXModel? { tutor == nil ? fittingTutor : nil }
}
