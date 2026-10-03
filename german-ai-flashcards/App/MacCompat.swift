//
//  MacCompat.swift
//  german-ai-flashcards
//
//  The macOS build's stand-ins for the iOS APIs the app uses, so the same SwiftUI screens compile
//  and run on the Mac unchanged. macOS-only: on iOS this file is empty and nothing here exists.
//
//  The rule: a stand-in keeps the iOS name and shape and does the nearest Mac thing, or nothing
//  when there is no Mac equivalent. A view file should never need to know it's on a Mac. When a
//  screen genuinely has to behave differently, guard that screen with `#if os(macOS)` instead of
//  bending a stand-in. See docs/MACOS.md.
//

#if os(macOS)
@_exported import AppKit
import AVFAudio
import SwiftData
import SwiftUI

// MARK: - UIKit type names

typealias UIImage = NSImage
typealias UIColor = NSColor
typealias UIFont = NSFont

nonisolated extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// SF Symbols by name, as `UIImage(systemName:)`.
    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }

    func pngData() -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

extension Image {
    nonisolated init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

extension Color {
    nonisolated init(uiColor: NSColor) { self.init(nsColor: uiColor) }
}

// MARK: - Colors

enum UIUserInterfaceStyle: Sendable { case unspecified, light, dark }

/// Just enough of `UITraitCollection` for dynamic colors and display scale.
nonisolated struct UITraitCollection: Sendable {
    var userInterfaceStyle: UIUserInterfaceStyle
    var displayScale: CGFloat

    static var current: UITraitCollection {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return UITraitCollection(
            userInterfaceStyle: dark ? .dark : .light,
            displayScale: NSScreen.main?.backingScaleFactor ?? 2
        )
    }
}

nonisolated extension NSColor {
    /// `UIColor { traits in … }`: resolved against the appearance it's drawn in.
    convenience init(dynamicProvider: @escaping @Sendable (UITraitCollection) -> NSColor) {
        self.init(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return dynamicProvider(UITraitCollection(
                userInterfaceStyle: dark ? .dark : .light,
                displayScale: NSScreen.main?.backingScaleFactor ?? 2
            ))
        }
    }

    /// iOS's light/dark values, so the Mac build draws the same palette as the phone.
    private static func ios(_ light: (Int, Int, Int, CGFloat), _ dark: (Int, Int, Int, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: c.3)
        }
    }

    static var systemBackground: NSColor { ios((255, 255, 255, 1), (0, 0, 0, 1)) }
    static var secondarySystemBackground: NSColor { ios((242, 242, 247, 1), (28, 28, 30, 1)) }
    static var tertiarySystemBackground: NSColor { ios((255, 255, 255, 1), (44, 44, 46, 1)) }
    static var systemGroupedBackground: NSColor { ios((242, 242, 247, 1), (0, 0, 0, 1)) }
    static var secondarySystemGroupedBackground: NSColor { ios((255, 255, 255, 1), (28, 28, 30, 1)) }
    static var tertiarySystemGroupedBackground: NSColor { ios((242, 242, 247, 1), (44, 44, 46, 1)) }
    static var systemGray2: NSColor { ios((174, 174, 178, 1), (99, 99, 102, 1)) }
    static var systemGray3: NSColor { ios((199, 199, 204, 1), (72, 72, 74, 1)) }
    static var systemGray4: NSColor { ios((209, 209, 214, 1), (58, 58, 60, 1)) }
    static var systemGray5: NSColor { ios((229, 229, 234, 1), (44, 44, 46, 1)) }
    static var systemGray6: NSColor { ios((242, 242, 247, 1), (28, 28, 30, 1)) }
    static var systemFill: NSColor { ios((120, 120, 128, 0.20), (120, 120, 128, 0.36)) }
    static var secondarySystemFill: NSColor { ios((120, 120, 128, 0.16), (120, 120, 128, 0.32)) }
    static var tertiarySystemFill: NSColor { ios((118, 118, 128, 0.12), (118, 118, 128, 0.24)) }
    static var quaternarySystemFill: NSColor { ios((116, 116, 128, 0.08), (118, 118, 128, 0.18)) }
    /// The app's accent (the AccentColor asset), as `UIColor.tintColor` resolves on iOS.
    static var tintColor: NSColor { NSColor(named: "AccentColor") ?? .controlAccentColor }
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var quaternaryLabel: NSColor { .quaternaryLabelColor }
    static var placeholderText: NSColor { .placeholderTextColor }
    static var separator: NSColor { .separatorColor }
    static var opaqueSeparator: NSColor { ios((198, 198, 200, 1), (56, 56, 58, 1)) }
}

// MARK: - Drawing

/// `UIGraphicsImageRenderer` for the few places that draw a bitmap in code.
nonisolated final class UIGraphicsImageRenderer {
    struct Context {
        let cgContext: CGContext
        func fill(_ rect: CGRect) { cgContext.fill(rect) }
    }

    let size: CGSize
    init(size: CGSize) { self.size = size }

    func image(actions: (Context) -> Void) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        if let cg = NSGraphicsContext.current?.cgContext { actions(Context(cgContext: cg)) }
        image.unlockFocus()
        return image
    }
}

// MARK: - App and device

@MainActor final class UIDevice {
    static let current = UIDevice()
    let systemName = "macOS"
    var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    /// Generic, like iOS's "iPhone"/"iPad". The iCloud device list shows it with a laptop icon.
    let model = "Mac"
}

@MainActor final class UIApplication {
    static let shared = UIApplication()

    /// There is no per-app page in System Settings; this opens System Settings itself.
    static let openSettingsURLString = "x-apple.systempreferences:"
    /// Posted by ``MacMemoryPressure`` when the system reports memory pressure.
    static let didReceiveMemoryWarningNotification = Notification.Name("MacCompat.didReceiveMemoryWarning")
    static let willEnterForegroundNotification = NSApplication.willBecomeActiveNotification
    static let didEnterBackgroundNotification = NSApplication.didHideNotification

    enum State { case active, inactive, background }

    var applicationState: State {
        let app = NSApplication.shared
        if app.isHidden { return .background }
        return app.isActive ? .active : .inactive
    }

    /// iOS keeps the screen awake for long generations; on the Mac, hold off idle sleep instead.
    private var idleActivity: NSObjectProtocol?
    var isIdleTimerDisabled: Bool {
        get { idleActivity != nil }
        set {
            if newValue, idleActivity == nil {
                idleActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated],
                    reason: "Die Kartei is generating"
                )
            } else if !newValue, let activity = idleActivity {
                ProcessInfo.processInfo.endActivity(activity)
                idleActivity = nil
            }
        }
    }

    func registerForRemoteNotifications() {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Turns the system's memory-pressure events into `UIApplication.didReceiveMemoryWarningNotification`,
/// which the memory saver and the story reader already listen for. Started once at launch.
@MainActor enum MacMemoryPressure {
    private static var source: DispatchSourceMemoryPressure?

    static func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        source.resume()
        self.source = source
    }
}

nonisolated final class UIPasteboard: @unchecked Sendable {
    static let general = UIPasteboard()
    private var board: NSPasteboard { .general }

    var string: String? {
        get { board.string(forType: .string) }
        set {
            board.clearContents()
            if let newValue { board.setString(newValue, forType: .string) }
        }
    }
    var hasStrings: Bool { board.canReadObject(forClasses: [NSString.self], options: nil) }
    var url: URL? { board.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL }
    var hasURLs: Bool { board.canReadObject(forClasses: [NSURL.self], options: nil) }
}

// MARK: - Audio

/// macOS has no audio session: apps share the output device and ask for the microphone once.
/// Categories and activation are accepted and ignored; permission goes to the real Mac API.
nonisolated final class AVAudioSession: @unchecked Sendable {
    static func sharedInstance() -> AVAudioSession { AVAudioSession() }

    struct Category: Sendable { static let playback = Category(), playAndRecord = Category(), record = Category(), ambient = Category() }
    struct Mode: Sendable { static let `default` = Mode(), measurement = Mode(), spokenAudio = Mode(), voiceChat = Mode() }
    struct CategoryOptions: OptionSet, Sendable {
        let rawValue: Int
        static let defaultToSpeaker = CategoryOptions(rawValue: 1 << 0)
        static let duckOthers = CategoryOptions(rawValue: 1 << 1)
        static let mixWithOthers = CategoryOptions(rawValue: 1 << 2)
        static let allowBluetooth = CategoryOptions(rawValue: 1 << 3)
        static let allowBluetoothA2DP = CategoryOptions(rawValue: 1 << 4)
    }
    struct SetActiveOptions: OptionSet, Sendable {
        let rawValue: Int
        static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1)
    }

    func setCategory(_ category: Category, mode: Mode = .default, options: CategoryOptions = []) throws {}
    func setActive(_ active: Bool, options: SetActiveOptions = []) throws {}

    func requestRecordPermission(_ response: @escaping @Sendable (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission(completionHandler: response)
    }
}

// MARK: - Background tasks

/// macOS has no continued-processing tasks. Registration reports failure and `submit` throws, and
/// `StoryBackgroundGenerator` already treats both as "run the job inline", which is what the Mac
/// wants anyway: the app isn't suspended when its window is in the background.
nonisolated class BGTask: @unchecked Sendable {
    var identifier: String { "" }
    var expirationHandler: (() -> Void)?
    func setTaskCompleted(success: Bool) {}
}

nonisolated final class BGContinuedProcessingTask: BGTask, @unchecked Sendable {
    let progress = Progress()
    func updateTitle(_ title: String, subtitle: String) {}
}

nonisolated final class BGContinuedProcessingTaskRequest: @unchecked Sendable {
    enum SubmissionStrategy: Sendable { case fail, queue }
    struct Resources: OptionSet, Sendable {
        let rawValue: Int
        static let `default` = Resources([])
        static let gpu = Resources(rawValue: 1)
    }
    var strategy: SubmissionStrategy = .fail
    var requiredResources: Resources = []
    init(identifier: String, title: String, subtitle: String) {}
}

nonisolated final class BGTaskScheduler: @unchecked Sendable {
    static let shared = BGTaskScheduler()
    struct Unsupported: Error {}

    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool { false }

    func submit(_ request: BGContinuedProcessingTaskRequest) throws { throw Unsupported() }
}

// MARK: - SwiftUI modifiers that iOS has and macOS doesn't

enum MacCompatTitleDisplayMode { case automatic, inline, large }

struct MacCompatAutocapitalization {
    static let never = Self(), words = Self(), sentences = Self(), characters = Self()
}

enum MacCompatKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad,
         emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

extension View {
    /// Mac windows have no large titles; the title shows in the toolbar either way.
    func navigationBarTitleDisplayMode(_ mode: MacCompatTitleDisplayMode) -> some View { self }

    func textInputAutocapitalization(_ autocapitalization: MacCompatAutocapitalization?) -> some View { self }

    func keyboardType(_ type: MacCompatKeyboardType) -> some View { self }

    func statusBarHidden(_ hidden: Bool = true) -> some View { self }

    /// A full-screen cover opens in a window of its own, where its toolbar (close button, title,
    /// step bar) shows as on the phone. See `MacCoverWindow.swift`.
    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(MacCoverPresenter(isPresented: isPresented, key: nil, onDismiss: onDismiss, cover: content))
    }

    func fullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(MacCoverPresenter(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            // A different item while one is showing replaces the window rather than leaving the
            // old cover up.
            key: item.wrappedValue.map { AnyHashable($0.id) },
            onDismiss: onDismiss
        ) {
            if let value = item.wrappedValue { content(value) }
        })
    }
}

private struct MacCoverPresenter<Cover: View>: ViewModifier {
    @Binding var isPresented: Bool
    var key: AnyHashable?
    var onDismiss: (() -> Void)?
    @ViewBuilder var cover: () -> Cover

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    // What the cover's screens read from the environment, carried into the new window.
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme
    @Environment(ActivityRouter.self) private var activityRouter: ActivityRouter?
    @Environment(SettingsRouter.self) private var settingsRouter: SettingsRouter?
    @Environment(MLXGenerationService.self) private var mlxService: MLXGenerationService?
    @Environment(MacNavigator.self) private var navigator: MacNavigator?

    @State private var windowID: UUID?
    @State private var shownKey: AnyHashable?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let windowID {
                    MacCoverPlaceholder {
                        openWindow(id: MacCoverRegistry.sceneID, value: windowID)
                    }
                }
            }
            .onChange(of: isPresented, initial: true) { _, presented in
                presented ? open() : close()
            }
            .onChange(of: key) { _, newKey in
                guard isPresented, windowID != nil, newKey != shownKey else { return }
                close(notify: false)
                open()
            }
    }

    private func open() {
        guard windowID == nil else { return }
        let view = cover()
            .environment(\.modelContext, modelContext)
            .environment(\.appTheme, appTheme)
            .environment(\.modelTheme, modelTheme)
            .environment(activityRouter)
            .environment(settingsRouter)
            .environment(mlxService)
            .environment(navigator)
            .formStyle(.grouped)
        let binding = $isPresented
        let windowState = $windowID
        let dismissed = onDismiss
        let id = MacCoverRegistry.shared.register(AnyView(view)) {
            // The window closed on its own (close button, ⌘W, the screen's dismiss()).
            windowState.wrappedValue = nil
            if binding.wrappedValue { binding.wrappedValue = false }
            dismissed?()
        }
        windowID = id
        shownKey = key
        openWindow(id: MacCoverRegistry.sceneID, value: id)
    }

    /// The opener ended the cover (the screen's own close button cleared the binding).
    private func close(notify: Bool = true) {
        guard let id = windowID else { return }
        windowID = nil
        MacCoverRegistry.shared.remove(id)
        dismissWindow(id: MacCoverRegistry.sceneID, value: id)
        if notify { onDismiss?() }
    }
}

enum MacCompat {
    /// The smallest a full-screen cover's window is drawn on the Mac.
    static let coverSize = CGSize(width: 720, height: 760)
}

extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

extension ListStyle where Self == InsetListStyle {
    static var insetGrouped: InsetListStyle { .inset }
}

enum MacCompatPageIndexDisplayMode { case automatic, always, never }

extension TabViewStyle where Self == DefaultTabViewStyle {
    static var page: DefaultTabViewStyle { .automatic }
    static func page(indexDisplayMode: MacCompatPageIndexDisplayMode) -> DefaultTabViewStyle { .automatic }
}

enum MacCompatListSectionSpacing { case `default`, compact }

extension View {
    func listSectionSpacing(_ spacing: MacCompatListSectionSpacing) -> some View { self }
    func listSectionSpacing(_ spacing: CGFloat) -> some View { self }
}

/// Lists on the Mac delete with the Delete key and the context menu; there is no edit mode to enter.
struct EditButton: View {
    var body: some View { EmptyView() }
}
#endif
