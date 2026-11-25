import Foundation
import MLX

/// One image, as the app asks for it.
public struct FamilyRequest {
    public var prompt: String
    public var seed: Int
    public var width: Int
    public var height: Int
    public var steps: Int
    public var guidance: Double
    /// Composite an RGBA result onto white (families that produce alpha).
    public var flattenAlpha: Bool
    /// Video families: how many frames and at what rate; `imagePath` the picture a clip starts
    /// from, or an image is edited from (FLUX.2 Klein, Qwen-Image Edit).
    public var frames: Int?
    public var fps: Double?
    /// LTX-2.5: the model picks the length the prompt describes, `frames` being the longest.
    public var autoDuration = false
    public var imagePath: String?
    /// Upscalers: the factor the picture's shorter side is scaled by, the softening before (0–1).
    public var upscale: Double?
    public var softness: Double?
    /// Keep the transformer's residual stream in the weights' 16-bit precision where the reference
    /// runs it in float32 (Z-Image, Qwen-Image and its editor; the other families are in 16 bits
    /// already): faster, at the price of small differences in the pixels.
    public var halfPrecision = false

    public init(
        prompt: String, seed: Int, width: Int, height: Int, steps: Int, guidance: Double, flattenAlpha: Bool,
        frames: Int? = nil, fps: Double? = nil, imagePath: String? = nil, upscale: Double? = nil, softness: Double? = nil,
        halfPrecision: Bool = false
    ) {
        self.prompt = prompt
        self.seed = seed
        self.width = width
        self.height = height
        self.steps = steps
        self.guidance = guidance
        self.flattenAlpha = flattenAlpha
        self.frames = frames
        self.fps = fps
        self.imagePath = imagePath
        self.upscale = upscale
        self.softness = softness
        self.halfPrecision = halfPrecision
    }
}

/// A model family the native engine runs: the Swift twin of the `FAMILIES` adapters in
/// `turbo_worker.py`. The engine encodes every prompt of a job first (while the text encoder is
/// resident), tells the model the prompts are done, then generates.
public protocol FamilyModel: AnyObject {
    /// The bits the checkpoint was saved with (nil: unquantized).
    var bits: Int? { get }
    /// "Save memory": decode in tiles where the decoder allows it, and for the families whose
    /// text encoder is large (Ming-Image, Qwen-Image), keep it and the transformer out of memory
    /// at the same time. Set before `encode` and `generate`.
    var lowRam: Bool { get set }
    /// Release the text encoder in `promptsEncoded` (KarteiDiffusion change, see VENDORED.md).
    var releasesPromptReader: Bool { get set }
    /// The prompt's encodings are in the cache.
    func isCached(_ prompt: String) -> Bool
    /// Encodes a prompt into the cache, loading the text encoder if it had been released.
    func encode(_ prompt: String) throws
    /// Every prompt of the job is encoded: a family that releases its text encoder in low-RAM
    /// mode does so now.
    func promptsEncoded()
    /// The pipeline after the prompt is encoded. `progress` gets each finished step and
    /// `isCancelled` is consulted between steps (and tiles).
    func generate(
        _ request: FamilyRequest,
        phase: (GenerationPhase) -> Void,
        progress: (Int, Int) -> Void,
        isCancelled: () -> Bool
    ) throws -> GeneratedImage
}

/// A family that can show the image as it forms: at some steps (`LatentPreview.shows`) `preview`
/// gets the clean image the model predicts, decoded small. Adopting it gives the plain
/// `FamilyModel.generate` for free.
public protocol PreviewingFamilyModel: FamilyModel {
    func generate(
        _ request: FamilyRequest,
        phase: (GenerationPhase) -> Void,
        progress: (Int, Int) -> Void,
        preview: (Preview) -> Void,
        isCancelled: () -> Bool
    ) throws -> GeneratedImage
}

extension PreviewingFamilyModel {
    public func generate(
        _ request: FamilyRequest,
        phase: (GenerationPhase) -> Void,
        progress: (Int, Int) -> Void,
        isCancelled: () -> Bool
    ) throws -> GeneratedImage {
        try generate(request, phase: phase, progress: progress, preview: { _ in }, isCancelled: isCancelled)
    }
}

/// Loads one of the two families Die Kartei draws with. (Upstream's loader takes the app's JSON ModelSpec
/// and knows nine families; this copy keeps only Z-Image Turbo and FLUX.2 klein 4B.)
public enum FamilyLoader {
    public enum Family: String, CaseIterable, Sendable {
        case zImageTurbo = "z-image-turbo"
        case flux2Klein4B = "flux2-klein"
    }

    public static func load(_ family: Family, modelPath: URL, loadTokenizer: Bool = true) throws -> FamilyModel {
        switch family {
        case .zImageTurbo:
            return try ZImageModel(modelPath: modelPath, config: .turbo, loadTokenizer: loadTokenizer)
        case .flux2Klein4B:
            return try KleinModel(modelPath: modelPath, config: KleinConfig.forModel(name: "flux2-klein-4b", variant: nil), loadTokenizer: loadTokenizer)
        }
    }
}
