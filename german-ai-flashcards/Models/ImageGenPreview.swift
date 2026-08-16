import Foundation

/// Whether the generating screen shows the real picture as it's drawn, instead of the placeholder
/// animation standing in for it.
///
/// The pictures already exist mid-run: the diffusion pipeline reports its latents at every step,
/// and running the VAE decoder over them turns one into a viewable image. What it costs is a real
/// decode per preview, on top of a loaded UNet — which is why this is gated on
/// ``DeviceCapability/canPreviewImageGeneration`` rather than switched on everywhere.
/// MainActor-isolated (the project default), like ``DeviceCapability`` which it reads: the
/// diffusion loop can't consult it from its own thread, so `StoryImageService` resolves it once
/// per picture before handing work off.
enum ImageGenPreview {
    /// Backs the Settings toggle's `@AppStorage`, which declares the same `true` default.
    static let defaultsKey = "imageGenLivePreview"

    /// Whether this device has the memory headroom for previews at all.
    static var isAvailable: Bool { DeviceCapability.canPreviewImageGeneration }

    /// The learner's preference. On by default, so a device that can do this does it without
    /// anyone having to find the switch.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// What generation code asks. Both halves must agree, and a run still skips individual
    /// previews when memory is tight at that moment (see `StoryImageService`).
    static var isActive: Bool { isAvailable && isEnabled }
}
