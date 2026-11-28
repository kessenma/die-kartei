#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
#endif

/// `.kartei` files on Android (transpiled Kotlin): the system's document picker, reading a file
/// another app hands over (a `content://` link), and sending a deck through the share sheet.
/// The picker's result arrives as an ordinary "open this file" intent, so the app takes both
/// paths in through the same `onOpenURL`.
public final class DeckFiles {
    public static let shared = DeckFiles()

    #if SKIP
    /// Set by MainActivity: opens the system document picker. (An activity-result launcher has
    /// to be registered by the activity itself, before it starts.)
    public var openDocument: (() -> Void)? = nil
    #endif

    public init() {
    }

    /// Show the document picker. False when there is none (not on Android, or not ready).
    public func pick() -> Bool {
        #if SKIP
        guard let open = openDocument else { return false }
        open()
        return true
        #else
        return false
        #endif
    }

    /// The bytes behind a `content://` (or `file://`) link, or nil.
    public func read(_ url: String) -> Data? {
        #if SKIP
        do {
            let context = ProcessInfo.processInfo.androidContext
            guard let stream = context.contentResolver.openInputStream(Uri.parse(url)) else { return nil }
            let bytes = stream.readBytes()
            stream.close()
            return Data(platformValue: bytes)
        } catch {
            return nil
        }
        #else
        return try? Data(contentsOf: URL(string: url) ?? URL(fileURLWithPath: url))
        #endif
    }

    /// Offer a file to other apps (the share sheet). False when it couldn't be written.
    public func share(_ data: Data, fileName: String, title: String) -> Bool {
        #if SKIP
        do {
            let context = ProcessInfo.processInfo.androidContext
            let dir = java.io.File(context.cacheDir, "shared")
            dir.mkdirs()
            let file = java.io.File(dir, fileName)
            file.writeBytes(data.platformValue)
            let uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
            let send = Intent(Intent.ACTION_SEND)
            send.setType("application/octet-stream")
            send.putExtra(Intent.EXTRA_STREAM, uri)
            send.putExtra(Intent.EXTRA_SUBJECT, title)
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            let chooser = Intent.createChooser(send, title)
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(chooser)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}
#endif
