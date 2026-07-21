import Foundation
import CoreML

/// The on-device image-generation model (CoreML Stable Diffusion). Deliberately separate from
/// `MLXModel`: that enum drives every LLM picker and list in the app, while this one exists only
/// for the Stories / flashcard illustration path. Downloaded on demand into the same HuggingFace
/// hub cache as the language models, with the same refs/main "complete" semantics.
nonisolated enum ImageGenModel: String, CaseIterable, Identifiable {
    /// Apple's Core ML SD 2.1 base, 6-bit palettized. The original shipped model.
    case sd21Base = "Stable Diffusion 2.1"
    /// Nota AI's block-removed, knowledge-distilled SD1.4 (BK-SDM-Tiny), converted to Core ML.
    /// Smaller + fewer steps than SD 2.1. Our own conversion, hosted on the app author's HF.
    case bkSdmTiny = "BK-SDM Tiny"

    /// UserDefaults key backing `current` — shared with the Settings picker's `@AppStorage`.
    static let selectionDefaultsKey = "imageGenModel.selected"

    /// The active model: what Stories and flashcards draw with. User-selectable in
    /// Settings ▸ Model ▸ Image generation; persisted in UserDefaults.
    static var current: ImageGenModel {
        get {
            UserDefaults.standard.string(forKey: selectionDefaultsKey)
                .flatMap(ImageGenModel.init(rawValue:)) ?? .bkSdmTiny
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectionDefaultsKey) }
    }

    var id: String { rawValue }
    var displayName: String { rawValue }

    var repoID: String {
        switch self {
        case .sd21Base: "apple/coreml-stable-diffusion-2-1-base-palettized"
        case .bkSdmTiny: "kessenma/coreml-bk-sdm-tiny"
        }
    }

    /// Which repo variant to download and load. Both ship the GPU-friendly `original/compiled`
    /// variant, paired with `ImageGenConstants.computeUnits = .cpuAndGPU` — the resource the
    /// continued-processing background task is granted. (The ANE `split_einsum_v2` variant would
    /// need `.cpuAndNeuralEngine`.)
    var subfolder: String { "original/compiled" }

    /// fnmatch patterns for `ResumableModelDownloader` — just the one compiled variant.
    var downloadPatterns: [String] { [subfolder + "/*"] }

    /// Approx download size of `original/compiled`.
    var approximateSizeMB: Int {
        switch self {
        case .sd21Base: 1200
        case .bkSdmTiny: 950
        }
    }

    /// Short "~1.2 GB" label for buttons and status rows.
    var downloadSizeLabel: String {
        String(format: "~%.1f GB", Double(approximateSizeMB) / 1000)
    }

    var isDownloaded: Bool { HubCacheLocation.isDownloaded(repoID: repoID) }

    var cachedSizeBytes: Int64? { HubCacheLocation.cachedSizeBytes(repoID: repoID) }

    /// The pipeline resources directory inside the downloaded snapshot — the folder holding
    /// TextEncoder.mlmodelc, Unet.mlmodelc, VAEDecoder.mlmodelc, vocab.json, merges.txt.
    var resourcesURL: URL? {
        HubCacheLocation.snapshotDirectory(repoID: repoID)?.appending(path: subfolder)
    }

    func deleteFromCache() throws {
        try HubCacheLocation.delete(repoID: repoID)
    }
}
