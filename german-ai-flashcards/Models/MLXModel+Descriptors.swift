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
        case .mistral7B:    4000
        case .qwen3_8B:     4900
        case .qwen3_4B:     2200
        case .phi4Mini:     2300
        case .llama3_2_1B:   800
        case .gemma3_1B:     800
        case .qwen3_0_6B:    500
        case .granite2B_german: 1430
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
            "Gemma 4 E4B fine-tuned for this app on the parts of German learners actually get wrong: verbs with prepositions, separable and reflexive verbs, da-/wo-compounds, and haben/sein. The strongest model measured here, scoring 90% on this app's German grammar test against 80% for the same model untuned. It also catches the most real mistakes of anything in this list, missing only 9%, while rarely inventing a correction. About 5 GB."
        case .gemma4_E2B_german:
            "The same German fine-tune as the E4B tutor, trained on the smaller Gemma 4 E2B. Scores 83% on this app's German grammar test, just behind the E4B tutor, and it almost never 'corrects' a sentence that was already right. It does let more real mistakes through than the E4B tutor. About 3.3 GB instead of 5 GB, so it fits devices the E4B tutor doesn't."
        case .granite2B_german:
            "IBM's Granite 3.3 2B, fine-tuned on the same German material as the Gemma tutors above. Built for devices that can't fit either of them: it scores 62% on this app's German grammar test against 33% for the Gemma 3 1B it replaces, and it never once 'corrected' a sentence that was already right. It still misses more than half of real mistakes, so treat what it does catch as reliable and don't assume silence means your sentence was fine. It also writes German roughly half as fast as its size suggests, because its vocabulary splits German words into more pieces. About 1.4 GB."
        case .mistral7B:
            "Mistral AI's 7B Instruct v0.3, 4-bit quantized. Well regarded generally, but it scored 48% on this app's German grammar test and was the weakest of the mid-size models on da-/wo-compounds, getting 1 of 15. It's also the most eager to 'fix' sentences that were already correct, flagging 59% of them, and the slowest model in the app. Not recommended for German."
        case .qwen3_8B:
            "Alibaba's Qwen3 8B, 4-bit quantized, and the strongest Qwen tested here. It follows instructions well, but scored 58% on this app's German grammar test and missed roughly half of the real mistakes it was shown, so it's unreliable for corrections."
        case .qwen3_4B:
            "Alibaba's Qwen3 4B, 4-bit quantized. Fits on devices the larger models don't, but it scored 52% on this app's German grammar test and missed 61% of the real mistakes it was shown. Reasonable for drafting vocabulary, unreliable for judging your German."
        case .phi4Mini:
            "Microsoft's Phi-4 Mini 3.8B Instruct, 4-bit quantized. Strong on English benchmarks, but its German lands near Mistral's at 47% on this app's grammar test, and it missed 77% of the real mistakes it was shown. Weak on da-/wo-compounds and N-declension."
        case .llama3_2_1B:
            "Meta's LLaMA 3.2 1B Instruct, 4-bit quantized. Small and fast, and the weakest model measured here at 28% on this app's German grammar test. Shown 69 incorrect sentences, it accepted every one of them, so it will not catch your mistakes at all. Vocabulary only."
        case .gemma3_1B:
            "Google's Gemma 3 1B Instruct with QAT 4-bit quantization. Small and fast, and it writes usable vocabulary cards, but it can't correct German: it scores 33% on this app's grammar test and missed every single one of the 69 real mistakes it was shown. It answers in a shape this app can't display, so where you'd expect a correction you get nothing. Vocabulary only. If your device can run it, the Granite tutor is the better choice at this size."
        case .qwen3_0_6B:
            "A compact 0.6B model from Alibaba's Qwen3 family, 4-bit quantized. The fastest and smallest option here, and the least capable. Not measured on this app's grammar test; expect it to fall well short of the rest. Best for quick vocabulary drafts."
        }
    }

    var parameterCount: String {
        switch self {
        case .appleIntelligence: "On-device"
        case .gemma4_E4B_german: "~4B"
        case .gemma4_E2B_german: "~2B"
        case .mistral7B:    "7B"
        case .qwen3_8B:     "8B"
        case .qwen3_4B:     "4B"
        case .phi4Mini:     "3.8B"
        case .llama3_2_1B:  "1B"
        case .gemma3_1B:    "1B"
        case .qwen3_0_6B:   "0.6B"
        case .granite2B_german: "2B"
        }
    }

    /// Numeric parameter count for sorting the Parameters tab.
    var parameterCountValue: Double {
        switch self {
        case .appleIntelligence: 0   // Apple doesn't publish a size; sort to an end
        case .mistral7B:     7.0
        case .qwen3_8B:      8.0
        case .gemma4_E4B_german: 4.0
        case .gemma4_E2B_german: 2.0
        case .qwen3_4B:      4.0
        case .phi4Mini:      3.8
        case .llama3_2_1B:   1.0
        case .gemma3_1B:     1.0
        case .qwen3_0_6B:    0.6
        case .granite2B_german: 2.0
        }
    }

    /// Relative German quality score used by the Recommended sort (1 = lowest, 5 = highest).
    ///
    /// Anchored to measured core-suite accuracy in `training/MODEL_SCOREBOARD.md` rather than to
    /// parameter count or general reputation, both of which mispredict German badly here: a tuned
    /// 2B Granite (62%) beats Qwen3 8B (58%) and Mistral 7B (48%), each many times its size.
    ///
    /// **All percentages below are guarded** — scored as the app behaves. This matters most for the
    /// small end: Gemma 3 1B used to sit at 3 here on a recorded 58%, which turned out to be a
    /// scoring artifact (it answers `OK` followed by a `FIX:`, which the app discards entirely).
    /// Its real score is 33% with a 100% miss rate, so it now sits at 1. Rebuild these from
    /// `scripts/rescore_app_models.py`.
    ///
    /// Miss rate is a tie-breaker, not just core accuracy: a model that never contradicts the
    /// learner is worse than its percentage suggests, because silence reads as approval.
    var germanQualityScore: Int {
        switch self {
        case .gemma4_E4B_german: 5   // 90%, misses only 9% of real errors — the best measured
        case .gemma4_E2B_german: 5   // 83%, with a 3% false-correction rate
        case .granite2B_german: 4    // 62% and 0% false corrections, in 1.4 GB
        case .appleIntelligence: 3   // 60%, but flags 16% of correct sentences and misses 35%
        case .qwen3_8B:     3        // 58%, and misses ~48% of real errors despite the size
        case .qwen3_4B:     2        // 52%, misses 61%
        case .mistral7B:    2        // 48%, worst on da-/wo-compounds (1/15), "fixes" 59% of correct sentences
        case .phi4Mini:     2        // 47%, misses 77% of real errors
        case .gemma3_1B:    1        // 33%, and misses 100% — it shows the learner nothing
        case .llama3_2_1B:  1        // 28%, answered OK to all 69 errors in the suite
        case .qwen3_0_6B:   1        // untested in-app; expected well below the usable floor
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
        case .qwen3_0_6B, .llama3_2_1B, .gemma3_1B, .granite2B_german: 4
        case .qwen3_4B, .phi4Mini, .gemma4_E2B_german: 6
        case .mistral7B, .gemma4_E4B_german, .qwen3_8B: 8
        }
    }

    /// Short device compatibility hint shown in the model picker.
    var deviceNote: String {
        switch self {
        case .appleIntelligence:
            "Requires Apple Intelligence (iPhone 15 Pro or newer)"
        case .qwen3_0_6B, .llama3_2_1B, .gemma3_1B:
            "iPhone 12 or newer"
        case .granite2B_german:
            "iPhone 12 or newer (4 GB RAM) \u{2014} the tutor for smaller devices"
        case .qwen3_4B, .phi4Mini:
            "iPhone 13 Pro / iPhone 14 or newer (6 GB RAM)"
        case .gemma4_E2B_german:
            "iPhone 13 Pro / iPhone 14 or newer (6 GB RAM) — the lightest German tutor"
        case .mistral7B, .gemma4_E4B_german, .qwen3_8B:
            "iPhone 15 Pro or newer (8 GB RAM)"
        }
    }

    var promoPageURL: URL {
        switch self {
        case .appleIntelligence:
            URL(string: "https://www.apple.com/apple-intelligence/")!
        case .qwen3_0_6B, .qwen3_4B, .qwen3_8B:
            URL(string: "https://qwen.ai/blog?id=qwen3")!
        case .llama3_2_1B:
            URL(string: "https://www.llama.com/models/llama-3/")!
        case .gemma3_1B:
            URL(string: "https://deepmind.google/models/gemma/")!
        case .gemma4_E4B_german:
            URL(string: "https://huggingface.co/kessenma/gemma4-e4b-german-tutor-4bit")!
        case .gemma4_E2B_german:
            URL(string: "https://huggingface.co/kessenma/gemma4-e2b-german-tutor-4bit")!
        case .mistral7B:
            URL(string: "https://mistral.ai/models/")!
        case .phi4Mini:
            URL(string: "https://azure.microsoft.com/en-us/products/phi")!
        case .granite2B_german:
            URL(string: "https://huggingface.co/kessenma/granite33-2b-german-tutor-4bit")!
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

    /// Longer marketing points for the intro wizard. Hero only.
    var heroSellingPoints: [String] {
        [
            "Not a general-purpose model.",
            "Built on Google's Gemma family, which draws on years of Google Translate research.",
            "Sharper on the hard parts of German: verbs with prepositions, separable and reflexive "
            + "verbs, da-/wo-compounds, and haben/sein, with fewer false corrections.",
            "~5 GB download.",
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
    static let germanTutors: [MLXModel] = [.gemma4_E4B_german, .gemma4_E2B_german, .granite2B_german]

    /// Whether this is one of the in-house German tutors.
    var isGermanTutor: Bool { Self.germanTutors.contains(self) }

    /// The best tutor a device with `ramGB` can actually run, or nil when neither fits. Decides
    /// which tutor leads the Settings section: the E4B tutor where there's room for it, the E2B
    /// tutor on a 6 GB device, and no promoted section at all below that.
    static func leadTutor(ramGB: Int) -> MLXModel? {
        germanTutors.first { $0.minimumRAMGB <= ramGB }
    }

    /// One line on why this tutor is worth picking, for the Settings tutor cards. The E4B line is
    /// the hero tagline the pickers and the intro wizard already share.
    var tutorTagline: String {
        switch self {
        case .gemma4_E2B_german:
            "The same German training as the E4B tutor, sized to fit a 6 GB iPhone."
        case .granite2B_german:
            "German training on a smaller base, for devices the Gemma tutors don't fit."
        default:
            heroTagline
        }
    }

    /// Canonical "recommended" ordering for a device with `ramGB` RAM. One source of truth for every
    /// picker: the hero model leads when it fits, then Apple Intelligence (instant, no download), then
    /// the remaining runnable models by German quality, with anything the device can't run sinking to
    /// the bottom.
    static func recommendedOrder(ramGB: Int) -> [MLXModel] {
        allCases.sorted { recommendationRank($0, ramGB: ramGB) < recommendationRank($1, ramGB: ramGB) }
    }

    /// The single model to badge as "Recommended" for this device — the hero when it fits, otherwise
    /// the best option the device can actually run.
    static func recommended(ramGB: Int) -> MLXModel {
        recommendedOrder(ramGB: ramGB).first ?? hero
    }

    /// Sort key for `recommendedOrder`. Lower sorts first:
    /// (priority bucket, inverted German quality, inverted parameter count).
    private static func recommendationRank(_ model: MLXModel, ramGB: Int) -> (Int, Int, Double) {
        let runnable = model.isAppleIntelligence
            ? AppleIntelligenceService.currentlyAvailable()
            : model.minimumRAMGB <= ramGB
        let bucket: Int
        if model.isHero && runnable {
            bucket = 0                                   // hero pinned to the very top when it fits
        } else if model.isAppleIntelligence && runnable {
            bucket = 1                                   // instant, zero-download option next
        } else if runnable {
            bucket = 2                                   // other models the device can run
        } else {
            bucket = 3                                   // can't run here — sink to the bottom
        }
        return (bucket, -model.germanQualityScore, -model.parameterCountValue)
    }
}
