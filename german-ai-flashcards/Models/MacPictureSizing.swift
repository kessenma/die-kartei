import Foundation
import Metal

/// How big the Mac's MLX picture models draw, and whether this Mac has the memory for it.
/// docs/MAC_PICTURES.md has the measurements behind the numbers.
///
/// Pure and platform-neutral on purpose: the unit tests run on the iOS simulator, and the sizing
/// rules are the part worth testing. Only `isOffered` without an explicit budget reads the device.
nonisolated enum MacPictureSizing {

    /// What a picture is for. Cards are decoded at ≤ 512 px on screen and every card file syncs,
    /// so they stay smaller than story pictures.
    enum Purpose: Equatable {
        case card
        case story
        /// The style sheet's preview: always the smallest size, so it comes back quickly.
        case sample
    }

    static let sizes = [512, 768, 1024]

    /// The size a quality tier asks for, before the memory check.
    static func preferredSize(purpose: Purpose, tier: ImageGenQuality) -> Int {
        switch (purpose, tier) {
        case (.sample, _), (.card, .fast), (.card, .balanced), (.story, .fast): 512
        case (.card, .best), (.story, .balanced): 768
        case (.story, .best): 1024
        }
    }

    /// Steps are fixed per model: both are distilled to a set number and get worse off it.
    static func steps(_ model: ImageGenModel) -> Int {
        model == .flux2Klein ? 4 : 9
    }

    /// MLX's peak for one picture, in MB, with the prompt reader released after encoding and
    /// Z-Image's decoder in tiles: the least memory a picture can take. Measured on an M1 Max
    /// with the vendored engine (docs/MAC_PICTURES.md), rounded up.
    static func peakMB(_ model: ImageGenModel, size: Int) -> Int {
        switch (model, size) {
        case (.zImageTurbo, _): 5_800
        case (.flux2Klein, ...512): 4_900
        case (.flux2Klein, ...768): 7_400
        case (.flux2Klein, _): 11_400
        default: 0
        }
    }

    /// The same with the prompt reader kept in memory between pictures, which saves reading it
    /// back from disk for every card. Worth it only where the budget has room.
    static func residentPeakMB(_ model: ImageGenModel, size: Int) -> Int {
        switch (model, size) {
        case (.zImageTurbo, _): 7_900
        case (.flux2Klein, ...512): 6_500
        case (.flux2Klein, ...768): 9_000
        case (.flux2Klein, _): 12_900
        default: 0
        }
    }

    /// Seconds a picture takes on an M1 Max, for captions until this Mac has drawn one itself
    /// (`MacPictureTiming` remembers real ones).
    static func referenceSeconds(_ model: ImageGenModel, size: Int) -> Int {
        switch (model, size) {
        case (.zImageTurbo, ...512): 33
        case (.zImageTurbo, ...768): 64
        case (.zImageTurbo, _): 122
        case (.flux2Klein, ...512): 13
        case (.flux2Klein, ...768): 24
        case (.flux2Klein, _): 44
        default: 0
        }
    }

    /// The memory a drawing run may use, in MB: what Metal recommends for the GPU (about two
    /// thirds of RAM on smaller Macs), capped at three quarters of RAM, less 2 GB for the app and
    /// macOS. A separate number from `MemoryBudget`, whose RAM/2 Mac fallback gates the tutors.
    static func budgetMB(physicalMB: Int, recommendedGPUMB: Int?) -> Int {
        let gpu = recommendedGPUMB ?? physicalMB * 2 / 3
        return min(gpu, physicalMB * 3 / 4) - 2_048
    }

    /// This Mac's drawing budget.
    static var deviceBudgetMB: Int {
        let physical = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        let recommended = MTLCreateSystemDefaultDevice().map { Int($0.recommendedMaxWorkingSetSize / 1_048_576) }
        return budgetMB(physicalMB: physical, recommendedGPUMB: recommended)
    }

    /// The biggest size up to the tier's that fits the budget, or nil when not even 512 does.
    static func size(_ model: ImageGenModel, purpose: Purpose, tier: ImageGenQuality, budgetMB: Int) -> Int? {
        let preferred = preferredSize(purpose: purpose, tier: tier)
        return sizes.filter { $0 <= preferred && peakMB(model, size: $0) <= budgetMB }.last
    }

    /// Whether this Mac can draw with the model at all (512 px fits).
    static func isOffered(_ model: ImageGenModel, budgetMB: Int) -> Bool {
        model.engine == .mlx && peakMB(model, size: 512) <= budgetMB
    }

    static func isOffered(_ model: ImageGenModel) -> Bool {
        isOffered(model, budgetMB: deviceBudgetMB)
    }

    /// What the picture is for, from where it's saved: story pictures live under StoryImages/,
    /// and the style sheet's sample is the only caller that passes its own step count.
    static func purpose(destination: URL, stepCountOverride: Int?) -> Purpose {
        if stepCountOverride != nil { return .sample }
        return destination.pathComponents.contains("StoryImages") ? .story : .card
    }
}

/// Seconds per picture this Mac actually took, per model and size, so captions and the inbox's
/// estimate stop quoting an M1 Max once there's a real number. Per-device, never synced.
nonisolated enum MacPictureTiming {
    private static func key(_ model: ImageGenModel, _ size: Int) -> String {
        "macPictures.seconds.\(model.rawValue).\(size)"
    }

    static func record(_ seconds: Double, model: ImageGenModel, size: Int) {
        let old = UserDefaults.standard.double(forKey: key(model, size))
        // A running average, so one slow picture (another app busy) doesn't set the estimate.
        UserDefaults.standard.set(old > 0 ? old * 0.7 + seconds * 0.3 : seconds, forKey: key(model, size))
    }

    static func seconds(_ model: ImageGenModel, size: Int) -> Int {
        let measured = UserDefaults.standard.double(forKey: key(model, size))
        return measured > 0 ? Int(measured.rounded()) : MacPictureSizing.referenceSeconds(model, size: size)
    }
}
