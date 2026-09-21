import Foundation

// MARK: - MLXModel descriptors

/// Human-facing metadata for each model — size, description, parameter count, quality, RAM needs,
/// device hints, and links. Split out of `ModelConfiguration.swift` so the copy lives in one place
/// and can be reused anywhere a model needs describing (the info sheet, pickers, recommendations).
extension MLXModel {
    var approximateSizeMB: Int {
        switch self {
        case .appleIntelligence: 0   // built-in, no download
        case .gemma4_E4B_german: 5000
        case .gemma4_E2B_german: 3300
        case .granite2B_german: 1430
        case .granite41_3B_german: 1915
        }
    }

    /// One-paragraph description shown in the model guide and info sheets.
    ///
    /// Quality claims here are anchored to the measured core-suite results in
    /// `training/MODEL_SCOREBOARD.md`, not to reputation or parameter count. Several of these models
    /// have strong general benchmarks and mediocre German, so saying so plainly is the point.
    ///
    /// **Every percentage here is a *guarded* score** — the suite scored the way this app actually
    /// behaves, where a reply the app renders as nothing counts as nothing. Until 2026-08-12 these
    /// strings mixed guarded numbers for the tutors with raw ones for the stock models, inside the
    /// same sentences, which made them non-comparable and in one case simply wrong: Gemma 3 1B was
    /// credited with 58% for replies (`OK` followed by a `FIX:`) that `ConversationPrompts`
    /// discards, so the learner saw nothing at all. Its real figure is 33%.
    /// Regenerate all of these with `scripts/rescore_app_models.py`.
    var description: String {
        switch self {
        case .appleIntelligence:
            "Apple's built-in on-device model (Apple Intelligence). No download, and it runs entirely on your device, privately and offline. Apple updates it with each major iOS release. It scores 60% on this app's German grammar test, but it's shaky on judgement: it flags about one in six already-correct sentences as wrong, and it misses a third of real mistakes. It's weakest exactly where German learners struggle most, getting 0 of 15 on da-/wo-compounds. Fine for quick vocabulary work, less so for correction practice. Requires a supported device with Apple Intelligence turned on."
        case .gemma4_E4B_german:
            "Gemma 4 E4B fine-tuned for this app on the parts of German learners actually get wrong, from verbs with prepositions and separable verbs to relative pronouns and Konjunktiv II. The strongest model measured here: 90% across this app's full 203-item German grammar test, with the best score ever recorded on the hardest section. It almost never 'corrects' a sentence that was already right (once in 32 correct sentences), and it talks like a conversation partner rather than a worksheet. It misses about one real mistake in six. About 5 GB."
        case .gemma4_E2B_german:
            "The same German fine-tune as the E4B tutor, trained on the smaller Gemma 4 E2B. Scores 83% on this app's German grammar test, just behind the E4B tutor, and it almost never 'corrects' a sentence that was already right. It does let more real mistakes through than the E4B tutor. About 3.3 GB instead of 5 GB, so it fits devices the E4B tutor doesn't."
        case .granite2B_german:
            "IBM's Granite 3.3 2B, fine-tuned on the same German material as the Gemma tutors. The smallest tutor in the app, and the one for phones the others don't fit: 75% across the full 203-item grammar test, and it never once 'corrected' a sentence that was already right. It still misses over 40% of real mistakes, so treat what it does catch as reliable and don't assume silence means your sentence was fine. It also writes German more slowly than its size suggests, because its vocabulary splits German words into many pieces. About 1.4 GB."
        case .granite41_3B_german:
            "IBM's newer Granite 4.1 3B on the same German training as the 2B Granite, and the stronger of the two: 81% across the full 203-item grammar test, and it misses far fewer real mistakes (about one in four, against the 2B's four in ten). The trade: it occasionally flags a sentence that was already right, where the 2B never does, and it's about 0.5 GB bigger. Its larger vocabulary handles German words in fewer pieces, so it also writes faster than the 2B despite its size. About 1.9 GB."
        }
    }

    var parameterCount: String {
        switch self {
        case .appleIntelligence: "On-device"
        case .gemma4_E4B_german: "~4B"
        case .gemma4_E2B_german: "~2B"
        case .granite2B_german: "2B"
        case .granite41_3B_german: "3B"
        }
    }

    /// Guarded accuracy on the app's 203-item German grammar suite, as a percentage.
    ///
    /// The number every piece of copy on the model screens quotes, so it lives in exactly one
    /// place. It replaced a 1–5 `germanQualityScore` abstraction: with a lineup that is one
    /// family at four sizes, the bucket added nothing the percentage doesn't say better, and the
    /// hand-typed percentages it sat alongside had already drifted apart (the guide sheet said
    /// the E2B tutor scored 84%, the model descriptions said 83%).
    ///
    /// **Guarded** means scored the way the app behaves, where a reply the app renders as nothing
    /// counts as nothing. Anchored to `training/MODEL_SCOREBOARD.md`; regenerate with
    /// `scripts/rescore_app_models.py`.
    var suiteScorePercent: Int {
        switch self {
        case .gemma4_E4B_german: 90   // 3% false corrections, misses 9% — the best measured
        case .gemma4_E2B_german: 83   // 3% false corrections, misses 19%
        case .granite41_3B_german: 81 // misses 25% — the best small-device tutor
        case .granite2B_german: 75    // 0% false corrections but misses 43%, in 1.4 GB
        case .appleIntelligence: 60   // flags 16% of correct sentences, misses 35%
        }
    }

    var quantization: String {
        switch self {
        case .appleIntelligence: "Built-in"
        default: "4-bit"
        }
    }

    /// Measured peak memory (MB) for one ordinary generation turn, where we have a real number.
    ///
    /// `approximateSizeMB` is a *download* size and overstates what a model actually occupies —
    /// E2B ships as 3.4 GB on disk but only 2.6 GB of it is resident weights — so estimating the
    /// runtime need from it is wrong by enough to matter: the old `size × 1.15` rule predicted
    /// 3.8 GB for E2B against a measured 2.7 GB, which is the difference between a 6 GB iPhone
    /// being offered this model and being told it won't fit.
    ///
    /// Measured with `mlx_lm` on Apple silicon (`mx.get_peak_memory()` after a correction-length
    /// generation), 2026-07-22. **These are Mac readings used as a proxy for iOS** — same MLX,
    /// same unified memory, but not the same runtime. Confirm against `MemoryBudget.footprintMB`
    /// on a real device before trusting them for a tier the app hasn't been run on.
    ///
    /// Deliberately `nil` for models nobody has measured: those keep the conservative estimate
    /// rather than inheriting a guess dressed up as a measurement.
    var measuredPeakMB: Int? {
        switch self {
        case .gemma4_E2B_german: 2710   // 2.60 GB weights, 3.42 GB under a very long context
        case .gemma4_E4B_german: 4330   // 4.20 GB weights, 4.99 GB under a very long context
        default: nil
        }
    }

    /// Minimum device RAM (in GB) needed to run this model.
    ///
    /// Sized against what iOS actually hands an app, not against physical RAM: the jetsam limit is
    /// roughly half of RAM even with the increased-memory-limit entitlement, so a 6 GB iPhone has
    /// about 3.4 GB to work with and cannot hold a 4 GB set of weights plus a KV cache. Anything
    /// whose weights are over ~3 GB therefore lands in the 8 GB tier.
    ///
    /// This drives the *interface*: which model gets recommended, and when the memory check sheet
    /// appears. It's deliberately a fixed tier rather than a live reading, so rows don't appear and
    /// vanish as the app allocates. Runtime safety is ``MemoryBudget``'s job, which measures the
    /// real budget on the device in hand.
    var minimumRAMGB: Int {
        switch self {
        case .appleIntelligence: 0   // gated by Apple Intelligence eligibility, not by RAM
        case .granite2B_german, .granite41_3B_german: 4
        case .gemma4_E2B_german: 6
        case .gemma4_E4B_german: 8
        }
    }

    /// Short device compatibility hint shown in the model picker.
    var deviceNote: String {
        switch self {
        case .appleIntelligence:
            "Requires Apple Intelligence (iPhone 15 Pro or newer)"
        case .granite2B_german:
            "iPhone 12 or newer (4 GB RAM) \u{2014} the smallest tutor"
        case .granite41_3B_german:
            "iPhone 12 or newer (4 GB RAM) \u{2014} the stronger small-device tutor"
        case .gemma4_E2B_german:
            "iPhone 13 Pro / iPhone 14 or newer (6 GB RAM) \u{2014} the lightest Gemma tutor"
        case .gemma4_E4B_german:
            "iPhone 15 Pro or newer (8 GB RAM)"
        }
    }

    /// Where "Learn more" goes: the *base model* this tutor was fine-tuned from.
    ///
    /// Deliberately not the tutor's own HuggingFace repo. Each tutor's `promoPageURL` used to be
    /// exactly its `huggingFaceRepoURL`, so the info sheet offered two links to the same page.
    /// Pointing at the base family is the genuinely different information, and it's the app's
    /// only remaining credit to the open-weight models these are built on.
    var promoPageURL: URL {
        switch self {
        case .appleIntelligence:
            URL(string: "https://www.apple.com/apple-intelligence/")!
        case .gemma4_E4B_german, .gemma4_E2B_german:
            URL(string: "https://deepmind.google/models/gemma/")!
        case .granite2B_german, .granite41_3B_german:
            URL(string: "https://www.ibm.com/granite")!
        }
    }
}

// MARK: - Hero model & recommendation ordering

extension MLXModel {
    /// The single model this app promotes above all others: our Gemma 4 E4B, fine-tuned in-house on
    /// German grammar specifically for this app. It's the only model trained on this app's coaching
    /// task, so wherever the device can run it the UI leads with it and treats the rest as
    /// alternatives. See training/PLAN.md. Changing the hero is a one-line edit here.
    static let hero: MLXModel = .gemma4_E4B_german

    /// Whether this is the promoted hero model.
    var isHero: Bool { self == Self.hero }

    /// One-line reason the hero wins — reused by the hero card, the pickers, and the intro wizard.
    /// Only meaningful for the hero model.
    var heroTagline: String {
        "Fine-tuned on German grammar just for this app,"
    }

    /// Longer pitch points for the intro wizard and the onboarding pitch page.
    ///
    /// Per-tutor rather than hero-only, because onboarding now pitches whichever tutor the
    /// device can actually run — a 6 GB phone was previously shown no model at all. The size
    /// line is derived so it can't drift from `approximateSizeMB`, which it had already: this
    /// list hard-coded "~5 GB download." while the E2B tutor is 3.3 GB.
    var heroSellingPoints: [String] {
        [
            "Trained specifically to correct German learners, not to do everything.",
            isGermanTutor && logoName == "logo-gemma"
                ? "Built on Google's Gemma family, which draws on years of Google Translate research."
                : "Built on IBM's open-weight Granite family, sized for phones the Gemma tutors don't fit.",
            "Sharper on the hard parts of German: verbs with prepositions, separable and reflexive "
            + "verbs, da-/wo-compounds, and haben/sein, with fewer false corrections.",
            "Scores \(suiteScorePercent)% on the app's own German grammar test.",
            "~\(approximateSizeLabel) download, then it runs offline.",
        ]
    }

    // MARK: - German tutor family

    /// The in-house German tutors, best first. The UI keeps them together rather than letting a size
    /// or parameter sort scatter them: the E2B tutor is ~2B and the Granite tutor 2B, so both would
    /// otherwise land below every 4B–8B stock model in the list, underneath models they outscore on
    /// this app's own grammar suite.
    ///
    /// Not all one family: the two Gemmas are the same fine-tune at two capacities, and the Granite
    /// is a different base entirely, trained on the same German material to reach the 4 GB devices
    /// neither Gemma fits. What they share is being tuned for this app's correction task, which is
    /// what this list is for.
    static let germanTutors: [MLXModel] = [.gemma4_E4B_german, .gemma4_E2B_german, .granite41_3B_german, .granite2B_german]

    /// Whether this is one of the in-house German tutors.
    var isGermanTutor: Bool { Self.germanTutors.contains(self) }

    /// **The one function that answers "which model for this phone."**
    ///
    /// The best tutor a device with `ramGB` can run: E4B where there's room, E2B on a 6 GB
    /// phone, the Granite 3B below that. Nil only on a device smaller than any tutor, which no
    /// iPhone meeting the deployment target is — the callers keep their fallbacks anyway, since
    /// "nil means no tutor fits" is cheaper to keep true than to re-derive.
    ///
    /// This replaced a four-bucket `recommendedOrder`/`recommendationRank` sort. With one family
    /// at four sizes there is nothing to rank: the tutors are already in quality order, so the
    /// question collapses to "which is the first one that fits".
    static func leadTutor(ramGB: Int) -> MLXModel? {
        germanTutors.first { $0.minimumRAMGB <= ramGB }
    }

    /// One line on why this tutor is worth picking, for the Settings tutor cards. The E4B line is
    /// the hero tagline the pickers and the intro wizard already share.
    var tutorTagline: String {
        switch self {
        case .gemma4_E2B_german:
            "The same German training as the E4B tutor, sized to fit a 6 GB iPhone."
        case .granite41_3B_german:
            "The stronger of the two small-device tutors, for phones the Gemma tutors don't fit."
        case .granite2B_german:
            "The smallest tutor. Never flags correct German, but lets more mistakes through."
        default:
            heroTagline
        }
    }

    /// "~4.2 GB"-style label for the one-time download, shared by every surface that offers one.
    ///
    /// Lived on the hero intro sheet until the onboarding explainer, the Home card and the
    /// conversation nudge all needed it too. It belongs next to the sizes it formats.
    var approximateSizeLabel: String {
        approximateSizeMB >= 1000
            ? String(format: "%.1f GB", Double(approximateSizeMB) / 1000.0)
            : "\(approximateSizeMB) MB"
    }

}
