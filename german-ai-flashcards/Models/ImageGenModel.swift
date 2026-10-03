import Foundation
import CoreML
import Synchronization

/// The on-device image-generation model. Deliberately separate from `MLXModel`: that enum drives
/// every LLM picker and list in the app, while this one exists only for the Stories / flashcard
/// illustration path. Downloaded on demand into the same HuggingFace hub cache as the language
/// models, with the same refs/main "complete" semantics.
///
/// Two engines draw: Core ML Stable Diffusion everywhere, and on the Mac two big MLX models
/// (`engine == .mlx`, docs/MAC_PICTURES.md). `allCases` lists only what this device can run, so
/// every picker, storage row and orphan sweep that iterates it never shows an iPhone a Mac model.
nonisolated enum ImageGenModel: String, CaseIterable, Identifiable {
    /// Apple's Core ML SD 2.1 base, 6-bit palettized. The original shipped model.
    case sd21Base = "Stable Diffusion 2.1"
    /// Nota AI's block-removed, knowledge-distilled SD1.4 (BK-SDM-Tiny), converted to Core ML.
    /// Smaller + fewer steps than SD 2.1. Our own conversion, hosted on the app author's HF.
    case bkSdmTiny = "BK-SDM Tiny"
    // MAC-PICTURES: the two MLX models, Mac only.
    /// Tongyi's Z-Image Turbo (6B, 4-bit, 9 steps). The best pictures the app can draw.
    case zImageTurbo = "Z-Image Turbo"
    /// Black Forest Labs' FLUX.2 klein 4B (4-bit, 4 steps). About three times faster.
    case flux2Klein = "FLUX.2 klein"

    enum Engine { case coreML, mlx }

    var engine: Engine {
        switch self {
        case .sd21Base, .bkSdmTiny: .coreML
        case .zImageTurbo, .flux2Klein: .mlx
        }
    }

    /// The models this device can draw with. The MLX models only exist in the Mac build, and
    /// only on a Mac with the memory to draw at 512 px (`MacPictureSizing.isOffered`).
    static var allCases: [ImageGenModel] {
        [.sd21Base, .bkSdmTiny] + macModels
    }

    /// The MLX models this Mac can run, best first.
    static var macModels: [ImageGenModel] {
        #if os(macOS)
        [.zImageTurbo, .flux2Klein].filter(MacPictureSizing.isOffered)
        #else
        []
        #endif
    }

    /// UserDefaults key backing `current` — shared with the Settings picker's `@AppStorage`.
    static let selectionDefaultsKey = "imageGenModel.selected"

    /// The active model: what Stories and flashcards draw with. User-selectable in
    /// Settings ▸ Model ▸ Image generation; persisted in UserDefaults. A stored model this device
    /// can't run (a Mac model on an iPad restored from a Mac backup) reads as BK-SDM Tiny.
    static var current: ImageGenModel {
        get {
            if let override = runOverride.withLock({ $0 }) { return override }
            let stored = UserDefaults.standard.string(forKey: selectionDefaultsKey)
                .flatMap(ImageGenModel.init(rawValue:)) ?? .bkSdmTiny
            return allCases.contains(stored) ? stored : .bkSdmTiny
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectionDefaultsKey) }
    }

    /// A model to draw with for one run, whatever the setting says: the Mac's picture inbox draws
    /// an iPhone's order with a big model even when the learner's own pick is BK-SDM. Set and
    /// cleared around the run (`MacPictureInbox`); never persisted.
    static let runOverride = Mutex<ImageGenModel?>(nil)

    var id: String { rawValue }
    var displayName: String { rawValue }

    var repoID: String {
        switch self {
        case .sd21Base: "apple/coreml-stable-diffusion-2-1-base-palettized"
        case .bkSdmTiny: "kessenma/coreml-bk-sdm-tiny"
        case .zImageTurbo: "mflux-community/z-image-turbo-mflux-q4"
        case .flux2Klein: "mflux-community/flux2-klein-4b-mflux-q4"
        }
    }

    /// Which repo variant to download and load. Both Core ML repos ship the GPU-friendly
    /// `original/compiled` variant, paired with `ImageGenConstants.computeUnits = .cpuAndGPU` —
    /// the resource the continued-processing background task is granted. (The ANE
    /// `split_einsum_v2` variant would need `.cpuAndNeuralEngine`.) The MLX repos are mflux
    /// checkpoints whose components sit at the root.
    var subfolder: String {
        engine == .mlx ? "" : "original/compiled"
    }

    /// fnmatch patterns for `ResumableModelDownloader` — just the one compiled variant, or an
    /// mflux checkpoint's four components (skipping its README and sample pictures).
    var downloadPatterns: [String] {
        switch engine {
        case .coreML: [subfolder + "/*"]
        case .mlx: ["text_encoder/*", "transformer/*", "vae/*", "tokenizer/*"]
        }
    }

    /// Approx download size.
    var approximateSizeMB: Int {
        switch self {
        case .sd21Base: 1200
        case .bkSdmTiny: 950
        case .zImageTurbo: 5900
        case .flux2Klein: 4600
        }
    }

    /// Short "~1.2 GB" label for buttons and status rows.
    var downloadSizeLabel: String {
        String(format: "~%.1f GB", Double(approximateSizeMB) / 1000)
    }

    var isDownloaded: Bool { HubCacheLocation.isDownloaded(repoID: repoID) }

    var cachedSizeBytes: Int64? { HubCacheLocation.cachedSizeBytes(repoID: repoID) }

    /// What the engine loads from: for Core ML the folder holding TextEncoder.mlmodelc,
    /// Unet.mlmodelc, VAEDecoder.mlmodelc, vocab.json, merges.txt; for MLX the snapshot root
    /// holding text_encoder/, transformer/, vae/ and tokenizer/.
    var resourcesURL: URL? {
        guard let snapshot = HubCacheLocation.snapshotDirectory(repoID: repoID) else { return nil }
        return subfolder.isEmpty ? snapshot : snapshot.appending(path: subfolder)
    }

    func deleteFromCache() throws {
        try HubCacheLocation.delete(repoID: repoID)
    }
}
