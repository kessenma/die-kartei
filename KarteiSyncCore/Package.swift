// swift-tools-version:6.2
// Pure sync logic shared with the app: Sources/KarteiSyncCore is a symlink to
// german-ai-flashcards/Services/Sync/Core, which the app target compiles directly.
import PackageDescription

let package = Package(
    name: "KarteiSyncCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .target(name: "KarteiSyncCore"),
        .testTarget(name: "KarteiSyncCoreTests", dependencies: ["KarteiSyncCore"]),
    ]
)
