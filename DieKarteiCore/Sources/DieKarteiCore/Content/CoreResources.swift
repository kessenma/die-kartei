import Foundation

/// Locates the JSON content files bundled with the core.
///
/// On Apple platforms SwiftPM's `Bundle.module` resolves resources directly.
/// On Android there is no bundle on disk — the host app extracts the files
/// from APK assets and points `overrideDirectory` at them before first use.
public enum CoreResources {

    public static var overrideDirectory: URL?

    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let dir = overrideDirectory {
            let candidate = dir.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }

    public static func decode<T: Decodable>(_ type: T.Type, resource name: String) -> T? {
        guard let url = url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
