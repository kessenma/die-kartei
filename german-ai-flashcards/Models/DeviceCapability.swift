import Foundation

/// Central answer to "what can this device run" so the model pickers don't each re-derive RAM.
/// Card generation, conversation, and the settings model list all share these values.
enum DeviceCapability {
    /// Physical RAM rounded to the nearest GB.
    static var ramGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }

    /// Whether this device can comfortably run `model` — RAM for MLX models, Apple Intelligence
    /// eligibility for the built-in one.
    static func canRun(_ model: MLXModel) -> Bool {
        if model.isAppleIntelligence { return AppleIntelligenceService.currentlyAvailable() }
        return model.minimumRAMGB <= ramGB
    }

    /// Whether this device can run the promoted hero model. The gate for how hard the UI pushes it:
    /// on devices that can't run it we don't lead with a download the hardware can't handle.
    static var canRunHero: Bool { canRun(.hero) }
}
