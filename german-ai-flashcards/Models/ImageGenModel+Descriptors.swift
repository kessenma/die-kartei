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
            + "network, and nothing leaving the phone."
        case .bkSdmTiny:
            "Nota AI's BK-SDM-Tiny — a block-removed, knowledge-distilled Stable Diffusion "
            + "(SD 1.4-class), converted to Core ML for this app. Its U-Net is about a third the "
            + "size of Stable Diffusion's, so it downloads smaller and draws in fewer steps, still "
            + "fully on-device with nothing leaving the phone."
        }
    }

    var parameterCount: String {
        switch self {
        case .sd21Base: "~1.3 B (U-Net 865 M)"
        case .bkSdmTiny: "~0.5 B (U-Net 330 M)"
        }
    }

    var quantization: String {
        switch self {
        case .sd21Base: "6-bit palettized"
        case .bkSdmTiny: "16-bit (fp16)"
        }
    }

    /// Fixed by the compiled Core ML model — the reason the quality setting tunes steps, not size.
    var outputResolution: String {
        switch self {
        case .sd21Base, .bkSdmTiny: "512 × 512"
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
        }
    }

    /// No bundled brand asset, so the sheet draws an SF Symbol — the same path `MLXModel` takes
    /// for Apple Intelligence.
    var sfSymbolLogo: String {
        switch self {
        case .sd21Base: "photo.on.rectangle.angled"
        case .bkSdmTiny: "wand.and.stars"
        }
    }

    /// Brand-logo asset — the twin of `MLXModel.logoName`. Both image models ship a gradient tile
    /// logo, so `usesSFSymbolLogo` is always false; `sfSymbolLogo` is only a defensive fallback.
    var logoName: String {
        switch self {
        case .sd21Base: "logo-sd21"
        case .bkSdmTiny: "logo-bksdm"
        }
    }

    var usesSFSymbolLogo: Bool { false }

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
        }
    }
}
