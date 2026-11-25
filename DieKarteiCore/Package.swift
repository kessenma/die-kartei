// swift-tools-version:6.2
// The portable half of die Kartei, shared with the Android app.
// Sources/DieKarteiCore holds symlinks to app files that only need Foundation, so the iOS
// target keeps compiling them in place and nothing moves. `scripts/core_sync.py` rebuilds
// the link list. Settings mirror the app target (Swift 5 mode, MainActor by default).
import PackageDescription

let package = Package(
    name: "DieKarteiCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "DieKarteiCore", targets: ["DieKarteiCore"]),
    ],
    dependencies: [
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
            ]
        ),
        .testTarget(
            name: "DieKarteiCoreTests",
            dependencies: ["DieKarteiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
