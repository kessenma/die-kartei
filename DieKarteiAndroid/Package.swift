// swift-tools-version: 6.2
// This is a Skip (https://skip.dev) package: the Android app, in Swift and SwiftUI.
//
// Two modules:
// - DieKarteiCore: the iOS app's portable files. Sources/DieKarteiCore is a symlink to
//   ../DieKarteiCore/Sources/DieKarteiCore, whose files are symlinks into german-ai-flashcards/
//   (scripts/core_sync.py keeps the list). Plain Swift, no Skip plugin: SwiftPM plugins are
//   sandboxed to this folder and couldn't read the linked files anyway. Settings mirror the iOS
//   target (Swift 5 mode, MainActor by default) so the shared files mean the same thing.
// - DieKartei: the Android UI in SwiftUI (Skip Fuse). It reaches the core's internal types
//   through `@testable import`, which is why the core builds with -enable-testing: the iOS
//   app's code is internal, and making it public just for Android isn't worth the churn.
import PackageDescription

let package = Package(
    name: "DieKarteiAndroid",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DieKartei", type: .dynamic, targets: ["DieKartei"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.21"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "DieKarteiCore",
            dependencies: [
                // CryptoKit stands in on Apple platforms (the sync files pick one with canImport).
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.android, .linux])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .unsafeFlags(["-enable-testing"]),
            ]
        ),
        .target(
            name: "DieKartei",
            dependencies: [
                "DieKarteiCore",
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
