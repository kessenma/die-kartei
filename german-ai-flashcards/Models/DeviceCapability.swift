import Foundation

/// Central answer to "what can this device run" so the model pickers don't each re-derive RAM.
/// Card generation, conversation, and the settings model list all share these values.
///
/// This is the *interface* half of the memory story: stable, tier-based, and safe to drive layout
/// from. ``MemoryBudget`` is the runtime half — it measures what iOS will actually give the app
/// right now and is what the load path and the token loops trust. The two are deliberately
/// separate: a live reading is the right thing to stop a generation with, and the wrong thing to
/// show or hide a row with, since it falls as the app allocates.
enum DeviceCapability {
    /// Physical RAM in GB, as marketed. `physicalMemory` reports RAM minus the kernel/SoC
    /// carveout — a 12 GB iPhone reads back around 11.2 GB — so rounding to nearest would
    /// understate every device whose carveout tops half a GB. The carveout only ever subtracts,
    /// so rounding *up* recovers the marketing number on every tier.
    static var ramGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded(.up))
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

    /// Whether `model` should be *offered* here — either the device fits it, or the user has read
    /// the memory check and chosen to run oversized models anyway.
    ///
    /// Deliberately looser than ``canRun(_:)``: that one decides what the app recommends, this one
    /// decides what it permits. Nothing here is recommended to a device that can't hold it, but
    /// nothing is locked away from someone willing to trade speed for it either. Feature gates that
    /// need a specific model (stories and their batch jobs) ask this one.
    static func mayRun(_ model: MLXModel) -> Bool { canRun(model) || MemorySaver.allowsOversizedModels }

    /// ``mayRun(_:)`` for the promoted hero model.
    static var mayRunHero: Bool { mayRun(.hero) }

    /// App-memory budget a device needs before the generating screen decodes real diffusion
    /// previews. Roughly a 6 GB iPhone and up — see ``canPreviewImageGeneration``.
    private static let livePreviewMinimumBudgetMB = 3000

    /// Whether this device has room to decode the picture *while it's being drawn*.
    ///
    /// A higher bar than running the image model at all. The normal decode happens after the
    /// UNet is unloaded; a preview decode happens inside the denoise loop, so the VAE decoder's
    /// weights and activations land on top of a resident UNet. Roomy devices absorb that spike;
    /// smaller ones keep the drawn animation, which costs nothing.
    ///
    /// Measured against ``MemoryBudget/totalMB`` rather than physical RAM because the jetsam
    /// limit is what a mid-loop spike actually runs into.
    static var canPreviewImageGeneration: Bool {
        MemoryBudget.totalMB >= livePreviewMinimumBudgetMB
    }

    /// Physical RAM a device needs before the app renders its 3D canvases live rather than as
    /// flat stills — see ``LightweightGraphics``.
    ///
    /// Set at the same 6 GB step the model tiers use, so "small device" means one thing across the
    /// app: the phones that get the Granite tutor instead of a Gemma one are the phones that get
    /// stills instead of RealityKit. Those are also the devices where a resident model leaves the
    /// least room for a second renderer.
    private static let liveSceneMinimumRAMGB = 6

    /// Whether this device should draw the 3D scenes live. The *hardware* half of the question —
    /// ``LightweightGraphics/isActive`` is what a view asks, since the user can override this.
    ///
    /// Measured against physical RAM, not ``MemoryBudget``, and that is the point of the split
    /// documented on this type: which renderer a screen uses is layout, and layout must not flip
    /// mid-session as the app allocates.
    static var canRenderLiveScenes: Bool { ramGB >= liveSceneMinimumRAMGB }
}
