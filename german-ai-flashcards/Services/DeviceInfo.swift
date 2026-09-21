import UIKit

/// The handful of device and build facts every diagnostic surface wants: the feedback form's
/// pre-filled bug report, the memory log's header, and the app-update check in
/// `MemoryDiagnostics`. One place, so the three never drift in format.
nonisolated enum DeviceInfo {
    /// "1.6" — the marketing version.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// "42" — the build number.
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// "1.6 (42)".
    static var appVersion: String { "\(version) (\(build))" }

    /// The hardware identifier (e.g. "iPhone15,2" or "iPad14,3"), more useful for debugging than
    /// UIDevice's generic "iPhone". Falls back to UIDevice if unavailable.
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 {
                result.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return machine.isEmpty ? "unknown" : machine
    }

    /// "iOS 26.1" / "iPadOS 26.1".
    @MainActor
    static var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    /// The OS version string without touching UIKit, for code that runs off the main actor.
    static var osVersionNumber: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
