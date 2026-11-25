import SwiftUI

// MARK: - ImageGenModel descriptors

/// Human-facing metadata for the image model — the twin of `MLXModel+Descriptors`, feeding
/// `ImageModelInfoSheet`. Split out of `ImageGenModel.swift` so the SwiftUI import (for the brand
/// theme) stays out of the file that talks to CoreML.
extension ImageGenModel {
    var modelDescription: String {
        switch self {
        case .sd21Base:
            "Stability AI's Stable Diffusion 2.1, converted to Core ML by Apple and compressed to "
            + "6-bit palettized weights so it runs on an iPhone. It draws every picture in the app "
            + "— story illustrations and flashcard pictures — fully on-device, with no account, no "
            + "network, and nothing leaving your \(ThisDevice.name)."
        case .bkSdmTiny:
            "Nota AI's BK-SDM-Tiny — a block-removed, knowledge-distilled Stable Diffusion "
            + "(SD 1.4-class), converted to Core ML for this app. Its U-Net is about a third the "
            + "size of Stable Diffusion's, so it downloads smaller and draws in fewer steps, still "
            + "fully on-device with nothing leaving your \(ThisDevice.name)."
        case .zImageTurbo:
            "Tongyi Lab's Z-Image Turbo: a 6-billion-parameter picture model that reads your prompt "
            + "with a small language model, so it follows scenes, styles and details far more "
            + "closely than Stable Diffusion. It needs a Mac's memory and runs on its graphics chip, "
            + "with nothing leaving your \(ThisDevice.name)."
        case .flux2Klein:
            "Black Forest Labs' FLUX.2 klein 4B: a compact model from the makers of FLUX that draws "
            + "a picture in four steps, about three times faster than Z-Image Turbo, with a little "
            + "less detail. It runs on your Mac's graphics chip, with nothing leaving your "
            + "\(ThisDevice.name)."
        }
    }

    var parameterCount: String {
        switch self {
        case .sd21Base: "~1.3 B (U-Net 865 M)"
        case .bkSdmTiny: "~0.5 B (U-Net 330 M)"
        case .zImageTurbo: "6 B (+ Qwen3 4B prompt reader)"
        case .flux2Klein: "4 B (+ Qwen3 4B prompt reader)"
        }
    }

    var quantization: String {
        switch self {
        case .sd21Base: "6-bit palettized"
        case .bkSdmTiny: "16-bit (fp16)"
        case .zImageTurbo, .flux2Klein: "4-bit (MLX)"
        }
    }

    /// Fixed by the compiled Core ML model — the reason the quality setting tunes steps there.
    /// The MLX models draw at the size the quality setting picks instead.
    var outputResolution: String {
        switch self {
        case .sd21Base, .bkSdmTiny: "512 × 512"
        case .zImageTurbo, .flux2Klein: "512 to 1024 px"
        }
    }

    var huggingFaceRepoURL: URL? {
        URL(string: "https://huggingface.co/\(repoID)")
    }

    var promoPageURL: URL {
        switch self {
        case .sd21Base:
            URL(string: "https://machinelearning.apple.com/research/stable-diffusion-coreml")!
        case .bkSdmTiny:
            URL(string: "https://github.com/Nota-NetsPresso/BK-SDM")!
        case .zImageTurbo:
            URL(string: "https://huggingface.co/Tongyi-MAI/Z-Image-Turbo")!
        case .flux2Klein:
            URL(string: "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B")!
        }
    }

    /// No bundled brand asset, so the sheet draws an SF Symbol — the same path `MLXModel` takes
    /// for Apple Intelligence.
    var sfSymbolLogo: String {
        switch self {
        case .sd21Base: "photo.on.rectangle.angled"
        case .bkSdmTiny: "wand.and.stars"
        case .zImageTurbo: "paintbrush.pointed.fill"
        case .flux2Klein: "bolt.fill"
        }
    }

    /// Brand-logo asset — the twin of `MLXModel.logoName`. The Core ML models ship a gradient tile
    /// logo; the Mac models have none bundled and draw `sfSymbolLogo` instead.
    var logoName: String {
        switch self {
        case .sd21Base: "logo-sd21"
        case .bkSdmTiny: "logo-bksdm"
        case .zImageTurbo, .flux2Klein: ""
        }
    }

    var usesSFSymbolLogo: Bool { engine == .mlx }

    /// The model's logo as an `Image` — mirrors `MLXModel.logoImage`, so call sites keep their
    /// `.resizable()/.frame()/.clipShape()` modifiers.
    var logoImage: Image {
        usesSFSymbolLogo ? Image(systemName: sfSymbolLogo) : Image(logoName)
    }

    var theme: ModelTheme {
        switch self {
        case .sd21Base:
            // Stability's brand gradient: pink → violet.
            ModelTheme(
                palette: [
                    Color(hex: 0xFF9BD2), Color(hex: 0xF25A8E),
                    Color(hex: 0xB44BE0), Color(hex: 0x7A2CC4),
                ],
                accent: Color(hex: 0xD44BC8)
            )
        case .bkSdmTiny:
            // Distinct teal → green gradient so the two models read apart at a glance.
            ModelTheme(
                palette: [
                    Color(hex: 0x5EE7C6), Color(hex: 0x2FB8A8),
                    Color(hex: 0x2E9BD6), Color(hex: 0x2C6FC4),
                ],
                accent: Color(hex: 0x2FB8A8)
            )
        case .zImageTurbo:
            // Warm amber → coral: the "best pictures" model.
            ModelTheme(
                palette: [
                    Color(hex: 0xFFC46B), Color(hex: 0xFF9A4D),
                    Color(hex: 0xF2685A), Color(hex: 0xD9466A),
                ],
                accent: Color(hex: 0xF2685A)
            )
        case .flux2Klein:
            // Cool slate → electric blue: the fast one.
            ModelTheme(
                palette: [
                    Color(hex: 0x9FB4D9), Color(hex: 0x6B8BD6),
                    Color(hex: 0x3F66E0), Color(hex: 0x2A44B8),
                ],
                accent: Color(hex: 0x3F66E0)
            )
        }
    }
}
