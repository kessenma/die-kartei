import Foundation

/// The words copy uses for the device the app is running on: "this iPhone", "your iPad",
/// "iPhone is low on memory", "Mac" in System Settings paths.
///
/// Nonisolated and UIKit-free, because some of that copy is written by services off the main actor
/// (the memory saver's notifications, a model's load error). iPad is told apart by its hardware
/// identifier rather than `UIDevice.userInterfaceIdiom`, which is main-actor only.
nonisolated enum ThisDevice {
    enum Kind: Sendable { case iPhone, iPad, mac }

    static let kind: Kind = {
        #if os(macOS)
        return .mac
        #else
        // The simulator reports the host's "arm64"; it names the simulated device separately.
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? DeviceInfo.deviceModel
        return model.hasPrefix("iPad") ? .iPad : .iPhone
        #endif
    }()

    /// "iPhone", "iPad" or "Mac".
    static var name: String {
        switch kind {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }

    /// "iOS", "iPadOS" or "macOS".
    static var system: String {
        switch kind {
        case .iPhone: "iOS"
        case .iPad: "iPadOS"
        case .mac: "macOS"
        }
    }

    /// The app people open to change system settings: "Settings", or "System Settings" on a Mac.
    static var settingsApp: String { kind == .mac ? "System Settings" : "Settings" }

    static var isMac: Bool { kind == .mac }
}
