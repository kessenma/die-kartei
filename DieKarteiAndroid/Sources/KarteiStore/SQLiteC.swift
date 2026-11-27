import Foundation
import SQLExt

/// SkipSQLPlus' SQLite, reached through its C headers (`SQLExt`). Code that talks to SQLite
/// directly, like WiktionaryValidator's `import SQLite3` on iOS, can use this module on Android.
public enum SQLiteC {
    public static var libraryVersion: String {
        sqlite3_libversion().map { String(cString: $0) } ?? "unknown"
    }
}
