import Foundation
import os

/// How much memory this app may actually use, which is not the same as how much RAM the phone has.
///
/// iOS terminates an app that crosses its jetsam limit, and that limit sits far below physical
/// memory — roughly half of it, even with `com.apple.developer.kernel.increased-memory-limit`
/// (which this app ships). A 6 GB iPhone gives an app somewhere around 3.4 GB. So "6 GB of RAM"
/// says very little about whether a 5 GB model will survive a generation run.
///
/// Model sizes are quoted in decimal MB (`approximateSizeMB`) while everything measured here is in
/// binary MB. Treating one as the other overstates a model's needs by about 5%, which is the
/// direction we want to be wrong in.
enum MemoryBudget {
    /// Bytes this process can still allocate before iOS kills it. Returns 0 if the OS won't say —
    /// including on macOS, where the API doesn't exist and ``fallbackTotalMB`` takes over.
    ///
    /// Nonisolated, like the live readings built on it: they ask the kernel about this process and
    /// touch no app state, so background work that has to know its own headroom — the diffusion
    /// loop deciding whether to decode a preview — can read them where it runs.
    nonisolated static var availableBytes: Int {
        #if os(macOS)
        return 0
        #else
        return Int(os_proc_available_memory())
        #endif
    }

    nonisolated static var availableMB: Int { availableBytes / 1_048_576 }

    /// Physical footprint of this process in MB — the number jetsam actually watches.
    static var footprintMB: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) / 1_048_576 : -1
    }

    /// Total memory this app gets on this device: what's left plus what it already holds. Near
    /// enough to constant for a given device, so it's safe to show in the UI — unlike
    /// ``availableMB``, which falls as the app allocates and would make rows flicker.
    static var totalMB: Int {
        let available = availableMB
        guard available > 0 else { return fallbackTotalMB }
        return available + max(0, footprintMB)
    }

    /// Used only when `os_proc_available_memory()` reports 0, which it can outside a normal app
    /// process. Half of physical RAM is the rough shape of the real limit on recent iPhones.
    private static var fallbackTotalMB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_048_576) / 2
    }

    /// Peak memory a model needs: its weights plus room for the KV cache, activations, and
    /// tokenizer. Prefers a real measurement (``MLXModel/measuredPeakMB``) and falls back to
    /// scaling the download size for models nobody has profiled. ``MemorySaver`` caps the KV
    /// cache, which is what keeps either number honest for long conversations — see
    /// ``hasSlimHeadroom(_:)`` for why that cap must not switch itself off here.
    static func requiredMB(for model: MLXModel) -> Int {
        guard !model.isAppleIntelligence else { return 0 }
        if let measured = model.measuredPeakMB { return measured }
        return Int(Double(model.approximateSizeMB) * 1.15)
    }

    /// Left for the rest of the app — UI, decks, images, the OS's own headroom.
    static let reserveMB = 250

    /// Whether `model` fits this device's budget with room to work in.
    static func fits(_ model: MLXModel) -> Bool {
        if model.isAppleIntelligence { return true }
        return requiredMB(for: model) + reserveMB <= totalMB
    }

    /// Whether `model` runs over this device's budget. Loading it is still allowed — the memory
    /// check sheet explains the trade and ``MemorySaver`` engages its governors — but nothing in
    /// the UI recommends or auto-loads a model in this state.
    static func isOverBudget(_ model: MLXModel) -> Bool { !fits(model) }

    /// How far over budget, in MB. 0 when the model fits.
    static func overageMB(for model: MLXModel) -> Int {
        max(0, requiredMB(for: model) + reserveMB - totalMB)
    }

    /// Fraction of the budget a model may occupy before it counts as a tight fit.
    private static let slimHeadroomFraction = 0.75

    /// Whether `model` fits, but without much room to spare.
    ///
    /// This exists because ``requiredMB(for:)`` describes an *ordinary* turn, while a long
    /// conversation grows the KV cache well past it — E2B measures 2.7 GB on a normal turn and
    /// 3.4 GB with a very long context. On a roomy device that spread is irrelevant; on a device
    /// where the model only just fits, it's the whole difference between working and being killed.
    ///
    /// Without this, making the budget more accurate would have made the app *less* safe: a
    /// model that newly "fits" would stop being over budget, ``MemorySaver`` would switch off its
    /// KV-cache cap, and the long-context peak it was capping would be free to happen on the very
    /// devices with the least room. Fit and governed are separate questions, so they get separate
    /// predicates.
    static func hasSlimHeadroom(_ model: MLXModel) -> Bool {
        guard !model.isAppleIntelligence, totalMB > 0 else { return false }
        return Double(requiredMB(for: model) + reserveMB) > Double(totalMB) * slimHeadroomFraction
    }

    // MARK: - Live pressure

    /// Below this much free memory, generation winds down rather than letting the next allocation
    /// trip jetsam.
    nonisolated static let criticalFloorMB = 220

    /// Approaching the floor: worth warning about, not yet worth stopping for.
    nonisolated static let elevatedFloorMB = 450

    /// Current headroom, bucketed. `.normal` when the OS won't report availability, since a
    /// missing reading is not evidence of pressure.
    nonisolated static var pressure: Pressure {
        let available = availableMB
        guard available > 0 else { return .normal }
        if available < criticalFloorMB { return .critical }
        if available < elevatedFloorMB { return .elevated }
        return .normal
    }

    enum Pressure: Int, Comparable {
        case normal = 0, elevated = 1, critical = 2
        static func < (lhs: Pressure, rhs: Pressure) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Formatting

    /// "3.4 GB" — the phrasing used everywhere memory is shown to the user.
    static func formattedGB(_ mb: Int) -> String {
        String(format: "%.1f GB", Double(mb) / 1024)
    }
}
