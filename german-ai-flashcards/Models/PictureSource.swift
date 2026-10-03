import Foundation
import Synchronization

/// Where pictures for flashcards and stories are drawn: by the downloaded CoreML model on this
/// phone, or by a cloud model on the learner's own OpenRouter account. On-device stays the
/// default; cloud is opt-in from Settings ▸ Model ▸ Image generation.
nonisolated enum PictureSource: String, CaseIterable, Identifiable, Sendable {
    case onDevice
    case cloud

    static let defaultsKey = "pictureSource"

    static var current: PictureSource {
        get {
            if let override = runOverride.withLock({ $0 }) { return override }
            return UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(PictureSource.init(rawValue:)) ?? .onDevice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// MAC-PICTURES: pinned to `.onDevice` by the Mac's picture inbox around an order's run, so an
    /// order from the phone is drawn by this Mac's model, never on the learner's OpenRouter account.
    static let runOverride = Mutex<PictureSource?>(nil)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onDevice: "On this \(ThisDevice.name)"   // MAC-PICTURES
        case .cloud:    "Cloud"
        }
    }
}

/// The one question every picture feature asks before it shows itself: can pictures be drawn
/// right now? Replaces the old "is the image model downloaded" check, which is only the answer
/// for the on-device source.
///
/// Readable from anywhere (it's what view bodies and background services both gate on), so the
/// cloud half reads a UserDefaults mirror of "a key is stored" rather than the Keychain.
nonisolated enum PictureEngine {
    static var isReady: Bool {
        isReady(source: .current)
    }

    static func isReady(source: PictureSource) -> Bool {
        switch source {
        case .onDevice: ImageGenModel.current.isDownloaded
        case .cloud:    OpenRouterAccount.hasKey
        }
    }

    /// "on-device" or "in the cloud by Muse Image", for copy that says where a picture comes from.
    static var drawnWherePhrase: String {
        switch PictureSource.current {
        case .onDevice: "on-device"
        case .cloud:    "in the cloud by \(CloudImageModel.current.displayName)"
        }
    }

    /// Roughly how long one picture takes, for copy that sets the wait.
    static var perPictureWait: String {
        switch PictureSource.current {
        case .onDevice: "a minute or two"
        case .cloud:    "about \(Int(CloudImageModel.current.typicalSeconds)) seconds"
        }
    }

    /// " (about $1.20 on your OpenRouter account)" for a cloud run of `pictures`, or "" on-device,
    /// so a big deck never starts without the learner seeing what it costs.
    static func costPhrase(pictures: Int) -> String {
        guard PictureSource.current == .cloud, pictures > 0 else { return "" }
        let dollars = Double(pictures) * CloudImageModel.current.approxCostUSD
        return " (about \(dollars.formatted(.currency(code: "USD").precision(.fractionLength(2)))) on your OpenRouter account)"
    }

    /// What to do when `isReady` is false, in one sentence.
    static var notReadyMessage: String {
        switch PictureSource.current {
        case .onDevice: "The picture model isn't downloaded. You can get it in Settings ▸ Model."
        case .cloud:    "Cloud pictures need your OpenRouter account. Connect it in Settings ▸ Model."
        }
    }
}
