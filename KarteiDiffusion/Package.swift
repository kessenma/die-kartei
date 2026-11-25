// swift-tools-version:6.2
// Z-Image Turbo and FLUX.2 klein 4B on MLX, for the Mac build's picture models. A trimmed copy of
// turbo-mlx's TurboEngineCore (MIT, see LICENSE and VENDORED.md), pinned to the same mlx-swift
// minor as the app's tutors (mlx-swift-lm 3.31.x pins 0.31.x), so the app links one MLX.
import PackageDescription

let package = Package(
    name: "KarteiDiffusion",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "KarteiDiffusion", targets: ["KarteiDiffusion"]),
        .executable(name: "kartei-diffusion-probe", targets: ["kartei-diffusion-probe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.4")),
    ],
    targets: [
        .target(
            name: "KarteiDiffusion",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "kartei-diffusion-probe",
            dependencies: ["KarteiDiffusion"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KarteiDiffusionTests",
            dependencies: ["KarteiDiffusion"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
