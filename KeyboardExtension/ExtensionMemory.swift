import Foundation
import os

/// Memory readings for the extension process.
///
/// Deliberately a fresh ~30 lines rather than a reuse of the app's `MemoryBudget`: that type lives
/// inside the app target's synchronized folder and reaches into MLX, which must never be linked
/// here. The numbers below are the whole point of the probe — a keyboard extension is given a
/// small fraction of an app's allowance, and Foundation Models keeps its weights in a separate
/// system process but charges the session and the streamed response to *us*.
enum ExtensionMemory {

    /// Resident footprint of this process in MB — the number iOS jetsams against.
    static var footprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// How much more this process may allocate before it is killed, in MB.
    ///
    /// This is the headline number. In the app it sits in the thousands; if it comes back in the
    /// low tens here, a Foundation Models session inside a keyboard is not viable no matter how
    /// well the call itself behaves.
    static var availableMB: Double {
        Double(os_proc_available_memory()) / 1_048_576
    }

    /// One-line snapshot for the log.
    static var snapshot: String {
        String(format: "footprint %.1f MB · available %.1f MB", footprintMB, availableMB)
    }
}

/// Whether the probe grid is reachable at all.
///
/// Mirrors the app's `ScreenshotSeeding.isAvailable`: DEBUG builds always, TestFlight betas by
/// their sandbox receipt, and never in an App Store build. The probes print raw memory figures and
/// can type a diagnostic log into whatever the person is writing, which is developer furniture and
/// has no business in a keyboard someone installed to write German email with.
enum KeyboardDiagnostics {
    static var isAvailable: Bool {
        #if DEBUG
        return true
        #else
        // `Bundle.main` here is the .appex. The receipt belongs to the containing app, which sits
        // two levels up (Die Kartei.app/PlugIns/Die Kartei Keyboard.appex).
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sandbox = app.appendingPathComponent("_MASReceipt/sandboxReceipt")
        return FileManager.default.fileExists(atPath: sandbox.path)
        #endif
    }
}
