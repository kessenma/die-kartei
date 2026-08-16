import Foundation

// MARK: - Lightweight Graphics

/// Whether the app draws its 3D canvases live, or falls back to flat stills of the same subjects.
///
/// The 3D scenes — die Figur, the preposition props — are cheap as geometry (a handful of
/// primitives) but not cheap as *machinery*: each one stands up a Metal render context, a
/// RealityKit scene, and a 60 Hz display link, and on the smallest supported phones that lands on
/// top of a multi-gigabyte language model that has already taken most of the app's budget. The
/// still costs a decoded bitmap and nothing else.
///
/// Deliberately shaped like ``MemorySaver``: automatic by default, forceable either way in
/// Settings. Forcing it *on* is also the only way to see this path on a device that would never
/// choose it, which is what makes the fallback testable.
enum LightweightGraphics {
    enum Mode: String, CaseIterable, Identifiable {
        case automatic, on, off
        var id: String { rawValue }

        var label: String {
            switch self {
            case .automatic: "Automatic"
            case .on:        "Stills Only"
            case .off:       "Always 3D"
            }
        }
    }

    private static let modeKey = "lightweightGraphicsMode"

    static var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// The resolved answer a view should ask. Reads `mode`, falling back to the hardware tier.
    static var isActive: Bool {
        switch mode {
        case .on:        true
        case .off:       false
        case .automatic: !DeviceCapability.canRenderLiveScenes
        }
    }

    /// One line for the Settings footer, so "Automatic" says what it decided on *this* phone
    /// rather than leaving the user to guess.
    static var automaticExplanation: String {
        DeviceCapability.canRenderLiveScenes
            ? "This device has \(DeviceCapability.ramGB) GB of memory, so Automatic draws the scenes live."
            : "This device has \(DeviceCapability.ramGB) GB of memory, so Automatic uses stills."
    }
}
