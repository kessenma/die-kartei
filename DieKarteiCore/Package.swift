// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DieKarteiCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DieKarteiCore", targets: ["DieKarteiCore"]),
    ],
    targets: [
        .target(
            name: "DieKarteiCore",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "DieKarteiCoreTests",
            dependencies: ["DieKarteiCore"]
        ),
    ]
)
