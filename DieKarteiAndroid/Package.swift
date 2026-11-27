// swift-tools-version: 6.2
// This is a Skip (https://skip.dev) package: the Android app, in Swift and SwiftUI.
//
// Two modules:
// - DieKarteiCore: the iOS app's portable files. Sources/DieKarteiCore is a symlink to
//   ../DieKarteiCore/Sources/DieKarteiCore, whose files are symlinks into german-ai-flashcards/
//   (scripts/core_sync.py keeps the list). Plain Swift, no Skip plugin: SwiftPM plugins are
//   sandboxed to this folder and couldn't read the linked files anyway. Settings mirror the iOS
//   target (Swift 5 mode, MainActor by default) so the shared files mean the same thing.
// - GermanVoice: a few lines of transpiled Swift around Android's TextToSpeech (Skip Lite).
// - CLlama: llama.cpp's C API (Android only), for the tutor models as GGUF. See TutorEngine.swift.
// - KarteiStore: the app's SQLite database (SkipSQLPlus, its own SQLite build). Kept out of the
//   core so the iOS-side core builds don't pull in skip-sql.
// - DieKartei: the Android UI in SwiftUI (Skip Fuse). It reaches the core's internal types
//   through `@testable import`, which is why the core builds with -enable-testing: the iOS
//   app's code is internal, and making it public just for Android isn't worth the churn.
import PackageDescription

/// llama.cpp's Android libraries, built by scripts/build_llama_android.sh (gitignored).
let llamaLibs = Context.packageDirectory + "/Vendor/llama/arm64-v8a"

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
        .package(url: "https://github.com/skiptools/skip-fuse.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.0.0"),
        .package(url: "https://github.com/skiptools/skip-bridge.git", "0.17.3"..<"2.0.0"),
        .package(url: "https://github.com/skiptools/skip-sql.git", from: "0.16.1"),
    ],
    targets: [
        .target(
            name: "DieKarteiCore",
            dependencies: [
                // CryptoKit stands in on Apple platforms (the sync files pick one with canImport).
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.android, .linux])),
                // The core's @Observable types (the conversation session) import SkipFuse on
                // Android, so their changes reach Compose like the UI module's own stores.
                .product(name: "SkipFuse", package: "skip-fuse", condition: .when(platforms: [.android])),
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
        // Transpiled to Kotlin (Skip Lite) so it can use Android's TextToSpeech; see its skip.yml.
        .target(
            name: "GermanVoice",
            dependencies: [
                .product(name: "SkipFoundation", package: "skip-foundation"),
                .product(name: "SkipBridge", package: "skip-bridge"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],  // a shared voice; TextToSpeech is main-thread only anyway
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        // llama.cpp, called straight from Swift: no Kotlin, no JNI. Android only; the libraries are
        // packaged into the APK by app/build.gradle.kts.
        .target(
            name: "CLlama",
            linkerSettings: [
                .unsafeFlags(["-L\(llamaLibs)"], .when(platforms: [.android])),
            ]
        ),
        // Native Swift on SkipSQLPlus (SQLite + SQLCipher built from source for each ABI).
        // `-enable-testing` for the same reason as the core: its API speaks the core's internal
        // record types, and the UI module reaches it with `@testable import`.
        .target(
            name: "KarteiStore",
            dependencies: [
                "DieKarteiCore",
                .product(name: "SkipSQLPlus", package: "skip-sql"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .unsafeFlags(["-enable-testing"]),
            ]
        ),
        .testTarget(
            name: "KarteiStoreTests",
            dependencies: ["KarteiStore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "DieKartei",
            dependencies: [
                "DieKarteiCore",
                "KarteiStore",
                "GermanVoice",
                .target(name: "CLlama", condition: .when(platforms: [.android])),
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
