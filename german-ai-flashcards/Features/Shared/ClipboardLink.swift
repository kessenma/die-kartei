import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The Maps-style "paste copied link" offer: a URL on the clipboard, or a short string that looks
/// like one. Reading the pasteboard shows the system "pasted from" banner, so callers ask only
/// while a link field is empty. (The Paper screens carry an older inline copy of this check.)
enum ClipboardLink {
    @MainActor static func suggestion() -> String? {
        #if canImport(UIKit)
        let board = UIPasteboard.general
        if board.hasURLs, let url = board.url {
            return url.absoluteString
        }
        if board.hasStrings,
           let copied = board.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           copied.count < 400, !copied.contains(" "),
           copied.lowercased().hasPrefix("http") || copied.contains(".") {
            return copied
        }
        #endif
        return nil
    }
}
