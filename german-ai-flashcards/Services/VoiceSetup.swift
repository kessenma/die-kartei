import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The chosen voices this device doesn't have. A choice can come from another device through iCloud
/// Sync (`VoicesSyncDocument`) or outlive a voice deleted in Settings. No app can download a system
/// voice or open Settings ▸ Accessibility, so this only names what's missing: Settings ▸ Voice lists
/// it, and the first time speech has to stand in a basic voice, an alert offers the way there.
///
/// The choices themselves never change here. A stand-in voice is never written back, or a device
/// without the voice would replace every other device's choice with "System Default".
@Observable
final class VoiceSetup {
    static let shared = VoiceSetup()

    /// A chosen voice that isn't installed, and which pickers chose it.
    struct MissingVoice: Identifiable, Equatable {
        let id: String
        let name: String
        let uses: [String]
    }

    @ObservationIgnored weak var modelManager: MLXModelManager?
    /// Every voice identifier installed on this device, refreshed when the system's list changes.
    private(set) var installed: Set<String> = []
    /// The alert shows at most once per launch.
    @ObservationIgnored private var promptedThisLaunch = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// "Don't Ask Again" holds for this set of missing voices on this device only. Choosing another
    /// voice that isn't here asks again.
    private static let declinedKey = "voices.promptDeclined"

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in VoiceSetup.shared.refresh() }
        }
    }

    func refresh() {
        installed = Set(AVSpeechSynthesisVoice.speechVoices().map(\.identifier))
    }

    func isInstalled(_ id: String) -> Bool { installed.contains(id) }

    var missing: [MissingVoice] {
        guard let m = modelManager else { return [] }
        let picks: [(use: String, id: String?)] = [
            ("Pronunciation", m.selectedVoiceIdentifier),
            ("Man's voice", m.voiceMaleIdentifier),
            ("Woman's voice", m.voiceFemaleIdentifier),
            ("Boy's voice", m.voiceBoyIdentifier),
            ("Girl's voice", m.voiceGirlIdentifier),
        ]
        var order: [String] = []
        var uses: [String: [String]] = [:]
        for case let (use, id?) in picks where !installed.contains(id) {
            if uses[id] == nil { order.append(id) }
            uses[id, default: []].append(use)
        }
        return order.map { MissingVoice(id: $0, name: GermanVoiceCatalog.name(forIdentifier: $0), uses: uses[$0] ?? []) }
    }

    /// Speech wanted `id` and read with a basic voice instead. Offers the way to Settings ▸ Voice once
    /// per launch, unless the learner said not to for these voices.
    func speechFellBack(wanted id: String) {
        guard !promptedThisLaunch else { return }
        // A stale list would ask about a voice downloaded since launch.
        refresh()
        guard !isInstalled(id) else { return }
        let missing = missing
        guard !missing.isEmpty, UserDefaults.standard.string(forKey: Self.declinedKey) != Self.key(missing) else { return }
        if present(missing) { promptedThisLaunch = true }
    }

    /// DEBUG. `-voices.debugSpeak 1` speaks a line at launch, as tapping a speaker does: with a chosen
    /// voice the simulator lacks (`-selectedVoiceIdentifier com.apple.voice.premium.de-DE.Anna`), that
    /// raises the alert. `-voices.debugSheet 1` opens what "Show Me How" opens.
    func applyDebugLaunchArgumentIfNeeded() {
        #if DEBUG
        let speak = UserDefaults.standard.bool(forKey: "voices.debugSpeak")
        let sheet = UserDefaults.standard.bool(forKey: "voices.debugSheet")
        guard speak || sheet else { return }
        Task {
            // The window has to be up before anything can present on it.
            try? await Task.sleep(for: .seconds(1.5))
            if speak { SpeechService.shared.speak("Guten Tag!") }
            #if canImport(UIKit)
            if sheet { presentVoiceSettings() }
            #endif
        }
        #endif
    }

    private static func key(_ missing: [MissingVoice]) -> String {
        missing.map(\.id).sorted().joined(separator: ",")
    }

    // MARK: - The alert

    static let alertTitle = "Download your voices"

    static func alertMessage(_ missing: [MissingVoice]) -> String {
        let names = ListFormatter.localizedString(byJoining: missing.map(\.name))
        let one = missing.count == 1
        return "You chose \(names), but \(one ? "it isn't" : "they aren't") on this \(deviceName) yet, so a basic voice is reading instead. Download \(one ? "it" : "them") in \(ThisDevice.settingsApp) to hear \(one ? "it" : "them") here."
    }

    static var deviceName: String {
        switch ThisDevice.kind {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }

    private func decline(_ missing: [MissingVoice]) {
        UserDefaults.standard.set(Self.key(missing), forKey: Self.declinedKey)
    }

    #if canImport(UIKit)
    /// UIKit rather than a SwiftUI `.alert`: speech plays from inside sheets and full-screen covers,
    /// and a root-level alert can't present over those. The topmost controller can.
    private func present(_ missing: [MissingVoice]) -> Bool {
        guard let top = Self.topViewController(), !(top is UIAlertController), !top.isBeingDismissed else { return false }
        let alert = UIAlertController(title: Self.alertTitle, message: Self.alertMessage(missing), preferredStyle: .alert)
        let show = UIAlertAction(title: "Show Me How", style: .default) { [weak self] _ in self?.presentVoiceSettings() }
        alert.addAction(show)
        alert.addAction(UIAlertAction(title: "Don't Ask Again", style: .default) { [weak self] _ in self?.decline(missing) })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.preferredAction = show
        top.present(alert, animated: true)
        return true
    }

    /// Settings ▸ Voice as a sheet over whatever is showing, so a study session stays where it was.
    private func presentVoiceSettings() {
        guard let modelManager, let top = Self.topViewController() else { return }
        weak var host: UIViewController?
        let theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: AppTheme.defaultsKey) ?? "") ?? .klar
        let sheet = UIHostingController(rootView:
            NavigationStack {
                VoiceSettingsView(modelManager: modelManager)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { host?.dismiss(animated: true) }
                        }
                    }
            }
            .environment(\.appTheme, theme)
        )
        host = sheet
        top.present(sheet, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
    #else
    /// Bumped by "Show Me How"; `ContentView` answers by opening Settings ▸ Voice.
    var settingsRequest = 0

    private func present(_ missing: [MissingVoice]) -> Bool {
        guard NSApp.isActive, let window = NSApp.keyWindow, window.attachedSheet == nil else { return false }
        let alert = NSAlert()
        alert.messageText = Self.alertTitle
        alert.informativeText = Self.alertMessage(missing)
        alert.addButton(withTitle: "Show Me How")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.settingsRequest += 1
            case .alertThirdButtonReturn: self?.decline(missing)
            default: break
            }
        }
        return true
    }
    #endif
}
